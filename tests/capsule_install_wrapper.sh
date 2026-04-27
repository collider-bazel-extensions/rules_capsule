#!/usr/bin/env bash
# Sources the kind cluster's env file (which sets KUBECONFIG) and then exec's
# the rules_capsule capsule_install binary. The capsule_install rule itself
# is cluster-source-agnostic — this wrapper is what binds it to a specific
# rules_kind cluster. Lives in tests/ (not the public rule) per
# DESIGN.md decision #9.
set -euo pipefail

CLUSTER_NAME="cluster"
CAPSULE_INSTALL="${CAPSULE_INSTALL:?missing}"

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
deadline=$(( $(date +%s) + 60 ))
while [[ ! -f "$env_file" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "capsule_install_wrapper: kind env file never appeared at $env_file" >&2
    exit 1
  fi
  sleep 1
done

# shellcheck disable=SC1090
source "$env_file"

# The kind env file exports KUBECONFIG; capsule_install's launcher reads
# whatever kubeconfig_env points at (default: KUBECONFIG). Just exec it.
exec "$CAPSULE_INSTALL"
