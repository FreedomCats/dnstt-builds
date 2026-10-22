#!/bin/sh
# Print the body of a release, in Markdown, to stdout: what was built, links
# to download every archive, the dnstt source and SHA256SUMS, and how to check
# a download. The release workflow writes the body with it; run it by hand to
# rewrite the body of an existing release (gh release edit --notes-file).
#
#   ./release-notes.sh <archive dir>
#
# <archive dir> holds the archives and SHA256SUMS made by build.sh. The
# platforms are those of build.sh: every one must have its archive there, and
# SHA256SUMS must list exactly these archives.
#
# The rest comes from the environment:
#   REPO_URL      this repository, https://github.com/<owner>/<name>
#   MIRROR        the dnstt mirror, https://github.com/<owner>/<name>
#   RELEASE       the release tag: <tag> or <tag>-<suffix>
#   TAG           the upstream tag
#   COMMIT        the upstream commit of TAG, as in versions.txt
#   GO_VERSION    the Go release of the build, such as go1.26.10
#   RUN_URL       the workflow run that built the archives
#   BUILD_COMMIT  the commit of this repository that built them
set -eu

die() {
	echo "release-notes.sh: $*" >&2
	exit 1
}

[ $# -eq 1 ] || {
	echo 'usage: release-notes.sh <archive dir> (and the environment, see the script)' >&2
	exit 2
}
dir=$1

for v in REPO_URL MIRROR RELEASE TAG COMMIT GO_VERSION RUN_URL BUILD_COMMIT; do
	eval "[ -n \"\${$v-}\" ]" || die "$v is not set"
done

here=$(cd "$(dirname "$0")" && pwd -P)

# Only what can be checked here is checked: a typo must not end up in a
# published release.
matches() {
	printf '%s\n' "$1" | grep -Eqx "$2"
}
matches "$REPO_URL" 'https://[^/]+/[^/]+/[^/]+' || die "bad REPO_URL: $REPO_URL"
matches "$MIRROR" 'https://[^/]+/[^/]+/[^/]+' || die "bad MIRROR: $MIRROR"
matches "$TAG" 'v[0-9]+\.[0-9]+\.[0-9]+' || die "bad TAG: $TAG"
[ "$RELEASE" = "$TAG" ] || matches "$RELEASE" "$TAG-[0-9]+" || die "bad RELEASE for $TAG: $RELEASE"
matches "$GO_VERSION" 'go[0-9]+(\.[0-9]+)*' || die "bad GO_VERSION: $GO_VERSION"
matches "$RUN_URL" "$REPO_URL/actions/runs/[0-9]+" || die "bad RUN_URL: $RUN_URL"
matches "$BUILD_COMMIT" '[0-9a-f]{40}' || die "bad BUILD_COMMIT: $BUILD_COMMIT"
want=$(awk -v tag="$TAG" '$1 == tag { print $2 }' "$here/versions.txt")
[ -n "$want" ] || die "$TAG is not in versions.txt"
[ "$COMMIT" = "$want" ] || die "COMMIT is $COMMIT, versions.txt wants $want for $TAG"
repo=${REPO_URL#https://*/}

# The platforms, in the order of build.sh.
platforms=$(sed -n "s/^platforms='\(.*\)'\$/\1/p" "$here/build.sh")
[ -n "$platforms" ] || die "build.sh: no platforms line"

[ -d "$dir" ] || die "$dir: no such directory"
[ -f "$dir/SHA256SUMS" ] || die "$dir: no SHA256SUMS"

download=$REPO_URL/releases/download/$RELEASE
list=
win=
n=0
for p in $platforms; do
	os=${p%/*}
	arch=${p#*/}
	# The same words as the table in README.md.
	case $p in
	windows/amd64) label='**Windows** x86-64 (amd64)' ;;
	windows/arm64) label='**Windows** ARM64' ;;
	linux/amd64) label='**Linux** x86-64 (amd64)' ;;
	linux/arm64) label='**Linux** ARM64 (aarch64)' ;;
	darwin/amd64) label='**macOS** Intel (amd64)' ;;
	darwin/arm64) label='**macOS** Apple silicon (arm64)' ;;
	*) die "no label for $p: add it here" ;;
	esac
	name=
	for ext in .tar.gz .zip; do
		f=dnstt-$RELEASE-$os-$arch$ext
		[ -f "$dir/$f" ] || continue
		[ -z "$name" ] || die "$dir: both $name and $f"
		name=$f
	done
	[ -n "$name" ] || die "$dir: no archive dnstt-$RELEASE-$os-$arch.tar.gz or .zip"
	awk -v f="$name" '$2 == f { found = 1 } END { exit !found }' "$dir/SHA256SUMS" ||
		die "$dir/SHA256SUMS: no $name"
	# The example in the checks below.
	[ "$p" != windows/amd64 ] || win=$name
	list="$list- $label: [$name]($download/$name)
"
	n=$((n + 1))
done
sums=$(awk 'END { print NR }' "$dir/SHA256SUMS")
[ "$sums" -eq "$n" ] || die "$dir/SHA256SUMS: $sums archives, build.sh has $n platforms"
[ -n "$win" ] || die "build.sh: no windows/amd64"

cat <<EOF
Unofficial build of [dnstt](https://www.bamsoftware.com/software/dnstt/) $TAG. It is not made or endorsed by the author of dnstt.

How to set up and use dnstt is on the [dnstt home page](https://www.bamsoftware.com/software/dnstt/) and in the \`README\` inside every archive. About these builds and how to check them: the [README]($REPO_URL#readme) of this repository.

## Download

$list- **Source** of dnstt $TAG: [zip]($MIRROR/archive/refs/tags/$TAG.zip) · [tar.gz]($MIRROR/archive/refs/tags/$TAG.tar.gz)
- **SHA-256 checksums**: [SHA256SUMS]($download/SHA256SUMS)

Each archive holds \`dnstt-client\` and \`dnstt-server\` (\`.exe\` on Windows) with \`README\`, \`CHANGELOG\` and \`COPYING\` from dnstt. The binaries are not code-signed: Windows SmartScreen may ask for confirmation, and if macOS Gatekeeper refuses to run them, see the [README]($REPO_URL#platforms).

## Build

- Upstream tag: \`$TAG\`, commit [\`$COMMIT\`]($MIRROR/commit/$COMMIT)
- Changes: [CHANGELOG]($MIRROR/blob/$TAG/CHANGELOG)
- Built with \`$GO_VERSION\`, \`CGO_ENABLED=0\`, by [this workflow run]($RUN_URL) from $REPO_URL/commit/$BUILD_COMMIT

Check a download (see the [README]($REPO_URL#verify-a-download)). On Windows, in PowerShell, compare the output with the line in \`SHA256SUMS\`:

\`\`\`powershell
(Get-FileHash $win -Algorithm SHA256).Hash.ToLower()
\`\`\`

On Linux (for macOS, see the README):

\`\`\`sh
sha256sum -c --ignore-missing SHA256SUMS
\`\`\`

The build provenance attestation, with the [GitHub CLI](https://cli.github.com/):

\`\`\`sh
gh attestation verify $win --repo $repo
\`\`\`
EOF
