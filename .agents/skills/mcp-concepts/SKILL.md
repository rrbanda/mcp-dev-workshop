---
name: mcp-concepts
description: Standalone MCP concept teaching with multi-level explanations (beginner, developer, architect). Covers protocol fundamentals, architecture, primitives, tool lifecycle, transport, descriptions, and error handling. Use when asked to explain MCP or loaded during workshop Stage 1.
---

# MCP Concepts — Multi-Level Teaching

Teach MCP (Model Context Protocol) concepts at the appropriate depth for the participant's
experience level. This skill can be loaded standalone ("tell me about MCP") or as part of
the workshop Stage 1 teaching phase.

## ADAPTATION RULES

Before teaching, determine the participant's level:
- **Beginner**: Use analogies, explain every term, maximum warmth
- **Developer**: Show code patterns, skip analogies, focus on SDK
- **Architect**: Design trade-offs, protocol evolution, integration points

If loaded during the workshop, the workshop-guide skill will have already detected
the persona. Use that. If loaded standalone, ask with the question tool.

## CONCEPT 1: What is MCP?

### Beginner Version (use restaurant analogy)

"Imagine you're at a restaurant:
- **Your MCP server** = the kitchen (it has the capabilities)
- **Tools** = the menu items (each tool does one thing)
- **The AI model** = the waiter (reads the menu, takes orders, delivers food)
- **MCP protocol** = the language the waiter and kitchen speak

Without MCP, every AI model needs custom code to talk to every data source.
With MCP, you build ONE server and ANY AI model that speaks MCP can use it."

### Developer Version

"MCP (Model Context Protocol) is an open standard that defines how AI models discover
and call external tools. Think of it as a **standardized plugin system** for LLMs — the
model gets a typed function signature, calls it with JSON arguments, and gets a string
result back. One server, any client."

### Architect Version

"MCP is the interoperability layer between AI hosts and capability providers. It defines
a JSON-RPC 2.0 protocol for tool discovery (`tools/list`), invocation (`tools/call`),
resource access, and prompt templates. The key architectural property: **servers are
stateless capability endpoints** that multiple clients can connect to simultaneously."

