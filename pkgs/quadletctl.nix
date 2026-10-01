{
  lib,
  writeShellApplication,
  argc,
  installShellFiles,
  podman,
  util-linux,
}:
writeShellApplication {
  name = "quadletctl";
  # The modules install the table of their units, so the package does not depend on them.
  text = lib.readFile ./quadletctl.sh;
  runtimeInputs = [
    argc
    podman
    util-linux
  ];
  # argc leaves the variables of absent parameters unset.
  bashOptions = [
    "errexit"
    "pipefail"
  ];
  # argc assigns the variables of the parameters and calls the functions of the subcommands.
  excludeShellChecks = [
    "SC2154"
    "SC2329"
  ];
  derivationArgs.nativeBuildInputs = [
    argc
    installShellFiles
  ];
  # argc names the man pages and completions after the file.
  # The completions call argc at runtime, and zsh autoloads its file as the completion function,
  # which has to define the completer first.
  derivationArgs.postCheck = ''
    argc --argc-mangen "$target" man
    installManPage man/*
    for shell in bash fish zsh; do
      argc --argc-completions "$shell" quadletctl > "completion.$shell"
      substituteInPlace "completion.$shell" \
        --replace-fail "argc --argc-compgen" "${lib.getExe argc} --argc-compgen"
    done
    { echo '#compdef quadletctl'; cat completion.zsh; echo '_argc_completer "$@"'; } > _quadletctl
    installShellCompletion --cmd quadletctl --bash completion.bash --fish completion.fish --zsh _quadletctl
  '';
}
