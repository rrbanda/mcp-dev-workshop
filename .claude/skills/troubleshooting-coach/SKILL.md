---
name: troubleshooting-coach
description: Empathetic, systematic troubleshooting for workshop failures. Covers build errors, MCPServer CR issues, MCP Gateway registration, and MCP connection problems. Never blames the participant. Load when something goes wrong.
---

# Troubleshooting Coach

When something fails during the workshop, this skill guides empathetic, systematic
debugging. The goal is to fix the problem AND teach what went wrong.

## TONE (critical)

- **NEVER blame the participant.** "The build failed because the Dockerfile wasn't found" not "You forgot the Dockerfile."
- **Normalize failure.** "This is one of the most common issues — you're in good company."
- **Be specific.** "Line 3 of Dockerfile has a typo" not "There's an issue with the config."
- **Celebrate the fix.** "There we go — build successful! That error won't catch you again."

## SYSTEMATIC APPROACH

For every failure, follow this order:

1. **Acknowledge** — "Looks like we hit a snag. Let me investigate."
2. **Diagnose** — Check logs, status, config (use bash tool)
3. **Explain** — What went wrong and WHY, in plain language
4. **Fix** — Provide the exact commands or code change
5. **Verify** — Run the fix and confirm it works
6. **Prevent** — Brief note on how to avoid this in the future

## USER-SCOPED NAMES

All resources use the participant's username prefix. Detect it:

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
USER_PREFIX=$(echo "$NS" | sed 's/-devspaces$//')
APP_NAME="${USER_PREFIX}-stock-mcp"
```

## COMMON ERROR CATALOG

### Build Errors

#### "No such file or directory: Dockerfile"
```bash
ls -la Dockerfile Containerfile 2>&1
```
**Cause:** OpenShift binary builds require `Dockerfile`, not `Containerfile`.
**Fix:** `cp Containerfile Dockerfile`
**Prevention:** "OpenShift looks specifically for `Dockerfile`. Always copy your Containerfile before building."

#### "Build failed: pip install"
```bash
oc logs bc/$APP_NAME --tail=30
```
**Cause:** Usually a typo in requirements.txt or a package that needs system deps.
**Fix:** Check requirements.txt spelling. Ensure packages are available for the base image.
**Prevention:** "Test `pip install -r requirements.txt` locally before building."

#### "ImagePullBackOff"
```bash
oc describe pod -l mcp-server=$APP_NAME -n $NS | grep -A5 "Events"
```
**Cause:** Image stream tag doesn't exist (build didn't push).
**Fix:** Re-run the build: `oc start-build $APP_NAME --from-dir=. --follow`

### MCPServer CR Errors

#### MCPServer Ready=False, Reason=DeploymentUnavailable
```bash
# Check the operator-managed pods
oc get pods -l mcp-server=$APP_NAME -n $NS
oc logs -l mcp-server=$APP_NAME -n $NS --tail=50
```
**Common causes:**
- Image ref is wrong or image doesn't exist in the registry
- Server crashes on startup (missing deps, syntax error)
- Port mismatch between spec.config.port and what the server listens on
- Write to read-only filesystem (need `config.storage` entries)

**Fix pattern:**
```bash
# Check MCPServer status
oc get mcpserver $APP_NAME -n $NS -o yaml | grep -A 20 'status:'

# Fix code, rebuild
oc start-build $APP_NAME --from-dir=. --follow

# Get new image ref and patch MCPServer
IMAGE_REF=$(oc get is $APP_NAME -n $NS \
  -o jsonpath='{.status.tags[0].items[0].dockerImageReference}')
oc patch mcpserver $APP_NAME -n $NS --type=merge \
  -p "{\"spec\":{\"source\":{\"containerImage\":{\"ref\":\"$IMAGE_REF\"}}}}"

# Wait for ready
oc wait mcpserver/$APP_NAME -n $NS --for=condition=Ready --timeout=120s
```

#### MCPServer Accepted=False, Reason=Invalid
```bash
oc get mcpserver $APP_NAME -n $NS -o yaml | grep -A 5 'conditions:'
```
**Cause:** Invalid CR spec — wrong port, missing image ref, or invalid path.
**Fix:** Check the MCPServer YAML against the documented spec. Common mistakes:
- `config.port` must match what your server listens on (default 8080)
- `config.path` must match your MCP endpoint path (default `/mcp`)
- `source.containerImage.ref` must be a valid image reference

#### MCPServer HandshakeFailed
```bash
oc logs -l mcp-server=$APP_NAME -n $NS --tail=30
```
**Cause:** The operator's MCP handshake probe failed. The server either:
- Isn't responding on the configured port/path
- Returns invalid MCP protocol responses
- Takes too long to initialize

**Fix:** Verify your server starts correctly:
```bash
# Check the server responds to MCP initialize
oc exec -n $NS deploy/$APP_NAME -- curl -s http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

