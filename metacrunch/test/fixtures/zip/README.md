# ZIP archives of other writers

The tests read these archives to check the ZIP reader against writers that the test builder does not imitate:
Windows XP, 7-Zip, Info-ZIP, macOS, WinRAR, WinZip and Go.

They come unchanged from the test data of Go's `archive/zip` package:
<https://github.com/golang/go/tree/3a9c8e1d9067525fec32c186cd562c4e3e56264b/src/archive/zip/testdata>. Go keeps
`go-no-datadesc-sig.zip` as a Base64 file, `go-no-datadesc-sig.zip.base64`; it is decoded here.

They are under Go's BSD-3-Clause license, which is in [LICENSE](LICENSE).

| File | |
|---|---|
| `comment-truncated.zip` | an end record whose comment is cut off |
| `crc32-not-streamed.zip` | a data descriptor, with the CRC32 also in the local header |
| `dd.zip` | a data descriptor |
| `go-no-datadesc-sig.zip` | a data descriptor without its signature |
| `symlink.zip` | a symlink |
| `test-trailing-junk.zip` | bytes after the end record |
| `unix.zip` | Unix modes |
| `utf8-7zip.zip`, `utf8-infozip.zip`, `utf8-osx.zip`, `utf8-winrar.zip`, `utf8-winzip.zip` | a UTF-8 name, as each writer stores it |
| `winxp.zip` | written by Windows XP |
| `zip64.zip`, `zip64-2.zip` | Zip64 |
