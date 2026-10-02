---
name: build-deploy-openshift
description: Build a container image and deploy it on OpenShift directly from this DevSpaces workspace. Use when asked to deploy, ship, build and deploy, containerize, or put an MCP server (or any Python app) on the cluster.
---

# Build & Deploy on OpenShift

Build a container image using OpenShift binary builds and deploy it as a running
pod with a public route — all from inside this DevSpaces workspace.

## When to use

Use this skill when asked to deploy, ship, build and deploy, containerize, or put
a server on OpenShift. Works for any Python application that has a `Dockerfile`
(or `Containerfile`) and listens on a port.

## Prerequisites

The workspace service account already has the `edit` role in this namespace.
The `oc` CLI is available and authenticated via the mounted service account token.

## Step-by-step procedure

Follow these steps **exactly** and **in order**. Run each command with the `bash`
tool. Do NOT skip steps or combine them.

### Step 0: Prepare the project directory

Make sure the project directory contains at minimum:
- `server.py` (or your main application file)
- `requirements.txt`
- A `Dockerfile` (if only a `Containerfile` exists, copy it)

```bash
cd /path/to/project

# If only Containerfile exists, copy it to Dockerfile (oc build requires Dockerfile)
if [ -f Containerfile ] && [ ! -f Dockerfile ]; then
  cp Containerfile Dockerfile
fi

# Verify
ls -la Dockerfile requirements.txt server.py
```

> **Critical**: OpenShift binary builds require the file to be named `Dockerfile`,
> not `Containerfile`. Always ensure `Dockerfile` exists.

### Step 1: Detect the namespace

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
echo "Namespace: $NS"
```

### Step 2: Choose an app name

Derive from the project directory name. Use lowercase, hyphens only.
Example: `stock-market-mcp`

```bash
APP_NAME="stock-market-mcp"
```

### Step 3: Clean up any previous deployment (idempotent)

```bash
oc delete route "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete svc "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete deployment "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete bc "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete is "$APP_NAME" -n "$NS" 2>/dev/null || true
echo "Previous resources cleaned (if any)"
```

### Step 4: Create the BuildConfig

```bash
oc new-build --binary --name="$APP_NAME" --strategy=docker -n "$NS"
```

Expected output includes:
```
imagestream.image.openshift.io "stock-market-mcp" created
buildconfig.build.openshift.io "stock-market-mcp" created
```

### Step 5: Start the build (uploads source, builds image)

```bash
oc start-build "$APP_NAME" --from-dir=. --follow -n "$NS"
```

This uploads the project directory, runs the Dockerfile build on the cluster,
and pushes the image to the internal registry. Wait for "Push successful".

> This step takes 30–90 seconds. The `--follow` flag streams build logs.

### Step 6: Deploy the application

```bash
oc new-app "$APP_NAME" -n "$NS"
```

Expected output:
```
deployment.apps "stock-market-mcp" created
service "stock-market-mcp" created
```

### Step 7: Expose the route

```bash
oc expose svc/"$APP_NAME" --port=8080 -n "$NS"
```

### Step 8: Wait for the pod to be ready

```bash
oc rollout status deployment/"$APP_NAME" -n "$NS" --timeout=120s
```

### Step 9: Get the route URL and verify

```bash
ROUTE=$(oc get route "$APP_NAME" -n "$NS" -o jsonpath='{.spec.host}')
echo "Route: http://$ROUTE"
echo ""
echo "Testing /mcp endpoint..."
curl -s -X POST "http://$ROUTE/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | head -c 500
```

A successful response contains `"result"` with server capabilities.

### Step 10: Print summary

```bash
echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo "  App:       $APP_NAME"
echo "  Namespace: $NS"
echo "  Route:     http://$ROUTE"
echo "  MCP URL:   http://$ROUTE/mcp"
echo "============================================"
echo ""
echo "To use this MCP server, configure your client with:"
echo "  URL: http://$ROUTE/mcp"
```

## Rebuilding after code changes

If you need to update the deployed server after code changes:

```bash
# Just re-trigger the build and rollout:
oc start-build "$APP_NAME" --from-dir=. --follow -n "$NS"
# The deployment auto-updates when the image stream tag changes.
oc rollout status deployment/"$APP_NAME" -n "$NS" --timeout=120s
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `error: open /tmp/build/inputs/Dockerfile: no such file or directory` | Rename `Containerfile` to `Dockerfile` |
| Build fails pulling base image | Check network; use `registry.access.redhat.com/ubi9/python-312:latest` |
| Pod in CrashLoopBackOff | Check logs: `oc logs deployment/$APP_NAME -n $NS` |
| Route returns 503 | Pod not ready yet; wait or check readiness probe |
| "already exists" errors | Run Step 3 cleanup first, then retry from Step 4 |

## Complete example (stock market MCP server)

After generating the server code with the `build-mcp-server` skill:

```bash
cd ~/mcp-dev-workshop/stock-market-mcp
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
APP_NAME="stock-market-mcp"

# Ensure Dockerfile exists
cp Containerfile Dockerfile 2>/dev/null || true

# Clean previous
oc delete route "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete svc "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete deployment "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete bc "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete is "$APP_NAME" -n "$NS" 2>/dev/null || true

# Build
oc new-build --binary --name="$APP_NAME" --strategy=docker -n "$NS"
oc start-build "$APP_NAME" --from-dir=. --follow -n "$NS"

# Deploy
oc new-app "$APP_NAME" -n "$NS"
oc expose svc/"$APP_NAME" --port=8080 -n "$NS"
oc rollout status deployment/"$APP_NAME" -n "$NS" --timeout=120s

# Verify
ROUTE=$(oc get route "$APP_NAME" -n "$NS" -o jsonpath='{.spec.host}')
echo "MCP Server URL: http://$ROUTE/mcp"
curl -s -X POST "http://$ROUTE/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```
