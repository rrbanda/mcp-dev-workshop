#!/usr/bin/env bash
#
# Enable the RHOAI 3.5 Gen AI Playground for MCP server testing.
#
# This script is run ONCE by a facilitator before the workshop starts.
# It is idempotent — safe to re-run.
#
# What it does:
#   1. Enables the Gen AI Studio dashboard navigation
#   2. Enables the OGX Operator (required for the Playground UI)
#   3. Enables Models-as-a-Service in the dashboard
#   4. Creates the gen-ai-aa-mcp-servers ConfigMap so the Playground
#      can discover workshop MCP servers via the MCP Gateway
#
# Prerequisites:
#   - oc CLI authenticated as cluster-admin
#   - MCP Gateway deployed in mcp-system namespace
#   - RHOAI 3.5+ installed
#
# Usage:
#   ./scripts/setup-playground.sh
#   ./scripts/setup-playground.sh --gateway-ns mcp-system
#
set -euo pipefail

GATEWAY_NS="${GATEWAY_NS:-mcp-system}"
RHOAI_NS="${RHOAI_NS:-redhat-ods-applications}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --gateway-ns)  GATEWAY_NS="$2";  shift 2 ;;
    --rhoai-ns)    RHOAI_NS="$2";    shift 2 ;;
    --help)
      echo "Usage: $0 [--gateway-ns NS] [--rhoai-ns NS]"
      echo "  --gateway-ns   MCP Gateway namespace (default: mcp-system)"
      echo "  --rhoai-ns     RHOAI applications namespace (default: redhat-ods-applications)"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

info()  { printf "\033[36m[INFO]\033[0m %s\n" "$1"; }
pass()  { printf "\033[32m[DONE]\033[0m %s\n" "$1"; }
fail()  { printf "\033[31m[FAIL]\033[0m %s\n" "$1"; exit 1; }
warn()  { printf "\033[33m[WARN]\033[0m %s\n" "$1"; }

# ── Pre-flight checks ─────────────────────────────────────────
info "Verifying cluster connectivity..."
oc whoami >/dev/null 2>&1 || fail "Not logged in to cluster. Run 'oc login' first."
CONSOLE=$(oc whoami --show-console 2>/dev/null || echo "unknown")
info "Cluster console: $CONSOLE"

info "Verifying RHOAI namespace ($RHOAI_NS)..."
oc get namespace "$RHOAI_NS" >/dev/null 2>&1 || fail "Namespace $RHOAI_NS not found. Is RHOAI installed?"

info "Verifying MCP Gateway namespace ($GATEWAY_NS)..."
oc get namespace "$GATEWAY_NS" >/dev/null 2>&1 || fail "Namespace $GATEWAY_NS not found. Run ./scripts/setup-platform.sh first to deploy the MCP Gateway."

# ── Step 1: Enable Gen AI Studio ───────────────────────────────
info "Step 1: Enabling Gen AI Studio in the dashboard..."
CURRENT=$(oc get odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
  -o jsonpath='{.spec.dashboardConfig.genAiStudio}' 2>/dev/null || echo "")
if [ "$CURRENT" = "true" ]; then
  pass "Gen AI Studio already enabled"
else
  oc patch odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
    --type=merge \
    -p '{"spec":{"dashboardConfig":{"genAiStudio":true}}}'
  pass "Gen AI Studio enabled (genAiStudio: true)"
fi

