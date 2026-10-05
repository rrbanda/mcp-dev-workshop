---
name: workshop-cleanup
description: Interactive cleanup of all workshop resources from OpenShift. Walks the user through what will be deleted, confirms each step, verifies cleanup, and optionally resets the workspace to a fresh state for the next participant. Use after the workshop is complete or when the user says clean up, reset, tear down, or done.
---

# Workshop Cleanup

Guide the participant through a safe, interactive teardown of everything
created during the workshop. Never delete anything without confirmation.

## WHEN TO TRIGGER

- User says "clean up", "done", "tear down", "reset", "finished"
- Workshop Stage 9 is complete and participant is satisfied
- Facilitator wants to prepare for the next participant

## STEP 1: Confirm Intent

Use the **question** tool:

"You've completed the workshop! Before we clean up, let me check..."

"What would you like to do with your MCP server?"
- **Clean up everything** — Remove all deployed resources (recommended after workshop)
- **Keep it running** — Leave the server deployed, I'll just summarize what was built
- **Reset for next participant** — Full cleanup + reset scaffold to blank starter

## STEP 2: Detect User-Scoped Names and Show What Exists

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
USER_PREFIX=$(echo "$NS" | sed 's/-devspaces$//')
APP_NAME="${USER_PREFIX}-stock-mcp"

echo "=== Your workshop resources ==="
echo "Namespace: $NS"
echo "User: $USER_PREFIX"
echo ""

# MCP Lifecycle resources (operator-managed)
oc get mcpserver "$APP_NAME" -n "$NS" 2>/dev/null \
  && echo "  📦 MCPServer: $APP_NAME (operator manages Deployment, Service, NetworkPolicy)" \
  || echo "  (no MCPServer)"

# Gateway registration
oc get mcpserverregistration "${APP_NAME}-reg" -n "$NS" 2>/dev/null \
  && echo "  🔗 MCPServerRegistration: ${APP_NAME}-reg" \
  || echo "  (no gateway registration)"

oc get httproute "${APP_NAME}-route" -n "$NS" 2>/dev/null \
  && echo "  🌐 HTTPRoute: ${APP_NAME}-route" \
  || echo "  (no HTTPRoute)"

# Build artifacts
oc get bc "$APP_NAME" -n "$NS" 2>/dev/null \
  && echo "  🏗️ BuildConfig: $APP_NAME" \
  || echo "  (no build config)"

oc get is "$APP_NAME" -n "$NS" 2>/dev/null \
  && echo "  📀 ImageStream: $APP_NAME" \
  || echo "  (no image stream)"
```

Present the summary and use the **question** tool:

"These are the resources that will be deleted. The MCPServer CR deletion
will automatically garbage-collect the Deployment, Service, and NetworkPolicy
that the operator created."

"Delete all of the above?"
- "Yes, clean it all up"
- "Wait, keep the deployment but remove gateway registration"
- "Cancel — don't delete anything"

## STEP 3: Execute Cleanup

Run deletions in the correct order (registration first, then MCPServer):

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
USER_PREFIX=$(echo "$NS" | sed 's/-devspaces$//')
APP_NAME="${USER_PREFIX}-stock-mcp"

echo "Cleaning up workshop resources..."

# 1. Remove OpenCode MCP registration
echo "  Removing OpenCode MCP registration..."
opencode mcp remove "$APP_NAME" 2>/dev/null || true

# 2. Remove gateway registration (MCPServerRegistration + HTTPRoute)
echo "  Removing gateway registration..."
oc delete mcpserverregistration "${APP_NAME}-reg" -n "$NS" --ignore-not-found
oc delete httproute "${APP_NAME}-route" -n "$NS" --ignore-not-found

# 3. Remove MCPServer CR (operator garbage-collects Deployment, Service, NetworkPolicy)
echo "  Removing MCPServer (operator will clean up Deployment, Service, NetworkPolicy)..."
oc delete mcpserver "$APP_NAME" -n "$NS" --ignore-not-found

# 4. Remove build artifacts
echo "  Removing build artifacts..."
oc delete bc "$APP_NAME" -n "$NS" --ignore-not-found
oc delete is "$APP_NAME" -n "$NS" --ignore-not-found

# 5. Remove any legacy manual resources (from older deploy method)
oc delete route "$APP_NAME" -n "$NS" --ignore-not-found 2>/dev/null || true
oc delete svc "$APP_NAME" -n "$NS" --ignore-not-found 2>/dev/null || true
oc delete deployment "$APP_NAME" -n "$NS" --ignore-not-found 2>/dev/null || true

echo ""
echo "  ✅ OpenCode MCP registration removed"
echo "  ✅ MCPServerRegistration deleted"
echo "  ✅ HTTPRoute deleted"
echo "  ✅ MCPServer deleted (Deployment, Service, NetworkPolicy auto-cleaned)"
echo "  ✅ BuildConfig deleted"
echo "  ✅ ImageStream deleted"
```

## STEP 4: Verify Cleanup

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
USER_PREFIX=$(echo "$NS" | sed 's/-devspaces$//')
APP_NAME="${USER_PREFIX}-stock-mcp"

echo "=== Verification ==="
oc get mcpserver,mcpserverregistration,httproute,deploy,svc,bc,is -n "$NS" 2>/dev/null \
  | grep "$APP_NAME" || echo "✅ No $APP_NAME resources found — cleanup complete"
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

**Workshop Complete!**

What you built today:
- ✅ A stock market MCP server with N tools
- ✅ Containerized with UBI9 Python 3.12
- ✅ Deployed via MCPServer CR (operator-managed)
- ✅ Imported to the AI Hub MCP Catalog
- ✅ Registered with the MCP Gateway (federated tool discovery)
- ✅ Connected to your AI IDE via MCP protocol
- ✅ Used real stock data from the AI chat

What you learned:
- ✅ MCP protocol (tools, resources, prompts) — an open standard
- ✅ Python MCP SDK (@server.tool decorator)
- ✅ OpenShift binary builds (oc new-build)
- ✅ MCP Lifecycle Operator (MCPServer CR)
- ✅ MCP Gateway (HTTPRoute + MCPServerRegistration)
- ✅ Tool design for AI discoverability

Then show the "Continue Learning" resources from the `redhat-mcp-resources` skill.

## KEEP-RUNNING PATH

If the user chose "Keep it running":

"Your server is still live and managed by the MCP Lifecycle Operator."

- **Direct URL:** (from `oc get mcpserver $APP_NAME -o jsonpath='{.status.address.url}'`)
- **Gateway URL:** (from MCP Gateway hostname)
- **Tools:** N tools available
- To use: start a new OpenCode session
- To clean up later: type "clean up"
- To add tools: "add more tools to my server"
