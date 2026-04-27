"""Repository rules: the hub repo for one Capsule version.

Two-tier layout (mirrors rules_playwright):
- Hub repo: emits one `capsule_toolchain` per platform, gated on
  `target_compatible_with`. Resolves the pinned manifest + sha256.
- The Capsule manifest itself is *not* fetched at repo-rule time — it lives
  in the source tree at `//private/manifests/capsule-<ver>.yaml`. The hub
  repo just records the version and exposes it via the toolchain.
"""

load(":versions.bzl", "CAPSULE_VERSIONS", "PLATFORMS")

# ---- hub repo ---------------------------------------------------------------

_HUB_BUILD_TMPL = """\
load("@rules_capsule//toolchain:toolchain.bzl", "capsule_toolchain")

package(default_visibility = ["//visibility:public"])

{toolchains}
"""

_HUB_TC_TMPL = """\
capsule_toolchain(
    name = "{plat}_impl",
    version = "{version}",
    manifest = "@rules_capsule//private/manifests:capsule-{version}.yaml",
    manifest_sha256 = "{manifest_sha256}",
)

toolchain(
    name = "{plat}",
    toolchain_type = "@rules_capsule//toolchain:capsule",
    target_compatible_with = {compat},
    toolchain = ":{plat}_impl",
)
"""

def _hub_repo_impl(rctx):
    version = rctx.attr.version
    if version not in CAPSULE_VERSIONS:
        fail("rules_capsule: unknown version '{}'. Known: {}".format(
            version,
            sorted(CAPSULE_VERSIONS.keys()),
        ))
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))

    manifest_sha = CAPSULE_VERSIONS[version]["manifest_sha256"]
    chunks = []
    for plat, compat in PLATFORMS.items():
        chunks.append(_HUB_TC_TMPL.format(
            plat = plat,
            version = version,
            manifest_sha256 = manifest_sha,
            compat = repr(compat),
        ))
    rctx.file("BUILD.bazel", _HUB_BUILD_TMPL.format(
        toolchains = "\n".join(chunks),
    ))

_capsule_hub_repository = repository_rule(
    implementation = _hub_repo_impl,
    attrs = {
        "version": attr.string(mandatory = True),
    },
)

# ---- public entry point (called from extensions.bzl) ------------------------

def capsule_version_repository(name, version):
    """Materialize the hub repo for one Capsule version."""
    if version not in CAPSULE_VERSIONS:
        fail("rules_capsule: unknown version '{}'. Known: {}".format(
            version,
            sorted(CAPSULE_VERSIONS.keys()),
        ))
    _capsule_hub_repository(name = name, version = version)
