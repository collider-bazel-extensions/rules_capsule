#!/usr/bin/env bash
# Same role as capsule_install_wrapper.sh but for the health_check binary.
# itest invokes the health_check directly, so we resolve the bin via runfiles
# (sh_binary's `env=` attr only fires under `bazel run`, not when itest exec's
# the wrapper).
set -euo pipefail

CLUSTER_NAME="cluster"

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi
CAPSULE_HEALTH="${RUNFILES_DIR}/_main/tests/capsule_health_bin.sh"
[[ -x "$CAPSULE_HEALTH" ]] || { echo "wrapper: capsule_health_bin not at $CAPSULE_HEALTH" >&2; exit 1; }

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || exit 1

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

exec "$CAPSULE_HEALTH"
