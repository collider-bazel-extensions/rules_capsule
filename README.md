# rules_capsule

Hermetic [Project Capsule](https://capsule.clastix.io/) (Kubernetes
multi-tenancy operator) install + readiness for Bazel tests. Drops into
[`rules_itest`](https://github.com/dzbarsky/rules_itest) and composes with
[`rules_kind`](https://github.com/collider-bazel-extensions/rules_kind) (or
any cluster the consumer provides via `KUBECONFIG`).

**Supported platforms (v0.1):** Linux (x86\_64). macOS bundles work in theory
(the rule is platform-independent — it's just `kubectl apply` on a pinned
manifest) but not validated. See
[Contributing → Help wanted: macOS validation](#help-wanted-macos-validation).

**Pinned versions:** Capsule 0.10.4 (chart pre-rendered with `helm template`,
sha256-verified). cert-manager wiring lives in
[`rules_certmanager`](https://github.com/collider-bazel-extensions/rules_certmanager) —
not part of the public `capsule_install` contract; see [TLS provider
prerequisite](#tls-provider-prerequisite).

> **Note on hermeticity.** The Capsule manifest is fully pinned and committed
> at `private/manifests/`. `kubectl` is **not** vendored — v0.1 trusts host
> kubectl on PATH (matches the sibling `rules_kind` posture). Capsule's
> webhooks need a TLS provider (cert-manager or trust-manager) in the cluster
> *before* `capsule_install` runs — see [TLS provider
> prerequisite](#tls-provider-prerequisite).

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Rules](#rules)
  - [capsule\_install](#capsule_install)
  - [capsule\_health\_check](#capsule_health_check)
- [`rules_itest` integration](#rules_itest-integration)
- [Providers](#providers)
- [TLS provider prerequisite](#tls-provider-prerequisite)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_capsule", version = "0.1.0")

capsule = use_extension("@rules_capsule//:extensions.bzl", "capsule")
capsule.version(version = "0.10.4")
use_repo(capsule, "capsule")

register_toolchains("@capsule//:all")
```

`rules_capsule` is **Bzlmod-only** in v0.1 — `repositories.bzl` exists but
exports no top-level setup macros. Until the rule lands in BCR, consume via
`archive_override` or a git pin pointing at a tag.

---

## Quickstart

Compose Capsule against an existing cluster (kubeconfig path provided via
env). Most consumers will wire this up to a `kind_cluster` from
`rules_kind` — see [`rules_itest` integration](#rules_itest-integration)
below.

```python
load("@rules_capsule//:defs.bzl", "capsule_install", "capsule_health_check")

# 1. cert-manager (or another TLS provider) must already be running in the
#    cluster — see "TLS provider prerequisite" below.

# 2. Install Capsule. Long-running: applies the pinned manifest and stays
#    alive so rules_itest treats it as a service.
capsule_install(
    name = "capsule",
    kubeconfig_env = "KUBECONFIG",  # default; override to "KUBECONFIG_<cluster>"
                                    # when composed with rules_kind via itest.
)

# 3. Readiness probe: tenant CRD registered + capsule-system Deployments
#    Available. Drops into itest_service.health_check.
capsule_health_check(name = "capsule_health")
```

---

## Rules

### `capsule_install`

```python
load("@rules_capsule//:defs.bzl", "capsule_install")

capsule_install(
    name = "capsule",
    kubeconfig_env = "KUBECONFIG_my_cluster",
)
```

`kubectl apply -f` of the toolchain's pre-rendered Capsule manifest, then
sleeps until SIGTERM (so `rules_itest` treats it as a long-running
`itest_service`). The manifest is sha256-pinned; running `bazel build` on
this target verifies the file hasn't been tampered with.

The rule does **not** install cert-manager. See
[TLS provider prerequisite](#tls-provider-prerequisite).

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `kubeconfig_env` | `string` | `"KUBECONFIG"` | Env var holding the path to the target cluster's kubeconfig. With `rules_kind` + `rules_itest`, set this to whatever env name the upstream `kind_cluster` exports. |

### `capsule_health_check`

```python
load("@rules_capsule//:defs.bzl", "capsule_health_check")

capsule_health_check(
    name = "capsule_health",
    namespace = "capsule-system",
)
```

One-shot probe. Verifies (in order):
1. The `tenants.capsule.clastix.io` CRD is registered.
2. All Deployments in the configured namespace are `Available=True`.

`rules_itest` retries until success or timeout.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `namespace` | `string` | `"capsule-system"` | Namespace Capsule was installed into. Must match what the manifest renders to. |
| `kubeconfig_env` | `string` | `"KUBECONFIG"` | Env var holding the target cluster's kubeconfig. |

---

## `rules_itest` integration

`rules_capsule` integrates by emitting `itest_service.exe` / `health_check`
shaped targets. **There is no pass-through `services =` attr** — composition
is the consumer's job, matching the
`rules_pg`/`rules_temporal`/`rules_kind`/`rules_playwright` convention.

### Example: kind + cert-manager + Capsule + a tenant test

The shape used by this repo's own smoke test:

```python
load("@rules_capsule//:defs.bzl", "capsule_install", "capsule_health_check")
load("@rules_certmanager//:defs.bzl", "cert_manager_install", "cert_manager_health_check")
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# 1. The cluster.
kind_cluster(name = "cluster", k8s_version = "1.29")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

# 2. cert-manager (TLS provider for Capsule's webhooks), via rules_certmanager.
#    The cluster-source-agnostic rule binaries are bound to the rules_kind
#    cluster by thin wrappers that source $TEST_TMPDIR/<cluster>.env (set -a
#    so KUBECONFIG/KUBECTL cross the `exec` boundary).
cert_manager_install(name = "cert_manager_bin")
cert_manager_health_check(name = "cert_manager_health_bin")
sh_binary(
    name = "cert_manager_install_wrapper",
    srcs = ["cert_manager_install_wrapper.sh"],
    data = [":cert_manager_bin"],
)
sh_binary(
    name = "cert_manager_health_wrapper",
    srcs = ["cert_manager_health_wrapper.sh"],
    data = [":cert_manager_health_bin"],
)
itest_service(
    name = "cert_manager_svc",
    exe = ":cert_manager_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":cert_manager_health_wrapper",
)

# 3. Capsule itself — same wrapper pattern as cert-manager.
capsule_install(name = "capsule_bin")
capsule_health_check(name = "capsule_health_bin")
sh_binary(
    name = "capsule_install_wrapper",
    srcs = ["capsule_install_wrapper.sh"],
    data = [":capsule_bin"],
)
sh_binary(
    name = "capsule_health_wrapper",
    srcs = ["capsule_health_wrapper.sh"],
    data = [":capsule_health_bin"],
)
itest_service(
    name = "capsule_svc",
    exe = ":capsule_install_wrapper",
    deps = [":cert_manager_svc"],
    health_check = ":capsule_health_wrapper",
)

# 4. The actual test: create a Tenant, assert it's accepted + Active.
sh_test(name = "smoke_test_bin", srcs = ["smoke_test.sh"])
service_test(
    name = "smoke_test",
    services = [":capsule_svc"],
    test = ":smoke_test_bin",
    tags = ["manual", "no-sandbox", "requires-network"],
)
```

The `tests/` directory in this repo is the canonical reference — read those
files for the exact shell scripts.

---

## Providers

### `CapsuleInfo`

A single Capsule install (currently always one per toolchain).

| Field | Type | Description |
|---|---|---|
| `version` | `string` | Capsule version, e.g. `"0.10.4"` |
| `manifest` | `File` | The pre-rendered, sha256-verified Capsule install YAML |
| `namespace` | `string` | Namespace the rendered manifest installs into (default `"capsule-system"`) |

---

## TLS provider prerequisite

Capsule's mutating + validating admission webhooks need TLS certs at runtime.
Capsule itself does **not** ship a CA; it expects something else in the
cluster (almost always [cert-manager](https://cert-manager.io/), occasionally
[trust-manager](https://github.com/cert-manager/trust-manager) or a custom
issuer) to mint them.

This rule does not own that piece — by design (DESIGN.md decision #6).
Reasons:

1. cert-manager is small, pinning is trivial, and many consumers already
   have it deployed by other means (Helm, ArgoCD, etc.). Owning it in
   `rules_capsule` would force a duplicate install path on those users.
2. Keeping the surface focused lets the cert-manager wiring live in its
   own focused rule set — [`rules_certmanager`](https://github.com/collider-bazel-extensions/rules_certmanager)
   — which any consumer can compose with rules_capsule (or use
   independently for any operator that needs cert-manager).

For the in-tree smoke test we depend on `rules_certmanager` directly
(`bazel_dep` with `dev_dependency = True`) and apply it as a separate
`itest_service` upstream of `capsule_install`. See the example above for
the shape, or `tests/BUILD.bazel` for the canonical wiring.

---

## Hermeticity exceptions

| Component | Hermeticity status | Notes |
|---|---|---|
| Capsule install YAML | Fully hermetic. Pre-rendered with `helm template` by a maintainer (`tools/render_capsule.sh`), committed under `private/manifests/`, sha256 in `private/versions.bzl`. | Update via the maintainer tool when bumping versions. Helm is **not** required at consumer test time. |
| `kubectl` | **Not vendored.** v0.1 trusts host `kubectl` on PATH. | Future v0.x: bundle a hermetic kubectl via toolchain. |
| Target cluster | Out of scope. Bring your own (`rules_kind`, real cluster, etc.). | The rule reads `KUBECONFIG` from env — anything that points there works. |
| TLS provider for webhooks | Out of scope. Bring your own. | See [TLS provider prerequisite](#tls-provider-prerequisite). |
| Capsule container images | **Pulled at runtime by the kind nodes.** The Capsule controller image (`projectcapsule/capsule:vX.Y.Z`) is not pre-loaded into the cluster. | Future: optional `images = [...]` attr on `capsule_install` for pre-loading via `kind_cluster.images`. |

---

## Contributing

PRs welcome. The repo is small; the bar is concrete: keep `bazel build //...`
and the analysis tests green, and bump pinned versions via the maintainer
tool (`tools/render_capsule.sh`) so future runs are no-op diffs.

Conventions:

- New rules need an analysis test in `tests/analysis_tests.bzl`.
- Bumping the pinned Capsule version: edit `MODULE.bazel`'s
  `capsule.version(version = ...)`, run
  `tools/render_capsule.sh <new-version>` to regenerate the manifest, then
  update `private/versions.bzl` with the new sha256.
- `MODULE.bazel.lock` is intentionally not committed (matches sibling rules).

### Help wanted: end-to-end smoke test on a Docker host

The smoke test composition (`//tests:smoke_test`) is **build-validated**
(`bazel build //tests:smoke_test` is green) but **not yet runtime-validated**
on any host. Two upstream gates currently block it:

1. **[rules_kind#1](https://github.com/collider-bazel-extensions/rules_kind/issues/1):**
   the `kind_cluster` launcher propagates Bazel's long `TEST_TMPDIR` via
   `TMPDIR`/`HOME`, exceeding the 108-char unix-socket limit and breaking
   rootless `podman`'s `conmon-term` socket. A patch is sketched in the
   issue; once it lands, kind clusters come up under `bazel test`.
2. **Rootless podman + nested containerd:** even with #1, cert-manager pods
   inside the kind node fail with
   `runc create failed: error mounting /etc/hostname: operation not permitted`
   because the inner user namespace can't bind-mount system files. **Docker
   (rooted by daemon) or rootful podman both clear it.** Pure rootless
   podman fundamentally cannot run kind workloads that need bind mounts.

Bottom line: a green run on `ubuntu-latest` GitHub Actions (or any host with
docker) would flip the smoke test from build-validated to runtime-validated
in v0.1.x. A pasted CI log is enough.

### Help wanted: macOS validation

The rule is platform-independent (just kubectl + YAML), but no one has run
the smoke test on Darwin. The `kind_cluster` story on macOS is via Docker
Desktop (which sidesteps the rootless-podman issues above). A green smoke
test on macOS arm64 or x86_64 — even a pasted log — flips this from "should
work" to "verified" in v0.1.x.

To validate on a Mac:

```bash
# 1. Host prereqs:
brew install bazelisk kubectl
# Install Docker Desktop (or colima, podman-desktop with rooted mode)

# 2. Clone + run:
git clone https://github.com/collider-bazel-extensions/rules_capsule
cd rules_capsule
bazel test //tests:smoke_test --test_tag_filters= --test_output=streamed --test_timeout=600
```
