#!/usr/bin/env bash
#
# Setup the MCP Developer Workshop on an existing PCA DevWorkspace.
#
# What this script does:
#   1. Creates the rhoai-api-key Secret (LLM provider credentials)
#   2. Creates RBAC so the workspace SA can run oc new-build / oc apply
#   3. Patches PostStart [1] — writes workshop opencode.json with correct
#      provider, model, system prompt, and injects apiKey from K8s secret
#   4. Adds PostStart [2] — clones workshop repo and copies skills
#   5. Patches PostStart [4] — clears stale DB, overrides env vars, starts OpenCode Web
#   6. Restarts the DevWorkspace to apply changes
#
# Prerequisites:
#   - oc CLI authenticated to the target cluster (cluster-admin or ns-admin)
#   - PCA DevWorkspace already deployed (make devspace-deploy-existing-openshift)
#   - The rhoai-api-key value (pass via --api-key or RHOAI_API_KEY env var)
#
# Usage:
#   ./scripts/setup-workshop-devworkspace.sh \
#     --namespace dev-user1-devspaces \
#     --api-key "sk-oai-..." \
#     --values workshop-values.yaml
#
#   Or with env var:
#   RHOAI_API_KEY="sk-oai-..." ./scripts/setup-workshop-devworkspace.sh \
#     --namespace dev-user1-devspaces
#
set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE=""
API_KEY="${RHOAI_API_KEY:-}"
VALUES_FILE="${REPO_ROOT}/workshop-values.yaml"
DW_NAME="code-workspace-1"
DRY_RUN=false
SKIP_RESTART=false

# ── Parse values from YAML (lightweight — no yq dependency) ────
# Reads simple key: "value" pairs from the values file.
yaml_val() {
    local key="$1"
    local file="$2"
    # Handles nested keys like llm.baseURL by flattening with awk
    python3 -c "
import yaml, sys, functools, operator
with open('$file') as f:
    d = yaml.safe_load(f)
keys = '$key'.split('.')
try:
    val = functools.reduce(operator.getitem, keys, d)
    print(val)
except (KeyError, TypeError):
    sys.exit(1)
" 2>/dev/null || grep -E "^\s*${key##*.}:" "$file" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

# ── Colours ─────────────────────────────────────────────────────
info()  { printf "\033[36m[INFO]\033[0m  %s\n" "$1"; }
pass()  { printf "\033[32m[DONE]\033[0m  %s\n" "$1"; }
fail()  { printf "\033[31m[FAIL]\033[0m  %s\n" "$1"; exit 1; }
warn()  { printf "\033[33m[WARN]\033[0m  %s\n" "$1"; }

# ── CLI Args ────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Required:
  --namespace NS        DevWorkspace namespace (e.g. dev-user1-devspaces)
  --api-key KEY         LLM provider API key (or set RHOAI_API_KEY env var)

Optional:
  --values FILE         Values file (default: workshop-values.yaml)
  --devworkspace NAME   DevWorkspace name (default: code-workspace-1)
  --dry-run             Print what would be done, don't apply
  --skip-restart        Patch but don't restart the DevWorkspace
  --help                Show this help

Example:
  $0 --namespace dev-user1-devspaces --api-key "sk-oai-..."
  $0 --namespace dev-user1-devspaces --values my-cluster.yaml
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)     NAMESPACE="$2"; shift 2 ;;
        --api-key)       API_KEY="$2"; shift 2 ;;
        --values)        VALUES_FILE="$2"; shift 2 ;;
        --devworkspace)  DW_NAME="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --skip-restart)  SKIP_RESTART=true; shift ;;
        --help)          usage ;;
        *)               fail "Unknown option: $1" ;;
    esac
done

# ── Validate inputs ─────────────────────────────────────────────
[ -z "$NAMESPACE" ] && fail "Missing --namespace"
[ -z "$API_KEY" ]   && fail "Missing --api-key (or set RHOAI_API_KEY env var)"
[ -f "$VALUES_FILE" ] || fail "Values file not found: $VALUES_FILE"

info "Values file:   $VALUES_FILE"
info "Namespace:     $NAMESPACE"
info "DevWorkspace:  $DW_NAME"

