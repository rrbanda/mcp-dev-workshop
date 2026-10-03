#!/usr/bin/env bash
# Deploy MCP Workshop DevSpaces for N participants.
#
# Usage:
#   ./deploy/workshop-deploy.sh \
#     --llm-url https://maas.apps.other-cluster.example.com/ai-serving/model/v1 \
#     --llm-api-key sk-xxxxxxxx \
#     --model-id qwen25-coder-7b \
#     --user-prefix user \
#     --user-count 30
#
# Requires: helm, oc (logged in as cluster-admin)
set -euo pipefail

# ---- Defaults ----
LLM_URL="${LLM_URL:-}"
LLM_API_KEY="${LLM_API_KEY:-EMPTY}"
MODEL_ID="${MODEL_ID:-}"
USER_PREFIX="${USER_PREFIX:-user}"
USER_COUNT="${USER_COUNT:-30}"
CHART_DIR="${CHART_DIR:-chart}"
CREATE_CHECLUSTER="${CREATE_CHECLUSTER:-false}"
CONTEXT_TOKENS="${CONTEXT_TOKENS:-20000}"
OUTPUT_TOKENS="${OUTPUT_TOKENS:-4096}"

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
  case $1 in
    --llm-url)        LLM_URL="$2";          shift 2 ;;
    --llm-api-key)    LLM_API_KEY="$2";      shift 2 ;;
    --model-id)       MODEL_ID="$2";         shift 2 ;;
    --user-prefix)    USER_PREFIX="$2";      shift 2 ;;
    --user-count)     USER_COUNT="$2";       shift 2 ;;
    --create-checluster) CREATE_CHECLUSTER="true"; shift ;;
    --context-tokens) CONTEXT_TOKENS="$2";   shift 2 ;;
    --output-tokens)  OUTPUT_TOKENS="$2";    shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ---- Validate ----
if [ -z "$LLM_URL" ]; then
  echo "ERROR: --llm-url is required (e.g. https://maas.apps.cluster.example.com/ns/model/v1)" >&2
  exit 1
fi
if [ -z "$MODEL_ID" ]; then
  echo "ERROR: --model-id is required (e.g. llama32-fp8)" >&2
  exit 1