# ── Step 2: Enable OGX Operator ────────────────────────────────
info "Step 2: Enabling OGX Operator..."
DSC_NAME=$(oc get datasciencecluster -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$DSC_NAME" ]; then
  fail "No DataScienceCluster found. Is RHOAI installed?"
fi
OGX_STATE=$(oc get datasciencecluster "$DSC_NAME" \
  -o jsonpath='{.spec.components.ogx.managementState}' 2>/dev/null || echo "")
if [ "$OGX_STATE" = "Managed" ]; then
  pass "OGX Operator already Managed"
else
  oc patch datasciencecluster "$DSC_NAME" --type=merge \
    -p '{"spec":{"components":{"ogx":{"managementState":"Managed"}}}}'
  pass "OGX Operator set to Managed"
  info "Waiting for OGX pods to start (this may take 1-2 minutes)..."
  sleep 10
fi

# ── Step 3: Enable Models-as-a-Service ─────────────────────────
info "Step 3: Enabling Models-as-a-Service in the dashboard..."
MAAS_CURRENT=$(oc get odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
  -o jsonpath='{.spec.dashboardConfig.modelAsService}' 2>/dev/null || echo "")
if [ "$MAAS_CURRENT" = "true" ]; then
  pass "Models-as-a-Service already enabled"
else
  oc patch odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
    --type=merge \
    -p '{"spec":{"dashboardConfig":{"modelAsService":true}}}'
  pass "Models-as-a-Service enabled (modelAsService: true)"
fi

# ── Step 4: Get MCP Gateway hostname ──────────────────────────
info "Step 4: Deriving MCP Gateway hostname..."
GW_HOSTNAME=$(oc get gateway mcp-gateway -n "$GATEWAY_NS" \
  -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null || echo "")
if [ -z "$GW_HOSTNAME" ]; then
  fail "Could not read gateway hostname from mcp-gateway in $GATEWAY_NS. Run ./scripts/setup-platform.sh first to deploy the MCP Gateway."
fi
pass "MCP Gateway hostname: $GW_HOSTNAME"

# Determine protocol — check if the gateway listener uses HTTPS or HTTP
# NOTE: The Playground MCP client runs server-side (inside the lsd-genai-playground pod).
# The external hostname should resolve from inside the cluster via OpenShift's internal
# DNS + Ingress. If it does not, you may need to use the internal service URL instead:
#   http://mcp-gateway.mcp-system.svc.cluster.local:80/mcp
# Test from a pod: oc exec -n redhat-ods-applications deploy/odh-dashboard -- curl -s http://$GW_HOSTNAME/mcp
GW_PROTOCOL=$(oc get gateway mcp-gateway -n "$GATEWAY_NS" \
  -o jsonpath='{.spec.listeners[0].protocol}' 2>/dev/null || echo "HTTP")
if [ "$GW_PROTOCOL" = "HTTPS" ] || [ "$GW_PROTOCOL" = "TLS" ]; then
  GW_URL="https://${GW_HOSTNAME}/mcp"
else
  GW_URL="http://${GW_HOSTNAME}/mcp"
fi
info "MCP Gateway URL for Playground: $GW_URL"

# ── Step 5: Create gen-ai-aa-mcp-servers ConfigMap ─────────────
info "Step 5: Creating gen-ai-aa-mcp-servers ConfigMap..."
cat <<EOF | oc apply -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: gen-ai-aa-mcp-servers
  namespace: ${RHOAI_NS}
data:
  Stock-Market-MCP-Gateway: |
    {
      "url": "${GW_URL}",
      "description": "MCP Gateway — federated access to all workshop participants stock market MCP servers. Each participants tools are prefixed with their username (e.g. user1_stock_get_stock_info). Deploy your own server and register it with the gateway to see your tools here."
    }
EOF
pass "ConfigMap gen-ai-aa-mcp-servers created/updated in $RHOAI_NS"

# ── Verification ──────────────────────────────────────────────
echo ""
info "=== Verification ==="

echo -n "  Gen AI Studio:       "
VAL=$(oc get odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
  -o jsonpath='{.spec.dashboardConfig.genAiStudio}' 2>/dev/null || echo "unknown")
echo "$VAL"

echo -n "  OGX Operator:        "
VAL=$(oc get datasciencecluster "$DSC_NAME" \
  -o jsonpath='{.spec.components.ogx.managementState}' 2>/dev/null || echo "unknown")
echo "$VAL"

echo -n "  Models-as-a-Service: "
VAL=$(oc get odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
  -o jsonpath='{.spec.dashboardConfig.modelAsService}' 2>/dev/null || echo "unknown")
echo "$VAL"

echo -n "  MCP ConfigMap:       "
VAL=$(oc get configmap gen-ai-aa-mcp-servers -n "$RHOAI_NS" \
  -o jsonpath='{.data}' 2>/dev/null | head -c 80 || echo "not found")
echo "${VAL}..."

echo ""
pass "=== Playground Setup Complete ==="
echo ""
echo "  Dashboard URL:    ${CONSOLE}"
echo "  Gateway URL:      ${GW_URL}"
echo "  ConfigMap key:    Stock-Market-MCP-Gateway"
echo ""
echo "  Participants can now:"
echo "    1. Open Gen AI Studio → Playground"
echo "    2. Select their project and create a playground"
echo "    3. Choose the llama-32-3b MaaS model"
echo "    4. Go to the MCP tab and enable Stock-Market-MCP-Gateway"
echo "    5. Test their deployed MCP tools from the chat"
echo ""