# ── Read values ─────────────────────────────────────────────────
BASE_URL=$(yaml_val "llm.baseURL" "$VALUES_FILE")
MODEL_ID=$(yaml_val "llm.modelId" "$VALUES_FILE")
MODEL_DISPLAY=$(yaml_val "llm.modelDisplayName" "$VALUES_FILE")
CONTEXT_WINDOW=$(yaml_val "llm.contextWindow" "$VALUES_FILE")
MAX_OUTPUT=$(yaml_val "llm.maxOutputTokens" "$VALUES_FILE")
PROVIDER_NAME=$(yaml_val "llm.providerName" "$VALUES_FILE")
PROVIDER_DISPLAY=$(yaml_val "llm.providerDisplayName" "$VALUES_FILE")
WORKSHOP_REPO=$(yaml_val "workshop.repo" "$VALUES_FILE")
WORKSHOP_BRANCH=$(yaml_val "workshop.branch" "$VALUES_FILE")

info "LLM endpoint:  $BASE_URL"
info "Model:         $MODEL_ID ($MODEL_DISPLAY)"
info "Provider:      $PROVIDER_NAME"
info "Workshop repo: $WORKSHOP_REPO ($WORKSHOP_BRANCH)"

# ── Verify cluster access ──────────────────────────────────────
oc whoami >/dev/null 2>&1 || fail "Not logged in. Run 'oc login' first."
oc get namespace "$NAMESPACE" >/dev/null 2>&1 || fail "Namespace $NAMESPACE not found"
oc get devworkspace "$DW_NAME" -n "$NAMESPACE" >/dev/null 2>&1 || fail "DevWorkspace $DW_NAME not found in $NAMESPACE"

DW_STATE=$(oc get devworkspace "$DW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
info "DevWorkspace state: $DW_STATE"

# ═══════════════════════════════════════════════════════════════
# STEP 1: Create rhoai-api-key Secret
# ═══════════════════════════════════════════════════════════════
info "Step 1: Creating rhoai-api-key secret..."

if oc get secret rhoai-api-key -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "Secret rhoai-api-key already exists — updating"
    if [ "$DRY_RUN" = false ]; then
        oc delete secret rhoai-api-key -n "$NAMESPACE"
    fi
fi

if [ "$DRY_RUN" = false ]; then
    oc create secret generic rhoai-api-key \
        --from-literal=api-key="$API_KEY" \
        -n "$NAMESPACE"
fi
pass "Secret rhoai-api-key created"

# ═══════════════════════════════════════════════════════════════
# STEP 2: Create RBAC for workshop builds
# ═══════════════════════════════════════════════════════════════
info "Step 2: Creating workshop-edit RoleBinding..."

if oc get rolebinding workshop-edit -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "RoleBinding workshop-edit already exists — skipping"
else
    if [ "$DRY_RUN" = false ]; then
        oc create rolebinding workshop-edit \
            --clusterrole=edit \
            --group="system:serviceaccounts:${NAMESPACE}" \
            -n "$NAMESPACE"
    fi
    pass "RoleBinding workshop-edit created"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 3: Build the opencode.json config
# ═══════════════════════════════════════════════════════════════
info "Step 3: Building opencode.json from template..."

SYSTEM_PROMPT=$(cat "${REPO_ROOT}/config/system-prompt.txt")

# Build the config JSON with Python (handles escaping correctly)
OPENCODE_CONFIG_B64=$(python3 << PYEOF
import json, base64, sys

prompt = open("${REPO_ROOT}/config/system-prompt.txt").read().strip()

cfg = {
    "\$schema": "https://opencode.ai/config.json",
    "provider": {
        "${PROVIDER_NAME}": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "${PROVIDER_DISPLAY}",
            "options": {
                "baseURL": "${BASE_URL}"
            },
            "models": {
                "${MODEL_ID}": {
                    "name": "${MODEL_DISPLAY}",
                    "limit": {
                        "context": ${CONTEXT_WINDOW},
                        "output": ${MAX_OUTPUT}
                    }
                }
            }
        }
    },
    "model": "${PROVIDER_NAME}/${MODEL_ID}",
    "permission": "allow",
    "default_agent": "code",
    "agent": {
        "code": {
            "prompt": prompt,
            "tools": {
                "write": True, "edit": True, "read": True,
                "bash": True, "glob": True, "grep": True,
                "skill": True, "task": True,
                "todowrite": True, "todoread": True, "question": True,
                "webfetch": False, "websearch": False, "lsp": False
            }
        }
    }
}

b64 = base64.b64encode(json.dumps(cfg).encode()).decode()
print(b64)
PYEOF
)