**Red Hat Resource** (surface after explaining):
> 📘 [Model Context Protocol: The Missing Link in AI Integration](https://www.redhat.com/en/blog/model-context-protocol-discover-missing-link-ai-integration)

---

## CONCEPT 2: Architecture — Host, Client, Server

Present this diagram:

```
┌─────────────────────────────────────────────────┐
│  HOST (OpenCode / IDE)                          │
│                                                 │
│   ┌──────────┐    MCP Protocol    ┌──────────┐  │
│   │  AI      │◄──────────────────►│  MCP     │  │
│   │  Model   │   JSON-RPC 2.0    │  Client   │  │
│   │ (qwen38) │                   │          │  │
│   └──────────┘                   └────┬─────┘  │
│                                       │         │
└───────────────────────────────────────┼─────────┘
                                        │
                              ┌─────────▼─────────┐
                              │   MCP SERVER       │
                              │   (your code!)     │
                              │                    │
                              │  Tool 1: get_stock │
                              │  Tool 2: get_price │
                              │  Tool N: ...       │
                              │                    │
                              │  Data: Yahoo API   │
                              └────────────────────┘
```

Three layers:
- **Host**: The application running the AI (OpenCode in our case)
- **Client**: Built into the host. Discovers tools, routes calls, returns results
- **Server**: YOUR code. Defines tools. Connects to external data.

For architects: "The host can connect to MULTIPLE MCP servers simultaneously.
Each server is an independent capability domain."

**Red Hat Resource:**
> 📘 [Building Effective AI Agents with MCP](https://developers.redhat.com/articles/building-effective-ai-agents-mcp)

---

## CONCEPT 3: Three Primitives

```
┌─────────────────────────────────────────────────────┐
│                  MCP Primitives                      │
├─────────────┬──────────────────┬────────────────────┤
│   TOOLS     │   RESOURCES      │   PROMPTS          │
│             │                  │                    │
│  Functions  │  Read-only data  │  Template          │
│  the AI     │  the AI can      │  messages the      │
│  can CALL   │  READ            │  AI can USE        │
│             │                  │                    │
│  Model      │  Application     │  User              │
│  controlled │  controlled      │  controlled        │
└─────────────┴──────────────────┴────────────────────┘
```

"Today we focus on **Tools** — the most powerful and most common. A tool is a function
the AI model can decide to call based on the user's request."

For developers: "Tool parameters use Python type hints that map to JSON Schema.
`str` → `string`, `int` → `integer`, `float` → `number`, `bool` → `boolean`."

---

## CONCEPT 4: Tool Call Lifecycle

```
User: "What's Apple's stock price?"
  │
  ▼
AI Model thinks: "I need stock data. I have get_stock_info. Apple = AAPL."
  │
  ▼
AI sends: { "name": "get_stock_info", "arguments": { "ticker": "AAPL" } }
  │
  ▼
MCP Client routes call to your server
  │
  ▼
Your server: yf.Ticker("AAPL").info → formats as JSON string
  │
  ▼
AI reads result and responds: "Apple is trading at $227.50..."
```

"The AI decides WHICH tool to call and WHAT arguments to pass.
Your server just handles the request and returns data."

---

## CONCEPT 5: Transport

```
┌────────────────────────────┬─────────────────────────────┐
│     stdio (local)          │  streamable-http (remote)   │
├────────────────────────────┼─────────────────────────────┤
│ Client spawns server as    │ Server runs as HTTP service  │
│ child process.             │ (pod, container).            │
│ stdin/stdout pipes.        │ POST to /mcp endpoint.       │
│                            │                             │
│ Best for: local dev        │ Best for: production,       │
│                            │ shared, OpenShift.          │
└────────────────────────────┴─────────────────────────────┘
```

"We build for BOTH — stdio for local testing, streamable-http for deployment."

For DevOps: "In production, the streamable-http transport means your MCP server
is just a regular HTTP microservice — standard Kubernetes patterns apply."

---

## CONCEPT 6: Writing Good Descriptions (critical)

```python
# ❌ BAD — AI has no idea what this does
@server.tool(name="data", description="Gets data")
async def data(x: str) -> str: ...

# ✅ GOOD — AI knows exactly when and how to use it
@server.tool(
    name="get_stock_info",
    description="Get comprehensive stock data including current price, "
                "company details, and key financial metrics."
)
async def get_stock_info(ticker: str) -> str:
    """Get stock info for a ticker symbol.
    Args:
        ticker: Stock ticker symbol (e.g. AAPL, TSLA, NVDA).
    """
```

"The AI reads the description to decide WHEN to call. Better descriptions = smarter AI."

---

## CONCEPT 7: Error Handling

```python
# ❌ BAD — AI sees "Internal error"
@server.tool(name="get_stock_info", description="...")
async def get_stock_info(ticker: str) -> str:
    company = yf.Ticker(ticker)
    info = company.info  # Raises if invalid!
    return json.dumps(info)

# ✅ GOOD — AI sees a helpful message
@server.tool(name="get_stock_info", description="...")
async def get_stock_info(ticker: str) -> str:
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        info = company.info
        if not info or 'symbol' not in info:
            return f"No stock info found for ticker '{ticker}'."
        return json.dumps(info)
    except Exception as e:
        return f"Error getting stock info for {ticker}: {e}"
```

"Return error strings, never raise exceptions. The AI reads your error to help the user."

**Red Hat Resource:**
> 🔒 [MCP Security: Understanding Risks](https://www.redhat.com/en/blog/mcp-security-current-situation-understanding-risks)

---

## CONCEPT RECAP

After all concepts, show:

```
✅ MCP = standardized protocol for AI ↔ tools
✅ Architecture: Host → Client → Server (you build the server)
✅ Three primitives: Tools, Resources, Prompts
✅ Tool call lifecycle: User asks → AI picks tool → Server executes → AI responds
✅ Transport: stdio (local) vs streamable-http (production)
✅ Good descriptions = good AI behavior
✅ Return errors as strings, never raise exceptions
```

Then: "Now you know enough to build a production MCP server. Ready?"
