# Build and Deploy MCP Servers on Red Hat OpenShift AI

Hands-on workshop: build, test, and deploy MCP servers on OpenShift — with an AI agent or from the command line.

**Workshop guide:** https://rrbanda.github.io/mcp-dev-workshop/

## What participants do

1. Log in to OpenShift, open a DevSpaces workspace (VS Code in the browser)
2. Understand MCP Python SDK v2 patterns from skill files
3. Build a stock market MCP server with 9 tools (using yfinance)
4. Test locally, deploy to OpenShift, call tools over streamable-http

No platform setup. No local tooling. Participants open a browser and start building.

## Two modes

The workshop supports **dual-track** participation — every module page has tabs:

| Mode | How it works |
|------|-------------|
| **Agent mode** | Use the OpenCode AI chat to generate code, load skills, and call tools |
| **Manual mode** | Read reference code, copy scaffold files, call tools with `curl` / JSON-RPC |

Both produce the same outcome. Participants can switch modes at any time.

## Tracks

| Track | Duration | Modules |
|-------|----------|---------|
| Core | ~90 min | Launch → Patterns → Build → Test → Deploy → Use |
| Extended | ~2.5 hr | + Multi-server composition + Enterprise governance |

## Repository structure

```
scaffold/                  # Starter files (requirements.txt, Containerfile, deployment.yaml)
                           # server.py is created by the participant in Module 3
solutions/                 # Per-lab reference solutions (lab-03, lab-05, lab-07)
.opencode/skills/          # Agent Skills (9 total; 3 core for the workshop)
.claude/skills/            # Cross-harness: Claude Code (same files)
.cursor/skills/            # Cross-harness: Cursor (same files)
.agents/skills/            # Cross-harness: generic agents (same files)
content/                   # Antora showroom source (builds to GitHub Pages)
Makefile                   # Workshop commands (validate, build-image, deploy, test-mcp, clean)
ansible/                   # Ansible playbook for N-user deployment
scripts/                   # generate-dw-patch.py, deploy-workshop.sh
config/                    # OpenCode config template, system prompt
```

## For facilitators

See the [Facilitator Guide](https://rrbanda.github.io/mcp-dev-workshop/modules/13-facilitator-guide.html) for cluster setup, DevSpaces configuration, and participant provisioning.

### Deploy N participants with Ansible (recommended)

```bash
export RHOAI_API_KEY="your-api-key"  # never committed to git
cd ansible/
ansible-playbook deploy-workshop.yml --check  # dry run
ansible-playbook deploy-workshop.yml          # real deploy
```

### Or with shell script

```bash
cd scripts/
./deploy-workshop.sh --dry-run   # preview
./deploy-workshop.sh             # deploy
```

Both methods are idempotent — safe to re-run.

## Local development

Build the workshop site locally:

```bash
npm i antora @sntke/antora-mermaid-extension @andrew-jones/antora-tabs-extension
npx antora site.yml
open www/modules/index.html
```

## License

Apache-2.0
