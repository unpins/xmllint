{
  description = "the libxml2 CLIs (xmllint + xmlcatalog) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libxml2 installs two CLIs (xmllint, xmlcatalog); nix-lib folds them into
  # one `xmllint` dispatcher binary with `xmlcatalog` as an argv[0]
  # UNPIN_META alias (canonical binary == package name, per the unpins
  # convention — CI resolves result/bin/<name>). Windows goes through mingw —
  # libxml2 is portable autotools C that cross-compiles cleanly.
  #
  # Man pages: libxml2 ships xmllint/xmlcatalog man as DocBook XML
  # (doc/<tool>.xml) that nixpkgs never builds (no docbook toolchain). Generate
  # both on the build host (OS-independent text) and restage the same bytes into
  # every target's share/man (windows included — the generator runs on the
  # build host either way), so each build harvests its OWN man. No graft.
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
      restageMan = pkgs: drv: drv.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          mkdir -p "$bin/share/man/man1"
          cp ${(mkMan pkgs.buildPackages)}/share/man/man1/xmllint.1    "$bin/share/man/man1/xmllint.1"
          cp ${(mkMan pkgs.buildPackages)}/share/man/man1/xmlcatalog.1 "$bin/share/man/man1/xmlcatalog.1"
        '';
      });
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
      # every target the engine compiles libxml2 (xmllint + xmlcatalog) to
      # bitcode and the standalone self-folds them into one `xmllint` binary.
      # Pure C — no requires.cxx. pkgsAttr=libxml2 (name ≠ attr); the canonical
      # bare smoke (`xmllint --version`) is itself an applet, so no defaultProgram
      # needed. Man is restaged onto the engine build so withMan embeds it (nixpkgs
      # builds no libxml2 man).
      pkgsAttr = "libxml2";
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [ { name = "xmllint"; } { name = "xmlcatalog"; } ];
      };
      # Restage the generated man pages into the build's share/man (libxml2 is
      # multi-output: `bin` holds the CLIs).
      build = pkgs:
        let base = restageMan pkgs pkgs.pkgsStatic.libxml2; in
        base.overrideAttrs (old: {
          # nixpkgs builds libxml2 --without-zlib (upstream's own default), so
          # `xmllint doc.xml.gz` failed with "Start tag expected" while every
          # distribution build reads it. zlib is the only real feature 2.15
          # still gates behind a flag -- HTTP is removed upstream (--with-http
          # only restores ABI stubs) and lzma is gone entirely -- so this is
          # what "no upstream features disabled" costs here.
          # (The store-path catalog default is retargeted set-wide in
          # nix-lib/native-overlay/libxml2.nix, since chafa/avif/biber carried
          # it through the library too.)
          configureFlags = (old.configureFlags or [ ]) ++ [ "--with-zlib" ];
          buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.pkgsStatic.zlib ];
          doCheck = base.stdenv.buildPlatform.canExecute base.stdenv.hostPlatform;
          # The suite passes whole (3879 regression tests + 49 recursion tests,
          # no errors) except `testModule`, which dlopen()s a built .so to prove
          # the module loader works. There is no .so in a static build and
          # never will be, so it fails "Failed to open module" — a test of a
          # feature this package does not ship. Drop that one line from
          # check-local; everything else in it runs.
          # (nixpkgs carries libxml2's phase hooks as LISTS, not strings.)
          preCheck = (old.preCheck or [ ]) ++ [
            ''
              substituteInPlace Makefile \
                --replace-fail '$(CHECKER) ./testModule$(EXEEXT)' 'true'
            ''
          ];
        } //
          pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
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
      # zlib as above; the sysconfdir retarget comes from
      # nix-lib/mingw-overlay/libxml2.nix.
      windowsBuild = pkgs:
        let mw = ulib.mingwStaticCross pkgs; in
        (restageMan pkgs mw.libxml2).overrideAttrs (old: {
          configureFlags = (old.configureFlags or [ ]) ++ [ "--with-zlib" ];
          buildInputs = (old.buildInputs or [ ]) ++ [ mw.zlib ];
        });
    };
}
