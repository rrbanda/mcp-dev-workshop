---
name: build-deploy-openshift
description: Build a container image, deploy it on OpenShift using the MCP Lifecycle Operator, import it to the AI Hub MCP Catalog, register it with the MCP Gateway, and connect it in OpenCode. Use when asked to deploy, ship, build and deploy, containerize, or put an MCP server on the cluster.
---

# Build, Deploy & Register an MCP Server on OpenShift

Build a container image, deploy it as a managed MCPServer resource, import it to
the AI Hub MCP Catalog, register it with the MCP Gateway for governed access,
and connect it in OpenCode — all from inside this DevSpaces workspace.

MCP (Model Context Protocol) is an **open standard** for connecting AI agents to
tools and data sources. It works across platforms and runtimes. On OpenShift,
the MCP Lifecycle Operator provides managed deployment, the AI Hub provides
discovery, and the MCP Gateway (Red Hat Connectivity Link) provides governed
routing — but MCP itself is not tied to any single vendor or platform.

## When to use

Use this skill when asked to deploy, ship, build and deploy, containerize, or put
a server on OpenShift. Also use when asked to connect, register, or test a deployed
MCP server from OpenCode. Works for any Python MCP server that has a `Dockerfile`
(or `Containerfile`) and listens on a port.

## Architecture overview

The full MCP server lifecycle on OpenShift has three layers:

| Layer | Component | What it does |
|-------|-----------|-------------|
| **Deploy** | MCP Lifecycle Operator | Watches MCPServer CRs, auto-creates Deployment + Service + NetworkPolicy, performs MCP handshake |
| **Discover** | AI Hub MCP Catalog | Dashboard UI where deployed MCPServer CRs appear on the Deployments tab for browsing and management |
| **Route & Govern** | MCP Gateway (RHCL) | Single entry point for all MCP servers; federated tool discovery, auth, rate limiting via HTTPRoute + MCPServerRegistration |

## Prerequisites

The workspace service account already has the `edit` role in this namespace.
The `oc` CLI is available and authenticated via the mounted service account token.

**Platform admin prerequisites** (already done — users do not need to do these):
- MCP Lifecycle Operator enabled in DSC (`mcplifecycleoperator: Managed`)
- MCP Catalog enabled in dashboard (`mcpCatalog: true`)
- MCP Gateway Operator installed in `mcp-system`
- Gateway `mcp-gateway` and MCPGatewayExtension created in `mcp-system`

See the **Platform Admin Setup** section at the end of this file for the one-time
commands that a cluster admin runs before the workshop.

## User-scoped naming

Every resource uses the participant's username as a prefix to avoid collisions
when multiple users share the same cluster:

- MCPServer: `$USER-stock-mcp`
- BuildConfig / ImageStream: `$USER-stock-mcp`
- HTTPRoute: `$USER-stock-mcp-route`
- MCPServerRegistration: `$USER-stock-mcp-reg`

## Step-by-step procedure

Follow these steps **exactly** and **in order**. Run each command with the `bash`
tool. Do NOT skip steps or combine them.

---

### Phase 1: Build the Container Image

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

#### Step 1: Detect namespace and username

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
# Extract username from namespace (e.g., user1-devspaces → user1)
USER_PREFIX=$(echo "$NS" | sed 's/-devspaces$//')
echo "Namespace: $NS"
echo "User prefix: $USER_PREFIX"
```

#### Step 2: Set the app name (user-scoped)

```bash
APP_NAME="${USER_PREFIX}-stock-mcp"
echo "App name: $APP_NAME"
```

#### Step 3: Clean up any previous deployment (idempotent)

```bash
# Remove MCPServer CR (operator will garbage-collect Deployment, Service, NetworkPolicy)
oc delete mcpserver "$APP_NAME" -n "$NS" 2>/dev/null || true

# Remove gateway registration
oc delete mcpserverregistration "${APP_NAME}-reg" -n "$NS" 2>/dev/null || true
oc delete httproute "${APP_NAME}-route" -n "$NS" 2>/dev/null || true

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

