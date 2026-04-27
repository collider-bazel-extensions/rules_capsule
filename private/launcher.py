#!/usr/bin/env python3
"""Runtime launcher for capsule_install / capsule_health_check.

Same role as `launcher.py` in rules_pg / rules_temporal / rules_kind /
rules_playwright. Owns:
- env setup (KUBECONFIG resolution, PATH)
- exec of `kubectl` against the resolved kubeconfig
- SIGTERM/SIGINT forwarding so itest can stop the long-running
  install service cleanly
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time


def _resolve_runfiles(rel: str) -> str:
    rfd = os.environ.get("RUNFILES_DIR") or os.environ.get("TEST_SRCDIR")
    if not rfd:
        return rel
    candidate = os.path.join(rfd, "_main", rel)
    if os.path.exists(candidate):
        return candidate
    candidate = os.path.join(rfd, rel)
    if os.path.exists(candidate):
        return candidate
    return rel


def _kubeconfig_from_env(name: str) -> str | None:
    """Resolve KUBECONFIG: prefer `<kubeconfig_env>` (set by rules_kind /
    consumer wiring), fall back to `KUBECONFIG`, finally None."""
    if name and os.environ.get(name):
        return os.environ[name]
    if os.environ.get("KUBECONFIG"):
        return os.environ["KUBECONFIG"]
    return None


def _run(cmd: list[str], env: dict[str, str]) -> int:
    print("rules_capsule: " + " ".join(cmd), file=sys.stderr, flush=True)
    return subprocess.run(cmd, env=env).returncode


def _install(args, env: dict[str, str]) -> int:
    manifest = _resolve_runfiles(args.manifest)
    if not os.path.isfile(manifest):
        print(f"rules_capsule: manifest not in runfiles: {manifest}", file=sys.stderr)
        return 2

    kubectl = shutil.which("kubectl")
    if not kubectl:
        print("rules_capsule: `kubectl` not found on PATH", file=sys.stderr)
        return 127

    kubeconfig = _kubeconfig_from_env(args.kubeconfig_env)
    if not kubeconfig:
        print(
            f"rules_capsule: no kubeconfig — set ${args.kubeconfig_env} or $KUBECONFIG.",
            file=sys.stderr,
        )
        return 2
    env["KUBECONFIG"] = kubeconfig

    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "apply", "-f", manifest,
         "--server-side=true", "--validate=false"],
        env,
    )
    if rc != 0:
        return rc

    # Stay alive so itest treats us as a long-running service. The actual
    # readiness gate is `capsule_health_check`, which itest polls.
    print("rules_capsule: install applied; sleeping until SIGTERM", file=sys.stderr, flush=True)
    while True:
        time.sleep(3600)


def _health_check(args, env: dict[str, str]) -> int:
    kubectl = shutil.which("kubectl")
    if not kubectl:
        print("rules_capsule: `kubectl` not found on PATH", file=sys.stderr)
        return 127

    kubeconfig = _kubeconfig_from_env(args.kubeconfig_env)
    if not kubeconfig:
        print(
            f"rules_capsule: no kubeconfig — set ${args.kubeconfig_env} or $KUBECONFIG.",
            file=sys.stderr,
        )
        return 2
    env["KUBECONFIG"] = kubeconfig

    # Three signals that "Capsule is ready":
    #   1. CRDs registered (api-resources mentions tenants.capsule.clastix.io)
    #   2. controller-manager Deployment Available=True
    #   3. webhook serving (we infer from #2; a Deployment Available implies
    #      readiness probes pass, which for Capsule means the webhook is up)
    ns = args.namespace
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "get", "crd",
         "tenants.capsule.clastix.io", "-o", "name"],
        env,
    )
    if rc != 0:
        return rc
    rc = _run(
        [kubectl, "--kubeconfig", kubeconfig, "-n", ns, "wait", "deploy",
         "--all", "--for=condition=Available", "--timeout=0s"],
        env,
    )
    return rc


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["install", "health_check"], required=True)
    ap.add_argument("--manifest", default="", help="Pre-rendered Capsule YAML (install mode).")
    ap.add_argument("--namespace", default="capsule-system")
    ap.add_argument("--kubeconfig-env", default="KUBECONFIG",
                    help="Env var holding the path to the kubeconfig file. " +
                         "Defaults to KUBECONFIG; rules_kind compositions " +
                         "typically set KUBECONFIG_<cluster> via itest.")
    args = ap.parse_args(argv[1:])

    env = os.environ.copy()

    if args.mode == "install":
        proc_func = lambda: _install(args, env)
    else:
        proc_func = lambda: _health_check(args, env)

    # SIGTERM forwarding for `install` mode (idle sleep loop). For
    # `health_check` mode the process is short-lived and forwarding is moot.
    rc = [None]

    def handle(_signum, _frame):
        sys.exit(143)

    signal.signal(signal.SIGTERM, handle)
    signal.signal(signal.SIGINT, handle)

    rc[0] = proc_func()
    return rc[0] or 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
