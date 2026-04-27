#!/usr/bin/env bash
# Sources the kind cluster's env file (which uses bare `KEY=VALUE` lines, no
# `export`) under `set -a` so KUBECONFIG/KUBECTL propagate across the `exec`
# boundary. Resolves the capsule_install bin via runfiles (sh_binary's `env=`
# attr only fires under `bazel run`, not when itest exec's the wrapper).
set -euo pipefail

CLUSTER_NAME="cluster"

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi
CAPSULE_INSTALL="${RUNFILES_DIR}/_main/tests/capsule_bin.sh"
[[ -x "$CAPSULE_INSTALL" ]] || { echo "wrapper: capsule_bin not at $CAPSULE_INSTALL" >&2; exit 1; }

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
deadline=$(( $(date +%s) + 60 ))
while [[ ! -f "$env_file" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "capsule_install_wrapper: kind env file never appeared at $env_file" >&2
    exit 1
  fi
  sleep 1
done

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

exec "$CAPSULE_INSTALL"
