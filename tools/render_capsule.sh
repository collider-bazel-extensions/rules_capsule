#!/usr/bin/env bash
# tools/render_capsule.sh — thin shim around the Bazel-native render flow.
#
# Maintainer flow for adding/updating a Capsule version:
#   1. Edit private/versions.bzl::CAPSULE_VERSIONS to add/change the entry,
#      including chart_url + chart_sha256. Easiest way to compute the sha:
#          curl -fsSL "https://projectcapsule.github.io/charts/capsule-${VERSION}.tgz" \
#              | sha256sum
#   2. Add (or update) a `helm_template` + `sh_binary` block in
#      tools/BUILD.bazel for the new version.
#   3. Run this script:
#          bash tools/render_capsule.sh <version>
#      It just invokes `bazel run //tools:render_writeback_<dotted_version>`,
#      which renders via the hermetic helm binary supplied by rules_helm,
#      writes the output to private/manifests/, and updates manifest_sha256
#      in private/versions.bzl.
#
# Host helm is NOT required at any point — the helm binary comes from
# rules_helm (declared as a dev dependency in MODULE.bazel).
set -euo pipefail

VERSION="${1:?usage: tools/render_capsule.sh <version>}"
TARGET="//tools:render_writeback_$(echo "$VERSION" | tr '.' '_')"

echo "[render_capsule] $TARGET"
exec bazel run "$TARGET"
