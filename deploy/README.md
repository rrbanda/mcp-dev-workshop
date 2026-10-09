# Deploy Templates

YAML templates for deploying your MCP server on OpenShift using the MCP Lifecycle.

## Files

| File | What it creates | Layer |
|------|----------------|-------|
| `01-mcpserver.yaml` | MCPServer CR — operator creates Deployment + Service + NetworkPolicy | Deploy |
| `02-httproute.yaml` | HTTPRoute — gateway path for your server | Route |
| `03-mcpserverregistration.yaml` | MCPServerRegistration — tool discovery + prefix | Govern |

## Placeholders

Set these environment variables before applying:

```bash
export USER_PREFIX=user1                          # your username
export USER_NAMESPACE=$(oc project -q)            # your namespace
export IMAGE_REF=$(oc get istag ${USER_PREFIX}-stock-mcp:latest \
  -o jsonpath='{.image.dockerImageReference}')    # image digest
export GATEWAY_HOSTNAME=$(oc get route -n mcp-system \
  -o jsonpath='{.items[0].spec.host}')            # gateway hostname
```

## Apply in order

```bash
sed "s|USER_PREFIX|$USER_PREFIX|g; s|IMAGE_REF|$IMAGE_REF|g" \
  deploy/01-mcpserver.yaml | oc apply -f -

# Wait for Ready
oc get mcpserver ${USER_PREFIX}-stock-mcp -w

sed "s|USER_PREFIX|$USER_PREFIX|g; s|GATEWAY_HOSTNAME|$GATEWAY_HOSTNAME|g" \
  deploy/02-httproute.yaml | oc apply -f -

sed "s|USER_PREFIX|$USER_PREFIX|g; s|USER_NAMESPACE|$USER_NAMESPACE|g" \
  deploy/03-mcpserverregistration.yaml | oc apply -f -
```

## Cleanup (reverse order)

```bash
oc delete mcpserverregistration ${USER_PREFIX}-stock-mcp
oc delete httproute ${USER_PREFIX}-stock-mcp
oc delete mcpserver ${USER_PREFIX}-stock-mcp
oc delete bc/${USER_PREFIX}-stock-mcp
oc delete is/${USER_PREFIX}-stock-mcp
```
