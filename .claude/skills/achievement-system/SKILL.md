---
name: achievement-system
description: Visual achievement badges and milestone celebrations for the MCP workshop. Awards badges at key moments, displays celebration cards, and feeds into the scoring system. Load at milestones during the workshop.
---

# Achievement System

Award visual badges at key workshop milestones. Each achievement triggers a celebration
card and may contribute to the Exploration Bonus in the scoring system.

## ACHIEVEMENT CATALOG

| Badge | Name | Trigger | Bonus pts |
|-------|------|---------|-----------|
| 🔧 | First Tool | First `@server.tool` added to server.py | 0 (part of Build score) |
| 🧪 | Data Scientist | First tool tested with real stock data | 0 |
| 🏆 | Full Suite | 4+ tools built and working | 0 |
| 🚀 | Deployed! | Pod running on OpenShift AI | 0 |
| 🔗 | Connected | MCP server registered in OpenCode | 0 |
| ⚡ | AI-Powered | Successfully used MCP tools from AI chat | 0 |
| 🧠 | Quiz Master | All quiz questions correct on first try | +2 Exploration |
| 🎨 | Customizer | Modified AI-generated code or added custom tool | +3 Exploration |
| 💡 | Curious Mind | Asked 3+ follow-up questions about concepts | +2 Exploration |
| 🛡️ | Security Aware | Asked about authentication or security | +2 Exploration |
| 🏗️ | Architect | Asked about scaling or production patterns | +2 Exploration |
| 🌟 | Innovator | Built a tool NOT in the standard spec | +5 Exploration |
| 🎓 | Graduate | Completed the full workshop | 0 (triggers certificate) |

## CELEBRATION CARD FORMAT

When an achievement is unlocked, display:

```
┌─ 🏆 ACHIEVEMENT UNLOCKED ─────────────────────┐
│                                                │
│  🚀 Deployed!                                  │
│                                                │
│  Your MCP server is running on OpenShift.      │
│  That's a real production service!             │
│                                                │
│  Achievements: 🔧 🧪 🏆 🚀                   │
│  Score: +3 pts (Build Completeness)            │
│                                                │
└────────────────────────────────────────────────┘
```

## DETECTION RULES

The agent should detect achievements automatically:

### Build milestones (detected via bash tool)
- **First Tool**: after writing `@server.tool` to server.py for the first time
- **Full Suite**: after grep shows 4+ `@server.tool` decorators
- **Deployed!**: after `oc get pods -l app=stock-market-mcp` shows Running
- **Connected**: after `opencode mcp list` shows connected status
- **AI-Powered**: after successfully using an MCP tool from chat

### Behavior milestones (detected via agent observation)
- **Quiz Master**: all knowledge-check questions answered correctly on first attempt
- **Customizer**: participant asked to modify generated code or add a non-standard tool
- **Curious Mind**: participant asked 3+ "why" or "how does" follow-up questions
- **Security Aware**: participant asked about auth, RBAC, or security
- **Architect**: participant asked about scaling, HA, or production patterns
- **Innovator**: participant built a tool not in stock-market-mcp-spec

### Workshop milestones
- **Data Scientist**: first tool test returns valid data
- **Graduate**: all stages completed and certificate generated

## ACHIEVEMENT TRACKING

Maintain achievement state in todowrite:

```
todowrite([
  { id: "achievements", content: "🏅 Achievements: 🔧 🧪 🏆 (3 unlocked)", status: "in_progress" }
], merge: true)
```

Update after each new achievement is unlocked.

## FINAL ACHIEVEMENT DISPLAY

At workshop completion, show all achievements in a summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🏅 Your Achievements
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  🔧 First Tool        — Built your first MCP tool
  🧪 Data Scientist    — Tested with real market data
  🏆 Full Suite        — 4+ tools in your server
  🚀 Deployed!         — Running on OpenShift AI
  🔗 Connected         — Registered in OpenCode
  ⚡ AI-Powered        — Used tools from AI chat
  🎨 Customizer        — Made it your own
  🎓 Graduate          — Completed the workshop!

  8 of 13 achievements unlocked

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

This feeds into the workshop-certificate skill for the certificate.
