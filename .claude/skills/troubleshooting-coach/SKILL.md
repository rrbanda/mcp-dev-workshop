---
name: troubleshooting-coach
description: Empathetic, systematic troubleshooting for workshop failures. Covers build errors, deployment issues, MCP connection problems, and common mistakes. Never blames the participant. Load when something goes wrong.
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

## COMMON ERROR CATALOG

### Build Errors

#### "No such file or directory: Dockerfile"
```bash
# Diagnosis
ls -la Dockerfile Containerfile 2>&1
```
**Cause:** OpenShift binary builds require `Dockerfile`, not `Containerfile`.
**Fix:** `cp Containerfile Dockerfile`
**Prevention:** "OpenShift looks specifically for `Dockerfile`. Always copy your Containerfile before building."

#### "Build failed: pip install"
```bash
# Diagnosis
oc logs bc/stock-market-mcp --tail=30
```
**Cause:** Usually a typo in requirements.txt or a package that needs system deps.
**Fix:** Check requirements.txt spelling. Ensure packages are available for the base image.
**Prevention:** "Test `pip install -r requirements.txt` locally before building."

#### "ImagePullBackOff"
```bash
# Diagnosis
oc describe pod -l app=stock-market-mcp | grep -A5 "Events"
```
**Cause:** Image stream tag doesn't exist (build didn't push).
**Fix:** Re-run the build: `oc start-build stock-market-mcp --from-dir=. --follow`

### Deployment Errors

#### Pod in CrashLoopBackOff
```bash
# Diagnosis
oc logs deployment/stock-market-mcp --tail=50
```
**Common causes:**
- Missing `MCP_TRANSPORT` env var → server tries stdio, fails in container
- Import error → missing dependency in requirements.txt
- Syntax error in server.py → check the traceback

**Fix pattern:**
```bash
# Fix code, then rebuild + redeploy
oc start-build stock-market-mcp --from-dir=. --follow
oc rollout status deployment/stock-market-mcp --timeout=120s
```

#### Route returns 503
```bash
# Diagnosis
oc get pods -l app=stock-market-mcp
oc get endpoints stock-market-mcp
```
**Cause:** Pod not ready yet, or readiness probe failing.
**Fix:** Wait for pod to be Ready, or check that port 8080 is correct.

### MCP Connection Errors

#### "opencode mcp list" shows disconnected
```bash
# Diagnosis
oc get pods -l app=stock-market-mcp -o wide
curl -s -X POST "http://stock-market-mcp.$NS.svc:8080/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```
**Cause:** Pod crashed, service not routing, or URL wrong.
**Fix:** Verify pod is running, then re-register with correct URL.

#### Tools not visible in OpenCode
**Cause:** MCP tools load at session start. New registrations need a new session.
**Fix:** "Press Ctrl+N to start a new session. Your tools will appear there."

#### "tools/call" returns error
```bash
# Diagnosis — check server logs
oc logs deployment/stock-market-mcp --tail=20
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
echo "=== Pod status ==="
oc get pods -l app=stock-market-mcp -o wide
echo "=== Pod logs ==="
oc logs deployment/stock-market-mcp --tail=100
echo "=== Events ==="
oc get events --sort-by='.lastTimestamp' | tail -20
echo "=== Config ==="
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
