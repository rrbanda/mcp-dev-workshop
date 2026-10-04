---
name: build-deploy-openshift
description: Build a container image, deploy it on OpenShift AI using the RHOAI MCPServer CR, and register it in OpenCode. Use when asked to deploy, ship, build and deploy, containerize, or put an MCP server on the cluster.
---

# Build, Deploy & Connect on OpenShift AI (RHOAI 3.5)

Build a container image using OpenShift binary builds, deploy it as a managed
MCPServer resource via the RHOAI MCP Lifecycle Operator, register it in OpenCode,
and verify the full chain — all from inside this DevSpaces workspace.

## When to use

Use this skill when asked to deploy, ship, build and deploy, containerize, or put
a server on OpenShift. Also use when asked to connect, register, or test a deployed
MCP server from OpenCode. Works for any Python MCP server that has a `Dockerfile`
(or `Containerfile`) and listens on a port.

## How it works

The RHOAI MCP Lifecycle Operator watches for `MCPServer` custom resources
(`mcp.x-k8s.io/v1alpha1`). When you create one, the operator automatically:

- Creates a **Deployment** with security-hardened pods (non-root, drop ALL
  capabilities, read-only root filesystem, seccomp RuntimeDefault)
- Creates a **Service** (ClusterIP) for internal access
- Creates a **NetworkPolicy** for network segmentation
- Performs an **MCP protocol handshake** to verify the server responds correctly
- Populates `status.address.url` with the internal service URL
- Reports `Ready=True` when the server is healthy

You do NOT manually create Deployments, Services, Routes, or security contexts.

## Prerequisites

The workspace service account already has the `edit` role in this namespace.
The `oc` CLI is available and authenticated via the mounted service account token.
The MCP Lifecycle Operator is enabled in the DataScienceCluster (`mcplifecycleoperator: Managed`).

## Step-by-step procedure

Follow these steps **exactly** and **in order**. Run each command with the `bash`
tool. Do NOT skip steps or combine them.

---

### Phase 1: Build the Container Image

The MCPServer CR needs an OCI image reference. We use OpenShift binary builds
to build and push the image to the internal registry.

#### Step 0: Prepare the project directory

Make sure the project directory contains at minimum:
- `server.py` (or your main application file)
- `requirements.txt`
- A `Dockerfile` (if only a `Containerfile` exists, copy it)

```bash
cd /path/to/project

# If only Containerfile exists, copy it (oc build requires Dockerfile)
if [ -f Containerfile ] && [ ! -f Dockerfile ]; then
  cp Containerfile Dockerfile
fi

# Verify
ls -la Dockerfile requirements.txt server.py
```

> **Critical**: OpenShift binary builds require the file to be named `Dockerfile`,
> not `Containerfile`. Always ensure `Dockerfile` exists before building.

#### Step 1: Detect the namespace

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
echo "Namespace: $NS"
```

#### Step 2: Choose an app name

Derive from the project directory name. Use lowercase, hyphens only.
Example: `stock-market-mcp`

```bash
APP_NAME="stock-market-mcp"
```

#### Step 3: Clean up any previous deployment (idempotent)

```bash
# Remove MCPServer CR (operator will garbage-collect Deployment, Service, NetworkPolicy)
oc delete mcpserver "$APP_NAME" -n "$NS" 2>/dev/null || true

# Remove build resources
oc delete bc "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete is "$APP_NAME" -n "$NS" 2>/dev/null || true

# Remove any legacy manual resources (from older deploy method)
oc delete route "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete svc "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete deployment "$APP_NAME" -n "$NS" 2>/dev/null || true

