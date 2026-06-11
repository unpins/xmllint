/*
 * One-symbol shim for the unpins `xmllint` multicall.
 *
 * The shared nix-lib dispatcher (lib.multicallDispatcherC) calls each applet as
 * `<applet>_main(int, char **)`. xmlcatalog already matches — its `main` is
 * renamed to `xmlcatalog_main` by objcopy at build time. xmllint's frontend
 * instead exports `xmllintMain` (lintmain.c's `main` wrapper is dropped) with a
 * wider signature, so adapt it to the `xmllint_main(int, char **)` the generator
 * expects. All dispatch policy lives in the shared generator; this file is just
 * the signature glue.
 */
#include <stdio.h>

int xmllintMain(int argc, const char **argv, FILE *errStream, void *loader);

int xmllint_main(int argc, char **argv) {
    return xmllintMain(argc, (const char **)argv, stderr, NULL);
}