info "Config base64 length: ${#OPENCODE_CONFIG_B64} chars"

# ═══════════════════════════════════════════════════════════════
# STEP 4: Build the postStart command patches
# ═══════════════════════════════════════════════════════════════
info "Step 4: Building DevWorkspace patches..."

# Command [1]: write-opencode-config — decode base64, inject apiKey from secret
CMD1=$(cat << 'CMDEOF'
mkdir -p ~/.config/opencode ~/.local/share/opencode
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
RHOAI_KEY=$(oc get secret rhoai-api-key -n "$NS" -o jsonpath='{.data.api-key}' | base64 -d)
python3 -c "
import base64, json, sys, os
cfg = base64.b64decode('__CONFIG_B64__').decode()
cfg_obj = json.loads(cfg)
key = sys.argv[1] if len(sys.argv) > 1 else ''
cfg_obj['provider']['__PROVIDER_NAME__']['options']['apiKey'] = key
with open(os.path.expanduser('~/.config/opencode/opencode.json'), 'w') as f:
    json.dump(cfg_obj, f, indent=2)
auth = json.dumps({'__PROVIDER_NAME__': {'type': 'api', 'key': key}})
with open(os.path.expanduser('~/.local/share/opencode/auth.json'), 'w') as f:
    f.write(auth)
print('OpenCode config written (__PROVIDER_DISPLAY__ + workshop prompt + apiKey)')
" "$RHOAI_KEY"
CMDEOF
)

# Substitute placeholders
CMD1="${CMD1//__CONFIG_B64__/$OPENCODE_CONFIG_B64}"
CMD1="${CMD1//__PROVIDER_NAME__/$PROVIDER_NAME}"
CMD1="${CMD1//__PROVIDER_DISPLAY__/$PROVIDER_DISPLAY}"

# Command [2]: write-opencode-skills — clone repo, copy all skills
CMD2=$(cat << CMDEOF
# Clone workshop repo and copy ALL skills dynamically
REPO_DIR=\$(mktemp -d)
git clone --depth 1 --branch ${WORKSHOP_BRANCH} ${WORKSHOP_REPO} "\$REPO_DIR" 2>/dev/null

# Copy every skill found in the repo (future-proof)
if [ -d "\$REPO_DIR/.opencode/skills" ]; then
  for skill_dir in "\$REPO_DIR/.opencode/skills"/*/; do
    skill_name=\$(basename "\$skill_dir")
    mkdir -p ~/.config/opencode/skills/"\$skill_name"
    cp "\$skill_dir/SKILL.md" ~/.config/opencode/skills/"\$skill_name"/SKILL.md
  done
  SKILL_COUNT=\$(ls -d ~/.config/opencode/skills/*/ 2>/dev/null | wc -l)
  echo "OpenCode skills written (\$SKILL_COUNT skills)"
fi

# Copy workshop repo to HOME so it appears in Open Project dropdown
rm -rf ~/mcp-dev-workshop
cp -a "\$REPO_DIR" ~/mcp-dev-workshop
echo "Workshop project copied to ~/mcp-dev-workshop"
rm -rf "\$REPO_DIR"
CMDEOF
)

# Command [4]: start-opencode-web — with all fixes
CMD4=$(cat << CMDEOF
# Clear stale OpenCode database for clean session state on pod restart
rm -f ~/.local/share/opencode/opencode.db ~/.local/share/opencode/opencode.db-shm ~/.local/share/opencode/opencode.db-wal
# Get credentials
NS=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
OPENCODE_SERVER_PASSWORD=\$(oc get secret opencode-web-password -n "\$NS" \\
  -o jsonpath='{.data.password}' | base64 -d)
export OPENCODE_SERVER_PASSWORD
# Override stale container env vars with correct LLM credentials
RHOAI_KEY=\$(oc get secret rhoai-api-key -n "\$NS" -o jsonpath='{.data.api-key}' | base64 -d)
export OPENAI_API_KEY="\$RHOAI_KEY"
export OPENAI_BASE_URL="${BASE_URL}"
printf '#!/bin/sh\\nexit 0\\n' > /tmp/xdg-open && chmod +x /tmp/xdg-open
export PATH="/home/user/.java/current/bin:/tmp:\$PATH"
cd /projects/mcp-dev-workshop
nohup opencode web --port 4096 --hostname 0.0.0.0 > /tmp/opencode-web.log 2>&1 &
echo "OpenCode Web started from /projects/mcp-dev-workshop"
CMDEOF
)

