# xmllint

The [libxml2](https://gitlab.gnome.org/GNOME/libxml2) command-line programs — `xmllint` and `xmlcatalog` — as a single self-contained binary built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/xmllint/actions/workflows/xmllint.yml/badge.svg)](https://github.com/unpins/xmllint/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install xmllint`.

Both programs share one binary with `libxml2` linked in statically.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin xmllint --noout --schema s.xsd doc.xml
unpin xmllint xmlcatalog --version
```

To install the programs onto your PATH:

```bash
unpin install xmllint
```

`unpin install xmllint` also creates the `xmlcatalog` command.

## Programs

| command | what it does |
| --- | --- |
| `xmllint` | parse, validate (DTD / RelaxNG / Schema), reformat and query (XPath) XML |
| `xmlcatalog` | manage XML / SGML catalogs |

## Man pages

`xmllint.1` and `xmlcatalog.1` are embedded in the binary — read with `unpin man xmllint` / `unpin man xmlcatalog`.

## Build locally

```bash
nix build github:unpins/xmllint
./result/bin/xmllint --version
```

Or run directly:

```bash
nix run github:unpins/xmllint -- --noout --schema schema.xsd doc.xml
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/xmllint/releases) page has standalone binaries for manual download.

## Build notes

- **Multicall:** one binary dispatches on `argv[0]` — `xmllint` (canonical) and `xmlcatalog`. `libxml2` is linked in statically.
- **Man pages:** generated from libxml2's DocBook sources (nixpkgs ships none) and embedded on every platform.
- **Windows:** `mingw` cross, single `.exe`, no companion DLLs.
- **No upstream features disabled** on any platform.
