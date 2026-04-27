#!/usr/bin/env bash
# Runs once Capsule is ready. Creates a Tenant, verifies it's accepted by
# the validating webhook (apply succeeds) and reconciled (status reaches
# Active). Proves the install + health_check chain works end-to-end.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

echo "smoke_test: creating Tenant 'alice'"
# Capsule's validating webhook may briefly refuse connections after
# Deployment goes Available — Service endpoints lag readiness, and
# cert-manager's CA injection into the ValidatingWebhookConfiguration
# completes asynchronously. Retry for up to 60s.
deadline=$(( $(date +%s) + 60 ))
while :; do
  if "$KUBECTL" --kubeconfig="$KUBECONFIG" apply -f - <<'EOF' 2>/tmp/apply.err
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: alice
spec:
  owners:
    - kind: User
      name: alice@example.com
EOF
  then
    break
  fi
  if (( $(date +%s) >= deadline )); then
    echo "smoke_test: FAIL — Tenant apply never accepted by webhook" >&2
    cat /tmp/apply.err >&2
    exit 1
  fi
  echo "smoke_test: webhook not ready yet ($(cat /tmp/apply.err | head -1)); retrying"
  sleep 2
done

echo "smoke_test: waiting for Capsule to reconcile"
deadline=$(( $(date +%s) + 30 ))
while (( $(date +%s) < deadline )); do
  state=$("$KUBECTL" --kubeconfig="$KUBECONFIG" get tenant alice -o jsonpath='{.status.state}' 2>/dev/null || true)
  if [[ "$state" == "Active" ]]; then
    echo "smoke_test: OK — tenant alice is $state"
    exit 0
  fi
  sleep 1
done

echo "smoke_test: FAIL — tenant alice never reached Active. Last status:" >&2
"$KUBECTL" --kubeconfig="$KUBECONFIG" get tenant alice -o yaml >&2 || true
exit 1
