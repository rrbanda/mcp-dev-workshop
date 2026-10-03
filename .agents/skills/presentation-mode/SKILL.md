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

Use a markdown heading with emoji + stage context:

```
## 🔨 Stage 3 · Build Your Server
### Tool 2 of 4: get_historical_stock_prices
```

Emoji prefixes by stage:
- 👋 Stage 1: Welcome
- 📘 Concepts
- 🎨 Stage 2: Design
- 🔨 Stage 3: Build
- 🧪 Stage 4: Test
- 🚀 Stage 5: Deploy
- 🔗 Stage 6: Connect
- ⚡ Stage 7: Use
- 🎓 Wrap-up

### 2. Progress Bar (after header)

Use filled/empty blocks on one line:

```
**Progress:** ████████░░░░░░░░ 2/4 tools built
```

Or for stages:
```
**Workshop:** ██████░░░░░░░░ Stage 3 of 7
```

### 3. Content Body (ONE topic per slide)

Rules:
- **ONE concept per slide.** Never two.
- **Maximum 20 lines** before a break.
- Use `##` / `###` for sections, `**bold**` for key terms, `>` for callouts.
- Diagrams → use code fences (monospace renders correctly inside fences).
- Code blocks limited to **15 lines max**.

### 4. Visual Elements

**Key Concept** — use a blockquote with bold label:

> **💡 KEY CONCEPT**
>
> MCP Tools are functions the AI model can discover and call.
> The model reads your tool's name and description to decide when to use it.

**Code Spotlight** — use a code fence with comments for annotations:

```python
@server.tool(
    name="get_stock_info",
    description="Get stock data..."  # ← AI reads this
)
async def get_stock_info(
    ticker: str  # ← becomes JSON Schema
) -> str:
```

**Comparison** — use a markdown table:

| ❌ Without MCP | ✅ With MCP |
|---|---|
| Custom code per AI model | One standard protocol |
| Hard to test | Discoverable tools |
| Tightly coupled | Modular servers |

**Step Checklist** — use emoji list:

- ✅ Build container image
- ✅ Push to internal registry
- 🔵 Deploy pod + service ← *current*
- ⬜ Create route
- ⬜ Register in OpenCode

**Callout** — use blockquote with emoji prefix:

> 💡 **TIP:** The AI reads your tool description to decide when to call it. Better descriptions = smarter AI behavior.

> ⚠️ **WARNING:** Start a NEW session after registering the MCP server. Tools only load at session start.

> 📘 **RED HAT:** [Model Context Protocol — The Missing Link](https://www.redhat.com/en/blog/model-context-protocol-discover-missing-link-ai-integration)

### 5. Slide Footer — Navigation (always last)

Every response MUST end with a clear next action.

**When there's a choice:** Use the `question` tool.

**When there's no choice:** End with a single line:

> *Next: [what's coming] →*

The participant types anything to continue.

---

## PACING RULES

1. **ONE concept per response, then STOP.** Wait for participant input.
2. **Live demos every 2-3 slides.** "Let me show you this..." → run code → show output.
3. **Celebrate milestones** with a scorecard:

### ✅ Milestone: Tool 2 of 4 built

**`get_stock_info`** — tested with AAPL ✅

**Progress:** ████████░░░░░░░░ 50%

4. **Stage transitions** — use horizontal rules + heading:

---

## 🚀 Stage 5: Deploy to OpenShift

Your server has 4 tools, all tested. Now let's package and deploy it.

---

## ANTI-PATTERNS (never do these)

1. ❌ Wall of text — more than 20 lines without a visual break
2. ❌ Multiple concepts in one response
3. ❌ Code dump — more than 15 lines without explanation
4. ❌ Missing progress indicator
5. ❌ No interaction — every slide must end with a question or "next →"
6. ❌ Box-drawing characters (╔═╗║╚┌─┐│└) — use markdown instead
7. ❌ Showing internal state, planning, or skill-loading status
