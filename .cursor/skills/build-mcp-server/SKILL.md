# Build MCP Server

Build a production-ready MCP (Model Context Protocol) server using the Python SDK v2.

## When to use

Use this skill when asked to create, build, scaffold, or generate an MCP server,
MCP tools, or anything related to extending an AI agent with external capabilities.

**Related skills** (load these when building a stock market MCP server):
- `yfinance-api` — Complete yfinance library API reference (Ticker methods, return types, DataFrame serialization)
- `stock-market-mcp-spec` — Exact specification for a stock market MCP server (9 tools, 3 Enums, 4 helpers)

## MCP Python SDK v2 API

The SDK is `mcp` (pip package). Import the server class and use decorators:

```python
from mcp.server import MCPServer

server = MCPServer("server-name")
```

### Defining Tools

Use the `@server.tool()` decorator with explicit name and description. Type hints become JSON Schema. Async functions recommended.

```python
@server.tool(
    name="get_data",
    description="Get data for a given identifier.",
)
async def get_data(identifier: str, limit: int = 10) -> str:
    """Get data for a given identifier.

    Args:
        identifier: The ID to look up.
        limit: Maximum results to return (default 10).
    """
    try:
        # implementation
        return json.dumps(result)
    except Exception as e:
        return f"Error: {e}"
```

### Using Enum Types for Validated Parameters

When a tool parameter has a fixed set of valid values, use `str, Enum` subclasses.
The Enum values appear in the JSON Schema as `{"enum": [...]}` so agents know
exactly what values are valid.

```python
from enum import Enum

class DataType(str, Enum):
    summary = "summary"
    detailed = "detailed"
    raw = "raw"

@server.tool(
    name="fetch_report",
    description="Fetch a report. type must be: summary, detailed, or raw.",
)
async def fetch_report(name: str, type: str) -> str:
    if type == DataType.summary:
        # ...
```

### Defining Resources (read-only context)

```python
@server.resource("config://cluster-info")
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
    server.run()  # defaults to stdio
```

**Dual-transport (recommended)** — stdio for dev, HTTP for deployment:

```python
def main() -> None:
    import os
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "streamable-http":
        server.run(transport="streamable-http", host="0.0.0.0", port=8080)
    else:
        server.run(transport="stdio")

if __name__ == "__main__":
    main()
```

**With uvicorn (production ASGI)**:

```python
app = server.streamable_http_app(stateless_http=True, json_response=True)
# Then run: uvicorn server:app --host 0.0.0.0 --port 8080
```

> For production HTTP deployments, pass `stateless_http=True` and `json_response=True` to avoid session tracking overhead.

## Best Practices

1. **Error handling**: Always wrap logic in try/except. Return error strings, never raise exceptions from tools.
2. **Timeouts**: Set `timeout=` on every subprocess.run() and network call.
3. **Type hints**: Use `str`, `int`, `float`, `bool`, `list[str]`, `float | None` — they map to JSON Schema for the caller.
4. **Docstrings**: First line is the tool description. `Args:` section describes each parameter.
5. **Security**: Never embed credentials in code. Use environment variables or mounted secrets.
6. **Stateless**: Each tool call should be independent. Do not store state between calls.
7. **Async**: Prefer `async def` for tools, especially when doing I/O operations.

## File Structure

When generating an MCP server, always create these files:

### server.py
The main server file with tools defined as shown above.

### requirements.txt
```
mcp[cli]>=2.1.0,<3
```
Add any additional dependencies the tools need (e.g., `yfinance>=1.6.0,<2`).

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
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "1000m"
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
| stdio | Local dev, agent-direct | `server.run()` or `mcp dev server.py` |
| streamable-http | Container deployment | `server.run(transport="streamable-http", host="0.0.0.0", port=8080)` |
| SSE | Legacy (deprecated 2025-03-26) | Do not use for new servers |

> **Important**: The default host for streamable-http is `127.0.0.1` (localhost only). For container deployments, you MUST set `host="0.0.0.0"` so the server accepts connections from outside the container. The default port is `8000`; the default endpoint path is `/mcp`.
