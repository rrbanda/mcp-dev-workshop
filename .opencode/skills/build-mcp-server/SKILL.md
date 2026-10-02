# Build MCP Server

Build a production-ready MCP (Model Context Protocol) server using the Python SDK v2.

## When to use

Use this skill when asked to create, build, scaffold, or generate an MCP server,
MCP tools, or anything related to extending an AI agent with external capabilities.

## MCP Python SDK v2 API

The SDK is `mcp` (pip package). Import the server class and use decorators:

```python
from mcp.server import MCPServer

mcp = MCPServer("server-name")
```

### Defining Tools

Use the `@mcp.tool()` decorator. Type hints become JSON Schema. Docstrings become descriptions.

```python
@mcp.tool()
def list_pods(namespace: str, label: str = "") -> str:
    """List pods in the given namespace, optionally filtered by label.

    Args:
        namespace: Kubernetes namespace to query.
        label: Optional label selector (e.g. 'app=nginx').
    """
    import subprocess
    cmd = ["oc", "get", "pods", "-n", namespace, "-o", "wide"]
    if label:
        cmd.extend(["-l", label])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        return f"Error: {result.stderr.strip()}"
    return result.stdout.strip() or "No pods found."
```

### Defining Resources (read-only context)

```python
@mcp.resource("config://cluster-info")
def cluster_info() -> str:
    """Current cluster and user context."""
    import subprocess
    result = subprocess.run(
        ["oc", "whoami", "--show-console"],
        capture_output=True, text=True, timeout=10
    )
    return result.stdout.strip()
```

### Running the Server

**Local development (stdio transport)** — used with `mcp dev` or wired into an agent:

```python
if __name__ == "__main__":
    mcp.run()  # defaults to stdio
```

**Production deployment (streamable HTTP)** — used when deployed as a container:

```python
if __name__ == "__main__":
    import os
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "streamable-http":
        mcp.run(transport="streamable-http", host="0.0.0.0", port=8080)
    else:
        mcp.run()
```

**With uvicorn (production ASGI)**:

```python
app = mcp.streamable_http_app(stateless_http=True, json_response=True)
# Then run: uvicorn server:app --host 0.0.0.0 --port 8080
```

> For production HTTP deployments, pass `stateless_http=True` and `json_response=True` to avoid session tracking overhead.

## Best Practices

1. **Error handling**: Always wrap subprocess/network calls in try/except. Return error strings, never raise exceptions from tools.
2. **Timeouts**: Set `timeout=` on every subprocess.run() and network call.
3. **Type hints**: Use `str`, `int`, `bool`, `list[str]`, `Optional[str]` — they map to JSON Schema for the caller.
4. **Docstrings**: First line is the tool description. `Args:` section describes each parameter.
5. **Security**: Never embed credentials in code. Use environment variables or mounted secrets.
6. **Stateless**: Each tool call should be independent. Do not store state between calls.

## File Structure

When generating an MCP server, always create these files:

### server.py
The main server file with tools defined as shown above.

### requirements.txt
```
mcp>=2.0
```
Add any additional dependencies the tools need (e.g., `kubernetes`, `requests`).

### Containerfile
```dockerfile
FROM registry.access.redhat.com/ubi9/python-312:latest

WORKDIR /opt/app-root/src
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

ENV MCP_TRANSPORT=streamable-http
EXPOSE 8080

CMD ["python", "server.py"]
```

### deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-mcp-server
  labels:
    app: my-mcp-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-mcp-server
  template:
    metadata:
      labels:
        app: my-mcp-server
    spec:
      containers:
        - name: server
          image: image-registry.openshift-image-registry.svc:5000/MY_NAMESPACE/my-mcp-server:latest
          ports:
            - containerPort: 8080
          env:
            - name: MCP_TRANSPORT
              value: "streamable-http"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: my-mcp-server
spec:
  selector:
    app: my-mcp-server
  ports:
    - port: 8080
      targetPort: 8080
```

## Transport Reference

| Transport | Use Case | How to Start |
|-----------|----------|-------------|
| stdio | Local dev, agent-direct | `mcp.run()` or `mcp dev server.py` |
| streamable-http | Container deployment | `mcp.run(transport="streamable-http", host="0.0.0.0", port=8080)` |
| SSE | Legacy (deprecated 2025-03-26) | Do not use for new servers |

> **Important**: The default host for streamable-http is `127.0.0.1` (localhost only). For container deployments, you MUST set `host="0.0.0.0"` so the server accepts connections from outside the container. The default port is `8000`; the default endpoint path is `/mcp`.

## Example: Complete DevOps MCP Server

```python
from mcp.server import MCPServer
import subprocess

mcp = MCPServer("openshift-devops")

@mcp.tool()
def list_pods(namespace: str, label: str = "") -> str:
    """List pods in a namespace with optional label filter.

    Args:
        namespace: The OpenShift namespace to query.
        label: Optional label selector like 'app=web'.
    """
    cmd = ["oc", "get", "pods", "-n", namespace, "-o", "wide"]
    if label:
        cmd.extend(["-l", label])
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return f"Error: {result.stderr.strip()}"
        return result.stdout.strip() or "No pods found."
    except subprocess.TimeoutExpired:
        return "Error: command timed out after 30s"

@mcp.tool()
def get_pod_logs(pod_name: str, namespace: str, tail: int = 50) -> str:
    """Get recent log lines from a pod.

    Args:
        pod_name: Name of the pod.
        namespace: The OpenShift namespace.
        tail: Number of recent lines to return (default 50).
    """
    try:
        result = subprocess.run(
            ["oc", "logs", pod_name, "-n", namespace, f"--tail={tail}"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            return f"Error: {result.stderr.strip()}"
        return result.stdout.strip() or "No logs available."
    except subprocess.TimeoutExpired:
        return "Error: command timed out after 30s"

@mcp.tool()
def get_route_url(route_name: str, namespace: str) -> str:
    """Get the public URL for an OpenShift Route.

    Args:
        route_name: Name of the Route resource.
        namespace: The OpenShift namespace.
    """
    try:
        result = subprocess.run(
            ["oc", "get", "route", route_name, "-n", namespace,
             "-o", "jsonpath={.spec.host}"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return f"Error: {result.stderr.strip()}"
        host = result.stdout.strip()
        if not host:
            return f"Route '{route_name}' not found in namespace '{namespace}'."
        tls = subprocess.run(
            ["oc", "get", "route", route_name, "-n", namespace,
             "-o", "jsonpath={.spec.tls}"],
            capture_output=True, text=True, timeout=10
        )
        scheme = "https" if tls.stdout.strip() else "http"
        return f"{scheme}://{host}"
    except subprocess.TimeoutExpired:
        return "Error: command timed out"

@mcp.tool()
def describe_resource(kind: str, name: str, namespace: str) -> str:
    """Describe any Kubernetes resource.

    Args:
        kind: Resource type (e.g. 'deployment', 'service', 'pod').
        name: Resource name.
        namespace: The OpenShift namespace.
    """
    try:
        result = subprocess.run(
            ["oc", "describe", kind, name, "-n", namespace],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            return f"Error: {result.stderr.strip()}"
        output = result.stdout.strip()
        if len(output) > 4000:
            return output[:4000] + "\n... (truncated)"
        return output
    except subprocess.TimeoutExpired:
        return "Error: command timed out after 30s"

if __name__ == "__main__":
    import os
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "streamable-http":
        mcp.run(transport="streamable-http", host="0.0.0.0", port=8080)
    else:
        mcp.run()
```
