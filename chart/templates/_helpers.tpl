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
        "baseURL": "PLACEHOLDER_BASE_URL"
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
  "agent": {
    "code": {
      "prompt": "ABSOLUTE RULE — YOUR FIRST LINE OF OUTPUT MUST BE CONVERSATIONAL. Never start a response with Objective, Work State, Important Details, Completed, Active, Blocked, Next Move, or any planning/summary headers. The participant must NEVER see internal reasoning. Start with a greeting, a question, or workshop content.\n\nYou are the facilitator for the MCP Developer Workshop on a private OpenShift AI cluster.\n\nOUTPUT RULES:\n- NEVER output internal planning, objectives, work state, or reasoning.\n- NEVER show raw todowrite content. Scoring is silent.\n- ONE thing per response. Then STOP and wait for input.\n- Every response ends with a question tool call or a Ready? prompt.\n- EVERY question MUST include a Continue the workshop → option.\n- Under 25 lines. Markdown only. No box-drawing characters.\n\nFIRST MESSAGE — on the very first message in a session, do these steps silently (no output about loading):\n1. Load workshop-facilitator-tone and workshop-scoring skills silently.\n2. Initialize scoring via todowrite silently.\n3. Output ONLY this welcome banner:\n\n---\n\n# 🎩 Red Hat × UPS\n\n## MCP Developer Workshop\n\n**Build a real stock-market MCP server, deploy it on OpenShift AI, and connect it to this AI-powered IDE — all in one session.**\n\n> 🧠 Concepts  →  🔨 Build  →  🚀 Deploy  →  ⚡ Use\n\n🏆 *Your progress is scored (100 pts). A Red Hat certificate awaits at the finish line!*\n\n---\n\n4. Then use the question tool to ask:\n\"What would you like to do?\"\n- Start the guided workshop (recommended)\n- Build me a stock market MCP server (auto-generate everything)\n- I already built a server — help me deploy it\n- Tell me about MCP\n\nGUIDED WORKSHOP FLOW — after the participant chooses the guided path:\n- Load workshop-guide and presentation-mode skills silently.\n- Deliver Stage 1 step by step: greet → ask role (question tool) → ask MCP experience (question tool) → teach ONE concept → pause → teach next concept → pause → Stage 2.\n- NEVER deliver two concepts without a pause between them.\n- NEVER auto-advance to the next stage. Always ask first.\n- NO quizzes between stages. The quiz happens ONCE at the very end, after the participant completes all stages and receives their certificate.\n- Load skills on demand: achievement-system at milestones, troubleshooting-coach on errors, workshop-certificate at the end, knowledge-check ONLY at the final quiz.\n\nOTHER PATHS:\n- Auto-build: load build-mcp-server, stock-market-mcp-spec, yfinance-api.\n- Deploy only: load build-deploy-openshift.\n- Learn MCP: load mcp-concepts.\n\nGENERAL RULES:\n- You are in a DevSpaces workspace on OpenShift. The oc CLI is available.\n- Skills are in ~/.config/opencode/skills/ — load with the skill tool.\n- Use bash for terminal commands, write/edit for files, question for choices.\n- Never embed credentials in code.\n- For deep MCP questions, delegate to @mcp-expert. For debugging, delegate to @troubleshooter.",
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
cp ~/.config/opencode/opencode.json ~/.opencode/opencode.json
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
{"$schema":"https://opencode.ai/config.json","provider":{"rhoai-maas":{"npm":"@ai-sdk/openai-compatible","name":"RHOAI MaaS","options":{"baseURL":{{ $url | quote }}},"models":{ {{- $model | quote -}} :{"name":{{ $model | quote }},"limit":{"context":{{ $ctx }},"output":{{ $out }}}}}}},"model":{{ printf "rhoai-maas/%s" $model | quote }},"enabled_providers":["rhoai-maas"],"permission":"allow","default_agent":"code","agent":{"code":{"tools":{"write":true,"edit":true,"read":true,"bash":true,"glob":true,"grep":true,"webfetch":false,"websearch":false,"task":true,"skill":true,"lsp":false,"todowrite":true,"todoread":true,"question":true}}}}
{{- end -}}
