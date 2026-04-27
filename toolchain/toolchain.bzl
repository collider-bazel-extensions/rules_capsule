"""capsule_toolchain — exposes the pinned, pre-rendered Capsule install
manifest as a `ToolchainInfo` so consumer rules (`capsule_install`,
`capsule_health_check`) can resolve it without depending on the manifest's
specific path.
"""

load("//private:providers.bzl", "CapsuleInfo")

CAPSULE_TOOLCHAIN_TYPE = Label("//toolchain:capsule")

def _toolchain_impl(ctx):
    capsule_info = CapsuleInfo(
        version = ctx.attr.version,
        manifest = ctx.file.manifest,
        namespace = ctx.attr.namespace,
    )
    return [
        platform_common.ToolchainInfo(capsule = capsule_info),
        DefaultInfo(files = depset([ctx.file.manifest])),
    ]

capsule_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "manifest": attr.label(allow_single_file = True, mandatory = True),
        "manifest_sha256": attr.string(
            doc = "Recorded for diagnostics; sha256 verification happens in " +
                  "the maintainer-side render tool, not at toolchain resolution.",
        ),
        "namespace": attr.string(
            default = "capsule-system",
            doc = "Namespace the rendered manifest installs Capsule into. " +
                  "Pinned at render time; surfaced for downstream rules that " +
                  "want to apply CRs in the right namespace.",
        ),
    },
)
