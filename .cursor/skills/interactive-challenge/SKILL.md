---
name: interactive-challenge
description: Optional bonus challenges between stages. Earn Exploration points. Always optional, always use the question tool.
---

# Interactive Challenges

Optional mini-challenges between stages. Always present as a choice — never force.

## RULES

1. **Always optional.** Ask "Want a bonus challenge?" using the question tool.
2. **One challenge per pause.** Don't stack multiple.
3. **Adapted to persona.** Beginners get simpler ones.
4. **Celebrate attempts.** Partial completion gets points.
5. **Show solution on request.**
6. **Use markdown only** — no box-drawing characters.

## FORMAT

### ⭐ Bonus Challenge

*[Description]*

⏱️ Usually takes 2-3 minutes | 🏅 Worth +3 Exploration points

Use question tool:
- I'll try it!
- Skip for now
- Show me the solution

## CHALLENGES

### After Stage 1 (Concepts)

**Name That Primitive** — for each scenario, is it a Tool, Resource, or Prompt?

Use question tool for each:
1. "A function that fetches current weather" → **Tool**
2. "A read-only endpoint returning server config" → **Resource**
3. "A template message: 'Analyze this stock'" → **Prompt**

Points: 1 per correct, max 3

### After Stage 3 (Build)

**Improve a Tool Description** — rewrite this vague description:

```python
@server.tool(name="get_news", description="Gets news")
```

Score: mentions financial/stock news (+1), parameter purpose (+1), return content (+1). Max 3.

### After Stage 4 (Test)

**Debug This Tool** — spot 3 bugs:

```python
@server.tool(name="stock_price", description="Get stock price")
async def stock_price(ticker):
    company = yf.Ticker(ticker)
    return company.info["currentPrice"]
```

Bugs: no type hint, no error handling, returns float not string. Max 3 pts.

### After Stage 5 (Deploy)

**Predict the Architecture** — describe the network path from user question to answer.

Expected: User → OpenCode AI → MCP Client → HTTP to server pod → yfinance → response back.

Points: 2 for full chain, 1 for partial.

### After Stage 6 (Connect)

**Add a Custom Tool** — build a tool NOT in the standard spec.

Examples: compare_stocks, market_summary, calculate_returns.

Points: 5 + 🌟 Innovator achievement.

## SCORING

After each challenge, update todowrite silently:

```
todowrite([
  { id: "score-exploration", content: "Exploration: X/15" }
], merge: true)
```

Then show the formatted scorecard.