#### Step 5: Start the build (uploads source, builds image)

```bash
oc start-build "$APP_NAME" --from-dir=. --follow -n "$NS"
```

This uploads the project directory, runs the Dockerfile build on the cluster,
and pushes the image to the internal registry. Wait for "Push successful".

> This step takes 30–90 seconds. The `--follow` flag streams build logs.

---

### Phase 2: Browse the AI Hub MCP Catalog

Before deploying your own server, explore what's already available.

#### Step 6: Tell the user to browse the catalog

> **Action for the participant**: Open the Red Hat OpenShift AI dashboard in your
> browser. Navigate to **AI Hub → MCP servers**. You'll see pre-curated MCP servers
> from Red Hat, technology partners, and the open source community.
>
> Each server card shows the name, description, tools, and support tier (Red Hat /
> Partner / Community). You could deploy any of these with one click — but we're
> going to deploy the server YOU just built.

This is a teaching moment: the catalog is a discovery hub. Pre-built servers are
ready to go, but the real power is deploying your own custom MCP servers.

---

### Phase 3: Import to the MCP Catalog (MCPServer CR)

Creating an MCPServer CR is how you "import" your server into the managed
platform. The MCP Lifecycle Operator picks it up, deploys it with security
hardening, and it appears on the AI Hub **Deployments** tab.

#### Step 7: Get the image reference

```bash
IMAGE_REF=$(oc get is "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.tags[0].items[0].dockerImageReference}')
echo "Image: $IMAGE_REF"
```

> Use the full `@sha256:` reference for reproducible deployments.

#### Step 8: Apply the MCPServer CR

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

**What the operator does automatically:**
- Creates a **Deployment** with security-hardened pods (non-root, drop ALL
  capabilities, read-only root filesystem, seccomp RuntimeDefault)
- Creates a **Service** (ClusterIP) for internal access
- Creates a **NetworkPolicy** for network segmentation
- Performs an **MCP protocol handshake** to verify the server responds correctly
- Populates `status.address.url` with the internal service URL
- Reports `Ready=True` when the server is healthy

You do NOT manually create Deployments, Services, Routes, or security contexts.

#### Step 9: Wait for the MCPServer to be ready

```bash
echo "Waiting for MCPServer to be ready..."
for i in $(seq 1 30); do
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

#### Step 10: Verify on the AI Hub Deployments tab

> **Action for the participant**: Go back to the OpenShift AI dashboard →
> **AI Hub → MCP servers → Deployments** tab. You should now see your
> `$APP_NAME` listed with a Ready status.
>
> This confirms the MCP Lifecycle Operator is managing your server. From this
> tab you can also scale, upgrade, edit the YAML, or delete the server.

---

### Phase 4: Register with the MCP Gateway

The MCP Gateway provides a single, governed entry point for all MCP servers
on the cluster. Registering your server makes its tools discoverable through
the gateway's federated tool catalog.

#### Step 11: Create an HTTPRoute to the gateway

```bash
# Get the MCP Gateway hostname
GW_HOSTNAME=$(oc get gateway mcp-gateway -n mcp-system \
  -o jsonpath='{.spec.listeners[0].hostname}')
echo "Gateway hostname: $GW_HOSTNAME"

cat <<EOF | oc apply -n "$NS" -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${APP_NAME}-route
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: mcp-gateway
      namespace: mcp-system
      sectionName: http
  hostnames:
    - ${GW_HOSTNAME}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /mcp
      backendRefs:
        - name: ${APP_NAME}
          port: 8080
EOF
```

#### Step 12: Create the MCPServerRegistration

```bash
cat <<EOF | oc apply -n "$NS" -f -
apiVersion: mcp.kuadrant.io/v1alpha1
kind: MCPServerRegistration
metadata:
  name: ${APP_NAME}-reg
spec:
  toolPrefix: "${USER_PREFIX}_stock_"
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${APP_NAME}-route
    namespace: ${NS}
