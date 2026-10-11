#!/usr/bin/env bash
# ============================================================================
# MCP Workshop — Pre-flight Readiness Check
# ============================================================================
# Validates that the cluster is fully ready for participants.
# Run this 30-60 minutes before the workshop starts.
#
# Usage:
#   ./deploy/preflight.sh                          # defaults: 30 users, no LLM check
#   ./deploy/preflight.sh --user-count 15          # check 15 users
#   ./deploy/preflight.sh --llm-url <url> --model-id <model>
# ============================================================================
set -euo pipefail

LLM_URL="${LLM_URL:-}"
MODEL_ID="${MODEL_ID:-}"
USER_COUNT="${USER_COUNT:-30}"
PASS=0
FAIL=0
WARN=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --llm-url)     LLM_URL="$2";     shift 2 ;;
    --model-id)    MODEL_ID="$2";     shift 2 ;;
    --user-count)  USER_COUNT="$2";   shift 2 ;;
    *) shift ;;
  esac
done

# --- Helpers ----------------------------------------------------------------
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }
info() { echo "  ℹ️  $1"; }

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        MCP Workshop — Pre-flight Readiness Check           ║"
echo "║        Users: ${USER_COUNT}                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# === 1. Cluster Connectivity ================================================
echo "─── 1. Cluster Connectivity ───"
check "oc CLI installed" command -v oc
check "helm CLI installed" command -v helm
check "Logged into cluster" oc whoami
check "Cluster reachable" oc get nodes --no-headers -o name

WHOAMI=$(oc whoami 2>/dev/null || echo "unknown")
API_SERVER=$(oc whoami --show-server 2>/dev/null || echo "unknown")
APPS_DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "unknown")
OCP_VERSION=$(oc version -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('openshiftVersion','unknown'))" 2>/dev/null || echo "unknown")
info "Logged in as: ${WHOAMI}"
info "API: ${API_SERVER}"
info "Apps domain: ${APPS_DOMAIN}"
info "OCP version: ${OCP_VERSION}"

echo ""
echo "─── 2. Admin Permissions ───"
check "Can create namespaces" oc auth can-i create namespaces
check "Can create CRDs" oc auth can-i create customresourcedefinitions
check "Can create subscriptions" oc auth can-i create subscriptions.operators.coreos.com -n openshift-operators
check "Can impersonate users" oc auth can-i impersonate users

# === 3. DevSpaces ===========================================================
echo ""
echo "─── 3. DevSpaces Operator ───"
if oc get crd devworkspaces.workspace.devfile.io >/dev/null 2>&1; then
  pass "DevWorkspace CRD exists"
  if oc get checluster devspaces -n openshift-devspaces >/dev/null 2>&1; then
    PHASE=$(oc get checluster devspaces -n openshift-devspaces -o jsonpath='{.status.chePhase}' 2>/dev/null || echo "unknown")
    if [ "$PHASE" = "Active" ]; then
      pass "CheCluster: Active"
    else
      fail "CheCluster phase: ${PHASE} (expected: Active)"
    fi
  else
    fail "CheCluster not found in openshift-devspaces"
  fi
else
  fail "DevWorkspace CRD not found — DevSpaces operator not installed"
fi

# Idle timeout
IDLE_TIMEOUT=$(oc get checluster devspaces -n openshift-devspaces \
  -o jsonpath='{.spec.devEnvironments.secondsOfInactivityBeforeIdling}' 2>/dev/null || echo "")
RUN_TIMEOUT=$(oc get checluster devspaces -n openshift-devspaces \
  -o jsonpath='{.spec.devEnvironments.secondsOfRunBeforeIdling}' 2>/dev/null || echo "")
if [ "$IDLE_TIMEOUT" = "-1" ]; then
  pass "Idle timeout: disabled (workspaces stay running)"
else
  warn "Idle timeout: ${IDLE_TIMEOUT:-not set}s — workspaces may auto-stop during workshop"
fi
if [ "$RUN_TIMEOUT" = "-1" ]; then
  pass "Run timeout: disabled"
else
  warn "Run timeout: ${RUN_TIMEOUT:-not set}s — workspaces may auto-stop"
fi

# === 4. MCP Infrastructure ==================================================
echo ""
echo "─── 4. MCP Infrastructure ───"
check "MCPServer CRD (mcp.x-k8s.io)" oc get crd mcpservers.mcp.x-k8s.io
check "MCPServerRegistration CRD (mcp.kuadrant.io)" oc get crd mcpserverregistrations.mcp.kuadrant.io
check "HTTPRoute CRD" oc get crd httproutes.gateway.networking.k8s.io

# MCP Lifecycle Operator
MLC_STATE=$(oc get datasciencecluster -o jsonpath='{.items[0].spec.components.mcplifecycleoperator.managementState}' 2>/dev/null || echo "")
if [ "$MLC_STATE" = "Managed" ]; then
  pass "MCP Lifecycle Operator: Managed"
else
  fail "MCP Lifecycle Operator: ${MLC_STATE:-not set} (expected: Managed)"
fi

