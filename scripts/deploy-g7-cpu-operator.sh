#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${CHART:-${ROOT_DIR}/deploy/helm/vllm-semantic-router}"
RELEASE="${RELEASE:-vllm-semantic-router}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-vllm-semantic-router}"
STATIC_VALUES="${STATIC_VALUES:-${CHART}/values-g7-cpu-operator.yaml}"
GENERATED_VALUES="${GENERATED_VALUES:-/tmp/values-g7-cpu-operator.generated.yaml}"
NODE="${NODE:-}"

fail() { echo "[FAIL] $*" >&2; exit 1; }
command -v oc >/dev/null || fail "oc command not found"
command -v helm >/dev/null || fail "helm command not found"
[[ -n "${HF_TOKEN:-}" ]] || fail "HF_TOKEN must be set"

if [[ -z "${NODE}" ]]; then
  NODE="$(oc get nodes -l 'cpu.example.com/node-class=mixed-cpu-amx-gpu,cpu.example.com/placement-ready=true' \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
[[ -n "${NODE}" ]] || fail "No CPU Operator mixed-cpu-amx-gpu node found; set NODE explicitly"

export NODE TARGET_NAMESPACE OUTPUT="${GENERATED_VALUES}"
"${ROOT_DIR}/scripts/generate-g7-cpu-operator-values.sh"

echo "[INFO] Generated dynamic values: ${GENERATED_VALUES}"
cat "${GENERATED_VALUES}"

echo "[INFO] Updating Helm dependencies"
helm dependency build "${CHART}"

export CPU_OPERATOR_NODE="${NODE}"
export CPU_OPERATOR_DISABLE_ISTIO="${CPU_OPERATOR_DISABLE_ISTIO:-1}"

oc get namespace "${TARGET_NAMESPACE}" >/dev/null 2>&1 || oc create namespace "${TARGET_NAMESPACE}"

helm upgrade --install "${RELEASE}" "${CHART}" \
  -n "${TARGET_NAMESPACE}" \
  -f "${CHART}/values.yaml" \
  -f "${STATIC_VALUES}" \
  -f "${GENERATED_VALUES}" \
  --set-string llm-service-research.secret.hf_token="${HF_TOKEN}" \
  --set-string llm-service-rag.secret.hf_token="${HF_TOKEN}" \
  --set-string llm-service-general.secret.hf_token="${HF_TOKEN}" \
  --set-string semanticRouter.hfToken="${HF_TOKEN}" \
  --post-renderer "${ROOT_DIR}/scripts/cpu-operator-kserve-post-renderer.py"

echo
oc get inferenceservice -n "${TARGET_NAMESPACE}" 2>/dev/null || true
oc get pods -n "${TARGET_NAMESPACE}" -o wide
