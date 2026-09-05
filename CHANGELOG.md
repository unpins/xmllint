# Changelog

## [Unreleased]

### Fixed

- The README's `xmlcatalog` example ran `unpin xmllint xmlcatalog --version`,
  which does not select `xmlcatalog` at all: the name is taken as a filename,
  so `xmllint` itself runs and prints its own version banner followed by
  "Can't open xmlcatalog". Pick a program with `--unpin-program=`, as the
  example now does. (`xmlcatalog` has no `--version` either.)
- `xmllint` looked for its default XML and SGML catalogs inside the build
  directory of the machine that produced the binary — a path that exists
  nowhere else — so catalog resolution never worked and `xmllint --help`
  printed that path back at you. Both now point at `/etc/xml/catalog` and
  `/etc/sgml/catalog` (`C:/etc/...` on Windows), where a distribution puts
  them; `XML_CATALOG_FILES` still overrides.
- Gzipped XML (`xmllint doc.xml.gz`) failed to parse. It now reads compressed
  input like a distribution build does.
