{
  lib,
  stdenvNoCC,
  mdbook,
  writeShellApplication,
  python3,
  sections,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  name = "book";
  nativeBuildInputs = [ mdbook ];
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./book.toml
      ./src
    ];
  };
  buildPhase = ''
    runHook preBuild

    ln -s ${../README.md} src/README.md

    ${lib.concatMapStringsSep "\n" (section: ''
      echo "" >> src/SUMMARY.md
      echo "# ${section.title}" >> src/SUMMARY.md
      echo "" >> src/SUMMARY.md
      mkdir -p src/${section.prefix}
      ${lib.concatMapStringsSep "\n" (page: ''
        echo "- [${page.title}](${section.prefix}/${page.name}.md)" >> src/SUMMARY.md
        ln -s ${page.value} src/${section.prefix}/${page.name}.md
      '') section.pages}
    '') sections}

    mdbook build

    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall

    mv book $out

    runHook postInstall
  '';
  passthru.serve = writeShellApplication {
    name = "serve";
    runtimeInputs = [ python3 ];
    text = ''
      python -m http.server \
        --bind 127.0.0.1 \
        --directory ${finalAttrs.finalPackage}
    '';
  };
})
