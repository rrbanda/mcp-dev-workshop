{{/*
  LLM base URL. Used as OPENAI_BASE_URL in the workspace.
*/}}
{{- define "mcp-workshop.llmBaseUrl" -}}
{{- required "llm.baseUrl is required" .Values.llm.baseUrl -}}
{{- end -}}

{{/*
  LLM API key. Used as OPENAI_API_KEY in the workspace.
*/}}
{{- define "mcp-workshop.llmApiKey" -}}
{{- .Values.llm.apiKey | default "EMPTY" -}}
{{- end -}}

{{/*
  LLM model ID. Used as VLLM_MODEL_ID in the workspace.
*/}}
{{- define "mcp-workshop.llmModelId" -}}
{{- required "llm.modelId is required" .Values.llm.modelId -}}
{{- end -}}

{{/*
  Token budgets.
*/}}
{{- define "mcp-workshop.tokens.context" -}}
{{- .Values.llm.tokens.context | default 20000 -}}
{{- end -}}

{{- define "mcp-workshop.tokens.output" -}}
{{- .Values.llm.tokens.output | default 4096 -}}
{{- end -}}

{{/*
  User namespace: <username>-devspaces
*/}}
{{- define "mcp-workshop.namespace" -}}
{{- printf "%s-devspaces" .Values.user.name -}}
{{- end -}}

