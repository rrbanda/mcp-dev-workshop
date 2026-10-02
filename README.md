# Build MCP Servers on Red Hat OpenShift AI

Hands-on workshop: use an AI agent to build, test, and deploy MCP servers on OpenShift.

**Workshop guide:** https://rrbanda.github.io/mcp-dev-workshop/

## What participants do

1. Launch a pre-configured DevSpaces workspace with OpenCode
2. Use an Agent Skill to teach the AI agent MCP SDK patterns
3. Tell the agent to build an MCP server — it generates the code
4. Test locally, deploy to OpenShift with `oc apply`, wire the agent to its own server

No platform setup. No infrastructure work. Participants open a browser and start building.

## Tracks

| Track | Duration | Modules |
|-------|----------|---------|
| Core | ~90 min | Launch → Skills → Build → Test → Deploy → Use |
| Extended | ~2.5 hr | + Multi-server composition + Enterprise governance |

## Repository structure

```
.opencode/skills/          # Agent Skills (auto-discovered by OpenCode)
.claude/skills/            # Cross-harness: Claude Code
.cursor/skills/            # Cross-harness: Cursor
scaffold/                  # Reference MCP server + deployment artifacts
solutions/                 # Per-lab checkpoint solutions
scripts/                   # Validation and facilitator setup
content/                   # Antora showroom source (builds to GH Pages)
Makefile                   # Workshop commands
```

## For facilitators

See the [Facilitator Guide](https://rrbanda.github.io/mcp-dev-workshop/modules/13-facilitator-guide.html) for cluster setup, DevSpaces configuration, and participant provisioning.

Quick setup:
```bash
./scripts/setup-workshop.sh --participants 10 --namespace-prefix dev-user
```

## Local development

Build the workshop site locally:
```bash
npm i antora @sntke/antora-mermaid-extension @andrew-jones/antora-tabs-extension
npx antora site.yml
# Open www/modules/index.html
```

## License

Apache-2.0
