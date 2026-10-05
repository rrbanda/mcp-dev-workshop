---
name: knowledge-check
description: Final quiz at the end of the workshop. One question at a time using the question tool. Load ONLY during Stage 9 wrap-up — never between stages.
---

# Knowledge Check — Final Workshop Quiz

## RULES

1. **End-of-workshop only.** This quiz runs once, at Stage 9c. NEVER use it between stages.
2. **One question at a time.** Use the question tool. Wait for answer. Give feedback. Then next question.
3. **Wrong answers are teaching moments.** Re-explain, then offer retry.
4. **Partial credit**: first try = full points, retry = partial points.
5. **Never block permanently**: after 2 wrong attempts, give the answer and move on.
6. **Update scores silently** via todowrite. Show a formatted scorecard after the quiz.
7. **Use markdown formatting only** — no box-drawing characters.

## QUIZ FORMAT

Start with a heading:

### 🧠 Final Knowledge Check
**Question 1 of 8**

Then use the question tool with the options.

**If correct:**

> ✅ **Correct!** +3 points
>
> *[Brief reinforcement]*

**If wrong (first try):**

> ❌ **Not quite** — common misconception though.
>
> *[2-3 sentence re-explanation]*
>
> Want to try again?

**If wrong (second try):**

> The answer is **[correct answer]**. Here's why:
>
> *[Explanation]*
>
> +1 point for engaging. Let's move on.

## QUESTIONS (8 total, 20 pts max)

### MCP Protocol Concepts (Stages 1-2)

**Q1** (3 pts / 2 retry): "When the AI calls `tools/call`, who executes the function?"
- The AI model itself
- The MCP client in the host
- **Your MCP server** ← correct
- The user's browser

*Why: The server executes. The AI decides which tool, the server does the work.*

**Q2** (3 pts / 2 retry): "Why do MCP tools return error strings instead of raising exceptions?"
- It's faster
- Python doesn't support async exceptions
- **So the AI can read the error and explain it to the user** ← correct
- The MCP protocol doesn't support exceptions

*Why: "No data found for XYZ" lets the AI help. A raised exception becomes "Internal error" — useless.*

### Build & Design (Stages 3-6)

**Q3** (3 pts / 2 retry): "What transport do we use for deploying on OpenShift?"
- stdio
- SSE
- **streamable-http** ← correct
- gRPC

*Why: stdio needs child-process spawning — impossible across containers. HTTP makes it a normal service.*

**Q4** (3 pts / 2 retry): "What does the AI read to decide WHEN to call a tool?"
- The Python source code
- The requirements.txt
- **The tool's name, description, and parameter types** ← correct
- Only the user's messages

*Why: The model sees JSON Schema — name, description, parameter types. Good descriptions = smart AI.*

**Q5** (2 pts / 1 retry): "What's wrong with this tool?"
```python
@server.tool(name="data", description="Gets data")
async def data(x: str) -> str:
    return yf.Ticker(x).info
```
- Nothing wrong
- Missing import
- **Vague name, vague description, no error handling, returns dict not string** ← correct
- Wrong decorator

**Q6** (2 pts / 1 retry): "Why does our server have `normalize_ticker`?"
- To uppercase tickers
- **Yahoo Finance needs BRK-B not BRK.B — silently returns empty data otherwise** ← correct
- To validate existence
- Required by MCP SDK

### Deploy & Govern (Stage 7)

**Q7** (2 pts / 1 retry): "Why use an MCPServer CR instead of manually creating a Deployment?"
- It's faster to type
- **The operator auto-creates Deployment, Service, NetworkPolicy, verifies MCP handshake, and enforces security** ← correct
- Manual Deployments don't work on OpenShift
- The MCP SDK requires it

**Q8** (2 pts / 1 retry): "What does the `prefix` field in MCPServerRegistration do?"
- Sets the server's DNS name
- **Namespaces your tools so they don't collide with other users' tools on the gateway** ← correct
- Defines the URL path
- Specifies the MCP protocol version

**Gate: 5/8 correct to pass.**

## SCORE UPDATE

After the quiz, update todowrite silently, then show the formatted scorecard from workshop-scoring.
