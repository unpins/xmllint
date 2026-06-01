{
  description = "Standalone build of the libxml2 CLIs (xmllint + xmlcatalog)";

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
  # both once on the build host (OS-independent text) and embed the same bytes
  # on every target — natively via multicall's install, on Windows via
  # winManRoot (the mingw cross can't run the generator either).
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      pkgsX = unpins-lib.inputs.nixpkgs.legacyPackages.x86_64-linux;
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
      # winManRoot may stay x86_64-pinned: the windows binary always builds on an
      # x86_64-linux runner (per the topology hardcoded-x86_64 trap note).
      winManRoot = mkMan pkgsX;
      # Canonical binary == package name (xmllint); `xmllint --version` exits 0
      # and prints the libxml version banner. A non-empty smoke arg is required:
      # an empty array trips `set -u` empty-array expansion on the macOS runners'
      # bash 3.2.
      smoke = [ "--version" ];
      smokePattern = "libxml version 215";
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; xmlMan = mkMan pkgs.buildPackages; xml = pkgs.pkgsStatic.libxml2; };
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; xmlMan = mkMan pkgs.buildPackages; xml = (ulib.mingwStaticCross pkgs).libxml2; };
    };
}
