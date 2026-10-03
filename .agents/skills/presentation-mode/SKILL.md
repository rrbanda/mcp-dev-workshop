---
name: presentation-mode
description: Formats agent responses as structured workshop slides with visual headers, progress tracking, navigation, and pacing. Use when running the MCP workshop or any interactive tutorial — load this alongside workshop-guide.
---

# Presentation Mode

Transform chat responses into a structured, visually polished workshop experience.
Each agent message becomes a **slide** — focused, visual, bounded, and interactive.

## LOAD THIS SKILL alongside workshop-guide

When the workshop-guide skill is active, ALSO load this skill to control formatting.
This skill defines HOW to present. The workshop-guide defines WHAT to present.

## SLIDE STRUCTURE

Every agent response during the workshop MUST follow this structure:

### 1. Slide Header (always first)

```
╔══════════════════════════════════════════════════════╗
║  📊 Stage 3 · Build Your Server                     ║
║  Tool 2 of 4: get_historical_stock_prices            ║
╚══════════════════════════════════════════════════════╝
```

Format: `Stage N · Title` on line 1, subtitle/context on line 2.
Use emoji prefix to match the stage:
- 👋 Stage 1: Welcome
- 📘 Concepts (teaching)
- 🎨 Stage 2: Design
- 🔨 Stage 3: Build
- 🧪 Stage 4: Test
- 🚀 Stage 5: Deploy
- 🔗 Stage 6: Connect
- ⚡ Stage 7: Use
- 🎓 Wrap-up

### 2. Progress Bar (after header)

Show progress within the current stage:

```
Progress: ████████░░░░░░░░ 2/4 tools built
```

Or for stages:

```
Workshop: ██████░░░░░░░░ Stage 3 of 7
```

Use filled block `█` and empty block `░` (8 filled = 50% of 16 total).
Scale to the actual progress fraction.

### 3. Content Body (one focused topic per slide)

Rules:
- **ONE concept per slide**. Never two.
- **Maximum 20 lines** of content before a break.
- Use visual hierarchy: `###` for sections, `**bold**` for key terms, `>` for callouts.
- Diagrams and tables over paragraphs when possible.
- Code blocks limited to **15 lines max** — show the essential part, not the whole file.

### 4. Visual Elements

Use these consistently:

**Key Concept Box** (for definitions and important ideas):
```
┌─ KEY CONCEPT ──────────────────────────────┐
│                                            │
│  MCP Tools are functions the AI model      │
│  can discover and call. The model reads    │
│  your tool's name and description to       │
│  decide when to use it.                    │
│                                            │
└────────────────────────────────────────────┘
```

**Code Spotlight** (for showing one piece of code with annotation):
```
┌─ CODE ─────────────────────────────────────┐
│ @server.tool(                              │
│     name="get_stock_info",                 │
│     description="Get stock data..."  ◄── AI reads this
│ )                                          │
│ async def get_stock_info(                  │
│     ticker: str  ◄── becomes JSON Schema   │
│ ) -> str:                                  │
└────────────────────────────────────────────┘
```

**Comparison Table** (for before/after, good/bad):
```
┌──────────────────┬──────────────────────┐
│  ❌ Without MCP   │  ✅ With MCP          │
├──────────────────┼──────────────────────┤
│  Custom code per │  One standard        │
│  AI model        │  protocol            │
│  Hard to test    │  Discoverable tools  │
│  Tightly coupled │  Modular servers     │
└──────────────────┴──────────────────────┘
```

**Step Checklist** (for multi-step processes):
```
  ✅ Build container image
  ✅ Push to internal registry
  🔵 Deploy pod + service        ◄ current
  ⬜ Create route
  ⬜ Register in OpenCode
```

**Callout Box** (for tips, warnings, Red Hat resources):
```
  💡 TIP: The AI reads your tool description to decide when to call it.
          Better descriptions = smarter AI behavior.
```

```
  ⚠️  WARNING: Start a NEW session after registering the MCP server.
               Tools only load at session start.
```

```
  📘 RED HAT: Model Context Protocol — The Missing Link in AI Integration
     https://www.redhat.com/en/blog/model-context-protocol-discover-...
```

### 5. Slide Footer — Navigation (always last)

End every slide with a clear **next action**. Use the `question` tool when choices exist.

**When there's a choice:**
Use the question tool with options like:
- "Show me the code"
- "Explain this more"
- "Next slide →"
- "Go back to [topic]"

**When there's no choice (just pacing):**
End with:
```
                                          Next: [what's coming] →
```

The participant types anything to continue (even just "next" or "ok").

---

## PACING RULES

1. **Never show more than ONE concept without pausing.**
   After explaining something, ask before generating code.
   After generating code, ask before explaining the next thing.

2. **Live demos break up the lecture.**
   Every 2-3 concept slides, do a live demo (bash tool).
   "Let me show you this in action..." → run code → show output.

3. **Celebrate milestones.**
   When a tool is built, tested, or deployed, show a success card:
   ```
   ┌─ ✅ MILESTONE ──────────────────────────────┐
   │                                             │
   │  Tool 2 of 4 built: get_stock_info          │
   │  Status: Working — tested with AAPL          │
   │                                             │
   │  Progress: ████████░░░░░░░░ 50%              │
   │                                             │
   └─────────────────────────────────────────────┘
   ```

4. **Transitions between stages.**
   When moving to a new stage, show a full-width stage card:
   ```

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     🚀 STAGE 5: Deploy to OpenShift
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Your server has 4 tools, all tested.
     Now let's package and deploy it.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   ```

---

## COMPLETE SLIDE EXAMPLE

Here is one complete slide showing all elements together:

```
╔══════════════════════════════════════════════════════╗
║  📘 Concepts · What is MCP?                          ║
║  Concept 1 of 7                                      ║
╚══════════════════════════════════════════════════════╝

Workshop: ██░░░░░░░░░░░░░░ Stage 1 of 7


Imagine you're at a restaurant:

┌──────────────┬──────────────────────────────┐
│  Restaurant  │  MCP                         │
├──────────────┼──────────────────────────────┤
│  Menu        │  Tool list (tools/list)       │
│  Waiter      │  AI model + MCP client        │
│  Kitchen     │  Your MCP server              │
│  Order       │  Tool call (tools/call)        │
│  Dish        │  Result (JSON string)          │
└──────────────┴──────────────────────────────┘

┌─ KEY CONCEPT ──────────────────────────────────┐
│                                                │
│  MCP lets you build ONE server and ANY AI      │
│  model that speaks MCP can use it.             │
│  No custom integrations per model.             │
│                                                │
└────────────────────────────────────────────────┘

  📘 RED HAT: "MCP is an AI-native platform primitive"
     redhat.com/blog/model-context-protocol-discover-...

                                    Concept 2: Architecture →
```

---

## ANTI-PATTERNS (never do these)

1. ❌ **Wall of text** — More than 20 lines without a visual break.
2. ❌ **Multiple concepts in one response** — One slide = one idea.
3. ❌ **Code dump** — More than 15 lines of code without explanation.
4. ❌ **Missing progress** — Every slide must show where we are.
5. ❌ **No interaction** — Every slide must end with a question or "next →".
6. ❌ **Skipping celebration** — Always acknowledge completed milestones.
7. ❌ **Inconsistent formatting** — Use the same box styles throughout.
