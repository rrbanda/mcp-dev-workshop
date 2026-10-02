"""OpenShift DevOps MCP Server — workshop scaffold.

Provides tools for querying cluster state from an AI agent.
Built with MCP Python SDK v2.
"""
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
            capture_output=True, text=True, timeout=30,
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
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return f"Error: {result.stderr.strip()}"
        host = result.stdout.strip()
        if not host:
            return f"Route '{route_name}' not found in namespace '{namespace}'."
        tls = subprocess.run(
            ["oc", "get", "route", route_name, "-n", namespace,
             "-o", "jsonpath={.spec.tls}"],
            capture_output=True, text=True, timeout=10,
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
            capture_output=True, text=True, timeout=30,
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
