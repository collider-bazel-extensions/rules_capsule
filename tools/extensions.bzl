"""Bzlmod extension for the maintainer-only chart fetch.

Mirrors the `version`-tag-class shape used by the public extension. Fires
only when rules_capsule is the root module (the maintainer's Bazel
invocation) — consumers don't pull the chart.
"""

load("//tools:repositories.bzl", "capsule_chart_repository")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            capsule_chart_repository(
                name = "capsule_chart_" + tag.version.replace(".", "_"),
                version = tag.version,
            )

capsule_chart = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
