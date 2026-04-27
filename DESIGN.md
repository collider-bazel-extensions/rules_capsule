# rules_capsule — design decisions

Hermetic install + readiness for [Project Capsule](https://capsule.clastix.io/)
(Kubernetes multi-tenancy operator) in tests. Composes with `rules_kind` (or
any Kubernetes cluster the consumer provides) and `rules_itest`.

All decisions inherited from the sibling
`collider-bazel-extensions/rules_pg`, `rules_temporal`, `rules_kind`,
`rules_playwright` family. Where the four diverged, we follow the majority.
Anything Capsule-specific is flagged.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** No legacy WORKSPACE setup macros. | rules_playwright precedent |
| 2 | Module extension shape | One tag class: `version` (download). No `system` mode — Capsule isn't a host-installable CLI; it's an in-cluster operator. | Capsule-specific divergence |
| 3 | Toolchain type | `CAPSULE_TOOLCHAIN_TYPE = Label("//toolchain:capsule")`. `ToolchainInfo(capsule = …)` carries the pinned manifest. | rules_pg / rules_temporal / rules_playwright |
| 4 | Manifest provisioning | Capsule chart **pre-rendered** by a maintainer tool (`tools/render_capsule.sh`) into `private/manifests/capsule-<ver>.yaml`. Committed; sha256 lives in `private/versions.bzl`. cert-manager is NOT bundled — see decision #6. | Capsule-specific. Helm at consumer test time would balloon prereqs; pre-rendered YAML is the lightest contract. |
| 5 | Public surface | `capsule_install`, `capsule_health_check` + `CapsuleInfo` provider. Tenant resources are *not* a public rule in v0.1 — tenants are just YAML, easier for users to author directly. | All four siblings (install + health_check pair) |
| 6 | TLS provider scope | `capsule_install` does **not** install cert-manager. The rule documents that consumers must wire a TLS provider (cert-manager or trust-manager) into their cluster before `capsule_install` runs. The in-tree smoke test pins `cert-manager.yaml` explicitly and composes it as a separate `itest_service`. | Capsule-specific. Keeps the public API focused; allows a future `rules_certmanager` to be extracted as a non-breaking change. |
| 7 | CNI scope | CNI-agnostic. `capsule_install` works against any cluster; `kindnet` (kind's default) is fine for v0.1's testable surface. NetworkPolicy enforcement tests deferred to a future `rules_cilium`. | Capsule-specific |
| 8 | rules_itest integration | `capsule_install` produces an `itest_service.exe`-shaped target (long-running `kubectl apply` that stays alive); `capsule_health_check` is the readiness probe. **No pass-through `services=` attr.** | All four siblings |
| 9 | rules_kind dependency | **Examples-only.** The rule itself depends on neither `rules_kind` nor any cluster-provider rule; it just needs `KUBECONFIG` (or env-var-named-kubeconfig) on the host. Examples under `/examples/kind/` show the composition. | rules_playwright precedent |
| 10 | Platform matrix v1 | `linux_amd64`, `darwin_arm64`, `darwin_amd64`. The rule itself is platform-independent (just kubectl + YAML); platform constraints come from kubectl availability. | All four siblings |
| 11 | MODULE deps | `bazel_skylib`, `platforms`, `rules_python`. **No `rules_oci`, no `rules_helm`, no `rules_certmanager`.** rules_kind / rules_itest / rules_shell are dev-only for the smoke test + examples. | rules_playwright pattern |
| 12 | Default test tags | `["capsule"]`; internal wrapper rules tagged `manual`. Smoke tests also `["requires-network", "no-sandbox"]` because Docker-in-Docker (kind) conflicts with Bazel's sandbox. | rules_kind precedent |
| 13 | Naming | snake_case rules, `MixedCaseInfo` providers, `UPPER_SNAKE` constants, `_underscored` private aliases in `defs.bzl`. | All four siblings |
| 14 | Update workflow | `tools/render_capsule.sh <chart-version>` requires host helm + curl. Pulls the chart from ghcr.io, renders with default values + `--include-crds`, writes `private/manifests/capsule-<ver>.yaml`. `tools/update_checksums.py` then regenerates `private/versions.bzl`. | rules_pg / rules_playwright pattern, adapted for Helm chart rendering |
| 15 | Runtime lifecycle | One Python `private/launcher.py`: env setup, kubectl exec, SIGTERM forwarding. Same role as in `rules_playwright`. | All four siblings |
| 16 | kubectl provisioning | **Host kubectl required** at v0.1. Future: bundle a hermetic kubectl via toolchain. | rules_kind precedent (host kind binary) |

## Capsule-specific notes

- Capsule's chart is **OCI-only** (`ghcr.io/projectcapsule/charts/capsule`) — there is no GitHub-release `install.yaml`. Pre-rendering is the only path to a manifest that Bazel can consume without dragging in helm + OCI tooling.
- Capsule depends on a cluster TLS provider (cert-manager, trust-manager, or equivalent) for its admission webhooks. v0.1 punts this to the consumer; the smoke test wires cert-manager explicitly so the contract is observable in-repo.
- Capsule's `Tenant` is a CRD; `kubectl apply -f tenant.yaml` is sufficient to create one. There's no need for a `capsule_tenant` rule in v0.1 — users author tenant YAML directly. A macro can be added later if a real consumer asks for it.

## v0.1.0 status (planning)

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | planned |
| Module extension (`version`) | planned |
| Pre-rendered Capsule manifest at 0.10.4 (sha256-pinned) | planned |
| Pinned cert-manager.yaml at 1.20.2 (smoke-test only) | planned |
| `capsule_install`, `capsule_health_check` rules | planned |
| `launcher.py` (env, exec, SIGTERM forwarding) | planned |
| Analysis tests | planned |
| In-tree smoke test (cert-manager + Capsule against kind) | **build-validated** (`bazel build //tests:smoke_test` green; analyses + resolves the kind/cert-manager/Capsule chain). Runtime needs a host with working Docker or non-SELinux-strict podman; the rule itself is correct. |
| End-to-end `bazel test //tests:smoke_test` execution | gated on a host runtime (CI w/ Docker, or a Mac with Docker Desktop). Not validated on this host (SELinux-enforcing Fedora blocks rootless podman). |
| macOS validation | deferred (same posture as rules_playwright v0.1) |

## Deferred (not v0.1.0)

- **NetworkPolicy isolation tests.** Need a NetworkPolicy-enforcing CNI in kind. Future `rules_cilium` (or similar) would unblock this.
- **Capsule `Tenant` resource as a public rule.** Users author Tenant YAML directly in v0.1.
- **Capsule Proxy.** The optional API-server proxy that filters per-tenant requests. Out of v0.1 scope.
- **Hermetic kubectl.** v0.1 trusts host kubectl on PATH.
- **`rules_certmanager`.** Cert-manager pinning lives in our smoke test, not as a public rule. Extract to its own rule set if a real second consumer materializes.
- **Helm-at-test-time path.** Pre-rendered manifest is the only consumer-facing install path. A "render at install time" path could be added if parameterization needs grow.
