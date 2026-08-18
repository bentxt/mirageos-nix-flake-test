#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")" && pwd)"
nix_bin="$(command -v nix || true)"

if [[ -z "$nix_bin" && -x /nix/var/nix/profiles/default/bin/nix ]]; then
  nix_bin=/nix/var/nix/profiles/default/bin/nix
fi

if [[ -z "$nix_bin" ]]; then
  echo "Nix was not found in PATH or /nix/var/nix/profiles/default/bin" >&2
  exit 127
fi

exec "$nix_bin" \
  --extra-experimental-features "nix-command flakes" \
  develop "$project_root" \
  --command "$project_root/scripts/run-mirage-demo.sh"
