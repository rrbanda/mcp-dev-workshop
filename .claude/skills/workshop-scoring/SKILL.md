---
name: workshop-scoring
description: Tracks participant progress across 5 dimensions (100 points) using todowrite. Scoring is SILENT — never show raw todowrite content. Only show formatted scorecards at milestones or when asked.
---

# Workshop Scoring System

Track progress across 5 dimensions, 100 points total, using `todowrite`.

## CRITICAL RULE

**Scoring is INVISIBLE to the participant by default.** Never show raw todowrite output, score IDs, or internal tracking in chat. Only show a formatted scorecard:
- At milestones (tool built, stage completed, quiz passed)
- When the participant asks "what's my score?"
- At the final workshop summary

## INITIALIZATION (silent)

At session start, create scoring todos **without mentioning them in chat**:

```
todowrite([
  { id: "score-mastery",     content: "MCP Mastery: 0/20", status: "in_progress" },
  { id: "score-build",       content: "Build: 0/25", status: "pending" },
  { id: "score-quality",     content: "Quality: 0/20", status: "pending" },
  { id: "score-fluency",     content: "Fluency: 0/20", status: "pending" },
  { id: "score-exploration",  content: "Exploration: 0/15", status: "pending" },
  { id: "score-total",       content: "Total: 0/100", status: "in_progress" }
])
```

## SCORING RUBRIC

### 🧠 MCP Mastery (20 pts)

| Quiz | Questions | Points | Max |
|------|-----------|--------|-----|
| Final Quiz (Stage 9) | 8 | 2-3 pts each (retry allowed) | 20 |

### 🔨 Build Completeness (25 pts)

| Milestone | Points |
|-----------|--------|
| Server skeleton | 3 |
| Each tool built (x4) | 2 each |
| Each tool tested (x4) | 1 each |
| Image built | 3 |
| MCPServer CR deployed + Ready | 3 |
| Gateway registered (HTTPRoute + MCPServerRegistration) | 2 |
| E2E verification (tool call from OpenCode) | 2 |

### 🎯 Code Quality (20 pts)

| Criterion | Points |
|-----------|--------|
| All tools have try/except | 5 |
| Specific tool descriptions | 4 |
| Parameter docstrings | 3 |
| normalize_ticker used | 2 |
| Dual transport | 3 |
| UBI base image | 2 |
| No hardcoded creds | 1 |

### 🚀 Agentic Fluency (20 pts)

| Behavior | Points |
|----------|--------|
| Customized tool selection | 4 |
| Asked follow-up questions | 3 |
| Modified generated code | 4 |
| Used AI to debug | 3 |
| Gave specific instructions | 3 |
| Explored beyond path | 3 |

### ⭐ Exploration Bonus (15 pts)

| Achievement | Points |
|-------------|--------|
| Built 5+ tools | 3 |
| Custom tool | 5 |
| Asked about security | 2 |
| Asked about scaling | 2 |
| Used tools in new session | 3 |

## DISPLAYING SCORES (only when appropriate)

### Milestone Scorecard (formatted markdown)

Show this after a scored event — quiz passed, tool built, stage completed:

**📊 Score Update**

| Dimension | Score |
|-----------|-------|
| 🧠 MCP Mastery | 12/20 |
| 🔨 Build | 16/25 |
| 🎯 Code Quality | 0/20 |
| 🚀 Agentic Fluency | 7/20 |
| ⭐ Exploration | 0/15 |
| **Total** | **35/100 — ⭐⭐ MCP Explorer** |

### Score Tiers

| Score | Tier |
|-------|------|
| 90-100 | ⭐⭐⭐⭐⭐ MCP Architect |
| 75-89 | ⭐⭐⭐⭐ MCP Developer |
| 60-74 | ⭐⭐⭐ MCP Builder |
| 40-59 | ⭐⭐ MCP Explorer |
| 0-39 | ⭐ MCP Curious |

## UPDATING (silent)

After each scoring event, update todowrite silently — no chat output about the update:

```
todowrite([
  { id: "score-mastery", content: "MCP Mastery: 9/20" },
  { id: "score-total", content: "Total: 9/100" }
], merge: true)
```

Then show the formatted milestone scorecard in chat (markdown table above).
