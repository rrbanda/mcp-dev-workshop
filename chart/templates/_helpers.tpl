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
mkdir -p ~/.local/share/opencode
cat > ~/.config/opencode/opencode.json <<EOF
{"\$schema":"https://opencode.ai/config.json","provider":{"vllm":{"npm":"@ai-sdk/openai-compatible","name":"Workshop LLM","options":{"baseURL":"$OPENAI_BASE_URL","extraBody":{"chat_template_kwargs":{"enable_thinking":false}}},"models":{"$VLLM_MODEL_ID":{"name":"$VLLM_MODEL_ID","limit":{"context":{{ include "mcp-workshop.tokens.context" . }},"output":{{ include "mcp-workshop.tokens.output" . }}}}}}},"model":"vllm/$VLLM_MODEL_ID","permission":"allow","default_agent":"build","agent":{"build":{"prompt":"You are the MCP Developer Workshop assistant. On every new session, load the workshop-guide and presentation-mode skills, then deliver the Stage 1 welcome greeting. All generated code goes into the scaffold/ folder. Skills are in .opencode/skills/.","tools":{"write":true,"edit":true,"read":true,"bash":true,"glob":true,"grep":true,"webfetch":false,"websearch":false,"task":true,"skill":true,"lsp":false,"todowrite":true,"todoread":true,"question":true}}}}
EOF
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
