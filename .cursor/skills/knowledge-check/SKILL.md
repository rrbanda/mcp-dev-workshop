---
name: knowledge-check
description: Interactive quiz gates between workshop stages. Uses the question tool to present multiple-choice questions, re-teaches on wrong answers, and reports scores to the workshop-scoring system. Load before each stage transition.
---

# Knowledge Check — Stage-Gated Quizzes

Mandatory quiz gates between workshop stages. Participants must pass before proceeding.
Wrong answers trigger re-teaching, not failure. Every question feeds into the scoring system.

## RULES

1. **Use the question tool** for every quiz question — never present options as text.
2. **One question at a time.** Show the question, wait for the answer, give feedback, then next question.
3. **Wrong answers are teaching moments**, not failures. Re-explain the concept, then offer retry.
4. **Partial credit**: correct on first try = full points. Correct on retry = partial points.
5. **Never block permanently**: after 2 wrong attempts, give the answer with full explanation and move on.
6. **Track scores** via todowrite (update the score-mastery dimension).
7. **Show the visual quiz card format** from the presentation-mode skill.

## QUIZ FORMAT

Present each question with the presentation-mode quiz card:

```
╔══════════════════════════════════════════════════════╗
║  🧠 Knowledge Check — Stage [N] Complete             ║
║  Question [X] of [Y]                                 ║
╚══════════════════════════════════════════════════════╝
```

Then use the question tool with the options. After the answer, show:

**If correct:**
```
  ✅ Correct! +[N] points

  [Brief reinforcement of why this is right]

  Score: 🧠 [current]/20 pts
```

**If wrong (first attempt):**
```
  ❌ Not quite — but this is a common misconception.

  [2-3 sentence re-explanation of the concept]

  Want to try again?
```

**If wrong (second attempt):**
```
  The answer is [correct answer]. Here's why:

  [Full explanation]

  +[partial] points (partial credit for engaging with the question)

  Let's move on — you'll see this concept in action during the next stage.
```

## STAGE 1 QUIZ — MCP Concepts (4 questions, 12 pts max)

### Q1 (3 pts / 2 on retry)
**"When the AI model calls `tools/call`, who actually executes the function?"**
- The AI model itself
- The MCP client in the host
- **Your MCP server** ← CORRECT
- The user's browser

**Why:** The server is the capability provider. The AI decides WHICH tool to call, but the server executes it and returns the result.

### Q2 (3 pts / 2 on retry)
**"Why do MCP tools return error strings instead of raising exceptions?"**
- It's faster than exception handling
- Python doesn't support async exceptions
- **So the AI can read the error and explain it to the user** ← CORRECT
- The MCP protocol doesn't support exceptions

**Why:** When a tool returns "No data found for ticker XYZ", the AI can tell the user "That ticker doesn't exist." But if the tool raises an exception, the AI only sees "Internal error" — useless for helping the user.

### Q3 (3 pts / 2 on retry)
**"What transport will we use for deploying our MCP server on OpenShift?"**
- stdio
- SSE (Server-Sent Events)
- **streamable-http** ← CORRECT
- gRPC

**Why:** stdio requires the client to spawn the server as a child process — impossible when the server runs in a separate container. streamable-http makes the MCP server a regular HTTP service.

### Q4 (3 pts / 2 on retry)
**"What does the AI model read to decide WHEN to call a tool?"**
- The Python source code of your function
- The requirements.txt file
- **The tool's name, description, and parameter types** ← CORRECT
- Only the user's previous messages

**Why:** The model sees the tool's JSON Schema: name, description, and parameter types with their descriptions. This is why good tool names and descriptions are critical.

## STAGE 3 QUIZ — Build (2 questions, 4 pts max)

### Q5 (2 pts / 1 on retry)
**"Look at this tool definition. What's wrong with it?"**
```python
@server.tool(name="data", description="Gets data")
async def data(x: str) -> str:
    return yf.Ticker(x).info
```
- Nothing, it works fine
- Missing import statement
- **Vague name, vague description, no error handling, returns dict not string** ← CORRECT
- Wrong decorator syntax

**Why:** The name "data" tells the AI nothing. The description "Gets data" is useless. No try/except means the AI sees "Internal error" on failures. And `.info` returns a dict, but tools must return strings.

### Q6 (2 pts / 1 on retry)
**"Why does our server have a `normalize_ticker` helper?"**
- To make tickers uppercase
- **Because Yahoo Finance silently returns empty data for `BRK.B` — it needs `BRK-B`** ← CORRECT
- To validate that tickers exist
- It's required by the MCP SDK

**Why:** US class-share tickers use dots (BRK.B) but Yahoo Finance uses hyphens (BRK-B). Without normalization, the API returns empty data with NO error — the hardest bug to find.

## STAGE 5 QUIZ — Deploy (2 questions, 4 pts max)

### Q7 (2 pts / 1 on retry)
**"Why did we copy `Containerfile` to `Dockerfile` before building?"**
- Containerfile is deprecated
- **OpenShift binary builds (`oc start-build`) require the file to be named `Dockerfile`** ← CORRECT
- Docker doesn't understand Containerfile
- It's a security requirement

**Why:** OpenShift's binary build strategy specifically looks for `Dockerfile`. Even though Podman uses Containerfile, the `oc start-build --from-dir` command requires Dockerfile.

### Q8 (2 pts / 1 on retry)
**"The `MCP_TRANSPORT` env var is set to `streamable-http` in the Containerfile. Why not `stdio`?"**
- stdio is slower
- **stdio requires the client to spawn the server as a child process — impossible across containers** ← CORRECT
- OpenShift blocks stdio
- HTTP is more secure

**Why:** stdio transport means the client launches the server as a subprocess and communicates via stdin/stdout pipes. When your server runs in a separate pod, the client can't spawn it — so we use HTTP.

## GATE LOGIC

After each quiz:

1. Count correct answers
2. Check against gate threshold:
   - Stage 1: must get 3/4 correct to proceed
   - Stage 3: must get 1/2 correct to proceed
   - Stage 5: must get 1/2 correct to proceed
3. If gate passed: show "✅ Quiz passed!" + score update + proceed
4. If gate failed: re-teach the missed concepts, offer full re-quiz or let them proceed with acknowledgment

**Never fail someone permanently.** The gate is a learning tool, not a barrier.

## SCORE REPORTING

After each quiz, update the scoring system:

```
todowrite([
  { id: "score-mastery", content: "🧠 MCP Mastery: [X]/20 pts (Stage N quiz: Y/Z correct)" }
], merge: true)
```

Then show the milestone scorecard from the workshop-scoring skill.