EOF
```

The `toolPrefix` ensures your tools don't collide with other users' tools
on the same gateway. Your tools will appear as `user1_stock_get_stock_info`,
`user1_stock_get_historical_stock_prices`, etc.

#### Step 13: Wait for the registration to be ready

```bash
echo "Waiting for gateway registration..."
for i in $(seq 1 20); do
  READY=$(oc get mcpserverregistration "${APP_NAME}-reg" -n "$NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  TOOLS=$(oc get mcpserverregistration "${APP_NAME}-reg" -n "$NS" \
    -o jsonpath='{.status.discoveredTools}')
  echo "  $i: Ready=$READY, Tools=$TOOLS"
  if [ "$READY" = "True" ]; then
    echo "Registered with gateway! $TOOLS tools discovered."
    break
  fi
  sleep 5
done
```

---

### Phase 5: Connect & Use in OpenCode

#### Step 14: Get the service URL and register in OpenCode

```bash
# Direct service URL (cluster-internal, no gateway)
MCP_URL=$(oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.address.url}')
echo "Direct MCP URL: $MCP_URL"

# Register with OpenCode using the direct URL
opencode mcp add "$APP_NAME" --url "$MCP_URL"
```

Verify it shows "connected":
```bash
opencode mcp list
```

Expected output:
```
●  ✓ user1-stock-mcp  connected
     http://user1-stock-mcp.user1-devspaces.svc.cluster.local:8080/mcp
```

#### Step 15: Print summary

```bash
MCP_URL=$(oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.address.url}')
TOOLS=$(oc get mcpserverregistration "${APP_NAME}-reg" -n "$NS" \
  -o jsonpath='{.status.discoveredTools}' 2>/dev/null || echo "N/A")

echo ""
echo "============================================"
echo "  MCP Server Lifecycle Complete"
echo "============================================"
echo "  Server:           $APP_NAME"
echo "  Namespace:        $NS"
echo "  MCP URL:          $MCP_URL"
echo "  OpenCode:         registered"
echo "  AI Hub Catalog:   visible on Deployments tab"
echo "  MCP Gateway:      registered ($TOOLS tools)"
echo ""
echo "  Managed by:       MCP Lifecycle Operator"
echo "  Security:         non-root, drop ALL, read-only FS"
echo "  Auto-created:     Deployment, Service, NetworkPolicy"
echo "============================================"
```

#### Step 16: Inform the user to start a new session

> **IMPORTANT**: After registering the MCP server, the tools are only visible
> in a **new** OpenCode session. Tell the user:

```bash
echo ""
echo "To use the MCP tools, start a NEW OpenCode session."
echo "Press Ctrl+N or click '+ New Session' in the sidebar."
echo "Then ask: 'Use the stock market tools to get the AAPL stock price'"
```

---

## Testing the MCP server from OpenCode

After registration (Step 14), the user must start a **new OpenCode session**.
In the new session, ask:

> "Use the stock market MCP tools to get the current price of AAPL"

The agent will see the registered MCP server's tools and call them directly.
This proves the full chain: OpenCode → MCPServer pod → yfinance → Yahoo Finance.

## Rebuilding after code changes

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

## Checking status

```bash
# MCPServer status
oc get mcpserver "$APP_NAME" -n "$NS"

# Gateway registration status
oc get mcpserverregistration "${APP_NAME}-reg" -n "$NS"

# Operator-managed resources
oc get deploy,svc,networkpolicy -n "$NS" | grep "$APP_NAME"
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails: `Dockerfile: no such file` | Copy `Containerfile` to `Dockerfile` |
| Build fails pulling base image | Check network; use `registry.access.redhat.com/ubi9/python-312:latest` |
| MCPServer `Ready=False` `DeploymentUnavailable` | Check pod logs: `oc logs -l mcp-server=$APP_NAME -n $NS` |
| MCPServer `Accepted=False` `Invalid` | Check the CR spec — port, image ref, or path may be wrong |
| MCPServerRegistration `Ready=False` | Check HTTPRoute accepted: `oc get httproute ${APP_NAME}-route -n $NS -o yaml` |
| Tools not showing in gateway | Check broker logs: `oc logs -n mcp-system deployment/mcp-gateway --tail=20` |
| MCP tools not visible in OpenCode | Start a new session after registering the MCP server |
| Write errors in container (read-only FS) | Add writable mount in `config.storage` for the needed path |

---

## Platform Admin Setup (one-time, before the workshop)

These commands prepare the cluster for the workshop. Run them once as
`cluster-admin`. Replace `<GATEWAY_HOSTNAME>` with the cluster's apps domain
(e.g., `mcp-gateway.apps.<cluster-domain>`).

### 1. Enable the MCP Lifecycle Operator

```bash
oc patch datasciencecluster default-dsc --type=merge \
  -p '{"spec":{"components":{"mcplifecycleoperator":{"managementState":"Managed"}}}}'
```

Verify:
```bash
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=mcp-lifecycle-operator
# Expect 1/1 Running
oc get crd mcpservers.mcp.x-k8s.io
# Expect the CRD to exist
```

### 2. Enable the MCP Catalog in the dashboard

```bash
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  --type=merge -p '{"spec":{"dashboardConfig":{"mcpCatalog":true}}}'
```

Verify: Open the RHOAI dashboard → AI Hub → MCP servers tab should appear.

### 3. Install the MCP Gateway Operator

```bash
oc create ns mcp-system

cat <<EOF | oc apply -n mcp-system -f -
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
  - mcp-system
EOF

# Wait for install
oc wait csv -n mcp-system -l operators.coreos.com/mcp-gateway.mcp-system="" \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=5m
```

### 4. Fix kuadrant-operator memory limit

The kuadrant-operator (installed as a dependency) defaults to 300Mi which
causes OOMKilled. Increase to 1Gi:

```bash
oc patch deployment -n mcp-system kuadrant-operator-controller-manager \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1Gi"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"512Mi"}]'
oc rollout status deployment/kuadrant-operator-controller-manager -n mcp-system --timeout=120s
```

### 5. Create the MCP Gateway

Replace `<GATEWAY_HOSTNAME>` with your cluster's hostname (e.g.,
`mcp-gateway.apps.mycluster.example.com`).

