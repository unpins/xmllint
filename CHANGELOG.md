# Changelog

## [Unreleased]

### Fixed

- `xmllint` looked for its default XML and SGML catalogs inside the build
  directory of the machine that produced the binary — a path that exists
  nowhere else — so catalog resolution never worked and `xmllint --help`
  printed that path back at you. Both now point at `/etc/xml/catalog` and
  `/etc/sgml/catalog` (`C:/etc/...` on Windows), where a distribution puts
  them; `XML_CATALOG_FILES` still overrides.
- Gzipped XML (`xmllint doc.xml.gz`) failed to parse. It now reads compressed
  input like a distribution build does.
