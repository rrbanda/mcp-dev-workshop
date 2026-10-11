#!/usr/bin/env bash
#
# Set up the MCP platform infrastructure on an OpenShift cluster.
#
# This script is run ONCE by a facilitator/cluster-admin before the workshop.
# It is idempotent — safe to re-run.
#
# What it does (in order):
#   1. Enables the MCP Lifecycle Operator (DataScienceCluster)
#   2. Enables the MCP Catalog in the RHOAI dashboard (OdhDashboardConfig)
#   3. Installs the MCP Gateway Operator (Subscription + OperatorGroup)
#   4. Fixes kuadrant-operator OOMKilled (increases memory to 1Gi)
#   5. Creates the MCP Gateway (Gateway CR with data-science-gateway-class)
#   6. Creates the MCPGatewayExtension (enables broker + EnvoyFilter)
#   7. Grants MCP CRD RBAC to participant namespaces
#
# Prerequisites:
#   - oc CLI authenticated as cluster-admin
#   - RHOAI 3.5+ installed (DataScienceCluster + OdhDashboardConfig exist)
#   - OpenShift 4.22+
#
# Usage:
#   ./scripts/setup-platform.sh
#   ./scripts/setup-platform.sh --apps-domain apps.ocp.example.com
#   ./scripts/setup-platform.sh --user-prefix user --user-count 30
#
# After this script completes, run:
#   ./scripts/setup-playground.sh    (for AI Playground support)
#
set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────
GATEWAY_NS="${GATEWAY_NS:-mcp-system}"
RHOAI_NS="${RHOAI_NS:-redhat-ods-applications}"
APPS_DOMAIN=""
USER_PREFIX="${USER_PREFIX:-user}"
USER_COUNT="${USER_COUNT:-30}"
SKIP_RBAC="${SKIP_RBAC:-false}"

# ── Parse args ──────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --gateway-ns)    GATEWAY_NS="$2";    shift 2 ;;
    --rhoai-ns)      RHOAI_NS="$2";      shift 2 ;;
    --apps-domain)   APPS_DOMAIN="$2";   shift 2 ;;
    --user-prefix)   USER_PREFIX="$2";   shift 2 ;;
    --user-count)    USER_COUNT="$2";    shift 2 ;;
    --skip-rbac)     SKIP_RBAC="true";   shift ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --apps-domain DOMAIN   Cluster apps domain (auto-detected if omitted)"
      echo "  --gateway-ns NS        MCP Gateway namespace (default: mcp-system)"
      echo "  --rhoai-ns NS          RHOAI applications namespace (default: redhat-ods-applications)"
      echo "  --user-prefix PREFIX   Participant username prefix (default: user)"
      echo "  --user-count N         Number of participants (default: 30)"
      echo "  --skip-rbac            Skip RBAC grants for participant namespaces"
      echo ""
      echo "After running this script, run: ./scripts/setup-playground.sh"
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
info "=== MCP Platform Setup ==="
echo ""

info "Verifying cluster connectivity..."
oc whoami >/dev/null 2>&1 || fail "Not logged in to cluster. Run 'oc login' first."
CONSOLE=$(oc whoami --show-console 2>/dev/null || echo "unknown")
info "Cluster console: $CONSOLE"

info "Verifying cluster-admin permissions..."
CAN_CREATE=$(oc auth can-i create namespaces 2>/dev/null || echo "no")
[ "$CAN_CREATE" = "yes" ] || fail "cluster-admin permissions required. Current user: $(oc whoami)"

info "Verifying RHOAI is installed..."
oc get namespace "$RHOAI_NS" >/dev/null 2>&1 || fail "Namespace $RHOAI_NS not found. Is RHOAI installed?"

