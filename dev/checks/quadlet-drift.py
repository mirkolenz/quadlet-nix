"""Detect drift between the declared Quadlet options and upstream Podman.

The authoritative list of keys Podman accepts per `[Section]` lives in
`pkg/systemd/quadlet/quadlet.go` (the `groupsInfo` / `supportedQuadletKeys`
maps that Quadlet validates unit files against). We read it straight from the
pinned `podman.src` so the reference always matches the Podman version in
nixpkgs, then diff it against the options declared by the Nix modules.

The `@...@` names are substituted with Nix store paths at build time via
`replaceVars` (the `--subst-var-by` mechanism), so the packaged tool is fully
self-contained.
"""

import json
import re
import sys
from pathlib import Path

DECLARED_KEYS = "@declaredKeys@"
QUADLET_GO = "@quadletGo@"
PODMAN_VERSION = "@podmanVersion@"

# Keys Podman still accepts but no longer documents, deliberately not modelled.
# `Remap*` were superseded by `UserNS`, `VolatileTmp` by `ReadOnlyTmpfs`.
DEPRECATED = {"RemapUid", "RemapGid", "RemapUidSize", "RemapUsers", "VolatileTmp"}

# `Name = "value"` constant definitions, e.g. `KeyAddHost = "AddHost"`, `PodGroup = "Pod"`.
CONST_RE = re.compile(r'(\w+)\s*=\s*"([^"]+)"')
# A `KeyXxx` constant reference inside a `SupportedKeys` map body.
KEY_RE = re.compile(r"\bKey\w+")
# One GroupInfo literal: its `GroupName` constant and the body of its `SupportedKeys` map.
GROUP_RE = re.compile(
    r"GroupName:\s*(\w+),.*?SupportedKeys:\s*map\[string\]bool\{(.*?)\}", re.S
)
# The shared `[Quadlet]` section's `supportedQuadletKeys` map body.
QUADLET_RE = re.compile(r"supportedQuadletKeys\s*=\s*map\[string\]bool\{(.*?)\}", re.S)


def upstream_keys(go: str) -> dict[str, set[str]]:
    """Map each `[Section]` to the set of keys Podman accepts for it."""
    const = dict(CONST_RE.findall(go))

    def resolve(block: str) -> set[str]:
        return {const[name] for name in KEY_RE.findall(block)}

    sections = {const[group]: resolve(block) for group, block in GROUP_RE.findall(go)}
    quadlet = QUADLET_RE.search(go)
    if not sections or quadlet is None:
        raise SystemExit(
            "quadlet.go layout changed; update the parser in quadlet-drift.py"
        )
    sections["Quadlet"] = resolve(quadlet.group(1))

    return sections


def main() -> int:
    declared = {
        k: set(v) for k, v in json.loads(Path(DECLARED_KEYS).read_text()).items()
    }
    upstream = upstream_keys(Path(QUADLET_GO).read_text())

    print(f"Comparing unit modules against Podman {PODMAN_VERSION}\n")

    drift = False
    for section in sorted(declared):
        accepted = upstream.get(section, set())
        modelled = declared[section]
        missing = sorted((accepted - modelled) - DEPRECATED)
        extra = sorted(modelled - accepted)
        if missing or extra:
            drift = True
            print(f"[{section}] DRIFT")
            for key in missing:
                print(
                    f"  + missing : {key} (accepted by Podman, not declared in the module)"
                )
            for key in extra:
                print(
                    f"  - extra   : {key} (declared in the module, not accepted by Podman)"
                )
        else:
            print(f"[{section}] ok ({len(modelled)} keys)")

    if drift:
        print(
            "\nDrift detected. Update the affected units/*.nix accordingly."
        )
        return 1

    print("\nNo drift: all declared options match the keys Podman accepts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
