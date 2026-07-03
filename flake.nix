{
  description = "the libxml2 CLIs (xmllint + xmlcatalog) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libxml2 installs two CLIs (xmllint, xmlcatalog); ./multicall.nix post-links
  # them into one `xmllint` dispatcher binary with `xmlcatalog` as an argv[0]
  # UNPIN_META alias (canonical binary == package name, per the unpins
  # convention — CI resolves result/bin/<name>). Windows goes through mingw —
  # libxml2 is portable autotools C that cross-compiles cleanly.
  #
  # Man pages: libxml2 ships xmllint/xmlcatalog man as DocBook XML
  # (doc/<tool>.xml) that nixpkgs never builds (no docbook toolchain). Generate
  # both on the build host (OS-independent text) and embed the same bytes on
  # every target — multicall.nix installs them into the binary's share/man on
  # EVERY target (windows included, since the generator is a buildPackages
  # nativeBuildInput that runs on the x86_64-linux runner), so each build
  # harvests its OWN man. No graft.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      # Generate the two man pages from libxml2's DocBook sources. Built with a
      # build-host (`buildPackages`) toolchain so it is NATIVE to whatever runner
      # builds each target — a hardcoded x86_64-linux man derivation would make
      # the native aarch64 build depend on an x86_64 builder it doesn't have. The
      # output bytes are host-independent, so every arch's copy is identical.
      mkMan = bp: bp.runCommand "xmllint-man"
        { nativeBuildInputs = [ bp.libxslt bp.docbook_xsl_ns ]; }
        ''
          mkdir -p "$out/share/man/man1"
          for p in xmllint xmlcatalog; do
            xsltproc --nonet --novalid --param man.output.quietly 1 \
              -o "$out/share/man/man1/$p.1" \
              ${bp.docbook_xsl_ns}/xml/xsl/docbook/manpages/docbook.xsl \
              ${bp.libxml2.src}/doc/$p.xml
          done
        '';
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "xmllint";
      # Canonical binary == package name (xmllint); `xmllint --version` exits 0
      # and prints the libxml version banner. A non-empty smoke arg is required:
      # an empty array trips `set -u` empty-array expansion on the macOS runners'
      # bash 3.2.
      smoke = [ "--version" ];
      smokePattern = "libxml version 215";

      # Build via the unpin-llvm engine + emit a bitcode multicall module. On
      # BOTH Linux and darwin (mac-on-mac) the engine compiles pkgsStatic.libxml2
      # (xmllint + xmlcatalog) to bitcode and the standalone self-folds them into
      # one `xmllint` binary. ./multicall.nix's objcopy fold can't run on the
      # engine's -flto bitcode objects, so it's windows-only now (windowsBuild).
      # Pure C — no requires.cxx. pkgsAttr=libxml2 (name ≠ attr); the canonical
      # bare smoke (`xmllint --version`) is itself an applet, so no defaultProgram
      # needed. Man is restaged onto the engine build so withMan embeds it (nixpkgs
      # builds no libxml2 man).
      pkgsAttr = "libxml2";
      engine = "unpin-llvm";
      multicall = {
        programs = [ { name = "xmllint"; } { name = "xmlcatalog"; } ];
      };
      # engine path (Linux + darwin): apps → bitcode → selfFold. Restage the
      # generated man pages into the build's share/man (libxml2 multi-output: bin
      # holds the CLIs).
      build = pkgs:
        pkgs.pkgsStatic.libxml2.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            mkdir -p "$bin/share/man/man1"
            cp ${(mkMan pkgs.buildPackages)}/share/man/man1/xmllint.1    "$bin/share/man/man1/xmllint.1"
            cp ${(mkMan pkgs.buildPackages)}/share/man/man1/xmlcatalog.1 "$bin/share/man/man1/xmlcatalog.1"
          '';
        } // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          # mkStandaloneFlake's filterEnableStaticOnDarwin strips libxml2's Nix-level
          # `--disable-shared` (so `--enable-static` can't become LDFLAGS=-static and
          # break the libSystem probe). Push it back via the bash configureFlagsArray
          # — invisible to that Nix-list filter — so libtool skips its darwin shared-
          # library link probe, which otherwise mis-drives the engine linker
          # (-platform_version → ld.lld, -soname → ld64.lld). Same dodge as jq/tmux/file.
          preConfigure = (old.preConfigure or "") + ''
            configureFlagsArray+=("--disable-shared")
          '';
        });
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; xmlMan = mkMan pkgs.buildPackages; xml = (ulib.mingwStaticCross pkgs).libxml2; };
    };
}