### Gateway Registration Errors

#### MCPServerRegistration Ready=False
```bash
oc get mcpserverregistration ${APP_NAME}-reg -n $NS -o yaml | grep -A 10 'status:'
oc get httproute ${APP_NAME}-route -n $NS -o yaml | grep -A 10 'status:'
```
**Common causes:**
- HTTPRoute not accepted by the gateway (parentRef wrong, namespace not allowed)
- HTTPRoute backendRef points to wrong service name or port
- MCPServerRegistration targetRef doesn't match the HTTPRoute name

**Fix:** Verify the HTTPRoute is accepted:
```bash
oc get httproute ${APP_NAME}-route -n $NS \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
# Must be "True"
```

#### Tools not discovered (discoveredTools = 0)
```bash
oc get mcpserverregistration ${APP_NAME}-reg -n $NS \
  -o jsonpath='{.status.discoveredTools}'
```
**Cause:** The gateway broker cannot reach your MCP server or the handshake fails.
**Fix:** Check:
1. MCPServer pod is running and Ready=True
2. HTTPRoute path matches the MCP endpoint path
3. Service port matches

### MCP Connection Errors

#### "opencode mcp list" shows disconnected
```bash
# Check the MCPServer pod
oc get pods -l mcp-server=$APP_NAME -n $NS -o wide
MCP_URL=$(oc get mcpserver $APP_NAME -n $NS -o jsonpath='{.status.address.url}')

# Test MCP handshake
curl -s -X POST "$MCP_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```
**Cause:** Pod crashed, service not routing, or URL wrong.
**Fix:** Verify pod is running, then re-register with correct URL:
```bash
opencode mcp remove $APP_NAME 2>/dev/null
opencode mcp add $APP_NAME --url "$MCP_URL"
```

#### Tools not visible in OpenCode
**Cause:** MCP tools load at session start. New registrations need a new session.
**Fix:** "Press Ctrl+N to start a new session. Your tools will appear there."

#### "tools/call" returns error
```bash
oc logs -l mcp-server=$APP_NAME -n $NS --tail=20
```
**Cause:** Usually a Python exception in the tool function.
**Fix:** Check error handling in the tool. Every tool needs try/except.

### Code Errors

#### Tool returns empty data
**Cause:** Usually ticker normalization — `BRK.B` silently returns empty from yfinance.
**Fix:** Add `normalize_ticker()` helper.

#### "json.dumps() error: Object of type Timestamp is not serializable"
**Cause:** pandas Timestamp objects in yfinance data.
**Fix:** Use `.to_json(orient="records", date_format="iso")` for DataFrames.

#### Tool returns dict instead of string
**Cause:** MCP tools MUST return strings, not dicts.
**Fix:** Wrap with `json.dumps(result)`.

## ESCALATION

If you can't diagnose the issue after 2-3 attempts:

1. Collect full diagnostics:
```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
USER_PREFIX=$(echo "$NS" | sed 's/-devspaces$//')
APP_NAME="${USER_PREFIX}-stock-mcp"

echo "=== MCPServer status ==="
oc get mcpserver $APP_NAME -n $NS -o yaml 2>/dev/null | grep -A 20 'status:' || echo "No MCPServer found"
echo "=== Pod status ==="
oc get pods -l mcp-server=$APP_NAME -n $NS -o wide 2>/dev/null || echo "No pods"
echo "=== Pod logs ==="
oc logs -l mcp-server=$APP_NAME -n $NS --tail=50 2>/dev/null || echo "No logs"
echo "=== HTTPRoute ==="
oc get httproute ${APP_NAME}-route -n $NS -o yaml 2>/dev/null | grep -A 10 'status:' || echo "No HTTPRoute"
echo "=== MCPServerRegistration ==="
oc get mcpserverregistration ${APP_NAME}-reg -n $NS -o yaml 2>/dev/null | grep -A 10 'status:' || echo "No registration"
echo "=== Events ==="
oc get events --sort-by='.lastTimestamp' -n $NS | tail -20
echo "=== OpenCode MCP config ==="
cat ~/.config/opencode/opencode.json | python3 -c "import sys,json; c=json.load(sys.stdin); print(json.dumps({k:v for k,v in c.get('mcp',{}).items()}, indent=2))"
```

2. Present findings to the participant and ask if they want to:
   - Try a different approach
   - Skip this step and continue
   - Start fresh (clean up and rebuild)

## SCORING IMPACT

When the troubleshooter helps fix an issue:
- +3 pts Agentic Fluency (for "Used AI to debug failures")
- The fix itself still earns Build Completeness points normally

Troubleshooting is a SKILL, not a penalty. Participants who debug learn more.
