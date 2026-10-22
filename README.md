# dnstt builds

[Русский](README.ru.md)

Unofficial, reproducible builds of [dnstt](https://www.bamsoftware.com/software/dnstt/),
the DNS tunnel by David Fifield. **These builds are not made or endorsed by the author of
dnstt.** The code is upstream dnstt as is, built from its release tags without changes.

- dnstt home page and documentation: <https://www.bamsoftware.com/software/dnstt/>
- upstream repository: <https://www.bamsoftware.com/git/dnstt.git>
- mirror the builds are made from: <https://github.com/FreedomCats/dnstt>

How to set up and use dnstt is described on the
[dnstt home page](https://www.bamsoftware.com/software/dnstt/) and in the `README` inside
every archive; it is not repeated here.

## Platforms

| System  | Architecture          | Archive                                      |
|---------|-----------------------|----------------------------------------------|
| Linux   | x86-64 (amd64)        | `dnstt-<version>-linux-amd64.tar.gz`         |
| Linux   | ARM64 (aarch64)       | `dnstt-<version>-linux-arm64.tar.gz`         |
| Windows | x86-64 (amd64)        | `dnstt-<version>-windows-amd64.zip`          |
| Windows | ARM64                 | `dnstt-<version>-windows-arm64.zip`          |
| macOS   | Intel (amd64)         | `dnstt-<version>-darwin-amd64.tar.gz`        |
| macOS   | Apple silicon (arm64) | `dnstt-<version>-darwin-arm64.tar.gz`        |

Each archive holds one directory with `dnstt-client` and `dnstt-server` (`.exe` on
Windows) and `README`, `CHANGELOG` and `COPYING` from dnstt. The programs are static Go
binaries (`CGO_ENABLED=0`) and need nothing else.

`<version>` is the upstream tag, such as `v1.20260501.0`. A rebuild of the same tag, for
example with a newer Go, gets a suffix: `v1.20260501.0-1`.

The binaries are not code-signed. On macOS, if Gatekeeper refuses to run them, remove the
quarantine flag: `xattr -d com.apple.quarantine dnstt-client dnstt-server`. On Windows,
SmartScreen may ask for confirmation.

## Verify a download

Download the archive for your platform and `SHA256SUMS` from
[Releases](https://github.com/FreedomCats/dnstt-builds/releases), then check the
checksum:

```sh
# Linux
sha256sum -c --ignore-missing SHA256SUMS
# macOS
grep dnstt-v1.20260501.0-darwin-arm64.tar.gz SHA256SUMS | shasum -a 256 -c
```

```powershell
# Windows (PowerShell): compare with the line in SHA256SUMS
(Get-FileHash dnstt-v1.20260501.0-windows-amd64.zip -Algorithm SHA256).Hash.ToLower()
```

Every archive also has a build provenance attestation: a signed statement that it was
built by the release workflow of this repository, from which commit and in which
workflow run. Check it with the [GitHub CLI](https://cli.github.com/):

```sh
gh attestation verify dnstt-v1.20260501.0-linux-amd64.tar.gz --repo FreedomCats/dnstt-builds
```

## Build the same yourself

The build is reproducible: the same tag built with the same `build.sh` gives archives
byte for byte equal to the released ones, so you can check a release without trusting
GitHub. You need `git`, a POSIX shell and Go 1.21 or newer; Linux or macOS (on Windows,
use WSL). The exact Go release is the `go` line in [`go.mod`](go.mod); `build.sh` fetches
and runs that release through `GOTOOLCHAIN`, whatever Go is installed (it is downloaded
from the Go module proxy, so `proxy.golang.org` must be reachable, or set `GOPROXY`).

```sh
# This repository at the release (its tag is the release name)
git clone --branch v1.20260501.0 https://github.com/FreedomCats/dnstt-builds
# dnstt at the upstream tag: the mirror or upstream, the commit is the same
git clone --branch v1.20260501.0 https://github.com/FreedomCats/dnstt
#   or: git clone --branch v1.20260501.0 https://www.bamsoftware.com/git/dnstt.git dnstt

dnstt-builds/build.sh dnstt v1.20260501.0 out
diff out/SHA256SUMS SHA256SUMS    # SHA256SUMS of the release: no output if equal
```

For a rebuild such as `v1.20260501.0-1`, clone this repository at `v1.20260501.0-1` and
pass the suffix as the fourth argument: `build.sh dnstt v1.20260501.0 out 1`.

What `build.sh` does:

- refuses a tag that is not in [`versions.txt`](versions.txt), a checkout whose `HEAD` or
  tag is another commit than the one listed there, and a checkout with local changes;
- builds both programs for every platform with `-trimpath`, `-ldflags "-s -w -buildid="`
  and `CGO_ENABLED=0`, ignoring the Go settings of your machine (`go env -w`, `GOFLAGS`,
  `GOAMD64` and the like);
- packs the archives with a small Go program ([`cmd/pack`](cmd/pack/main.go)) and not
  with `tar` or `zip`, so that they do not depend on the local tools, time zone or
  umask: names sorted, owner 0:0, the commit time of the tag as the time of every file;
- writes `SHA256SUMS`.

The binaries record the Go version, the upstream commit and the build settings; see them
with `go version -m dnstt-client`.

## Releasing (for maintainers)

1. To build a new upstream tag, add it to `versions.txt` with its full commit hash. Take
   the hash from upstream and check that the mirror has the same one (the mirror must
   be updated first):

   ```sh
   git ls-remote --tags https://www.bamsoftware.com/git/dnstt.git 'refs/tags/<tag>^{}'
   git ls-remote --tags https://github.com/FreedomCats/dnstt 'refs/tags/<tag>^{}'
   ```

   Commit and push to `main`.
2. In Actions, run the **release** workflow from `main`: `tag` is the upstream tag;
   `suffix` stays empty for the first build of a tag and is `1`, `2`, ... for rebuilds
   (for example after changing the Go release in `go.mod`); `draft` is on by default.
3. The workflow checks the commit, runs the upstream tests, builds, attests and creates
   the release (a draft by default). Look at the draft and publish it on the Releases
   page; publishing creates the tag in this repository.

The body of the release is written by [`release-notes.sh`](release-notes.sh): links to
every archive, the dnstt source and `SHA256SUMS`, and what was built. To rewrite the body
of an existing release, download its archives (`gh release download <release>`), run the
script on them with the values of its run (listed at the top of the script) and pass the
output to `gh release edit <release> --notes-file`.

An existing release or tag is never replaced: the workflow stops instead. Run from any
branch other than `main`, the workflow only builds and leaves the archives as an artifact
of the run.

Run a release only once this repository is public: on the free plan the provenance
attestation step fails in a private repository, and no release is created.

## License

The scripts and documents of this repository are dedicated to the public domain under
[CC0 1.0](COPYING), as dnstt itself is. dnstt is by David Fifield; its own `COPYING` is in
every archive.
