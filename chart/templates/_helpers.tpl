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
  Compact opencode.json body.
  Uses shell variable expansion at postStart time ($OPENAI_BASE_URL, $VLLM_MODEL_ID)
  so the config adapts without image rebuild.
*/}}
{{- define "mcp-workshop.opencodeWriteConfigScript" -}}
mkdir -p ~/.config/opencode/skills/mcp-server ~/.local/share/opencode
cat > ~/.config/opencode/opencode.json <<EOF
{"\$schema":"https://opencode.ai/config.json","provider":{"vllm":{"npm":"@ai-sdk/openai-compatible","name":"Workshop LLM","options":{"baseURL":"$OPENAI_BASE_URL","extraBody":{"chat_template_kwargs":{"enable_thinking":false}}},"models":{"$VLLM_MODEL_ID":{"name":"$VLLM_MODEL_ID","limit":{"context":{{ include "mcp-workshop.tokens.context" . }},"output":{{ include "mcp-workshop.tokens.output" . }}}}}}},"model":"vllm/$VLLM_MODEL_ID","permission":"allow","default_agent":"build","agent":{"build":{"prompt":"You are a coding agent in a workshop Dev Space. Use read, write, edit, bash, grep, and glob. When a task matches an agent skill, load that skill with the skill tool before writing code. Skills are discovered from .opencode/skills.","tools":{"write":true,"edit":true,"read":true,"bash":true,"glob":true,"grep":true,"webfetch":false,"websearch":false,"task":true,"skill":true,"lsp":false,"todowrite":true,"todoread":true,"question":true}}}}
EOF
cat > ~/.config/opencode/skills/mcp-server/SKILL.md <<'PCA_SKILL'
---
name: mcp-server
description: Build a standard Model Context Protocol server the OpenCode host can launch over stdio. Use when creating or extending an MCP server.
---

# Stock MCP server

Build a local stdio MCP server and register it with OpenCode.

1. Create a Python project and install the official SDK (`mcp`).
2. Define the server with `FastMCP`, register each capability with `@mcp.tool()`, and give every tool a docstring. That docstring is the description the model sees.
3. Start the server with `mcp.run()` so it speaks stdio. Do not open a public port for a local server.
4. Read secrets from the environment. Do not write them into source.
5. Register the server in `opencode.json` under `mcp` as a local command, for example `python server.py`, with `enabled` set to true.
6. Call one tool end to end before adding more tools. Keep the tool list small.
PCA_SKILL
echo "{\"vllm\":{\"type\":\"api\",\"key\":\"$OPENAI_API_KEY\"}}" > ~/.local/share/opencode/auth.json
echo "OpenCode config written"
{{- end -}}

{{/*
  Baked opencode.json for the BuildConfig (uses literal values, not shell vars).
*/}}
{{- define "mcp-workshop.opencodeJson" -}}
{{- $url := include "mcp-workshop.llmBaseUrl" . -}}
{{- $model := include "mcp-workshop.llmModelId" . -}}
{{- $ctx := include "mcp-workshop.tokens.context" . -}}
{{- $out := include "mcp-workshop.tokens.output" . -}}
{"$schema":"https://opencode.ai/config.json","provider":{"vllm":{"npm":"@ai-sdk/openai-compatible","name":"Workshop LLM","options":{"baseURL":{{ $url | quote }},"extraBody":{"chat_template_kwargs":{"enable_thinking":false}}},"models":{ {{ $model | quote }}:{"name":{{ $model | quote }},"limit":{"context":{{ $ctx }},"output":{{ $out }}}}}}},"model":{{ printf "vllm/%s" $model | quote }},"permission":"allow","default_agent":"build","agent":{"build":{"prompt":"You are a coding agent in a workshop Dev Space.","tools":{"write":true,"edit":true,"read":true,"bash":true,"glob":true,"grep":true,"webfetch":false,"websearch":false,"task":true,"skill":true,"lsp":false,"todowrite":true,"todoread":true,"question":true}}}}
{{- end -}}
