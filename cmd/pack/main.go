// Command pack writes the release archives and SHA256SUMS for build.sh.
//
//	pack archive -mtime <unix seconds> -o <file.tar.gz|file.zip> <dir>
//	pack sums <dir>
//
// The archives are made here and not with tar, gzip and zip so that they come
// out byte for byte the same on every machine: the standard library of the
// pinned Go release does not depend on the local versions of those tools, on
// the time zone or on the umask.
//
// An archive holds <dir> itself and everything below it, names sorted. Every
// entry gets the same modification time, owner 0:0 without user and group
// names, and mode 0755 (directories and files with any execute bit) or 0644.
// Zip entries carry no extra fields.
package main

import (
	"archive/tar"
	"archive/zip"
	"bufio"
	"compress/flate"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	var err error
	switch os.Args[1] {
	case "archive":
		err = archiveCmd(os.Args[2:])
	case "sums":
		err = sumsCmd(os.Args[2:])
	default:
		usage()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "pack:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: pack archive -mtime <unix seconds> -o <file.tar.gz|file.zip> <dir>")
	fmt.Fprintln(os.Stderr, "       pack sums <dir>")
	os.Exit(2)
}

// entry is one file or directory of an archive.
type entry struct {
	name string // slash-separated, directories end with "/"
	path string // on disk
	dir  bool
	mode fs.FileMode
	size int64
}

func archiveCmd(args []string) error {
	fl := flag.NewFlagSet("archive", flag.ExitOnError)
	mtime := fl.Int64("mtime", -1, "modification time of every entry, unix seconds")
	out := fl.String("o", "", "output file, .tar.gz or .zip")
	fl.Parse(args)
	if fl.NArg() != 1 || *out == "" || *mtime < 0 {
		usage()
	}
	entries, err := collect(fl.Arg(0))
	if err != nil {
		return err
	}
	t := time.Unix(*mtime, 0).UTC()

	var write func(io.Writer, []entry, time.Time) error
	switch {
	case strings.HasSuffix(*out, ".tar.gz"):
		write = writeTarGz
	case strings.HasSuffix(*out, ".zip"):
		write = writeZip
	default:
		return fmt.Errorf("%s: want .tar.gz or .zip", *out)
	}
	f, err := os.OpenFile(*out, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	if err := write(f, entries, t); err != nil {
		f.Close()
		os.Remove(*out)
		return fmt.Errorf("%s: %w", *out, err)
	}
	return f.Close()
}

// collect lists root and everything below it in lexical order of names.
func collect(root string) ([]entry, error) {
	root = filepath.Clean(root)
	base := filepath.Base(root)
	var entries []entry
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		name := base
		if rel != "." {
			name = base + "/" + filepath.ToSlash(rel)
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		switch {
		case info.IsDir():
			entries = append(entries, entry{name: name + "/", path: path, dir: true, mode: 0o755})
		case info.Mode().IsRegular():
			mode := fs.FileMode(0o644)
			if info.Mode()&0o111 != 0 {
				mode = 0o755
			}
			entries = append(entries, entry{name: name, path: path, mode: mode, size: info.Size()})
		default:
			return fmt.Errorf("%s: not a regular file or directory", path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	// WalkDir already goes in lexical order; sort by archive name anyway, so
	// that the order does not hang on how the walk is done.
	sort.Slice(entries, func(i, j int) bool { return entries[i].name < entries[j].name })
	return entries, nil
}

func writeTarGz(w io.Writer, entries []entry, t time.Time) error {
	zw, err := gzip.NewWriterLevel(w, gzip.BestCompression)
	if err != nil {
		return err
	}
	// The gzip header keeps no name and no time.
	tw := tar.NewWriter(zw)
	for _, e := range entries {
		hdr := &tar.Header{
			Name:    e.name,
			Mode:    int64(e.mode),
			ModTime: t,
			Format:  tar.FormatUSTAR,
		}
		if e.dir {
			hdr.Typeflag = tar.TypeDir
		} else {
			hdr.Typeflag = tar.TypeReg
			hdr.Size = e.size
		}
		if err := tw.WriteHeader(hdr); err != nil {
			return err
		}
		if !e.dir {
			if err := copyFile(tw, e); err != nil {
				return err
			}
		}
	}
	if err := tw.Close(); err != nil {
		return err
	}
	return zw.Close()
}

func writeZip(w io.Writer, entries []entry, t time.Time) error {
	zw := zip.NewWriter(w)
	zw.RegisterCompressor(zip.Deflate, func(w io.Writer) (io.WriteCloser, error) {
		return flate.NewWriter(w, flate.BestCompression)
	})
	date, clock := msDosTime(t)
	for _, e := range entries {
		// Only the MS-DOS time fields: setting Modified would add an
		// extended timestamp extra field to every entry.
		hdr := &zip.FileHeader{
			Name:         e.name,
			Method:       zip.Deflate,
			ModifiedDate: date,
			ModifiedTime: clock,
		}
		if e.dir {
			hdr.Method = zip.Store
			hdr.SetMode(fs.ModeDir | e.mode)
		} else {
			hdr.SetMode(e.mode)
		}
		fw, err := zw.CreateHeader(hdr)
		if err != nil {
			return err
		}
		if !e.dir {
			if err := copyFile(fw, e); err != nil {
				return err
			}
		}
	}
	return zw.Close()
}

// msDosTime packs t, taken as is (UTC), into the MS-DOS date and time fields.
func msDosTime(t time.Time) (date, clock uint16) {
	date = uint16(t.Day() + int(t.Month())<<5 + (t.Year()-1980)<<9)
	clock = uint16(t.Second()/2 + t.Minute()<<5 + t.Hour()<<11)
	return date, clock
}

func copyFile(w io.Writer, e entry) error {
	f, err := os.Open(e.path)
	if err != nil {
		return err
	}
	defer f.Close()
	n, err := io.Copy(w, f)
	if err != nil {
		return err
	}
	if n != e.size {
		return fmt.Errorf("%s: size changed while packing", e.path)
	}
	return nil
}

// sumsCmd writes <dir>/SHA256SUMS for the archives in dir, in the format of
// sha256sum, names sorted.
func sumsCmd(args []string) error {
	if len(args) != 1 {
		usage()
	}
	dir := args[0]
	des, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	var names []string
	for _, de := range des {
		n := de.Name()
		if de.Type().IsRegular() && (strings.HasSuffix(n, ".tar.gz") || strings.HasSuffix(n, ".zip")) {
			names = append(names, n)
		}
	}
	if len(names) == 0 {
		return errors.New(dir + ": no archives")
	}
	sort.Strings(names)

	out, err := os.OpenFile(filepath.Join(dir, "SHA256SUMS"), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	bw := bufio.NewWriter(out)
	for _, n := range names {
		sum, err := sha256File(filepath.Join(dir, n))
		if err != nil {
			out.Close()
			return err
		}
		fmt.Fprintf(bw, "%s  %s\n", sum, n)
	}
	if err := bw.Flush(); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func sha256File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
