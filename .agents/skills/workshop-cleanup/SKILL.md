---
name: workshop-cleanup
description: Interactive cleanup of all workshop resources from OpenShift. Walks the user through what will be deleted, confirms each step, verifies cleanup, and optionally resets the workspace to a fresh state for the next participant. Use after the workshop is complete or when the user says clean up, reset, tear down, or done.
---

# Workshop Cleanup

Guide the participant through a safe, interactive teardown of everything
created during the workshop. Never delete anything without confirmation.

## WHEN TO TRIGGER

- User says "clean up", "done", "tear down", "reset", "finished"
- Workshop Stage 7 is complete and participant is satisfied
- Facilitator wants to prepare for the next participant

## STEP 1: Confirm Intent

Use the **question** tool:

"You've completed the workshop! Before we clean up, let me check…"

"What would you like to do with your MCP server?"
- **Clean up everything** — Remove all deployed resources (recommended after workshop)
- **Keep it running** — Leave the server deployed, I'll just summarize what was built
- **Reset for next participant** — Full cleanup + reset scaffold to blank starter

## STEP 2: Show What Will Be Deleted

Before deleting anything, show exactly what exists:

```bash
echo "=== Your workshop resources ==="
oc get deployment stock-market-mcp 2>/dev/null && echo "  📦 Deployment: stock-market-mcp" || echo "  (no deployment)"
oc get svc stock-market-mcp 2>/dev/null && echo "  🔌 Service: stock-market-mcp:8080" || echo "  (no service)"
oc get route stock-market-mcp 2>/dev/null && echo "  🌐 Route: $(oc get route stock-market-mcp -o jsonpath='{.spec.host}')" || echo "  (no route)"
oc get bc stock-market-mcp 2>/dev/null && echo "  🏗️ BuildConfig: stock-market-mcp" || echo "  (no build config)"
oc get is stock-market-mcp 2>/dev/null && echo "  📀 ImageStream: stock-market-mcp" || echo "  (no image stream)"
```

Present as a checklist:

```
┌─ RESOURCES TO DELETE ──────────────────────────┐
│                                                │
│  📦 Deployment:   stock-market-mcp             │
│  🔌 Service:      stock-market-mcp:8080        │
│  🌐 Route:        stock-market-mcp-dev-...     │
│  🏗️ BuildConfig:  stock-market-mcp (binary)    │
│  📀 ImageStream:  stock-market-mcp:latest      │
│  🔗 MCP Config:   opencode mcp remove          │
│                                                │
└────────────────────────────────────────────────┘
```

Use the **question** tool:
"Delete all of the above?"
- "Yes, clean it all up"
- "Wait, keep the deployment running but remove the build artifacts"
- "Cancel — don't delete anything"

## STEP 3: Execute Cleanup

Run each deletion with visible output:

```bash
cd /projects/mcp-dev-workshop
make clean
```

Or if `make clean` is not available, run each step:

```bash
echo "🗑️ Deleting route..."
oc delete route stock-market-mcp --ignore-not-found

echo "🗑️ Deleting deployment + service..."
oc delete -f scaffold/deployment.yaml --ignore-not-found 2>/dev/null || true
oc delete deployment stock-market-mcp --ignore-not-found
oc delete svc stock-market-mcp --ignore-not-found

echo "🗑️ Deleting build artifacts..."
oc delete bc stock-market-mcp --ignore-not-found
oc delete is stock-market-mcp --ignore-not-found

echo "🗑️ Removing MCP registration..."
opencode mcp remove stock-market-mcp 2>/dev/null || true
```

Show a progress checklist as each step completes:

```
  ✅ Route deleted
  ✅ Deployment deleted
  ✅ Service deleted
  ✅ BuildConfig deleted
  ✅ ImageStream deleted
  ✅ MCP registration removed
```

## STEP 4: Verify Cleanup

```bash
echo "=== Verification ==="
oc get deploy,svc,route,bc,is 2>/dev/null | grep stock-market || echo "✅ No stock-market-mcp resources found"
```

## STEP 5: Reset for Next Participant (optional)

If the user chose "Reset for next participant":

```bash
# Reset scaffold/server.py to empty starter
cat > /projects/mcp-dev-workshop/scaffold/server.py << 'EOF'
"""Stock Market MCP Server — built during the workshop."""
EOF

# Remove any generated Dockerfile (Containerfile stays)
rm -f /projects/mcp-dev-workshop/scaffold/Dockerfile

# Remove __pycache__
rm -rf /projects/mcp-dev-workshop/scaffold/__pycache__

echo "✅ Scaffold reset to blank starter"
```

## STEP 6: Workshop Summary

Always end with a summary of what was accomplished, regardless of cleanup choice:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🎓 Workshop Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  What you built today:
  ✅ A stock market MCP server with N tools
  ✅ Containerized with UBI9 Python 3.12
  ✅ Deployed on OpenShift AI (pod + service + route)
  ✅ Connected to your AI IDE via MCP protocol
  ✅ Used real stock data from the AI chat

  What you learned:
  ✅ MCP protocol (tools, resources, prompts)
  ✅ Python MCP SDK (@server.tool decorator)
  ✅ OpenShift binary builds (oc new-build)
  ✅ MCP streamable-http transport
  ✅ Tool design for AI discoverability

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then show the "Continue Learning" resources from the `redhat-mcp-resources` skill.

## KEEP-RUNNING PATH

If the user chose "Keep it running":

```
┌─ YOUR SERVER IS LIVE ──────────────────────────┐
│                                                │
│  Route: http://stock-market-mcp-dev-...        │
│  Tools: N tools available                      │
│                                                │
│  To use: start a new OpenCode session          │
│  To clean up later: type "clean up"            │
│  To add tools: "add more tools to my server"   │
│                                                │
└────────────────────────────────────────────────┘
```
