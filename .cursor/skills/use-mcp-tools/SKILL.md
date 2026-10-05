---
name: use-mcp-tools
description: Call deployed MCP server tools directly via HTTP when OpenCode's native MCP client hasn't loaded them yet. The agent becomes its own MCP client using bash + curl. Use when MCP tools are registered in config but not available natively, or when the user asks to use stock market tools in a new session.
---

# Use MCP Tools via HTTP

When the user asks to use stock market tools (or any deployed MCP server tools)
and OpenCode's native MCP client hasn't connected them, YOU become the MCP client.

## WHEN TO USE THIS SKILL

- User asks about stock prices, financial data, or says "use my MCP tools"
- The `mcp` section in `~/.config/opencode/opencode.json` has a server registered
- But the tools don't appear in your native tool list
- OR you're in a new session after `opencode mcp add` was run

## HOW IT WORKS

The MCP server speaks streamable-http. You call it with `bash` + `curl`:

### Step 1: Read the MCP server URL from config

```bash
python3 -c "
import json
with open('/home/user/.config/opencode/opencode.json') as f:
    cfg = json.load(f)
for name, srv in cfg.get('mcp', {}).items():
    print(name, srv.get('url', ''))
"
```

### Step 2: Detect the user-scoped server name and initialize a session

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
USER_PREFIX=$(echo "$NS" | sed 's/-devspaces$//')
APP_NAME="${USER_PREFIX}-stock-mcp"

# Get MCP URL from the MCPServer status (operator-managed)
MCP_URL=$(oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.address.url}' 2>/dev/null)

# Fallback: construct from service name
if [ -z "$MCP_URL" ]; then
  MCP_URL="http://${APP_NAME}.${NS}.svc.cluster.local:8080/mcp"
fi

echo "MCP URL: $MCP_URL"

HDRFILE=$(mktemp)

# Initialize
curl -sD "$HDRFILE" -X POST "$MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"opencode-agent","version":"1.0"}}}'

# Extract session ID from response HEADER (not body)
SESSION_ID=$(grep -i 'mcp-session-id' "$HDRFILE" | tr -d '\r' | awk '{print $2}')
echo "SESSION=$SESSION_ID"
rm -f "$HDRFILE"
```

### Step 3: Call a tool

```bash
# Replace TOOL_NAME and ARGUMENTS as needed
curl -s -X POST "$MCP_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"TOOL_NAME","arguments":{"ticker":"AAPL"}}}'
```

### Step 4: Parse the SSE response

The response is Server-Sent Events format:
```
event: message
data: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{...JSON...}"}]}}
```

Extract the `data:` line and parse the JSON inside `result.content[0].text`.

## COMPLETE SINGLE-SHOT PATTERN

Use this Python script for reliable tool calls (handles SSE parsing, session management):

```bash
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
USER_PREFIX=$(echo "$NS" | sed 's/-devspaces$//')
APP_NAME="${USER_PREFIX}-stock-mcp"

# Get MCP URL from MCPServer status or construct from service
MCP_URL=$(oc get mcpserver "$APP_NAME" -n "$NS" \
  -o jsonpath='{.status.address.url}' 2>/dev/null)
if [ -z "$MCP_URL" ]; then
  MCP_URL="http://${APP_NAME}.${NS}.svc.cluster.local:8080/mcp"
fi

python3 - "$MCP_URL" "${1:-get_stock_info}" "${2:-{\"ticker\":\"AAPL\"}}" << 'PYEOF'
import json, sys
try:
    from urllib.request import Request, urlopen
except ImportError:
    from urllib2 import Request, urlopen

MCP_URL = sys.argv[1]
TOOL_NAME = sys.argv[2]
ARGS_JSON = sys.argv[3]

def post(url, payload, session=None, timeout=60):
    headers = {"Content-Type": "application/json",
               "Accept": "application/json, text/event-stream"}
    if session:
        headers["Mcp-Session-Id"] = session
    req = Request(url, data=json.dumps(payload).encode(), headers=headers, method="POST")
    resp = urlopen(req, timeout=timeout)
    sid = resp.headers.get("Mcp-Session-Id") or session
    body = resp.read().decode().strip()
    for line in body.splitlines():
        if line.startswith("data: "):
            return sid, json.loads(line[6:])
    if body:
        return sid, json.loads(body)
    return sid, None

# 1. Initialize
sid, resp = post(MCP_URL, {
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2025-03-26", "capabilities": {},
               "clientInfo": {"name": "opencode-agent", "version": "1.0"}}
})

# 2. Call the tool
sid, result = post(MCP_URL, {
    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
    "params": {"name": TOOL_NAME, "arguments": json.loads(ARGS_JSON)}
}, session=sid, timeout=120)

# 3. Output the result
text = result["result"]["content"][0]["text"]
try:
    parsed = json.loads(text)
    print(json.dumps(parsed, indent=2)[:2000])
except:
    print(text[:2000])
PYEOF
```

Usage examples:
```bash
# Get stock info
python3 /tmp/mcp_call.py get_stock_info '{"ticker":"AAPL"}'

# Get historical prices
python3 /tmp/mcp_call.py get_historical_stock_prices '{"ticker":"TSLA","period":"1mo","interval":"1d"}'

# Get news
python3 /tmp/mcp_call.py get_stock_news '{"ticker":"NVDA"}'

# Get recommendations
python3 /tmp/mcp_call.py get_recommendations '{"ticker":"AAPL","recommendation_type":"recommendations"}'
```

## AVAILABLE TOOLS

These are the 9 tools on the stock-market-mcp server:

| Tool | Arguments | Description |
|------|-----------|-------------|
| `get_stock_info` | `ticker` | Price, company details, key metrics |
| `get_historical_stock_prices` | `ticker`, `period?`, `interval?` | OHLCV history |
| `get_stock_news` | `ticker` | Latest news articles |
| `get_stock_actions` | `ticker` | Dividends and splits |
| `get_financial_statement` | `ticker`, `financial_type` | Income/balance/cashflow |
| `get_holder_info` | `ticker`, `holder_type` | Institutional/insider holders |
| `get_option_expiration_dates` | `ticker` | Options expiry dates |
| `get_option_chain` | `ticker`, `expiration_date`, `option_type`, `strike_window_pct?`, `fields?` | Options chain |
| `get_recommendations` | `ticker`, `recommendation_type` | Analyst ratings |

## PRESENTATION

When showing results to the user, DON'T dump raw JSON. Extract key fields and present nicely:

For `get_stock_info`:
```
📊 Apple Inc. (AAPL)
  Price:      $227.50
  Change:     +1.2% today
  Market Cap: $3.4T
  P/E:        34.2
  52w Range:  $164.08 – $260.10
  Sector:     Technology
```

For `get_stock_news`: Show title, summary, and URL for each article.
For `get_historical_stock_prices`: Summarize the trend (up/down, % change over period).
For `get_recommendations`: Show the consensus and recent analyst actions.

## IMPORTANT

- Always initialize a NEW session for each batch of tool calls
- Session ID comes from the HTTP **response header** `Mcp-Session-Id`
- Tool results are in `result.content[0].text` (always a JSON string)
- Parse the JSON string to extract meaningful data for the user
- If the server is not reachable, tell the user and suggest checking deployment
