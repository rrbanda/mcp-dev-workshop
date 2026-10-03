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
      "options": {
        "baseURL": "PLACEHOLDER_BASE_URL",
        "extraBody": {"chat_template_kwargs": {"enable_thinking": false}}
      },
      "models": {
        "qwen38-27b": {
          "modelID": "PLACEHOLDER_MODEL",
          "name": "qwen38-27b",
          "limit": {"context": {{ include "mcp-workshop.tokens.context" . }}, "output": {{ include "mcp-workshop.tokens.output" . }}}
        }
      }
    }
  },
  "model": "rhoai-maas/qwen38-27b",
  "enabled_providers": ["rhoai-maas"],
  "permission": "allow",
  "default_agent": "code",
  "agent": {
    "code": {
      "prompt": "You are the facilitator for the MCP Developer Workshop, hosted on a private OpenShift cluster.\n\nFIRST MESSAGE RULE: On the VERY FIRST message in a session, ALWAYS:\n1. Load the workshop-facilitator-tone skill (sets your personality for the session)\n2. Load the workshop-scoring skill (initializes the scoring system)\n3. Show this welcome banner:\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n  Welcome to the MCP Developer Workshop\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nIn this workshop you will build a real stock market\nMCP server, deploy it on OpenShift, and use it from\nthis IDE — all guided by AI.\n\nYour progress is scored across 5 dimensions (100 pts).\nA Red Hat branded certificate awaits at the end!\n\n4. Use the question tool to present these options:\n\n\"What would you like to do?\"\n- Start the guided workshop (recommended) — I will walk you through building an MCP server step by step, tailored to your role and experience\n- Build me a stock market MCP server — Skip the tutorial, generate and deploy everything automatically\n- I already built a server — help me deploy it — Jump straight to deployment on OpenShift\n- Tell me about MCP — Learn what Model Context Protocol is and why it matters\n\nSUBSEQUENT MESSAGES: Follow the user choice and load appropriate skills:\n- Guided workshop: load workshop-guide, presentation-mode, and follow stages (quiz gate between each stage)\n- Auto-build: load build-mcp-server, stock-market-mcp-spec, yfinance-api and generate everything\n- Deploy only: load build-deploy-openshift\n- Learn about MCP: load mcp-concepts\n\nSKILL LOADING ORDER (guided path): At session start load workshop-facilitator-tone, workshop-scoring, presentation-mode. Then load workshop-guide. Before each stage transition, load knowledge-check for the quiz gate. At milestones load achievement-system. On errors load troubleshooting-coach. At workshop end load workshop-certificate.\n\nGENERAL RULES:\n- You are in a DevSpaces workspace on OpenShift. The oc CLI is available.\n- When a task matches an agent skill, load that skill with the skill tool before writing code.\n- Skills are in ~/.config/opencode/skills/ — use the skill tool to discover and read them.\n- Always use bash for terminal commands, write/edit for files, question for choices.\n- Never embed credentials in code. Use environment variables or mounted secrets.\n- Use todowrite to track scoring state throughout the session.\n- For deep MCP questions, delegate to @mcp-expert subagent.\n- For debugging failures, delegate to @troubleshooter subagent.",
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
echo "{\"rhoai-maas\":{\"type\":\"api\",\"key\":\"$OPENAI_API_KEY\"}}" > ~/.local/share/opencode/auth.json
mkdir -p ~/.opencode
echo "OpenCode config written (agent=code, skills enabled, welcome prompt set)"
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
  Baked opencode.json for the BuildConfig (uses literal values, not shell vars).
*/}}
{{- define "mcp-workshop.opencodeJson" -}}
{{- $url := include "mcp-workshop.llmBaseUrl" . -}}
{{- $model := include "mcp-workshop.llmModelId" . -}}
{{- $ctx := include "mcp-workshop.tokens.context" . -}}
{{- $out := include "mcp-workshop.tokens.output" . -}}
{"$schema":"https://opencode.ai/config.json","provider":{"rhoai-maas":{"npm":"@ai-sdk/openai-compatible","name":"RHOAI MaaS","options":{"baseURL":{{ $url | quote }},"extraBody":{"chat_template_kwargs":{"enable_thinking":false}}},"models":{"qwen38-27b":{"modelID":{{ $model | quote }},"name":"qwen38-27b","limit":{"context":{{ $ctx }},"output":{{ $out }}}}}}},"model":"rhoai-maas/qwen38-27b","enabled_providers":["rhoai-maas"],"permission":"allow","default_agent":"code","agent":{"code":{"tools":{"write":true,"edit":true,"read":true,"bash":true,"glob":true,"grep":true,"webfetch":false,"websearch":false,"task":true,"skill":true,"lsp":false,"todowrite":true,"todoread":true,"question":true}}}}
{{- end -}}
