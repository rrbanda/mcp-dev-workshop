#!/usr/bin/env bash
set -euo pipefail

LAB="${1:-all}"
SCAFFOLD_DIR="${2:-scaffold}"

pass() { printf "\033[32mPASS\033[0m: %s\n" "$1"; }
fail() { printf "\033[31mFAIL\033[0m: %s\n" "$1"; exit 1; }
info() { printf "\033[36mINFO\033[0m: %s\n" "$1"; }
warn() { printf "\033[33mWARN\033[0m: %s\n" "$1"; }

validate_lab3() {
    info "Validating Lab 3: Build Stock Market MCP Server"
    [ -f "$SCAFFOLD_DIR/server.py" ] || fail "server.py not found"
    grep -q "MCPServer" "$SCAFFOLD_DIR/server.py" || fail "server.py does not import MCPServer"
    grep -q "@server.tool" "$SCAFFOLD_DIR/server.py" || fail "server.py has no @server.tool decorators"
    grep -q "server.run\|mcp.run" "$SCAFFOLD_DIR/server.py" || fail "server.py has no run() call"
    grep -q "yfinance\|yf" "$SCAFFOLD_DIR/server.py" || fail "server.py does not use yfinance"
    grep -q "normalize_ticker" "$SCAFFOLD_DIR/server.py" || fail "server.py missing normalize_ticker"
    [ -f "$SCAFFOLD_DIR/requirements.txt" ] || fail "requirements.txt not found"
    grep -q "mcp" "$SCAFFOLD_DIR/requirements.txt" || fail "requirements.txt missing mcp dependency"
    grep -q "yfinance" "$SCAFFOLD_DIR/requirements.txt" || fail "requirements.txt missing yfinance dependency"
    pass "Lab 3 — Stock Market MCP server code is well-formed"
}

validate_lab4() {
    info "Validating Lab 4: Test with Your Agent"
    command -v pip >/dev/null 2>&1 || fail "pip not installed"
    pass "Lab 4 — tooling available"
}

validate_lab5() {
    info "Validating Lab 5: Deploy to OpenShift"
    [ -f "$SCAFFOLD_DIR/Containerfile" ] || fail "Containerfile not found"
    [ -f "$SCAFFOLD_DIR/deployment.yaml" ] || fail "deployment.yaml not found"
    grep -q "containerPort: 8080" "$SCAFFOLD_DIR/deployment.yaml" || fail "deployment.yaml missing port 8080"
    grep -q "stock-market-mcp" "$SCAFFOLD_DIR/deployment.yaml" || fail "deployment.yaml missing stock-market-mcp name"
    NS=$(oc project -q 2>/dev/null || echo "unknown")
    if [ "$NS" != "unknown" ]; then
        oc get deployment stock-market-mcp -n "$NS" >/dev/null 2>&1 && pass "Deployment exists in $NS" || fail "Deployment not found in $NS"
        READY=$(oc get deployment stock-market-mcp -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        [ "$READY" = "1" ] && pass "Pod is ready" || fail "Pod not ready (readyReplicas=$READY)"
        # Check route exists
        ROUTE=$(oc get route stock-market-mcp -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
        if [ -n "$ROUTE" ]; then
            pass "Route exists: $ROUTE"
        else
            warn "No route — run: make expose"
        fi
    else
        info "Not connected to a cluster — skipping live checks"
    fi
    pass "Lab 5 — deployment artifacts valid"
}

validate_lab6() {
    info "Validating Lab 6: Close the Feedback Loop"
    NS=$(oc project -q 2>/dev/null || echo "unknown")
    if [ "$NS" != "unknown" ]; then
        SVC_IP=$(oc get svc stock-market-mcp -n "$NS" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
        [ -n "$SVC_IP" ] && pass "Service reachable at $SVC_IP:8080" || fail "Service not found"

        # Test MCP protocol: initialize
        ROUTE=$(oc get route stock-market-mcp -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
        if [ -n "$ROUTE" ]; then
            ENDPOINT="http://$ROUTE/mcp"
        else
            ENDPOINT="http://$SVC_IP:8080/mcp"
        fi

        info "Testing MCP endpoint at $ENDPOINT..."
        INIT=$(curl -s -m 10 -X POST "$ENDPOINT" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"validate","version":"1.0"}}}' 2>/dev/null || echo "")

        if echo "$INIT" | grep -q '"result"'; then
            pass "MCP initialize succeeded"
        else
            fail "MCP initialize failed — server may not be running"
        fi

        # Test tools/list
        SESSION=$(echo "$INIT" | grep -o '"sessionId":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
        if [ -n "$SESSION" ]; then
            TOOLS=$(curl -s -m 10 -X POST "$ENDPOINT" \
                -H "Content-Type: application/json" \
                -H "Mcp-Session-Id: $SESSION" \
                -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' 2>/dev/null || echo "")
            TOOL_COUNT=$(echo "$TOOLS" | grep -o '"name"' | wc -l | tr -d ' ')
            if [ "$TOOL_COUNT" -ge 9 ]; then
                pass "All 9 MCP tools registered"
            else
                fail "Expected 9 tools, found $TOOL_COUNT"
            fi
        fi

        # Check OpenCode MCP registration
        if command -v opencode >/dev/null 2>&1; then
            MCP_STATUS=$(opencode mcp list 2>&1 || echo "")
            if echo "$MCP_STATUS" | grep -q "connected"; then
                pass "MCP server registered and connected in OpenCode"
            else
                warn "MCP server not registered in OpenCode — run: make connect-mcp"
            fi
        fi
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
