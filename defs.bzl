"""Public API for rules_capsule.

Re-exports of private impl symbols + providers. Anything not re-exported
here is private to the rule set.
"""

load("//private:capsule_health_check.bzl", _capsule_health_check = "capsule_health_check")
load("//private:capsule_install.bzl", _capsule_install = "capsule_install")
load("//private:providers.bzl", _CapsuleInfo = "CapsuleInfo")

capsule_install = _capsule_install
capsule_health_check = _capsule_health_check

CapsuleInfo = _CapsuleInfo
