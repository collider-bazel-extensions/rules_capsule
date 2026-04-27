"""Bzlmod extension. Same shape as rules_pg / rules_temporal / rules_kind /
rules_playwright (the version tag class). v0.1 has no `system` mode — Capsule
is an in-cluster operator, not a host CLI.
"""

load("//private:repositories.bzl", "capsule_version_repository")

_version_tag = tag_class(attrs = {
    "name": attr.string(default = "capsule"),
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    for mod in mctx.modules:
        for tag in mod.tags.version:
            capsule_version_repository(
                name = tag.name,
                version = tag.version,
            )

capsule = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