echo "Previous resources cleaned (if any)"
```

#### Step 4: Create the BuildConfig

```bash
oc new-build --binary --name="$APP_NAME" --strategy=docker -n "$NS"
```

Expected output includes:
```
imagestream.image.openshift.io "stock-market-mcp" created
buildconfig.build.openshift.io "stock-market-mcp" created
```

#### Step 5: Start the build (uploads source, builds image)

```bash
oc start-build "$APP_NAME" --from-dir=. --follow -n "$NS"
```

This uploads the project directory, runs the Dockerfile build on the cluster,
and pushes the image to the internal registry. Wait for "Push successful".

> This step takes 30–90 seconds. The `--follow` flag streams build logs.

---

### Phase 2: Deploy via MCPServer CR

This is the RHOAI way — one declarative resource replaces manual Deployment,
Service, Route, and security configuration.

#### Step 6: Get the image reference

```bash
IMAGE_REF=$(oc get is "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.tags[0].items[0].dockerImageReference}')
echo "Image: $IMAGE_REF"
```

> Use the full `@sha256:` reference for reproducible deployments.

#### Step 7: Apply the MCPServer CR

```bash
cat <<EOF | oc apply -n "$NS" -f -
apiVersion: mcp.x-k8s.io/v1alpha1
kind: MCPServer
metadata:
  name: $APP_NAME
spec:
  source:
    type: ContainerImage
    containerImage:
      ref: $IMAGE_REF
  config:
    port: 8080
    path: /mcp
    storage:
      - path: /tmp
        permissions: ReadWrite
        source:
          type: EmptyDir
          emptyDir: {}
      - path: /.cache
        permissions: ReadWrite
        source:
          type: EmptyDir
          emptyDir: {}
  mcp:
    stateless: true
  runtime:
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "1"
        memory: "512Mi"
EOF
```

**What this does:**
- The operator creates a Deployment, Service, and NetworkPolicy automatically
- Security is enforced: non-root, drop ALL capabilities, read-only root FS, seccomp
- The `/tmp` and `/.cache` EmptyDir mounts provide writable space for runtime data
  (yfinance caches, temp files) on the read-only root filesystem
- `stateless: true` allows load balancing across replicas
- The operator performs an MCP handshake to verify the server is functional

#### Step 8: Wait for the MCPServer to be ready

```bash
echo "Waiting for MCPServer to be ready..."
for i in $(seq 1 20); do
  READY=$(oc get mcpserver "$APP_NAME" -n "$NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  REASON=$(oc get mcpserver "$APP_NAME" -n "$NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}')
  echo "  $i: Ready=$READY ($REASON)"
  if [ "$READY" = "True" ]; then
    echo "MCPServer is ready!"
    break
  fi
  sleep 5
done
```

#### Step 9: Get the service URL and verify

```bash
# The operator auto-populates the internal service URL
MCP_URL=$(oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.address.url}')
echo "MCP URL: $MCP_URL"

# Show server info from the MCP handshake
echo ""
echo "Server capabilities (from operator handshake):"
oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='  Name: {.status.serverInfo.name}{"\n"}  Tools: {.status.serverInfo.capabilities.tools}{"\n"}'

# Verify the MCP endpoint responds
echo ""
echo "Testing MCP endpoint..."
curl -s -X POST "$MCP_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | head -c 500
```

A successful response contains `"result"` with server capabilities.

---

### Phase 3: Register & Use

#### Step 10: Register as MCP server in OpenCode

Connect the deployed server to OpenCode so the AI agent can use it as a
tool provider. Use the internal URL from the MCPServer status:

```bash
MCP_URL=$(oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.address.url}')

opencode mcp add "$APP_NAME" --url "$MCP_URL"
```

Verify it shows "connected":
```bash
opencode mcp list
```

Expected output:
```
●  ✓ stock-market-mcp  connected
     http://stock-market-mcp.dev-user1-devspaces.svc.cluster.local:8080/mcp
```

#### Step 11: Print summary

```bash
MCP_URL=$(oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.address.url}')

echo ""
echo "============================================"
echo "  Deployment Complete (RHOAI MCPServer)"
echo "============================================"
echo "  App:            $APP_NAME"
echo "  Namespace:      $NS"
echo "  MCP URL:        $MCP_URL"
echo "  OpenCode MCP:   registered ✓"
echo ""
echo "  Managed by:     MCP Lifecycle Operator"
echo "  Security:       non-root, drop ALL, read-only FS"
echo "  Auto-created:   Deployment, Service, NetworkPolicy"
echo "============================================"
echo ""
echo "The MCP server is now available as a tool in OpenCode."
echo "Start a new session and ask the agent to use the stock market tools."
```

#### Step 12: Inform the user to start a new session

> **IMPORTANT**: After registering the MCP server, the tools are only visible
> in a **new** OpenCode session. Tell the user:

```bash
echo ""
echo "⚠️  To use the MCP tools, start a NEW OpenCode session."
echo "   Press Ctrl+N or click '+ New Session' in the sidebar."
echo "   Then ask: 'Use the stock market tools to get the AAPL stock price'"
echo ""
```

## Testing the MCP server from OpenCode

After registration (Step 10), the user must start a **new OpenCode session**.
The MCP tools will NOT appear in the current session. This is an OpenCode
limitation — MCP server connections are loaded at session start.

In the new session, ask:

> "Use the stock market MCP tools to get the current price of AAPL"

The agent will see the registered MCP server's tools and call them directly.
This proves the full chain: OpenCode → MCPServer pod → yfinance → Yahoo Finance.

## Rebuilding after code changes

If you need to update the deployed server after code changes:

```bash
# Re-trigger the build
oc start-build "$APP_NAME" --from-dir=. --follow -n "$NS"

# Get the new image reference
IMAGE_REF=$(oc get is "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.tags[0].items[0].dockerImageReference}')

# Patch the MCPServer CR with the new image
oc patch mcpserver "$APP_NAME" -n "$NS" --type=merge \
  -p "{\"spec\":{\"source\":{\"containerImage\":{\"ref\":\"$IMAGE_REF\"}}}}"

# Wait for rollout
for i in $(seq 1 20); do
  READY=$(oc get mcpserver "$APP_NAME" -n "$NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  [ "$READY" = "True" ] && echo "Updated and ready!" && break
  sleep 5
done
```

## Checking MCPServer status

```bash
# Quick status
oc get mcpserver "$APP_NAME" -n "$NS"

# Detailed status with conditions
oc get mcpserver "$APP_NAME" -n "$NS" -o yaml

# Operator-managed resources
oc get deploy,svc,networkpolicy -l mcp-server="$APP_NAME" -n "$NS"
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `error: open /tmp/build/inputs/Dockerfile: no such file or directory` | Copy `Containerfile` to `Dockerfile` |
| Build fails pulling base image | Check network; use `registry.access.redhat.com/ubi9/python-312:latest` |
| MCPServer `Ready=False` `DeploymentUnavailable` | Check pod logs: `oc logs -l mcp-server=$APP_NAME -n $NS` |
| MCPServer `Accepted=False` `Invalid` | Check the CR spec — port, image ref, or path may be wrong |
| MCP handshake fails | Server must respond to MCP `initialize` on the configured `path` |
| "already exists" errors | Run Step 3 cleanup first, then retry from Step 4 |
| OpenCode MCP shows "disconnected" | Check pod is running: `oc get mcpserver $APP_NAME -n $NS` |
| MCP tools not visible in OpenCode | Start a new session after registering the MCP server |
| Write errors in container (read-only FS) | Add writable mount in `config.storage` for the needed path |

## Complete example (stock market MCP server)

After generating the server code with the `build-mcp-server` skill:

```bash
cd ~/mcp-dev-workshop/scaffold
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
APP_NAME="stock-market-mcp"

# Ensure Dockerfile exists
cp Containerfile Dockerfile 2>/dev/null || true

# Clean previous
oc delete mcpserver "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete bc "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete is "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete route "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete svc "$APP_NAME" -n "$NS" 2>/dev/null || true
oc delete deployment "$APP_NAME" -n "$NS" 2>/dev/null || true

# Build
oc new-build --binary --name="$APP_NAME" --strategy=docker -n "$NS"
oc start-build "$APP_NAME" --from-dir=. --follow -n "$NS"

# Get image reference
IMAGE_REF=$(oc get is "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.tags[0].items[0].dockerImageReference}')

# Deploy via MCPServer CR
cat <<EOF | oc apply -n "$NS" -f -
apiVersion: mcp.x-k8s.io/v1alpha1
kind: MCPServer
metadata:
  name: $APP_NAME
spec:
  source:
    type: ContainerImage
    containerImage:
      ref: $IMAGE_REF
  config:
    port: 8080
    path: /mcp
    storage:
      - path: /tmp
        permissions: ReadWrite
        source:
          type: EmptyDir
          emptyDir: {}
      - path: /.cache
        permissions: ReadWrite
        source:
          type: EmptyDir
          emptyDir: {}
  mcp:
    stateless: true
  runtime:
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "1"
        memory: "512Mi"
EOF

# Wait for ready
for i in $(seq 1 20); do
  READY=$(oc get mcpserver "$APP_NAME" -n "$NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  [ "$READY" = "True" ] && echo "MCPServer ready!" && break
  sleep 5
done

# Get URL and register in OpenCode
MCP_URL=$(oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.address.url}')
echo "MCP URL: $MCP_URL"

opencode mcp add "$APP_NAME" --url "$MCP_URL"
opencode mcp list
```