# MCP Catalog flag
MCP_CATALOG=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.mcpCatalog}' 2>/dev/null || echo "")
if [ "$MCP_CATALOG" = "true" ]; then
  pass "MCP Catalog: enabled in RHOAI Dashboard"
else
  fail "MCP Catalog: ${MCP_CATALOG:-not set} (expected: true)"
fi

# Gateway
check "MCP Gateway CR exists" oc get gateway mcp-gateway -n mcp-system
GW_PROG=$(oc get gateway mcp-gateway -n mcp-system \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
if [ "$GW_PROG" = "True" ]; then
  pass "MCP Gateway: Programmed"
  GW_HOST=$(oc get gateway mcp-gateway -n mcp-system \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "unknown")
  info "Gateway address: ${GW_HOST}"
else
  fail "MCP Gateway: not Programmed (status: ${GW_PROG:-unknown})"
fi

check "MCPGatewayExtension exists" oc get mcpgatewayextension mcp-gateway-extension -n mcp-system

# === 5. Workspaces ==========================================================
echo ""
echo "─── 5. Workspaces (${USER_COUNT} users) ───"
WS_RUNNING=0
WS_STARTING=0
WS_STOPPED=0
WS_FAILED=0
WS_MISSING=0
FAILED_USERS=""

for i in $(seq 1 "$USER_COUNT"); do
  PHASE=$(oc get dw code-workspace-1 -n "user${i}-devspaces" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "missing")
  case "$PHASE" in
    Running)  WS_RUNNING=$((WS_RUNNING + 1)) ;;
    Starting) WS_STARTING=$((WS_STARTING + 1)) ;;
    Stopped)  WS_STOPPED=$((WS_STOPPED + 1)) ;;
    Failed*)  WS_FAILED=$((WS_FAILED + 1)); FAILED_USERS="$FAILED_USERS user${i}" ;;
    missing)  WS_MISSING=$((WS_MISSING + 1)) ;;
  esac
done

if [ "$WS_RUNNING" -eq "$USER_COUNT" ]; then
  pass "All ${USER_COUNT} workspaces: Running"
else
  info "Running: ${WS_RUNNING} | Starting: ${WS_STARTING} | Stopped: ${WS_STOPPED} | Failed: ${WS_FAILED} | Missing: ${WS_MISSING}"
  if [ "$WS_FAILED" -gt 0 ]; then
    fail "Failed workspaces:${FAILED_USERS}"
  fi
  if [ "$WS_STOPPED" -gt 0 ]; then
    warn "${WS_STOPPED} workspaces are Stopped — run: oc patch dw code-workspace-1 -n userN-devspaces --type=merge -p '{\"spec\":{\"started\":true}}'"
  fi
  if [ "$WS_MISSING" -gt 0 ]; then
    fail "${WS_MISSING} workspaces not found — Helm deploy may be incomplete"
  fi
  if [ "$WS_STARTING" -gt 0 ]; then
    warn "${WS_STARTING} workspaces still Starting — wait and re-run"
  fi
  if [ "$WS_RUNNING" -gt 0 ] && [ "$WS_FAILED" -eq 0 ] && [ "$WS_MISSING" -eq 0 ]; then
    pass "${WS_RUNNING}/${USER_COUNT} workspaces Running (others starting/stopped)"
  fi
fi

# === 6. Per-User RBAC =======================================================
echo ""
echo "─── 6. Per-User RBAC (spot check) ───"
RBAC_OK=0
RBAC_FAIL=0
# Spot-check 5 users across the range
for u in 1 5 10 20 "$USER_COUNT"; do
  [ "$u" -gt "$USER_COUNT" ] && continue
  CAN_MCP=$(oc auth can-i create mcpservers.mcp.x-k8s.io \
    -n "user${u}-devspaces" --as="user${u}" 2>/dev/null || echo "no")
  CAN_REG=$(oc auth can-i create mcpserverregistrations.mcp.kuadrant.io \
    -n "user${u}-devspaces" --as="user${u}" 2>/dev/null || echo "no")
  CAN_BUILD=$(oc auth can-i create buildconfigs.build.openshift.io \
    -n "user${u}-devspaces" --as="user${u}" 2>/dev/null || echo "no")
  if [ "$CAN_MCP" = "yes" ] && [ "$CAN_REG" = "yes" ] && [ "$CAN_BUILD" = "yes" ]; then
    RBAC_OK=$((RBAC_OK + 1))
  else
    RBAC_FAIL=$((RBAC_FAIL + 1))
    fail "user${u}: MCPServer=${CAN_MCP} MCPServerReg=${CAN_REG} BuildConfig=${CAN_BUILD}"
  fi
done

if [ "$RBAC_FAIL" -eq 0 ]; then
  pass "Users can create MCPServer, MCPServerRegistration, and BuildConfig"
fi

# Namespace isolation
ISOLATED=true
for u in 2 15; do
  [ "$u" -gt "$USER_COUNT" ] && continue
  CROSS=$(oc auth can-i list mcpservers.mcp.x-k8s.io \
    -n user1-devspaces --as="user${u}" 2>/dev/null || echo "no")
  if [ "$CROSS" = "yes" ]; then
    ISOLATED=false
    fail "user${u} can see MCPServers in user1's namespace — isolation broken"
  fi
