{
  lib,
  stdenvNoCC,
  mdbook,
  writeShellApplication,
  python3,
  optionPackages,
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

    ${lib.concatMapStringsSep "\n" (option: ''
      echo "[${option.title}](${option.name}.md)" >> src/SUMMARY.md
      echo "" >> src/SUMMARY.md
      ln -s ${option.value} src/${option.name}.md
    '') optionPackages}

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
