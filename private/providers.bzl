"""Providers exported by rules_capsule."""

CapsuleInfo = provider(
    doc = "The resolved Capsule install: pinned version + path to the " +
          "pre-rendered manifest YAML the consumer applies into a cluster.",
    fields = {
        "version": "Capsule version string, e.g. '0.10.4'.",
        "manifest": "File: the rendered Capsule install YAML.",
        "namespace": "string: namespace Capsule is rendered to install into.",
    },
)
