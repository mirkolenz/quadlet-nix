# @describe Manage the Quadlet units of quadlet-nix.
# Commands for units of other managers run there in a new session, which requires root or polkit authorization.

declare -A kinds=() owners=() podman_names=()

# Loads the tables of the NixOS and the Home Manager module from the XDG config directories,
# where the own UID becomes the calling user.
_load_tables() {
  local -a dirs
  local dir table service kind podman_name owner

  IFS=: read -ra dirs <<<"${XDG_CONFIG_DIRS:-/etc/xdg}"

  for dir in "${dirs[@]}" "${XDG_CONFIG_HOME:-$HOME/.config}"; do
    table=$dir/quadletctl/units.tsv
    [[ -r $table ]] || continue

    while IFS=$'\t' read -r service kind podman_name owner; do
      if [[ $owner == "$EUID" ]]; then
        owner=user
      fi

      kinds[$service]=$kind owners[$service]=$owner podman_names[$service]=$podman_name
    done <"$table"
  done
}

_load_tables

# @cmd List the units with their owner, kind, podman name, and state
list() {
  local -A services=()
  local -a units states rows=()
  local service owner i row

  for service in "${!owners[@]}"; do
    services[${owners[$service]}]+="$service "
  done

  for owner in "${!services[@]}"; do
    read -ra units <<<"${services[$owner]}"
    _manager
    mapfile -t states < <(systemctl "${manager[@]}" is-active "${units[@]/%/.service}")

    for i in "${!units[@]}"; do
      printf -v row '%s\t%s\t%s\t%s\t%s' "${units[i]}" "$owner" "${kinds[${units[i]}]}" "${podman_names[${units[i]}]}" "${states[i]}"
      rows+=("$row")
    done
  done

  printf '%s\n' "${rows[@]}" | column --table --separator $'\t' --table-columns UNIT,OWNER,KIND,PODMAN,STATE
}

# @cmd Run systemctl for a unit in the manager that owns it
# @arg verb!                 Verb of systemctl
# @arg unit![`_choice_unit`]  Name of the unit
# @arg args~                  Further arguments of systemctl
systemctl_() {
  _select "$argc_unit"
  exec systemctl "${manager[@]}" "$argc_verb" "$unit" "${argc_args[@]}"
}

# @cmd Show the journal of a unit
# @arg unit![`_choice_unit`]  Name of the unit
# @arg args~                  Further arguments of journalctl
journalctl_() {
  _select "$argc_unit"

  case $owner in
  system) exec journalctl --unit="$unit" "${argc_args[@]}" ;;
  user) exec journalctl --user-unit="$unit" "${argc_args[@]}" ;;
  # The matches of --user-unit for another UID, which only needs read access to the journal.
  # Further matches given as arguments only apply to the last alternative.
  *)
    exec journalctl "_SYSTEMD_USER_UNIT=$unit" "_UID=$owner" \
      + "USER_UNIT=$unit" "_UID=$owner" \
      + "COREDUMP_USER_UNIT=$unit" "_UID=$owner" _UID=0 \
      "${argc_args[@]}"
    ;;
  esac
}

# @cmd Run podman as the owner of a unit
# @arg unit![`_choice_unit`]  Name of the unit
# @arg args~                  Further arguments of podman
podman_() {
  _select "$argc_unit"
  _as_owner podman "${argc_args[@]}"
}

# @cmd Open a shell as the owner of a unit
# @arg unit![`_choice_unit`]  Name of the unit
# @arg command~               Command to run, defaults to $SHELL
shell() {
  _select "$argc_unit"
  _as_owner "${argc_command[@]:-${SHELL:-bash}}"
}

# Prints the units, with descriptions only for completions.
_choice_unit() {
  local service

  if [[ $ARGC_COMPGEN != 1 ]]; then
    printf '%s\n' "${!owners[@]}"
    return
  fi

  for service in "${!owners[@]}"; do
    printf '%s\t%s %s %s\n' "$service" "${owners[$service]}" "${kinds[$service]}" "${podman_names[$service]}"
  done
}

_select() {
  unit=$1.service owner=${owners[$1]}
  _manager
}

# Sets the systemctl flags of the manager of the owner, which is the system, the calling user, or another UID.
_manager() {
  case $owner in
  system) manager=() ;;
  user) manager=(--user) ;;
  *) manager=(--user --machine="$owner@.host") ;;
  esac
}

# Runs a command directly if the caller is the owner, otherwise in the manager of the owner.
_as_owner() {
  if [[ $owner == user || ($owner == system && $EUID == 0) ]]; then
    exec "$@"
  fi

  # Like machinectl shell, but propagates the exit status, passes stdio through unless all of it is a terminal,
  # and resolves the command via the PATH of quadletctl.
  exec systemd-run "${manager[@]}" --pty --pipe --quiet --collect --property=ExecSearchPath="$PATH" -- "$@"
}

eval "$(argc --argc-eval "$0" "$@")"
