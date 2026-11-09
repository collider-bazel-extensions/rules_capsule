#!/usr/bin/env bash
# Consumer checks against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do):
#   1. no capsule.version() in the root resolves, and an capsule_install builds
#      against rules_capsule's pinned version
#   2. the same version set twice in the root resolves
#   3. an unsupported version fails, naming capsule.version
#   4. tests/ and tools/ are not shipped, and @rules_capsule//... loads
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_capsule"
rm -rf "$work"; mkdir -p "$src"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in tests tools; do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
version="$(sed -n '/^capsule.version(/,/)/s/.*version = "\(.*\)".*/\1/p' "$src/MODULE.bazel")"

consumer() { # <name> <extra MODULE.bazel lines>
    local c="$work/$1"
    mkdir -p "$c"
    if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
    cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_capsule")
local_path_override(module_name = "rules_capsule", path = "$src")
$2
MOD
    cat > "$c/BUILD.bazel" <<'BUILD'
load("@rules_capsule//:defs.bzl", "capsule_install")

capsule_install(
    name = "capsule",
    kubeconfig_env = "KUBECONFIG",
)
BUILD
    echo "$c"
}

# 1. No capsule.version(): resolves, and the install builds with the pinned manifest.
c="$(consumer untagged "")"
(cd "$c" && bazel build //:capsule)
(cd "$c" && bazel mod show_extension @rules_capsule//:extensions.bzl%capsule) | tee "$work/untagged.out"
grep -q "$version" "$work/untagged.out" || { echo "FAIL: untagged consumer did not get Capsule $version" >&2; exit 1; }
echo "PASS: untagged root resolves, Capsule $version"

# 2. The same version twice in the root.
c="$(consumer twice "capsule = use_extension(\"@rules_capsule//:extensions.bzl\", \"capsule\")
capsule.version(version = \"$version\")
capsule.version(version = \"$version\")")"
(cd "$c" && bazel build //:capsule)
echo "PASS: repeated identical capsule.version resolves"

# 3. An unsupported version fails with a message naming capsule.version.
c="$(consumer unsupported 'capsule = use_extension("@rules_capsule//:extensions.bzl", "capsule")
capsule.version(version = "0.0.1")')"
if (cd "$c" && bazel mod deps) > "$work/unsupported.out" 2>&1; then
    echo "FAIL: unsupported version resolved" >&2; exit 1
fi
grep -q 'capsule.version(version = "0.0.1") is not supported' "$work/unsupported.out" || {
    cat "$work/unsupported.out" >&2; echo "FAIL: unsupported version: wrong error" >&2; exit 1; }
echo "PASS: unsupported version fails clearly"

# 4. //... loads.
(cd "$work/untagged" && bazel query @rules_capsule//... >/dev/null)
echo "PASS: @rules_capsule//... loads"
