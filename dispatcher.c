/*
 * Multicall dispatcher for the unpins `xmllint` package.
 *
 * libxml2 ships two CLIs — xmllint and xmlcatalog. We fold them into one
 * binary: xmllint's logic is reachable as `xmllintMain` (its lintmain.c `main`
 * wrapper is dropped), and xmlcatalog's `main` is renamed to `xmlcatalog_main`
 * by objcopy at build time. This dispatcher picks the entry point from
 * basename(argv[0]); the canonical name `xmllint` runs xmllintMain, so a bare
 * `xmllint --version` is the clean smoke target. An unrecognised argv[0] (e.g.
 * the CI smoke renames the binary to `smoke.exe`) first tries `<bin> <tool>
 * [args]`, then falls through to xmllintMain — xmllint is the canonical tool,
 * so `smoke.exe --version` prints the libxml version banner like the real name.
 */
#include <string.h>
#include <stdio.h>

/* From xmllint.c (kept) — lintmain.c's main() is left out of the link. */
int xmllintMain(int argc, const char **argv, FILE *errStream, void *loader);
/* From xmlcatalog.c, with main renamed to xmlcatalog_main by objcopy. */
int xmlcatalog_main(int argc, char **argv);

static void base_of(char *d, size_t cap, const char *s) {
    const char *p = s, *x;
    x = strrchr(p, '/'); if (x) p = x + 1;
#ifdef _WIN32
    x = strrchr(p, '\\'); if (x) p = x + 1;
#endif
    size_t n = strlen(p); if (n >= cap) n = cap - 1;
    memcpy(d, p, n); d[n] = 0;
    if (n > 4 && strcmp(d + n - 4, ".exe") == 0) d[n - 4] = 0;
}

int main(int argc, char **argv) {
    char b[64];
    base_of(b, sizeof b, (argc > 0 && argv[0]) ? argv[0] : "xmllint");
    if (strcmp(b, "xmlcatalog") == 0) return xmlcatalog_main(argc, argv);
    if (strcmp(b, "xmllint") == 0)    return xmllintMain(argc, (const char **)argv, stderr, NULL);
    /* unknown argv[0]: allow `<bin> <tool> [args]` ... */
    if (argc >= 2) {
        char c[64]; base_of(c, sizeof c, argv[1]);
        if (strcmp(c, "xmlcatalog") == 0) return xmlcatalog_main(argc - 1, argv + 1);
        if (strcmp(c, "xmllint") == 0)    return xmllintMain(argc - 1, (const char **)(argv + 1), stderr, NULL);
    }
    /* ... otherwise default to xmllint, the canonical tool. */
    return xmllintMain(argc, (const char **)argv, stderr, NULL);
}
