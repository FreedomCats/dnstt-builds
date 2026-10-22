#!/bin/sh
# Build the release archives of dnstt: the same script runs in the release
# workflow and on your machine, and both give the same bytes.
#
#   ./build.sh <dnstt checkout> <tag> <output dir> [<suffix>]
#
# <dnstt checkout> is a clean git clone of dnstt (the mirror or upstream) with
# <tag> checked out; HEAD and the tag must be the commit listed for <tag> in
# versions.txt. <output dir> must be missing or empty. <suffix> marks a rebuild
# of the same tag: the release, and the archive names, become <tag>-<suffix>.
#
# The output is one archive per platform, dnstt-<release>-<os>-<arch>.tar.gz
# (.zip for Windows), with a directory holding dnstt-client, dnstt-server and
# COPYING, README and CHANGELOG from the tag, and SHA256SUMS over the archives.
#
# Needs git and Go 1.21 or newer: the Go release from go.mod is fetched and
# used through GOTOOLCHAIN, whatever Go is installed.
set -eu

platforms='windows/amd64 windows/arm64 linux/amd64 linux/arm64 darwin/amd64 darwin/arm64'
docs='COPYING README CHANGELOG'

die() {
	echo "build.sh: $*" >&2
	exit 1
}

[ $# -eq 3 ] || [ $# -eq 4 ] || {
	echo 'usage: build.sh <dnstt checkout> <tag> <output dir> [<suffix>]' >&2
	exit 2
}
src=$1
tag=$2
out=$3
suffix=${4-}

here=$(cd "$(dirname "$0")" && pwd -P)

printf '%s\n' "$tag" | grep -Eqx 'v[0-9]+\.[0-9]+\.[0-9]+' || die "bad tag: $tag"
release=$tag
if [ -n "$suffix" ]; then
	printf '%s\n' "$suffix" | grep -Eqx '[0-9]+' || die "bad suffix: $suffix (want a number)"
	release=$tag-$suffix
fi

# The commit the tag must point to.
commit=$(awk -v tag="$tag" '$1 == tag { print $2 }' "$here/versions.txt")
[ -n "$commit" ] || die "$tag is not in versions.txt"
printf '%s\n' "$commit" | grep -Eqx '[0-9a-f]{40}' || die "versions.txt: bad commit for $tag: $commit"

[ -d "$src" ] || die "$src: no such directory"
src=$(cd "$src" && pwd -P)
head=$(git -C "$src" rev-parse --verify -q 'HEAD^{commit}') || die "$src: not a git checkout"
[ "$head" = "$commit" ] || die "$src: HEAD is $head, versions.txt wants $commit for $tag"
# Go stamps the module version from the tag at HEAD, so the tag must be there.
tagged=$(git -C "$src" rev-parse --verify -q "refs/tags/$tag^{commit}") || die "$src: no tag $tag"
[ "$tagged" = "$commit" ] || die "$src: tag $tag is $tagged, versions.txt wants $commit"

mkdir -p "$out"
out=$(cd "$out" && pwd -P)
[ -z "$(ls -A "$out")" ] || die "$out: not empty"
case $out/ in
"$src"/*) die "$out: inside the checkout" ;;
esac
# Go records local changes in the binaries (vcs.modified).
[ -z "$(git -C "$src" status --porcelain)" ] || die "$src: uncommitted or untracked files"

# Only what is set here goes into the build: no go env file, no GOFLAGS,
# GOAMD64 and the like from the environment.
gover=$(awk '$1 == "go" { print $2; exit }' "$here/go.mod")
[ -n "$gover" ] || die "go.mod: no go line"
GOTOOLCHAIN=go$gover
GOENV=off
GOFLAGS=-mod=readonly
GOWORK=off
CGO_ENABLED=0
export GOTOOLCHAIN GOENV GOFLAGS GOWORK CGO_ENABLED
unset GOEXPERIMENT GOFIPS140 GOAMD64 GOARM64 GO386 GOARM GOMIPS GOMIPS64 GOPPC64 GORISCV64 GOWASM GOOS GOARCH
[ "$(go env GOVERSION)" = "go$gover" ] || die "cannot run go$gover"

# Every archive entry gets the commit time.
mtime=$(git -C "$src" show -s --format=%ct "$commit")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
(cd "$here" && go build -buildvcs=false -o "$tmp/pack" ./cmd/pack)

echo "dnstt $tag ($commit), go$gover"
for p in $platforms; do
	os=${p%/*}
	arch=${p#*/}
	name=dnstt-$release-$os-$arch
	dir=$tmp/$name
	mkdir "$dir"
	ext=
	[ "$os" = windows ] && ext=.exe
	for cmd in dnstt-client dnstt-server; do
		(cd "$src" && GOOS=$os GOARCH=$arch go build -trimpath -buildvcs=true \
			-ldflags='-s -w -buildid=' -o "$dir/$cmd$ext" "./$cmd")
	done
	for f in $docs; do
		git -C "$src" cat-file -e "$commit:$f" 2>/dev/null || die "$tag has no $f"
		git -C "$src" show "$commit:$f" >"$dir/$f"
	done
	if [ "$os" = windows ]; then
		archive=$out/$name.zip
	else
		archive=$out/$name.tar.gz
	fi
	"$tmp/pack" archive -mtime "$mtime" -o "$archive" "$dir"
	echo "  $(basename "$archive")"
done
"$tmp/pack" sums "$out"
cat "$out/SHA256SUMS"
