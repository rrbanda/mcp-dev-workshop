#!/usr/bin/env bash
set -euo pipefail

LAB="${1:-all}"
SCAFFOLD_DIR="${2:-scaffold}"

pass() { printf "\033[32mPASS\033[0m: %s\n" "$1"; }
fail() { printf "\033[31mFAIL\033[0m: %s\n" "$1"; exit 1; }
info() { printf "\033[36mINFO\033[0m: %s\n" "$1"; }

validate_lab3() {
    info "Validating Lab 3: Build an MCP Server"
    [ -f "$SCAFFOLD_DIR/server.py" ] || fail "server.py not found"
    grep -q "MCPServer\|FastMCP" "$SCAFFOLD_DIR/server.py" || fail "server.py does not import MCPServer"
    grep -q "@mcp.tool" "$SCAFFOLD_DIR/server.py" || fail "server.py has no @mcp.tool decorators"
    grep -q "mcp.run" "$SCAFFOLD_DIR/server.py" || fail "server.py has no mcp.run() call"
    [ -f "$SCAFFOLD_DIR/requirements.txt" ] || fail "requirements.txt not found"
    grep -q "mcp" "$SCAFFOLD_DIR/requirements.txt" || fail "requirements.txt missing mcp dependency"
    pass "Lab 3 — MCP server code is well-formed"
}

validate_lab4() {
    info "Validating Lab 4: Test with Your Agent"
    command -v uv >/dev/null 2>&1 || fail "uv not installed"
    pass "Lab 4 — tooling available"
}

validate_lab5() {
    info "Validating Lab 5: Deploy to OpenShift"
    [ -f "$SCAFFOLD_DIR/Containerfile" ] || fail "Containerfile not found"
    [ -f "$SCAFFOLD_DIR/deployment.yaml" ] || fail "deployment.yaml not found"
    grep -q "containerPort: 8080" "$SCAFFOLD_DIR/deployment.yaml" || fail "deployment.yaml missing port 8080"
    NS=$(oc project -q 2>/dev/null || echo "unknown")
    if [ "$NS" != "unknown" ]; then
        oc get deployment my-mcp-server -n "$NS" >/dev/null 2>&1 && pass "Deployment exists in $NS" || fail "Deployment not found in $NS"
        READY=$(oc get deployment my-mcp-server -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        [ "$READY" = "1" ] && pass "Pod is ready" || fail "Pod not ready (readyReplicas=$READY)"
    else
        info "Not connected to a cluster — skipping live checks"
    fi
    pass "Lab 5 — deployment artifacts valid"
}

validate_lab6() {
    info "Validating Lab 6: Close the Feedback Loop"
    NS=$(oc project -q 2>/dev/null || echo "unknown")
    if [ "$NS" != "unknown" ]; then
        SVC_IP=$(oc get svc my-mcp-server -n "$NS" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
        [ -n "$SVC_IP" ] && pass "Service reachable at $SVC_IP:8080" || fail "Service not found"
    fi
    pass "Lab 6 — feedback loop ready"
}

case "$LAB" in
    3|lab-03|lab3) validate_lab3 ;;
    4|lab-04|lab4) validate_lab4 ;;
    5|lab-05|lab5) validate_lab3; validate_lab5 ;;
    6|lab-06|lab6) validate_lab6 ;;
    all)
        validate_lab3
        validate_lab4
        validate_lab5
        validate_lab6
        ;;
    *) echo "Usage: $0 {3|4|5|6|all} [scaffold-dir]"; exit 1 ;;
esac