done
if $ISOLATED; then
  pass "Namespace isolation: users cannot see other users' MCP resources"
fi

# === 7. Creator Labels ======================================================
# NOTE: The controller.devfile.io/creator label is immutable — set at DevWorkspace
# creation time by the controller. Since Helm (admin) creates the workspaces, the
# label points to the admin UID. This ONLY affects the DevSpaces dashboard view
# (users won't see their workspace listed). It does NOT block:
#   - Direct OpenCode URL access (users click their URL and are in)
#   - oc commands (user has edit RBAC in their namespace)
#   - MCP Catalog visibility (separate RBAC)
echo ""
echo "─── 7. Creator Labels ───"
LABEL_OK=0
LABEL_BAD=0
for u in 1 5 10 20 "$USER_COUNT"; do
  [ "$u" -gt "$USER_COUNT" ] && continue
  CREATOR=$(oc get dw code-workspace-1 -n "user${u}-devspaces" \
    -o jsonpath='{.metadata.labels.controller\.devfile\.io/creator}' 2>/dev/null || echo "")
  USER_UID=$(oc get user "user${u}" -o jsonpath='{.metadata.uid}' 2>/dev/null || echo "none")
  if [ "$CREATOR" = "$USER_UID" ] && [ -n "$CREATOR" ]; then
    LABEL_OK=$((LABEL_OK + 1))
  else
    LABEL_BAD=$((LABEL_BAD + 1))
  fi
done
if [ "$LABEL_BAD" -eq 0 ]; then
  pass "Creator labels correct — users can see workspace in DevSpaces dashboard"
else
  warn "Creator labels: ${LABEL_BAD} mismatch (cosmetic — users access via direct URL, not dashboard)"
  info "This is expected when Helm (admin) creates workspaces. Direct OpenCode URLs still work."
fi

# === 8. Clean Slate =========================================================
echo ""
echo "─── 8. Clean Slate ───"
STALE_MCP=$(oc get mcpservers --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
STALE_REG=$(oc get mcpserverregistrations --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$STALE_MCP" -eq 0 ]; then
  pass "No MCPServer CRs anywhere (clean slate)"
else
  warn "${STALE_MCP} MCPServer CR(s) found — leftover from testing?"
  oc get mcpservers --all-namespaces --no-headers 2>/dev/null | while read -r line; do
    info "  $line"
  done
fi
if [ "$STALE_REG" -eq 0 ]; then
  pass "No MCPServerRegistration CRs anywhere (clean slate)"
else
  warn "${STALE_REG} MCPServerRegistration(s) found — leftover from testing?"
fi

# === 9. LLM Endpoint (optional) =============================================
echo ""
echo "─── 9. LLM Endpoint ───"
if [ -n "$LLM_URL" ]; then
  MODELS_URL="${LLM_URL%/}/models"
  if curl -sk --connect-timeout 5 "$MODELS_URL" 2>/dev/null | grep -q '"object"'; then
    pass "LLM endpoint reachable: ${LLM_URL}"
    if [ -n "$MODEL_ID" ]; then
      if curl -sk --connect-timeout 5 "$MODELS_URL" 2>/dev/null | grep -q "\"${MODEL_ID}\""; then
        pass "Model '${MODEL_ID}' found"
      else
        fail "Model '${MODEL_ID}' not found at endpoint"
      fi
    fi
  else
    fail "LLM endpoint not reachable: ${MODELS_URL}"
  fi
else
  info "No --llm-url provided (skipping — not required for manual track)"
fi

# === 10. URL Summary ========================================================
echo ""
echo "─── 10. Participant URLs ───"
info "DevSpaces dashboard: https://devspaces.${APPS_DOMAIN}"
info "RHOAI Dashboard:     https://rhods-dashboard-redhat-ods-applications.${APPS_DOMAIN}"
info "MCP Gateway:         https://mcp-gateway.${APPS_DOMAIN}/mcp"
echo ""
info "Workspace URLs (direct access, already running):"
info "  https://user1-code-workspace-1-opencode-web.${APPS_DOMAIN}"
info "  https://user2-code-workspace-1-opencode-web.${APPS_DOMAIN}"
info "  ...through..."
info "  https://user${USER_COUNT}-code-workspace-1-opencode-web.${APPS_DOMAIN}"

# === Results ================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: ❌  ${PASS} passed, ${FAIL} FAILED, ${WARN} warnings"
  echo "  Fix the failures above before starting the workshop."
  echo "═══════════════════════════════════════════════════════════════"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "  RESULT: ⚠️   ${PASS} passed, ${WARN} warnings"
  echo "  Workshop can proceed but review warnings above."
  echo "═══════════════════════════════════════════════════════════════"
  exit 0
else
  echo "  RESULT: ✅  ${PASS} passed — cluster is READY for the workshop!"
  echo "═══════════════════════════════════════════════════════════════"
  exit 0
fi