DSC_NAME=$(oc get datasciencecluster -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
[ -n "$DSC_NAME" ] || fail "No DataScienceCluster found. Is RHOAI 3.5+ installed?"
info "DataScienceCluster: $DSC_NAME"

# Auto-detect apps domain if not provided
if [ -z "$APPS_DOMAIN" ]; then
  APPS_DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
  [ -n "$APPS_DOMAIN" ] || fail "Could not auto-detect apps domain. Pass --apps-domain explicitly."
fi
info "Apps domain: $APPS_DOMAIN"

GATEWAY_HOSTNAME="mcp-gateway.${APPS_DOMAIN}"
info "Gateway hostname will be: $GATEWAY_HOSTNAME"
echo ""

# ── Step 1: Enable MCP Lifecycle Operator ──────────────────────
info "Step 1: Enabling MCP Lifecycle Operator..."
MLC_STATE=$(oc get datasciencecluster "$DSC_NAME" \
  -o jsonpath='{.spec.components.mcplifecycleoperator.managementState}' 2>/dev/null || echo "")
if [ "$MLC_STATE" = "Managed" ]; then
  pass "MCP Lifecycle Operator already Managed"
else
  oc patch datasciencecluster "$DSC_NAME" --type=merge \
    -p '{"spec":{"components":{"mcplifecycleoperator":{"managementState":"Managed"}}}}'
  pass "MCP Lifecycle Operator set to Managed"
  info "Waiting for operator pod to start..."
  for i in $(seq 1 30); do
    POD_COUNT=$(oc get pods -n "$RHOAI_NS" -l app.kubernetes.io/name=mcp-lifecycle-operator \
      --no-headers 2>/dev/null | grep -c Running || echo "0")
    [ "$POD_COUNT" -ge 1 ] && break
    sleep 5
  done
  POD_COUNT=$(oc get pods -n "$RHOAI_NS" -l app.kubernetes.io/name=mcp-lifecycle-operator \
    --no-headers 2>/dev/null | grep -c Running || echo "0")
  if [ "$POD_COUNT" -ge 1 ]; then
    pass "MCP Lifecycle Operator pod is Running"
  else
    warn "Operator pod not Running yet — it may still be starting"
  fi
fi

# Verify CRD exists
info "Verifying MCPServer CRD..."
for i in $(seq 1 20); do
  oc get crd mcpservers.mcp.x-k8s.io >/dev/null 2>&1 && break
  sleep 5
done
oc get crd mcpservers.mcp.x-k8s.io >/dev/null 2>&1 || fail "MCPServer CRD not found after waiting. Check operator logs."
pass "MCPServer CRD exists"

# ── Step 2: Enable MCP Catalog in dashboard ────────────────────
info "Step 2: Enabling MCP Catalog in the dashboard..."
CATALOG_STATE=$(oc get odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
  -o jsonpath='{.spec.dashboardConfig.mcpCatalog}' 2>/dev/null || echo "")
if [ "$CATALOG_STATE" = "true" ]; then
  pass "MCP Catalog already enabled"
else
  oc patch odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
    --type=merge -p '{"spec":{"dashboardConfig":{"mcpCatalog":true}}}'
  pass "MCP Catalog enabled (mcpCatalog: true)"
fi

# ── Step 3: Install MCP Gateway Operator ───────────────────────
info "Step 3: Installing MCP Gateway Operator..."

# Create namespace
if oc get namespace "$GATEWAY_NS" >/dev/null 2>&1; then
  info "Namespace $GATEWAY_NS already exists"
else
  oc create namespace "$GATEWAY_NS"
  pass "Created namespace $GATEWAY_NS"
fi

# Check if already installed
CSV_EXISTS=$(oc get csv -n "$GATEWAY_NS" -l "operators.coreos.com/mcp-gateway.${GATEWAY_NS}=" \
  --no-headers 2>/dev/null | head -1 || echo "")
if [ -n "$CSV_EXISTS" ]; then
  pass "MCP Gateway Operator already installed"
else
  cat <<EOF | oc apply -n "$GATEWAY_NS" -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: mcp-gateway
spec:
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  name: mcp-gateway
  channel: preview
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: mcp-gateway
spec:
  targetNamespaces:
  - ${GATEWAY_NS}
EOF
  pass "MCP Gateway Subscription + OperatorGroup created"

  info "Waiting for MCP Gateway Operator CSV to succeed (up to 5 min)..."
  for i in $(seq 1 60); do
    PHASE=$(oc get csv -n "$GATEWAY_NS" -l "operators.coreos.com/mcp-gateway.${GATEWAY_NS}=" \
      -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    [ "$PHASE" = "Succeeded" ] && break
    sleep 5
  done
  PHASE=$(oc get csv -n "$GATEWAY_NS" -l "operators.coreos.com/mcp-gateway.${GATEWAY_NS}=" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "unknown")
  if [ "$PHASE" = "Succeeded" ]; then
    pass "MCP Gateway Operator CSV succeeded"
  else
    warn "CSV phase: $PHASE — may still be installing"
  fi
fi

# ── Step 4: Fix kuadrant-operator memory limit ─────────────────
info "Step 4: Fixing kuadrant-operator memory limit..."
CURRENT_MEM=$(oc get deployment kuadrant-operator-controller-manager -n "$GATEWAY_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")
if [ "$CURRENT_MEM" = "1Gi" ]; then
  pass "kuadrant-operator memory already set to 1Gi"
elif [ -z "$CURRENT_MEM" ]; then
  warn "kuadrant-operator deployment not found yet — it may still be installing"
  info "Waiting for kuadrant-operator deployment (up to 2 min)..."
  for i in $(seq 1 24); do
    oc get deployment kuadrant-operator-controller-manager -n "$GATEWAY_NS" >/dev/null 2>&1 && break
    sleep 5
  done
  if oc get deployment kuadrant-operator-controller-manager -n "$GATEWAY_NS" >/dev/null 2>&1; then
    oc patch deployment kuadrant-operator-controller-manager -n "$GATEWAY_NS" \
      --type=json \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1Gi"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"512Mi"}]'
    oc rollout status deployment/kuadrant-operator-controller-manager -n "$GATEWAY_NS" --timeout=120s 2>/dev/null || true
    pass "kuadrant-operator memory patched to 1Gi"
  else
    warn "kuadrant-operator deployment not found — patch manually after install completes"
  fi
else
  oc patch deployment kuadrant-operator-controller-manager -n "$GATEWAY_NS" \
    --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1Gi"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"512Mi"}]'
  oc rollout status deployment/kuadrant-operator-controller-manager -n "$GATEWAY_NS" --timeout=120s 2>/dev/null || true
  pass "kuadrant-operator memory patched from $CURRENT_MEM to 1Gi"
fi

# ── Step 5: Create the MCP Gateway ─────────────────────────────
info "Step 5: Creating MCP Gateway..."
GW_EXISTS=$(oc get gateway mcp-gateway -n "$GATEWAY_NS" \
  -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [ "$GW_EXISTS" = "mcp-gateway" ]; then
  pass "MCP Gateway already exists"
else
  cat <<EOF | oc apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: mcp-gateway
  namespace: ${GATEWAY_NS}
  labels:
    istio.io/rev: openshift-gateway
spec:
  gatewayClassName: data-science-gateway-class
  listeners:
    - name: http
      hostname: ${GATEWAY_HOSTNAME}
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
EOF
  pass "MCP Gateway created with hostname $GATEWAY_HOSTNAME"
fi

# Verify Gateway is programmed
info "Waiting for Gateway to be programmed..."
for i in $(seq 1 30); do
  PROGRAMMED=$(oc get gateway mcp-gateway -n "$GATEWAY_NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
  [ "$PROGRAMMED" = "True" ] && break
  sleep 5
done
PROGRAMMED=$(oc get gateway mcp-gateway -n "$GATEWAY_NS" \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "unknown")
if [ "$PROGRAMMED" = "True" ]; then
  pass "MCP Gateway is Programmed"
else
  warn "Gateway not yet Programmed (status: $PROGRAMMED) — may need more time"
fi

# ── Step 6: Create MCPGatewayExtension ─────────────────────────
info "Step 6: Creating MCPGatewayExtension..."
EXT_EXISTS=$(oc get mcpgatewayextension mcp-gateway-extension -n "$GATEWAY_NS" \
  -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [ "$EXT_EXISTS" = "mcp-gateway-extension" ]; then
  pass "MCPGatewayExtension already exists"
else
  cat <<EOF | oc apply -f -
apiVersion: mcp.kuadrant.io/v1alpha1
kind: MCPGatewayExtension
metadata:
  name: mcp-gateway-extension
  namespace: ${GATEWAY_NS}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: mcp-gateway
    namespace: ${GATEWAY_NS}
    sectionName: http
EOF
  pass "MCPGatewayExtension created"
fi

# ── Step 7: Grant MCP CRD RBAC to participant namespaces ──────
if [ "$SKIP_RBAC" = "true" ]; then
  info "Step 7: Skipping RBAC grants (--skip-rbac)"
else
  info "Step 7: Granting MCP CRD RBAC to participant namespaces..."
  info "  Participants: ${USER_PREFIX}1 through ${USER_PREFIX}${USER_COUNT}"

  RBAC_APPLIED=0
  for i in $(seq 1 "$USER_COUNT"); do
    NS="${USER_PREFIX}${i}-devspaces"
    if ! oc get namespace "$NS" >/dev/null 2>&1; then
      continue
    fi

    # Check if Role already exists
    if oc get role mcp-workshop-resources -n "$NS" >/dev/null 2>&1; then
      RBAC_APPLIED=$((RBAC_APPLIED + 1))
      continue
    fi

    cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: mcp-workshop-resources
  namespace: ${NS}
rules:
  - apiGroups: ["mcp.x-k8s.io"]
    resources: ["mcpservers"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["httproutes"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["mcp.kuadrant.io"]
    resources: ["mcpserverregistrations"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: mcp-workshop-resources
  namespace: ${NS}
subjects:
  - kind: Group
    name: system:serviceaccounts:${NS}
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: ${USER_PREFIX}${i}
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: mcp-workshop-resources
  apiGroup: rbac.authorization.k8s.io
EOF
    RBAC_APPLIED=$((RBAC_APPLIED + 1))
  done

  if [ "$RBAC_APPLIED" -gt 0 ]; then
    pass "RBAC granted to $RBAC_APPLIED namespaces"
  else
    warn "No participant namespaces found yet (${USER_PREFIX}*-devspaces). RBAC will be applied by the Helm chart during workspace deployment."
  fi
fi

# ── Verification ──────────────────────────────────────────────
echo ""
info "=== Verification ==="

echo -n "  MCP Lifecycle Operator:  "
MLC=$(oc get datasciencecluster "$DSC_NAME" \
  -o jsonpath='{.spec.components.mcplifecycleoperator.managementState}' 2>/dev/null || echo "unknown")
echo "$MLC"

echo -n "  MCP Catalog flag:        "
CAT=$(oc get odhdashboardconfig odh-dashboard-config -n "$RHOAI_NS" \
  -o jsonpath='{.spec.dashboardConfig.mcpCatalog}' 2>/dev/null || echo "unknown")
echo "$CAT"

echo -n "  MCPServer CRD:           "
oc get crd mcpservers.mcp.x-k8s.io >/dev/null 2>&1 && echo "exists" || echo "MISSING"

echo -n "  MCP Gateway Operator:    "
GW_CSV=$(oc get csv -n "$GATEWAY_NS" -l "operators.coreos.com/mcp-gateway.${GATEWAY_NS}=" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "not found")
echo "$GW_CSV"

echo -n "  kuadrant-operator mem:   "
KU_MEM=$(oc get deployment kuadrant-operator-controller-manager -n "$GATEWAY_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "unknown")
echo "$KU_MEM"

echo -n "  MCP Gateway:             "
GW_PROG=$(oc get gateway mcp-gateway -n "$GATEWAY_NS" \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "unknown")
echo "Programmed=$GW_PROG"

echo -n "  MCPGatewayExtension:     "
oc get mcpgatewayextension mcp-gateway-extension -n "$GATEWAY_NS" >/dev/null 2>&1 && echo "exists" || echo "MISSING"

echo ""
pass "=== MCP Platform Setup Complete ==="
echo ""
echo "  Gateway hostname: $GATEWAY_HOSTNAME"
echo "  Gateway namespace: $GATEWAY_NS"
echo ""
echo "  Next steps:"
echo "    1. Run ./scripts/setup-playground.sh   (for AI Playground support)"
echo "    2. Deploy user workspaces              (make workshop-deploy or ansible)"
echo ""
