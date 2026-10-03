#!/usr/bin/env bash
# Pre-flight checks before deploying the MCP Workshop.
# Validates cluster connectivity, permissions, LLM endpoint, and CRDs.
#
# Usage: ./deploy/preflight.sh --llm-url <url> --model-id <model>
set -euo pipefail

LLM_URL="${LLM_URL:-}"
MODEL_ID="${MODEL_ID:-}"
PASS=0
FAIL=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --llm-url)  LLM_URL="$2";  shift 2 ;;
    --model-id) MODEL_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✓ ${label}"
    PASS=$((PASS + 1))
  else
    echo "  ✗ ${label}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== MCP Workshop Pre-flight Checks ==="
echo ""

echo "--- Cluster connectivity ---"
check "oc is installed" command -v oc
check "helm is installed" command -v helm
check "Logged into cluster" oc whoami
check "Cluster reachable" oc get nodes --no-headers -o name

WHOAMI=$(oc whoami 2>/dev/null || echo "unknown")
echo ""
echo "--- Permissions (logged in as: ${WHOAMI}) ---"
check "Can create namespaces" oc auth can-i create namespaces
check "Can create CRDs" oc auth can-i create customresourcedefinitions
check "Can create subscriptions" oc auth can-i create subscriptions.operators.coreos.com -n openshift-operators
check "Can create rolebindings" oc auth can-i create rolebindings -n default

echo ""
echo "--- DevSpaces operator ---"
if oc api-resources 2>/dev/null | grep -q devworkspaces; then
  echo "  ✓ DevWorkspace CRD exists"
  PASS=$((PASS + 1))
  if oc get checluster devspaces -n openshift-devspaces >/dev/null 2>&1; then
    PHASE=$(oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.chePhase}' 2>/dev/null || echo "unknown")
    echo "  ✓ CheCluster exists (phase: ${PHASE})"
    PASS=$((PASS + 1))
  else
    echo "  ⚠ CheCluster not found — use cheCluster.create=true or make workshop-deploy-checluster"
  fi
else
  echo "  ⚠ DevWorkspace CRD not found — run 'make operator' first"
fi

echo ""
echo "--- LLM endpoint ---"
if [ -n "$LLM_URL" ]; then
  # Strip /v1 suffix for models endpoint
  MODELS_URL="${LLM_URL%/}/models"
  if curl -sk --connect-timeout 5 "$MODELS_URL" 2>/dev/null | grep -q '"object"'; then
    echo "  ✓ LLM endpoint reachable: ${LLM_URL}"
    PASS=$((PASS + 1))
    if [ -n "$MODEL_ID" ]; then
      if curl -sk --connect-timeout 5 "$MODELS_URL" 2>/dev/null | grep -q "\"${MODEL_ID}\""; then
        echo "  ✓ Model '${MODEL_ID}' found"
        PASS=$((PASS + 1))
      else
        echo "  ✗ Model '${MODEL_ID}' not found at endpoint"
        FAIL=$((FAIL + 1))
      fi
    fi
  else
    echo "  ✗ LLM endpoint not reachable: ${MODELS_URL}"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  ⚠ No --llm-url provided (skipping endpoint check)"
fi

echo ""
echo "--- OpenCode build image ---"
if oc get istag devspaces-opencode:latest -n opencode-build >/dev/null 2>&1; then
  echo "  ✓ OpenCode image already built"
  PASS=$((PASS + 1))
else
  echo "  ⚠ OpenCode image not built yet (will be built on first deploy)"
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Fix the failures above before deploying."
  exit 1
fi
echo "All checks passed — ready to deploy."
