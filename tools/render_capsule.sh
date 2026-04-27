#!/usr/bin/env bash
# tools/render_capsule.sh — pre-render the Capsule helm chart to a static YAML
# manifest under private/manifests/. Maintainer-side tool; not invoked by
# `bazel build` or `bazel test`. See DESIGN.md decision #4.
#
# Usage:
#     bash tools/render_capsule.sh <chart-version>            # e.g. 0.10.4
#     bash tools/render_capsule.sh <chart-version> --update   # also auto-edit
#                                                             # private/versions.bzl
#
# Requires `helm` (3.x) on PATH. The helm chart itself is fetched at run time
# from oci://ghcr.io/projectcapsule/charts/capsule and cached under a tmpdir;
# the chart is NOT committed to the repo (only the rendered YAML is). Helm is
# **not** required at consumer test time — `capsule_install` just applies the
# committed manifest.
set -euo pipefail

VERSION="${1:?usage: tools/render_capsule.sh <chart-version> [--update]}"
UPDATE=0
[[ "${2:-}" == "--update" ]] && UPDATE=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFESTS_DIR="$REPO_ROOT/private/manifests"
VERSIONS_BZL="$REPO_ROOT/private/versions.bzl"
OUT="$MANIFESTS_DIR/capsule-${VERSION}.yaml"

if ! command -v helm >/dev/null 2>&1; then
    echo "ERROR: helm not found on PATH. Install helm 3.x:" >&2
    echo "    https://helm.sh/docs/intro/install/" >&2
    exit 127
fi

mkdir -p "$MANIFESTS_DIR"
WORKDIR=$(mktemp -d -t render-capsule-XXXXXX)
# shellcheck disable=SC2064
trap "rm -rf '$WORKDIR'" EXIT

echo "[render_capsule] pulling chart oci://ghcr.io/projectcapsule/charts/capsule:${VERSION}"
helm pull "oci://ghcr.io/projectcapsule/charts/capsule" \
    --version "$VERSION" \
    --destination "$WORKDIR" >/dev/null

CHART_TGZ="$WORKDIR/capsule-${VERSION}.tgz"
if [[ ! -f "$CHART_TGZ" ]]; then
    echo "ERROR: expected $CHART_TGZ; helm pull produced:" >&2
    ls "$WORKDIR" >&2
    exit 1
fi

echo "[render_capsule] rendering with default values, --include-crds"
helm template capsule "$CHART_TGZ" \
    --namespace capsule-system \
    --include-crds \
    > "$OUT"

SHA256=$(sha256sum "$OUT" | awk '{print $1}')
LINES=$(wc -l < "$OUT")

echo
echo "[render_capsule] OK"
echo "    file:   $OUT"
echo "    sha256: $SHA256"
echo "    lines:  $LINES"

if (( UPDATE )); then
    echo
    echo "[render_capsule] updating $VERSIONS_BZL"
    python3 - "$VERSIONS_BZL" "$VERSION" "$SHA256" <<'PY'
import re, sys
path, version, sha = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
# Find the CAPSULE_VERSIONS dict body and rewrite the entry for `version`
# (or add it) without disturbing other keys / formatting.
m = re.search(r"(CAPSULE_VERSIONS\s*=\s*\{)([\s\S]*?)(\n\})", src)
if not m:
    sys.exit("could not locate CAPSULE_VERSIONS dict in versions.bzl")
head, body, tail = m.group(1), m.group(2), m.group(3)
entry = f'\n    "{version}": {{\n        "manifest_sha256": "{sha}",\n    }},'
# Replace existing entry for this version, else append before closing brace.
existing = re.search(rf'\n    "{re.escape(version)}":[\s\S]*?\n    \}},', body)
new_body = (body[:existing.start()] + entry + body[existing.end():]) if existing else (body.rstrip(",\n ") + "," + entry)
new_src = src[:m.start()] + head + new_body + tail + src[m.end():]
open(path, "w").write(new_src)
print(f"  wrote CAPSULE_VERSIONS['{version}'] = manifest_sha256 = {sha}")
PY
    echo
    echo "Next: bump MODULE.bazel's \`capsule.version(version = \"$VERSION\")\` if you want this"
    echo "      to be the default version, then run \`bazel test //tests:...analysis\`."
else
    echo
    echo "Next steps (re-run with --update to do this automatically):"
    echo "  1. Add or update in private/versions.bzl::CAPSULE_VERSIONS:"
    echo
    echo "       \"$VERSION\": {"
    echo "           \"manifest_sha256\": \"$SHA256\","
    echo "       },"
    echo
    echo "  2. Bump MODULE.bazel's \`capsule.version(version = \"$VERSION\")\`."
    echo "  3. Run \`bazel test //tests:capsule_install_analysis\` to verify."
fi
