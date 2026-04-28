"""Maintainer-only repository rule that downloads + extracts the Capsule
helm chart (`capsule-<ver>.tgz`) at the sha pinned in
`//private:versions.bzl`. The extracted tree exposes a `:files`
filegroup that downstream `helm_template` actions consume.

This is dev-only — consumers of rules_capsule never see this. The
chart download happens only when running the maintainer flow:

    bazel run //tools:render_writeback -- <capsule-version>

The committed pre-rendered manifest at
`private/manifests/capsule-<ver>.yaml` is what `capsule_install`
applies at runtime.
"""

load("//private:versions.bzl", "CAPSULE_VERSIONS")

_BUILD = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "files",
    srcs = glob(["**/*"]),
)
"""

def _impl(rctx):
    version = rctx.attr.version
    if version not in CAPSULE_VERSIONS:
        fail("rules_capsule: unknown chart version '{}'. Known: {}".format(
            version,
            sorted(CAPSULE_VERSIONS.keys()),
        ))
    pin = CAPSULE_VERSIONS[version]
    rctx.download_and_extract(
        url    = pin["chart_url"],
        sha256 = pin["chart_sha256"],
        # The chart .tgz extracts to a top-level `capsule/` directory.
        # We don't strip it — `helm_template` finds Chart.yaml inside.
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD)

capsule_chart_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "version": attr.string(mandatory = True),
    },
)
