# MCP Developer Workshop

Hands-on workshop: build, test, and deploy an MCP server on OpenShift — guided by an AI agent (AgentSherpa) inside a DevSpaces workspace.

Participants open a browser, land in OpenCode, and work through 9 stages that mirror the **AI-native software development lifecycle**:

> Intent → Skills → Design → Plan → Build+Test → Deploy → Connect & Use → Wrap-up

## What participants experience

1. Log in to OpenShift DevSpaces, open the OpenCode Web IDE
2. AgentSherpa guides them through building a stock market MCP server (yfinance, 9 tools)
3. Deploy using the full MCP Lifecycle: **MCPServer CR → AI Hub Catalog → MCP Gateway**
4. Use the deployed tools from the AI chat to query real stock data

No local tooling. No platform setup. Participants open a browser and start building.

## 9-stage workshop flow

| Stage | SDLC Phase | What happens |
|-------|-----------|-------------|
| 1 | Welcome | Role, experience, MCP concepts |
| 2 | Capture Intent | Describe the server, confirm scope |
| 3 | Skills & Knowledge | Load domain skills visibly |
| 4 | Design | Pick tools, confirm design |
| 5 | Plan | Review build plan before coding |
| 6 | Build + Test | Generate code, test each tool with real data |
| 7 | Deploy | Build image → MCPServer CR → AI Hub → MCP Gateway |
| 8 | Connect & Use | Wire to IDE, use tools, feedback loop |
| 9 | Wrap-up | SDLC recap → score → certificate → quiz → cleanup |

## MCP server lifecycle (Stage 7)

The deploy stage uses three layers:

- **Layer 1 — Deploy:** MCPServer CR → MCP Lifecycle Operator → Deployment + Service + NetworkPolicy + MCP handshake
- **Layer 2 — Discover:** AI Hub MCP Catalog → browse and manage servers from the dashboard
- **Layer 3 — Route & Govern:** MCP Gateway (RHCL) → HTTPRoute + MCPServerRegistration → federated tool discovery with `prefix`

## Repository structure

```
chart/                     # Helm chart (DevWorkspace, RBAC, system prompt, git-clone init)
  templates/
    _helpers.tpl           # System prompt (AgentSherpa), OpenCode config, skills copy
    rbac.yaml              # edit role + explicit MCP CRD rules
    devworkspace.yaml      # DevWorkspace CR with postStart hooks
.opencode/skills/          # 17 Agent Skills (source of truth)
.agents/skills/            # Mirror for generic agents
.claude/skills/            # Mirror for Claude Code
.cursor/skills/            # Mirror for Cursor
scaffold/                  # Starter files (requirements.txt, Containerfile)
solutions/                 # Per-lab reference solutions (lab-03, lab-05, lab-07)
```

## Key skills

| Skill | Purpose |
|-------|---------|
| `workshop-guide` | 9-stage flow with interaction rules |
| `build-deploy-openshift` | Full MCP lifecycle: build → MCPServer CR → Gateway |
| `build-mcp-server` | MCP Python SDK v2 patterns |
| `stock-market-mcp-spec` | Tool specifications (9 tools, enums, helpers) |
| `presentation-mode` | Slide formatting, visual elements |
| `voice-and-pacing` | Tone, pacing, "explain before execute" |
| `troubleshooting-coach` | MCPServer CR debugging |
| `workshop-scoring` | 100-point scoring across 5 dimensions |

## Deploy for N participants

Uses the Helm chart in `chart/`. Each participant gets their own namespace (`userN-devspaces`).

```bash
# Deploy for user1
helm upgrade user1-devspaces-workshop chart/ \
  -n user1-devspaces --create-namespace \
  --set user.name=user1 \
  --set llm.baseUrl=<MAAS_GATEWAY_URL> \
  --set llm.modelId=<MODEL_ID> \
  --set llm.apiKey=<API_KEY> \
  --set workshop.repoUrl=https://github.com/rrbanda/mcp-dev-workshop.git

# Start the workspace
oc patch dw code-workspace-1 -n user1-devspaces --type=merge -p '{"spec":{"started":true}}'
```

### Platform admin prerequisites

Before the workshop, a cluster admin must:
1. Enable MCP Lifecycle Operator (`mcplifecycleoperator: Managed` in DSC)
2. Enable MCP Catalog (`mcpCatalog: true` in OdhDashboardConfig)
3. Install MCP Gateway Operator in `mcp-system`
4. Create Gateway + MCPGatewayExtension

See the **Platform Admin Setup** section in `.opencode/skills/build-deploy-openshift/SKILL.md`.

## Security

- No secrets or credentials in code — API keys via Kubernetes Secrets
- No customer names, tokens, or credentials committed to git
- MCPServer CR enforces non-root, drop ALL caps, read-only FS, seccomp

## License

Apache-2.0