```bash
cat <<EOF | oc apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: mcp-gateway
  namespace: mcp-system
  labels:
    istio.io/rev: openshift-gateway
spec:
  gatewayClassName: data-science-gateway-class
  listeners:
    - name: http
      hostname: <GATEWAY_HOSTNAME>
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
EOF
```

Verify:
```bash
oc get gateway mcp-gateway -n mcp-system
# Expect PROGRAMMED=True
```

### 6. Create the MCPGatewayExtension

```bash
cat <<EOF | oc apply -f -
apiVersion: mcp.kuadrant.io/v1alpha1
kind: MCPGatewayExtension
metadata:
  name: mcp-gateway-extension
  namespace: mcp-system
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: mcp-gateway
    namespace: mcp-system
    sectionName: http
  httpRouteManagement: Enabled
EOF
```

Verify:
```bash
oc wait --for=condition=Ready mcpgatewayextension/mcp-gateway-extension \
  -n mcp-system --timeout=120s
# Expect: condition met

# Verify broker-router is running
oc get pods -n mcp-system | grep mcp-gateway
# Expect mcp-gateway-* (broker) and mcp-gateway-data-science-gateway-class-* (Envoy)

# Verify EnvoyFilter created
oc get envoyfilter -n mcp-system
```

### Verify the full platform setup

```bash
echo "=== MCP Lifecycle Operator ===" && \
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=mcp-lifecycle-operator --no-headers && \
echo "=== MCP Gateway ===" && \
oc get gateway mcp-gateway -n mcp-system --no-headers && \
echo "=== MCPGatewayExtension ===" && \
oc get mcpgatewayextension -n mcp-system --no-headers && \
echo "=== Broker pod ===" && \
oc get pods -n mcp-system -l app.kubernetes.io/name=mcp-gateway --no-headers
```

All components should show Ready/Running. The cluster is now prepared for
workshop participants to deploy MCP servers.
