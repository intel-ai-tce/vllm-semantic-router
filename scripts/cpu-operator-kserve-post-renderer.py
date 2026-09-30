#!/usr/bin/env python3
"""Helm post-renderer for CPU Operator-aware KServe InferenceServices."""

import os
import sys
import yaml

NODE = os.environ.get("CPU_OPERATOR_NODE", "").strip()
if not NODE:
    raise SystemExit("CPU_OPERATOR_NODE must be set")

TARGETS = {
    "qwen3-8b",
    "granite-3-1-8b-instruct",
    "granite-3-1-2b-instruct",
}
DISABLE_ISTIO = os.environ.get("CPU_OPERATOR_DISABLE_ISTIO", "1") == "1"

docs = list(yaml.safe_load_all(sys.stdin))
for doc in docs:
    if not isinstance(doc, dict):
        continue
    if doc.get("kind") != "InferenceService":
        continue
    name = ((doc.get("metadata") or {}).get("name") or "")
    if name not in TARGETS:
        continue

    metadata = doc.setdefault("metadata", {})
    annotations = metadata.setdefault("annotations", {})
    if DISABLE_ISTIO:
        annotations["sidecar.istio.io/inject"] = "false"
        annotations["sidecar.istio.io/rewriteAppHTTPProbers"] = "false"

    predictor = doc.setdefault("spec", {}).setdefault("predictor", {})
    selector = predictor.setdefault("nodeSelector", {})
    selector["kubernetes.io/hostname"] = NODE
    selector["cpu.example.com/placement-ready"] = "true"
    selector["cpu.example.com/node-class"] = "mixed-cpu-amx-gpu"

yaml.safe_dump_all(docs, sys.stdout, sort_keys=False, explicit_start=True)
