"""Multi-server MCP composition — Lab 7 solution.

Demonstrates connecting to multiple MCP servers from a single agent.
This server adds project-awareness tools alongside the DevOps tools.
"""
from mcp.server import MCPServer
import subprocess
import os
import json

mcp = MCPServer("project-helper")


@mcp.tool()
def search_code(pattern: str, directory: str = ".") -> str:
    """Search for a pattern in source files using grep.

    Args:
        pattern: The regex pattern to search for.
        directory: Directory to search in (default: current directory).
    """
    try:
        result = subprocess.run(
            ["grep", "-rn", "--include=*.py", "--include=*.yaml",
             "--include=*.json", pattern, directory],
            capture_output=True, text=True, timeout=15,
        )
        output = result.stdout.strip()
        if not output:
            return f"No matches found for '{pattern}' in {directory}."
        if len(output) > 3000:
            return output[:3000] + "\n... (truncated)"
        return output
    except subprocess.TimeoutExpired:
        return "Error: search timed out after 15s"


@mcp.tool()
def list_files(directory: str = ".", extension: str = "") -> str:
    """List files in a directory with optional extension filter.

    Args:
        directory: Directory to list (default: current directory).
        extension: Filter by file extension (e.g. '.py', '.yaml').
    """
    try:
        cmd = ["find", directory, "-maxdepth", "3", "-type", "f"]
        if extension:
            cmd.extend(["-name", f"*{extension}"])
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        output = result.stdout.strip()
        if not output:
            return f"No files found in {directory}."
        return output
    except subprocess.TimeoutExpired:
        return "Error: command timed out"


@mcp.tool()
def read_yaml(filepath: str) -> str:
    """Read and parse a YAML file, returning formatted content.

    Args:
        filepath: Path to the YAML file.
    """
    try:
        with open(filepath, "r") as f:
            content = f.read()
        if len(content) > 4000:
            return content[:4000] + "\n... (truncated)"
        return content
    except FileNotFoundError:
        return f"Error: file '{filepath}' not found."
    except Exception as e:
        return f"Error reading file: {e}"


@mcp.tool()
def get_git_status() -> str:
    """Get the current git status of the workspace."""
    try:
        result = subprocess.run(
            ["git", "status", "--short"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return f"Error: {result.stderr.strip()}"
        return result.stdout.strip() or "Working tree clean."
    except subprocess.TimeoutExpired:
        return "Error: command timed out"


if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "streamable-http":
        mcp.run(transport="streamable-http", host="0.0.0.0", port=8080)
    else:
        mcp.run()
