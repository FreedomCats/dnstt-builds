module github.com/FreedomCats/dnstt-builds

// The Go release that builds dnstt. build.sh runs exactly this toolchain
// (GOTOOLCHAIN), and the workflow installs it with setup-go. Changing it
// changes the binaries: rebuild a released tag with a new suffix.
go 1.26.10
