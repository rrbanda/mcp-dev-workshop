---
name: interactive-challenge
description: Mini-challenges between workshop stages that reinforce learning and earn Exploration Bonus points. Each challenge is optional, timed, and adapted to the participant's persona. Load between stages for bonus engagement.
---

# Interactive Challenges

Optional mini-challenges between stages that reinforce learning. Each challenge
earns Exploration Bonus points and deepens understanding through hands-on practice.

## RULES

1. **Always optional.** Present as "Want a bonus challenge?" — never force.
2. **Timed guidance, not pressure.** "This usually takes 2-3 minutes" — not a countdown.
3. **Adapted to persona.** Beginners get simpler challenges. Developers get harder ones.
4. **Celebrate attempts.** Even partial completion gets points.
5. **Show solution.** Always offer to show the answer if they're stuck.

## CHALLENGE FORMAT

```
╔══════════════════════════════════════════════════════╗
║  ⭐ Bonus Challenge — Before Stage [N+1]             ║
╚══════════════════════════════════════════════════════╝

  [Challenge description]

  ⏱️ Usually takes 2-3 minutes
  🏅 Worth: +[N] Exploration Bonus points
```

Use the question tool:
- "I'll try it!" → present the challenge
- "Skip for now" → proceed to next stage, no penalty
- "Show me the solution" → show solution, +1 point for engagement

## CHALLENGE CATALOG

### After Stage 1 (Concepts) → Before Stage 2

**Challenge: Name That Primitive**

"For each scenario, tell me if it's a Tool, Resource, or Prompt:"

Use the question tool for each:

1. "A function that fetches the current weather for a city"
   → **Tool** (model-controlled, performs an action)

2. "A read-only endpoint that returns the server's configuration"
   → **Resource** (application-controlled, read-only data)

3. "A template message that says 'Analyze this stock ticker for investment potential'"
   → **Prompt** (user-controlled, template message)

**Points:** 1 pt per correct answer, max 3 pts Exploration Bonus

---

### After Stage 3 (Build) → Before Stage 4

**Challenge: Improve a Tool Description**

"Here's a tool with a mediocre description. Rewrite it to be better:"

```python
@server.tool(name="get_news", description="Gets news")
async def get_news(ticker: str) -> str:
```

Ask the participant to type a better description. Score:
- Mentions what kind of news (financial/stock): +1 pt
- Mentions the parameter purpose: +1 pt
- Mentions return format or content: +1 pt

**Points:** max 3 pts Exploration Bonus

---

### After Stage 4 (Test) → Before Stage 5

**Challenge: Debug This Tool**

"This tool has 3 bugs. Can you spot them?"

```python
@server.tool(name="stock_price", description="Get stock price")
async def stock_price(ticker):
    company = yf.Ticker(ticker)
    return company.info["currentPrice"]
```

Bugs:
1. No type hint on `ticker` parameter → AI can't see the JSON Schema
2. No error handling → exception on invalid ticker
3. Returns a float, not a string → MCP tools must return strings

Use the question tool for each bug found. Accept any phrasing that identifies the issue.

**Points:** 1 pt per bug found, max 3 pts Exploration Bonus

---

### After Stage 5 (Deploy) → Before Stage 6

**Challenge: Predict the Architecture**

"Your server is deployed. Draw me the network path (in words) from when a user
asks 'What's AAPL's price?' to when they see the answer."

Accept any answer that includes these hops:
1. User → OpenCode AI
2. AI → MCP Client
3. MCP Client → HTTP POST to server pod
4. Server → yfinance API
5. Response flows back the same path

**Points:** 2 pts if they get the full chain, 1 pt for partial

---

### After Stage 6 (Connect) → Before Stage 7

**Challenge: Add a Custom Tool**

"Can you add a tool that's NOT in the standard spec? Any financial data tool you
think would be useful. I'll help you implement it."

This is the highest-value challenge — earning the 🌟 Innovator achievement.

Examples they might suggest:
- `compare_stocks` — compare two tickers side by side
- `get_market_summary` — overall market indices
- `calculate_returns` — return on investment calculator
- `get_sector_performance` — sector comparison

**Points:** 5 pts Exploration Bonus + 🌟 Innovator achievement

## SCORING INTEGRATION

After each challenge, update the scoring system:

```
todowrite([
  { id: "score-exploration", content: "⭐ Exploration Bonus: [X]/15 pts (challenges: Y pts)" }
], merge: true)
```

Also check if any achievements were unlocked (e.g., 🌟 Innovator for custom tool).
