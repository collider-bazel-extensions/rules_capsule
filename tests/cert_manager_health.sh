#!/usr/bin/env bash
# itest health_check: cert-manager is "ready" when all three Deployments
# are Available. We re-run the wait with a zero timeout so this exits
# fast — itest retries on non-zero.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?missing}"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || exit 1
# shellcheck disable=SC1090
source "$env_file"

"$KUBECTL" -n cert-manager wait deploy --all --for=condition=Available --timeout=0s 2>/dev/null