# ═══════════════════════════════════════════════════════════════
# STEP 5: Apply the DevWorkspace patches
# ═══════════════════════════════════════════════════════════════
info "Step 5: Patching DevWorkspace $DW_NAME..."

# Build the JSON patch with Python (handles all escaping)
PATCH_JSON=$(python3 << PYEOF
import json, sys

cmd1 = '''$CMD1'''
cmd2 = '''$CMD2'''
cmd4 = '''$CMD4'''

# Read current commands to preserve [0] and [3]
import subprocess
result = subprocess.run(
    ["oc", "get", "devworkspace", "$DW_NAME", "-n", "$NAMESPACE",
     "-o", "jsonpath={.spec.template.commands}"],
    capture_output=True, text=True
)
current_cmds = json.loads(result.stdout) if result.stdout else []

# Build the new command list
new_cmds = []

# [0] open-projects-folder — preserve original
if len(current_cmds) > 0:
    new_cmds.append(current_cmds[0])
else:
    new_cmds.append({
        "id": "open-projects-folder",
        "exec": {
            "label": "Open /projects as workspace folder",
            "component": "dev-tools",
            "commandLine": 'echo \'{"folders":[{"path":"/projects"}]}\' > /projects/.code-workspace'
        }
    })

# [1] write-opencode-config — PATCHED
new_cmds.append({
    "id": "write-opencode-config",
    "exec": {
        "label": "Write Workshop OpenCode Config",
        "component": "dev-tools",
        "commandLine": cmd1
    }
})

# [2] write-opencode-skills — NEW
new_cmds.append({
    "id": "write-opencode-skills",
    "exec": {
        "label": "Clone Workshop Skills",
        "component": "dev-tools",
        "commandLine": cmd2
    }
})

# [3] download-opencode-extension — preserve original
found_ext = None
for c in current_cmds:
    if c.get("id") == "download-opencode-extension":
        found_ext = c
        break
if found_ext:
    new_cmds.append(found_ext)
else:
    new_cmds.append({
        "id": "download-opencode-extension",
        "exec": {
            "label": "Download OpenCode Extension",
            "component": "dev-tools",
            "commandLine": 'mkdir -p /tmp/opencode-ext\ncurl -fsSL "https://open-vsx.org/api/sst-dev/opencode/latest/file/sst-dev.opencode-0.0.13.vsix" \\\\\n  --location -o /tmp/opencode-ext/sst-dev.opencode.vsix\necho "OpenCode extension downloaded"'
        }
    })

# [4] start-opencode-web — PATCHED
new_cmds.append({
    "id": "start-opencode-web",
    "exec": {
        "label": "Start OpenCode Web UI",
        "component": "dev-tools",
        "commandLine": cmd4
    }
})

patch = {
    "spec": {
        "template": {
            "commands": new_cmds,
            "events": {
                "postStart": [
                    "open-projects-folder",
                    "write-opencode-config",
                    "write-opencode-skills",
                    "download-opencode-extension",
                    "start-opencode-web"
                ]
            }
        }
    }
}

print(json.dumps(patch))
PYEOF
)