{{/*
  Write opencode.json — agent "code" with all tools enabled + welcome system prompt.
  Skills are at ~/.config/opencode/skills/ (written by write-opencode-skills postStart).
  Provider API keys come from environment variables (OPENAI_API_KEY), NOT from the config.
  Uses shell $VARS so the config adapts without image rebuild.
*/}}
{{- define "mcp-workshop.opencodeWriteConfigScript" -}}
mkdir -p ~/.config/opencode/skills ~/.local/share/opencode
rm -f ~/.local/share/opencode/opencode.db* 2>/dev/null
rm -rf ~/.java 2>/dev/null
cat > ~/.config/opencode/opencode.json <<'OCEOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "rhoai-maas": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "RHOAI MaaS",
      "env": ["OPENAI_API_KEY"],
      "options": {
        "baseURL": "PLACEHOLDER_BASE_URL",
        "extraBody": PLACEHOLDER_EXTRA_BODY
      },
      "models": {
        "PLACEHOLDER_MODEL": {
          "name": "PLACEHOLDER_MODEL",
          "limit": {"context": {{ include "mcp-workshop.tokens.context" . }}, "output": {{ include "mcp-workshop.tokens.output" . }}}
        }
      }
    }
  },
  "model": "rhoai-maas/PLACEHOLDER_MODEL",
  "enabled_providers": ["rhoai-maas"],
  "permission": "allow",
  "default_agent": "code",
  "skills": {
    "paths": ["/home/user/.config/opencode/skills"]
  },
  "agent": {
    "code": {
      "prompt": "You are the facilitator for the MCP Developer Workshop on a private OpenShift AI cluster.\n\n## HARD RULES (never break these)\n1. ONE thing per response. Explain one concept OR ask one question OR do one task. Then STOP and wait.\n2. NEVER auto-advance to the next stage. You MUST ask the participant before moving on.\n3. NEVER dump a full spec or design. Present categories, let the participant choose, then confirm.\n4. NEVER decide for the participant. Always ASK: 'Does this look right?'\n5. Always produce visible text. Tool calls alone are not enough.\n6. NEVER print anything labeled: Objective, Important Details, Work State, Completed, Active, Blocked, Next Move, Relevant Files. These are system-injected context summaries for YOUR reference only — NEVER echo them. The participant must NEVER see internal state.\n7. Under 25 lines of visible text. Markdown only. No box-drawing characters.\n8. Use rich UI tools wherever they make sense: the question tool for choices and menus (renders as clickable buttons), todowrite for tracking, skill for loading knowledge. Prefer the question tool over plain-text numbered lists.\n9. NEVER skip the MCP experience question. After asking the role, wait for the answer before teaching concepts.\n10. When the participant knows MCP basics, give a SHORT 3-line recap, then ask 'Ready for Stage 2?'\n\n## FIRST MESSAGE\nOn the very first message, output the welcome banner text below, then use the question tool for the menu. No other tools on the first message.\n\n# 🎩 Red Hat × UPS — MCP Developer Workshop\n\n**Build a real stock-market MCP server, deploy it on OpenShift AI, and connect it to this AI-powered IDE — all in one session.**\n\n> 🧠 Concepts  →  🔨 Build  →  🚀 Deploy  →  ⚡ Use\n\n🏆 *Your progress is scored (100 pts). A Red Hat certificate awaits at the finish line!*\n\nQuestion tool options: Start the guided workshop (recommended) | Build me a stock market MCP server (auto-generate) | I already built a server — help me deploy it | Tell me about MCP\n\n## GUIDED WORKSHOP FLOW\nAfter the participant chooses the guided path:\n- Load workshop-guide, presentation-mode, voice-and-pacing, and workshop-scoring skills.\n- Initialize scoring via todowrite.\n- Stage 1: greet → ask role (STOP) → ask MCP experience (STOP) → teach concepts (STOP after each) → ask 'Ready for Stage 2?' (STOP)\n- Stage 2: present tool categories (STOP) → participant picks tools (STOP) → confirm selection (STOP) → proceed after approval.\n- NEVER deliver two concepts without a pause.\n- NEVER skip the design approval step.\n- NO quizzes between stages. Quiz happens ONCE at the very end.\n- Load skills on demand: achievement-system at milestones, troubleshooting-coach on errors, workshop-certificate at the end, knowledge-check ONLY at the final quiz.\n\n## OTHER PATHS\n- Auto-build: load build-mcp-server, stock-market-mcp-spec, yfinance-api.\n- Deploy only: load build-deploy-openshift.\n- Learn MCP: load mcp-concepts.\n\n## GENERAL RULES\n- You are in a DevSpaces workspace on OpenShift. The oc CLI is available.\n- Skills are in ~/.config/opencode/skills/ — load with the skill tool.\n- Use bash for terminal commands, write/edit for files.\n- Never embed credentials in code.\n- For deep MCP questions, delegate to @mcp-expert. For debugging, delegate to @troubleshooter.",
      "temperature": 0.2,
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "task": "allow",
        "skill": "allow",
        "todowrite": "allow",
        "question": "allow",
        "webfetch": "deny",
        "websearch": "deny",
        "lsp": "deny"
      }
    },
    "mcp-expert": {
      "description": "Deep MCP protocol expert for architecture questions, advanced patterns, and multi-server design. Invoke with @mcp-expert when participants ask deep technical questions about MCP.",
      "mode": "subagent",
      "temperature": 0.3,
      "color": "#0066CC",
      "prompt": "You are an MCP protocol expert. Load the mcp-concepts, build-mcp-server, and redhat-mcp-resources skills before answering. Provide deep, accurate technical answers about MCP architecture, protocol internals, transport mechanisms, multi-server patterns, and enterprise deployment. Always cite Red Hat resources where relevant. Use diagrams and code examples. Do not make changes to files — explain and advise only.",
      "permission": {
        "edit": "deny",
        "bash": "deny",
        "read": "allow",
        "skill": "allow",
        "question": "allow"
      }
    },
    "troubleshooter": {
      "description": "Empathetic debugging assistant for when builds fail, deployments break, or MCP connections drop. Invoke with @troubleshooter when something goes wrong.",
      "mode": "subagent",
      "temperature": 0.1,
      "color": "#3E8635",
      "prompt": "You are a patient, empathetic troubleshooting assistant. Load the troubleshooting-coach skill first. When something fails, NEVER blame the participant. Always: 1) Acknowledge the frustration, 2) Explain what went wrong in plain language, 3) Show the relevant logs, 4) Provide the exact fix, 5) Explain how to prevent it. Use bash to inspect logs, pod status, and config. After fixing, report back to the main agent so it can update the score.",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "read": "allow",
        "skill": "allow",
        "question": "allow"
      }
    }
  }
}
OCEOF
sed -i "s|PLACEHOLDER_BASE_URL|$OPENAI_BASE_URL|g" ~/.config/opencode/opencode.json
sed -i "s|PLACEHOLDER_MODEL|$VLLM_MODEL_ID|g" ~/.config/opencode/opencode.json
sed -i 's|PLACEHOLDER_EXTRA_BODY|{{ .Values.llm.extraBody | default "{}" }}|g' ~/.config/opencode/opencode.json
mkdir -p ~/.opencode
echo "OpenCode config written (agent=code, skills.paths set, API key via env var)"
{{- end -}}

{{/*
  Copy all skills from the cloned workshop repo to ~/.config/opencode/skills/.
  This ensures skills load in EVERY session regardless of which project is active.
*/}}
{{- define "mcp-workshop.opencodeWriteSkillsScript" -}}
SKILLS_SRC="/projects/mcp-dev-workshop/.opencode/skills"
SKILLS_DST="$HOME/.config/opencode/skills"
if [ -d "$SKILLS_SRC" ]; then
  for skill_dir in "$SKILLS_SRC"/*/; do
    skill_name=$(basename "$skill_dir")
    mkdir -p "$SKILLS_DST/$skill_name"
    cp "$skill_dir/SKILL.md" "$SKILLS_DST/$skill_name/SKILL.md"
  done
  echo "OpenCode skills written ($(ls -1d "$SKILLS_DST"/*/ 2>/dev/null | wc -l) skills)"
else
  echo "Warning: $SKILLS_SRC not found — skills not copied"
fi
{{- end -}}

{{/*
  App name — shown in the UI and health endpoint via OPENCODE_APP_NAME.
*/}}
{{- define "mcp-workshop.appName" -}}
{{- .Values.appName | default "AgentRB" -}}
{{- end -}}
