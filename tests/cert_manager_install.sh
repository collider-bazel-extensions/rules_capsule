#!/usr/bin/env bash
# itest_service exe: source the kind cluster's env file, kubectl apply
# cert-manager, wait for all three Deployments to become Available, then
# sleep until SIGTERM (so itest treats us as a long-running service).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?missing}"
CERT_MANAGER_YAML="${CERT_MANAGER_YAML:?missing}"

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
deadline=$(( $(date +%s) + 60 ))
while [[ ! -f "$env_file" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "cert_manager_install: kind env file never appeared at $env_file" >&2
    exit 1
  fi
  sleep 1
done

# shellcheck disable=SC1090
source "$env_file"

echo "cert_manager_install: applying $CERT_MANAGER_YAML"
"$KUBECTL" apply -f "$CERT_MANAGER_YAML" --server-side=true

echo "cert_manager_install: waiting for cert-manager Deployments"
"$KUBECTL" -n cert-manager wait deploy --all --for=condition=Available --timeout=180s

echo "cert_manager_install: ready; sleeping until SIGTERM"
trap 'echo "cert_manager_install: SIGTERM" >&2; exit 143' TERM INT
while true; do sleep 3600 & wait $!; done
