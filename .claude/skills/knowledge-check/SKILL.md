---
name: knowledge-check
description: Interactive quiz gates between workshop stages. One question at a time using the question tool. Load before each stage transition.
---

# Knowledge Check — Stage-Gated Quizzes

## RULES

1. **One question at a time.** Use the question tool. Wait for answer. Give feedback. Then next question.
2. **Wrong answers are teaching moments.** Re-explain, then offer retry.
3. **Partial credit**: first try = full points, retry = partial points.
4. **Never block permanently**: after 2 wrong attempts, give the answer and move on.
5. **Update scores silently** via todowrite. Show a formatted scorecard after the quiz.
6. **Use markdown formatting only** — no box-drawing characters.

## QUIZ FORMAT

Start with a heading:

### 🧠 Knowledge Check — Stage 1 Complete
**Question 1 of 4**

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

## STAGE 1 QUIZ (4 questions, 12 pts max)

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

**Gate: 3/4 correct to proceed.**

## STAGE 3 QUIZ (2 questions, 4 pts max)

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

**Gate: 1/2 correct to proceed.**

## STAGE 5 QUIZ (2 questions, 4 pts max)

**Q7** (2 pts / 1 retry): "Why copy Containerfile to Dockerfile before building?"
- Containerfile is deprecated
- **OpenShift binary builds require the file named Dockerfile** ← correct
- Docker doesn't understand Containerfile
- Security requirement

**Q8** (2 pts / 1 retry): "Why `streamable-http` not `stdio` in the container?"
- stdio is slower
- **stdio needs child-process spawning — impossible across containers** ← correct
- OpenShift blocks stdio
- HTTP is more secure

**Gate: 1/2 correct to proceed.**

## SCORE UPDATE

After each quiz, update todowrite silently, then show the formatted scorecard from workshop-scoring.