if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would apply patch (${#PATCH_JSON} chars)"
    echo "$PATCH_JSON" | python3 -m json.tool | head -20
    echo "  ... (truncated)"
else
    echo "$PATCH_JSON" | oc patch devworkspace "$DW_NAME" -n "$NAMESPACE" \
        --type merge --patch-file /dev/stdin
    pass "DevWorkspace patched"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 6: Restart the DevWorkspace
# ═══════════════════════════════════════════════════════════════
if [ "$SKIP_RESTART" = true ]; then
    warn "Skipping restart (--skip-restart). Restart manually to apply changes."
elif [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would restart DevWorkspace $DW_NAME"
else
    info "Step 6: Restarting DevWorkspace..."
    oc patch devworkspace "$DW_NAME" -n "$NAMESPACE" \
        --type merge -p '{"spec":{"started":false}}'
    info "Waiting for DevWorkspace to stop..."
    sleep 5

    # Wait until it's actually stopped
    for i in $(seq 1 30); do
        STATE=$(oc get devworkspace "$DW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$STATE" = "Stopped" ] || [ "$STATE" = "Failed" ]; then
            break
        fi
        sleep 2
    done

    oc patch devworkspace "$DW_NAME" -n "$NAMESPACE" \
        --type merge -p '{"spec":{"started":true}}'
    info "DevWorkspace restarting..."

    # Wait for Running
    info "Waiting for DevWorkspace to be Running..."
    for i in $(seq 1 60); do
        STATE=$(oc get devworkspace "$DW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$STATE" = "Running" ]; then
            pass "DevWorkspace is Running"
            break
        fi
        if [ "$STATE" = "Failed" ]; then
            fail "DevWorkspace failed to start. Check: oc describe devworkspace $DW_NAME -n $NAMESPACE"
        fi
        printf "."
        sleep 5
    done
fi

# ═══════════════════════════════════════════════════════════════
# STEP 7: Verify
# ═══════════════════════════════════════════════════════════════
if [ "$DRY_RUN" = false ] && [ "$SKIP_RESTART" = false ]; then
    info "Step 7: Verifying..."
    sleep 10  # Give postStart commands time to run

    POD=$(oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep workspace | grep Running | awk '{print $1}' | head -1)
    if [ -z "$POD" ]; then
        warn "No running workspace pod found yet — verify manually after pod starts"
    else
        # Check skills
        SKILL_COUNT=$(oc exec -n "$NAMESPACE" "$POD" -c dev-tools -- \
            bash -c 'ls -d ~/.config/opencode/skills/*/ 2>/dev/null | wc -l' 2>/dev/null || echo "0")
        info "Skills installed: $SKILL_COUNT"

        # Check config
        CONFIG_OK=$(oc exec -n "$NAMESPACE" "$POD" -c dev-tools -- \
            bash -c 'python3 -c "
import json
with open(\"/home/user/.config/opencode/opencode.json\") as f:
    c = json.load(f)
key = list(c[\"provider\"].values())[0].get(\"options\",{}).get(\"apiKey\",\"\")
print(\"ok\" if len(key) > 20 else \"no-key\")
" 2>/dev/null' 2>/dev/null || echo "error")
        if [ "$CONFIG_OK" = "ok" ]; then
            pass "OpenCode config: apiKey injected"
        else
            warn "OpenCode config: apiKey may not be injected yet (postStart still running?)"
        fi

        # Check OpenCode process
        OC_PID=$(oc exec -n "$NAMESPACE" "$POD" -c dev-tools -- \
            pgrep -x opencode 2>/dev/null | tail -1 || echo "")
        if [ -n "$OC_PID" ]; then
            pass "OpenCode Web: running (PID $OC_PID)"
        else
            warn "OpenCode Web: not running yet (postStart may still be executing)"
        fi

        # Check RBAC
        CAN_BUILD=$(oc exec -n "$NAMESPACE" "$POD" -c dev-tools -- \
            oc auth can-i create builds 2>/dev/null || echo "no")
        if [ "$CAN_BUILD" = "yes" ]; then
            pass "RBAC: workspace can create builds"
        else
            warn "RBAC: workspace cannot create builds"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
cat << EOF

$(printf '\033[32m')━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Workshop setup complete for $NAMESPACE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(printf '\033[0m')

  DevWorkspace: $DW_NAME
  LLM Provider: $BASE_URL
  Model:        $MODEL_DISPLAY ($MODEL_ID)

  Access OpenCode Web:
    1. Get the route:
       oc get devworkspace $DW_NAME -n $NAMESPACE -o jsonpath='{.status.mainUrl}'

    2. Get the password:
       oc get secret opencode-web-password -n $NAMESPACE \\
         -o jsonpath='{.data.password}' | base64 -d

    3. Append /4096/ to the DevSpaces route to reach OpenCode Web

EOF
