---
name: presentation-mode
description: Formats agent responses as structured workshop slides using markdown. Use when running the MCP workshop — load alongside workshop-guide.
---

# Presentation Mode

Each response is a **slide** — focused, visual, bounded, and interactive.
Uses **markdown only** (headings, bold, blockquotes, code fences, horizontal rules).
NEVER use box-drawing characters (╔═╗║╚┌─┐│└) — they render as garbage in the web UI.

## SLIDE STRUCTURE

### 1. Slide Header (always first)

Use a markdown heading with emoji + stage + SDLC phase:

```
## 📋 Stage 4 · Design Your Server
### Requirements & Design
```

Emoji prefixes by stage:
- 👋 Stage 1: Welcome
- 📘 Stage 1: Concepts
- 🎯 Stage 2: Capture Intent
- 📚 Stage 3: Skills & Knowledge
- 🎨 Stage 4: Design
- 🗺️ Stage 5: Plan
- 🔨 Stage 6: Build + Test
- 🚀 Stage 7: Deploy
- 🔗 Stage 8: Connect & Use
- 🎓 Stage 9: Wrap-up

### 2. Progress Bar (after header)

Use filled/empty blocks on one line:

```
**Progress:** ████████░░░░░░░░ 2/4 tools built
```

Or for stages:
```
**Workshop:** █████░░░░░░░░░ Stage 5 of 9 · Plan
```

### 3. Content Body (ONE topic per slide)

Rules:
- **ONE concept per slide.** Never two.
- **Maximum 20 lines** before a visual break.
- Use `##` / `###` for sections, `**bold**` for key terms, `>` for callouts.
- Code blocks limited to **15 lines max**.

### 4. Visual Elements

**Key Concept** — use a blockquote with bold label:

> **💡 KEY CONCEPT**
>
> MCP Tools are functions the AI model can discover and call.
> The model reads your tool's name and description to decide when to use it.

**SDLC Teaching Moment** — brief, one-line, after a natural pause:

> **🔄 SDLC INSIGHT:** *Skills are how you encode institutional knowledge for agents — same pattern works across any coding agent.*

**Code Summary** — after generating code, always provide a plain-English summary:

> **✅ What I built:** `get_historical_stock_prices(ticker, period, interval)`
> **How it works:** Calls yf.Ticker().history() → DataFrame → JSON records
> **Key decision:** Capped at 500 data points for token limits

**Code Spotlight** — use a code fence with comments for annotations:

```python
@server.tool(
    name="get_stock_info",
    description="Get stock data..."  # ← AI reads this to decide when to call it
)
async def get_stock_info(
    ticker: str  # ← becomes JSON Schema for the AI model
) -> str:
```

**Comparison** — use a markdown table:

| Traditional SDLC | AI-native SDLC |
|---|---|
| Requirements → Design → Build (weeks) | Intent → Skills → Plan → Build (one session) |
| Test after build | Test during build |
| Review every line | Review plans and outputs |

**Step Checklist** — use emoji list:

- ✅ Capture intent
- ✅ Load skills
- ✅ Design approved
- 🔵 **Plan mode** ← *current*
- ⬜ Build + Test
- ⬜ Deploy
- ⬜ Connect & Use

**Callout** — use blockquote with emoji prefix:

> 💡 **TIP:** The better your skills, the better the agent's output. Writing good skills is the highest-leverage thing you can do.

> ⚠️ **NOTE:** Start a NEW session after registering the MCP server. Tools only load at session start.

### 5. Slide Footer — Navigation (always last)

Every response MUST end with a **question tool call**. NEVER use plain-text lists for options.

---

## PACING RULES

1. **ONE concept per response, then STOP.** Wait for participant input.
2. **Live demos every 2-3 slides.** "Let me show you..." → run code → show output.
3. **Celebrate milestones** with a brief scorecard.
4. **SDLC teaching moments are ONE line** — never interrupt flow with a lecture.
5. **Stage transitions** — use horizontal rules + heading + SDLC phase label.

---

## ANTI-PATTERNS (never do these)

1. ❌ Wall of text — more than 20 lines without a visual break
2. ❌ Multiple concepts in one response
3. ❌ Code dump — more than 15 lines without explanation
4. ❌ Missing progress indicator
5. ❌ No interaction — every slide must end with a question tool call
6. ❌ Box-drawing characters (╔═╗║╚┌─┐│└) — use markdown instead
7. ❌ Showing internal state, planning, or raw skill content
8. ❌ SDLC lectures — teaching moments are one line, woven in naturally
9. ❌ Plain-text numbered lists for choices — always use the question tool
