"""capsule_install — long-running `kubectl apply` of the toolchain's
pre-rendered Capsule manifest. Drops directly into `itest_service.exe`.

The rule does NOT install cert-manager (or any other TLS provider for
Capsule's webhooks) — that's the consumer's job. See DESIGN.md decision #6
and the in-tree smoke test for the canonical composition.
"""

load("//private:providers.bzl", "CapsuleInfo")  # buildifier: keep

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:capsule"]
    info = tc.capsule

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{LAUNCHER}": ctx.executable._launcher.short_path,
            "{MANIFEST}": info.manifest.short_path,
            "{NAMESPACE}": info.namespace,
            "{KUBECONFIG_ENV}": ctx.attr.kubeconfig_env,
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [ctx.executable._launcher, info.manifest])
    runfiles = runfiles.merge(ctx.attr._launcher[DefaultInfo].default_runfiles)
    return [
        DefaultInfo(executable = out, runfiles = runfiles),
        info,
    ]

capsule_install = rule(
    implementation = _impl,
    attrs = {
        "kubeconfig_env": attr.string(
            default = "KUBECONFIG",
            doc = "Env var holding the path to the target cluster's " +
                  "kubeconfig. Defaults to `KUBECONFIG`. rules_kind " +
                  "compositions typically set `KUBECONFIG_<cluster>` via " +
                  "itest's env interpolation; pass that name here.",
        ),
        "_launcher": attr.label(
            default = "//private:launcher",
            executable = True,
            cfg = "exec",
        ),
        "_tmpl": attr.label(
            default = "//private:install.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:capsule"],
    executable = True,
)
