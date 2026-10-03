---
name: workshop-scoring
description: Tracks participant progress across 5 scoring dimensions (100 points total) using todowrite. Load at session start to initialize scoring. Updates scores at milestones, quiz gates, code reviews, and workshop completion.
---

# Workshop Scoring System

Track participant progress across 5 dimensions, 100 points total.
Use the `todowrite` tool to maintain scoring state throughout the session.

## INITIALIZATION

At the start of every workshop session, create a scoring todo list:

```
todowrite([
  { id: "score-mastery",     content: "🧠 MCP Mastery: 0/20 pts", status: "in_progress" },
  { id: "score-build",       content: "🔨 Build Completeness: 0/25 pts", status: "pending" },
  { id: "score-quality",     content: "🎯 Code Quality: 0/20 pts", status: "pending" },
  { id: "score-fluency",     content: "🚀 Agentic Fluency: 0/20 pts", status: "pending" },
  { id: "score-exploration",  content: "⭐ Exploration Bonus: 0/15 pts", status: "pending" },
  { id: "score-total",       content: "TOTAL: 0/100 pts | Tier: ⭐ MCP Curious", status: "in_progress" }
])
```

## SCORING RUBRIC

### 🧠 MCP Mastery (20 pts) — Knowledge checks via question tool

Points come from the knowledge-check skill quiz gates:

| Quiz | Questions | Points per correct | Max |
|------|-----------|-------------------|-----|
| After Stage 1 (Concepts) | 4 questions | 3 pts (2 if retry) | 12 |
| After Stage 3 (Build) | 2 questions | 2 pts (1 if retry) | 4 |
| After Stage 5 (Deploy) | 2 questions | 2 pts (1 if retry) | 4 |
| **Total** | **8 questions** | | **20** |

### 🔨 Build Completeness (25 pts) — Verified with bash tool

| Milestone | Points | How to verify |
|-----------|--------|--------------|
| Server skeleton created | 3 | `test -f /projects/mcp-dev-workshop/scaffold/server.py` |
| Each tool built (up to 4) | 2 each | grep for `@server.tool` count in server.py |
| Each tool tested with real data | 1 each | curl/python test returns valid JSON |
| Container image built | 3 | `oc get is stock-market-mcp` succeeds |
| Pod deployed + running | 3 | `oc get pods -l app=stock-market-mcp` shows Running |
| Route created + MCP registered | 2 | `oc get route stock-market-mcp` + `opencode mcp list` |
| End-to-end verification | 2 | curl to /mcp returns initialize response |
| **Total** | | **25** |

### 🎯 Code Quality (20 pts) — Agent reads server.py and scores

| Criterion | Points | What to check |
|-----------|--------|--------------|
| All tools have try/except | 5 | Every tool function has error handling |
| Tool descriptions are specific | 4 | Descriptions mention what the tool does, not just "gets data" |
| Parameter docstrings present | 3 | Args section in docstrings |
| normalize_ticker helper used | 2 | `normalize_ticker` called in tool functions |
| Dual transport (stdio + HTTP) | 3 | Entry point checks MCP_TRANSPORT env var |
| UBI base image in Containerfile | 2 | `registry.access.redhat.com/ubi9` in Containerfile |
| No hardcoded credentials | 1 | No API keys or passwords in source |
| **Total** | | **20** |

### 🚀 Agentic Fluency (20 pts) — How they work WITH the AI

| Behavior | Points | How to detect |
|----------|--------|--------------|
| Customized tool selection | 4 | Didn't just accept the default 2 tools |
| Asked follow-up questions | 3 | Participant asked "why" or "how" at least twice |
| Modified generated code | 4 | Participant requested changes to AI-generated code |
| Used AI to debug failures | 3 | Participant asked for help when something broke |
| Gave specific instructions | 3 | Participant gave detailed prompts, not just "next" |
| Explored beyond guided path | 3 | Participant asked about topics not in the current stage |
| **Total** | | **20** |

### ⭐ Exploration Bonus (15 pts) — Going beyond the script

| Achievement | Points |
|-------------|--------|
| Built more than 4 tools | 3 |
| Added a custom tool not in the spec | 5 |
| Asked about security/authentication | 2 |
| Asked about scaling/production patterns | 2 |
| Used MCP tools from a new session | 3 |
| **Total** | **15** |

## UPDATING SCORES

After each scoring event, update the todowrite:

1. Calculate the new point value for the dimension
2. Update the relevant `score-*` todo item content with new points
3. Recalculate the total and tier
4. Update `score-total` with the new total and tier

Example after a quiz:
```
todowrite([
  { id: "score-mastery", content: "🧠 MCP Mastery: 9/20 pts (Stage 1 quiz: 3/4 correct)", status: "in_progress" },
  { id: "score-total", content: "TOTAL: 9/100 pts | Tier: ⭐ MCP Curious", status: "in_progress" }
], merge: true)
```

## SCORE TIERS

| Score | Tier | Description |
|-------|------|-------------|
| 90-100 | ⭐⭐⭐⭐⭐ MCP Architect | Production-grade build, deep exploration |
| 75-89 | ⭐⭐⭐⭐ MCP Developer | Solid build, good AI interaction |
| 60-74 | ⭐⭐⭐ MCP Builder | Completed the core workshop |
| 40-59 | ⭐⭐ MCP Explorer | Good start, learning the basics |
| 0-39 | ⭐ MCP Curious | Just getting started |

## DISPLAYING SCORES

### Milestone Scorecard (show after each scored event)

```
  ┌─ SCORE UPDATE ──────────────────────────────┐
  │  🧠 MCP Mastery     ██████░░░░  12/20       │
  │  🔨 Build           ████████░░  16/25       │
  │  🎯 Code Quality    ░░░░░░░░░░   0/20       │
  │  🚀 Agentic Fluency ████░░░░░░   7/20       │
  │  ⭐ Exploration      ░░░░░░░░░░   0/15       │
  │                                             │
  │  TOTAL: 35/100  ⭐⭐ MCP Explorer            │
  └─────────────────────────────────────────────┘
```

### Final Scorecard (show at workshop end)

Show the full scorecard with all dimension breakdowns, then hand off
to the workshop-certificate skill for certificate generation.

## CODE QUALITY REVIEW

At the end of Stage 3 (Build) or before generating the certificate,
read the participant's server.py and score each quality criterion:

```bash
# Check tool count
grep -c '@server.tool' /projects/mcp-dev-workshop/scaffold/server.py

# Check error handling
grep -c 'except Exception' /projects/mcp-dev-workshop/scaffold/server.py

# Check normalize_ticker usage
grep -c 'normalize_ticker' /projects/mcp-dev-workshop/scaffold/server.py

# Check dual transport
grep -c 'MCP_TRANSPORT' /projects/mcp-dev-workshop/scaffold/server.py
```

Score each criterion honestly. Do not inflate scores. The participant
should feel the score reflects their actual work.