fi
if ! [[ $USER_COUNT =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --user-count must be a positive integer (got '$USER_COUNT')" >&2
  exit 1
fi

echo "=== MCP Workshop Deploy ==="
echo "  LLM URL:      $LLM_URL"
echo "  Model ID:     $MODEL_ID"
echo "  API Key:      ${LLM_API_KEY:0:6}..."
echo "  Users:        ${USER_PREFIX}1..${USER_PREFIX}${USER_COUNT}"
echo "  CheCluster:   $CREATE_CHECLUSTER"
echo ""

# ---- Step 1: Deploy first user (owns opencode-build + globalConfig) ----
deploy_one() {
  local user="$1"
  local ns="${user}-devspaces"
  local global_cfg="$2"
  local build_enabled="$3"

  # Create and label the namespace for DevSpaces
  oc create namespace "$ns" --dry-run=client -o yaml | oc apply -f -
  oc label namespace "$ns" \
    app.kubernetes.io/component=workspaces-namespace \
    app.kubernetes.io/part-of=che.eclipse.org --overwrite
  oc annotate namespace "$ns" \
    che.eclipse.org/username="$user" --overwrite

  helm upgrade --install "${ns}-workshop" "$CHART_DIR" \
    --namespace "$ns" \
    --set "llm.baseUrl=${LLM_URL}" \
    --set "llm.apiKey=${LLM_API_KEY}" \
    --set "llm.modelId=${MODEL_ID}" \
    --set "llm.tokens.context=${CONTEXT_TOKENS}" \
    --set "llm.tokens.output=${OUTPUT_TOKENS}" \
    --set "user.name=${user}" \
    --set "opencodeBuild.enabled=${build_enabled}" \
    --set "globalConfig.enabled=${global_cfg}" \
    --set "cheCluster.create=false"

  echo "  ✓ ${user} → ${ns}"
}

# First user: create CheCluster (if requested), OpenCode build, global config
first_user="${USER_PREFIX}1"
first_ns="${first_user}-devspaces"

if [ "$CREATE_CHECLUSTER" = "true" ]; then
  echo "--- Creating CheCluster ---"
  # Ensure openshift-devspaces namespace exists (chart also creates it,
  # but the namespace must exist before Helm can apply resources into it).
  oc create namespace openshift-devspaces --dry-run=client -o yaml | oc apply -f -

  oc create namespace "$first_ns" --dry-run=client -o yaml | oc apply -f -
  oc label namespace "$first_ns" \
    app.kubernetes.io/component=workspaces-namespace \
    app.kubernetes.io/part-of=che.eclipse.org --overwrite
  oc annotate namespace "$first_ns" \
    che.eclipse.org/username="$first_user" --overwrite

  helm upgrade --install "${first_ns}-workshop" "$CHART_DIR" \
    --namespace "$first_ns" \
    --set "llm.baseUrl=${LLM_URL}" \
    --set "llm.apiKey=${LLM_API_KEY}" \
    --set "llm.modelId=${MODEL_ID}" \
    --set "llm.tokens.context=${CONTEXT_TOKENS}" \
    --set "llm.tokens.output=${OUTPUT_TOKENS}" \
    --set "user.name=${first_user}" \
    --set "opencodeBuild.enabled=true" \
    --set "globalConfig.enabled=true" \
    --set "cheCluster.create=true"
  echo "  ✓ ${first_user} → ${first_ns} (CheCluster + opencode-build + globalConfig)"

  echo "--- Waiting for CheCluster to become Active ---"
  oc wait checluster/devspaces -n openshift-devspaces \
    --for=jsonpath='{.status.chePhase}'=Active --timeout=300s 2>/dev/null || \
    echo "  ⚠ CheCluster not Active yet — may still be starting. Continuing with user deploys."
  start_idx=2
else
  echo "--- Deploying first user (opencode-build + globalConfig) ---"
  deploy_one "$first_user" "true" "true"
  start_idx=2
fi

# ---- Step 2: Wait for opencode-build image ----
echo "--- Waiting for OpenCode image build ---"
# Check if build already completed
if oc get istag devspaces-opencode:latest -n opencode-build >/dev/null 2>&1; then
  echo "  ✓ Image already exists"
else
  echo "  Starting build (this takes 2-3 minutes)..."
  # ConfigChange trigger should auto-start, but ensure it's running
  oc start-build devspaces-opencode -n opencode-build 2>/dev/null || true
  oc wait build -n opencode-build -l buildconfig=devspaces-opencode \
    --for=condition=Complete --timeout=600s 2>/dev/null || \
    echo "  ⚠ Build not complete yet — workspaces will wait for image"
fi

# ---- Step 3: Deploy remaining users in parallel ----
if [ "$USER_COUNT" -gt 1 ]; then
  echo "--- Deploying ${USER_PREFIX}${start_idx}..${USER_PREFIX}${USER_COUNT} in parallel ---"
  log_dir=$(mktemp -d)
  pids=()
  users=()

  for i in $(seq "$start_idx" "$USER_COUNT"); do
    user="${USER_PREFIX}${i}"
    deploy_one "$user" "false" "false" >"${log_dir}/${user}.log" 2>&1 &
    pids+=("$!")
    users+=("$user")
  done

  fail=0
  for idx in "${!pids[@]}"; do
    user="${users[$idx]}"
    if wait "${pids[$idx]}"; then
      echo "  ✓ ${user}"
    else
      echo "  ✗ ${user} FAILED:"
      cat "${log_dir}/${user}.log" | sed 's/^/    /'
      fail=1
    fi
  done
  rm -rf "$log_dir"

  if [ "$fail" -ne 0 ]; then
    echo "ERROR: one or more deployments failed" >&2
    exit 1
  fi
fi

echo ""
echo "=== Deploy complete ==="
echo "  ${USER_COUNT} workspaces created (started: false)"
echo "  Participants start their workspace from the DevSpaces dashboard."
echo ""
echo "  Run 'make credentials' to generate credentials cards."
