# libxml2 installs two command-line tools — xmllint (lint/validate/query XML)
# and xmlcatalog (manage XML/SGML catalogs). To honour the unpins
# one-pkg-one-bin rule we post-link them into a single multicall binary at
# $out/bin/xmllint (a busybox-style dispatcher named after the package, as the
# unpins CI resolves result/bin/<package-name>); `lib.withAliases` then embeds
# `xmlcatalog` as an UNPIN_META alias so unpin's installer recreates the
# argv[0] shim.
#
# This is the *easy* end of the multicall spectrum. The autotools build leaves
# each frontend's objects in the build root (automake `<tool>-<src>.o`), and
# each exports exactly ONE strong global: xmllint-xmllint.o → `xmllintMain`,
# xmllint-shell.o → `xmllintShell`, xmlcatalog-xmlcatalog.o → `main`. So there
# is nothing to disambiguate except xmlcatalog's `main`: rename it to
# `xmlcatalog_main` (objcopy --redefine-sym) and drop xmllint's `main` wrapper
# (lintmain.o) entirely. The dispatch front-end is the shared
# `lib.multicallDispatcherC`; it calls each applet as `<applet>_main`, so
# xmlcatalog_main matches directly and `xmllint_shim.c` adapts xmllintMain's
# wider signature to `xmllint_main`. The whole library is the single static
# archive `.libs/libxml2.a`, linked once; building it ourselves also sidesteps
# the darwin libtool dynamic-companion trap (the stock frontends link
# libxml2.2.dylib on pkgsStatic-darwin).
#
# Man pages are generated once on the build host from the DocBook sources
# (see flake.nix) and copied in; nixpkgs builds no man for libxml2.
#
# Shared by the native `build` (pkgsStatic) and `windowsBuild`
# (mingwStaticCross); isDarwin/isWindows come from the INPUT derivation's
# stdenv (under windowsBuild `pkgs` is the x86_64-linux root — the cross lives
# inside mingwStaticCross — so `pkgs.stdenv` would wrongly say "not Windows").
{ lib }:
{ pkgs, xml, xmlMan }:
let
  isDarwin = xml.stdenv.hostPlatform.isDarwin or false;
  isWindows = xml.stdenv.hostPlatform.isWindows or false;

  # Keep libxml2's stock outputs (bin/dev/out) and its install — its multiple-
  # outputs setup hook needs them and fighting it isn't worth it. We just build
  # the multicall binary in postBuild and SWAP the two stock frontends for it in
  # postInstall (binary + man land in the `bin` output, where withMan/withAliases
  # operate). `mc/` is relative to the (unchanged) build dir across both phases.
  multicall = xml.overrideAttrs (old: {
    pname = "xmllint-multi";

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p mc

      # Mach-O leads C symbols with '_'; detect from a known frontend symbol.
      if $NM --defined-only xmllint-xmllint.o 2>/dev/null \
           | awk '$3=="_xmllintMain"{f=1} END{exit !f}'; then up=_; else up=""; fi

      # The single libxml2 static archive. Take it from the unwrapped static
      # input's install (xml.out), not this build's .libs/: on darwin
      # mkStandaloneFlake's filterEnableStaticOnDarwin strips --disable-shared,
      # so the wrapped build emits only a dylib and no .libs/libxml2.a — but the
      # frontend objects are still produced here, and xml.out (== the cached
      # upstream static libxml2) carries the archive on every platform. Linking
      # the .a ourselves also sidesteps the darwin libtool dynamic-companion trap.
      A="${xml.out}/lib/libxml2.a"

      # xmlcatalog owns `main` → rename to `xmlcatalog_main`. objcopy rewrites
      # the definition; the dispatcher resolves it. (xmllint's frontends export
      # only xmllintMain/xmllintShell, so they need no rename.)
      cp xmlcatalog-xmlcatalog.o mc/xmlcatalog.o
      printf '%smain %sxmlcatalog_main\n' "$up" "$up" > mc/xmlcatalog.redef
      $OBJCOPY --redefine-syms=mc/xmlcatalog.redef mc/xmlcatalog.o

      # Multicall dispatcher via the shared nix-lib generator — one contract for
      # the whole catalog (argv[0] alias path + a `--unpin-program=NAME` selector
      # on the bare binary). It calls each applet as `<applet>_main(int,char**)`:
      # xmlcatalog_main is the renamed object above; xmllint_main is the shim
      # (xmllintMain has a wider signature — see xmllint_shim.c). defaultApplet =
      # "xmllint" makes a bare or renamed binary (CI's smoke.exe) default to
      # xmllint, the canonical tool, so `<bin> --version` prints the libxml banner.
      mkdir -p multicall
      printf '%s\n' xmllint xmlcatalog > multicall/apps.list
      cp ${./xmllint_shim.c} mc/xmllint_shim.c
      $CC -O2 -c -o mc/xmllint_shim.o mc/xmllint_shim.c
${lib.multicallDispatcherC { name = "xmllint"; defaultApplet = "xmllint"; }}
      $CC -O2 -c -o mc/dispatcher.o multicall/dispatcher.c

      # Final link: the two frontends' kept objects + the renamed xmlcatalog
      # object + the single libxml2 static archive, once. On mingw this manual
      # link bypasses the `-static` the normal build applies, so the gcc `mcf`
      # thread model would import libmcfgthread-2.dll next to the .exe; link the
      # runtime fully static so every implicit -l resolves to its .a. Per-platform
      # external libs libxml2.a pulls (it links the .a directly, bypassing the
      # .pc): Windows seeds dict.c from BCryptGenRandom → -lbcrypt; darwin's iconv
      # lives in a separate libiconv (it's in libc on musl) → -liconv. Both come
      # after the archive that references them.
      MCF=""
      ${lib.optionalString isWindows ''MCF="-static -lbcrypt"''}
      ${lib.optionalString isDarwin ''MCF="-liconv"''}
      $CC -O2 \
        mc/dispatcher.o mc/xmllint_shim.o xmllint-xmllint.o xmllint-shell.o mc/xmlcatalog.o \
        "$A" -lm $MCF \
        -o mc/xmllint
      [ -f mc/xmllint ] || mv mc/xmllint.exe mc/xmllint
    '';

    postInstall = (old.postInstall or "") + ''
      # Replace the stock frontends with the single multicall binary. On mingw
      # the stock install names them `*.exe`, so remove both spellings — else the
      # real xmllint.exe/xmlcatalog.exe survive next to ours (extra companion
      # binaries, and the wrong one wins the .exe name).
      rm -f "$bin/bin/xmllint" "$bin/bin/xmllint.exe" \
            "$bin/bin/xmlcatalog" "$bin/bin/xmlcatalog.exe"
      install -m755 mc/xmllint "$bin/bin/xmllint"
      ln -s xmllint "$bin/bin/xmlcatalog"
      # Man generated on the build host from the DocBook sources (flake.nix);
      # nixpkgs builds none. Lands in the bin output for withMan to embed.
      mkdir -p "$bin/share/man/man1"
      cp ${xmlMan}/share/man/man1/xmllint.1    "$bin/share/man/man1/xmllint.1"
      cp ${xmlMan}/share/man/man1/xmlcatalog.1 "$bin/share/man/man1/xmlcatalog.1"
    '';
  });

  aliased = lib.withAliases pkgs
    {
      primary = "xmllint";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  # Binaries live in the `bin` output, not `out` (libxml2 is multi-output).
  postFixup = (o.postFixup or "") + ''
    [ -f "$bin/bin/xmllint" ] && mv "$bin/bin/xmllint" "$bin/bin/xmllint.exe"
  '';
})
else aliased
