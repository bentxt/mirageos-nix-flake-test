#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_root/mirageapp"
opam_root="${MIRAGE_OPAM_ROOT:-/tmp/flaketest-mirage-opam-root}"
switch_name="${MIRAGE_OPAM_SWITCH:-mirage-4.10}"
ocaml_version="${MIRAGE_OCAML_VERSION:-4.14.2}"

case "$(uname -s)" in
  Darwin) target="macosx" ;;
  *) target="unix" ;;
esac
target="${MIRAGE_TARGET:-$target}"

export OPAMROOT="$opam_root"

if [[ ! -f "$OPAMROOT/config" ]]; then
  opam init --bare --yes
fi

if ! opam switch list --short | grep -Fqx "$switch_name"; then
  opam switch create "$switch_name" "ocaml-base-compiler.$ocaml_version" --yes
fi

eval "$(opam env --switch="$switch_name" --set-switch)"
opam install 'mirage>=4.9.0' 'mirage<4.12.0' --yes

cd "$app_dir"
mirage configure -t "$target"

lock_file="mirage/hello-$target.opam.locked"
vendored_project="$(find duniverse -mindepth 2 -maxdepth 2 -name dune-project -print -quit 2>/dev/null || true)"
if [[ ! -f "$lock_file" || -z "$vendored_project" ]]; then
  make depend
fi

make build

exec ./dist/hello
