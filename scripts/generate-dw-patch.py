#!/usr/bin/env python3
"""Generate the DevWorkspace JSON patch for the MCP workshop.

Usage:
    python3 generate-dw-patch.py \
        --namespace dev-user1-devspaces \
        --devworkspace code-workspace-1 \
        --values ../../workshop-values.yaml

Outputs the JSON patch to stdout. The caller pipes it into:
    oc patch devworkspace <name> -n <ns> --type merge --patch-file /dev/stdin
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import yaml


def read_values(path):
    with open(path) as f:
        return yaml.safe_load(f)


def read_system_prompt(repo_root):
    path = os.path.join(repo_root, "config", "system-prompt.txt")
    with open(path) as f:
        return f.read().strip()


def build_opencode_config_b64(vals, prompt):
    """Build the base64-encoded opencode.json (without apiKey — injected at runtime)."""
    llm = vals["llm"]
    cfg = {
        "$schema": "https://opencode.ai/config.json",
        "provider": {
            llm["providerName"]: {
                "npm": "@ai-sdk/openai-compatible",
                "name": llm["providerDisplayName"],
                "options": {
                    "baseURL": llm["baseURL"],
                },
                "models": {
                    llm["modelId"]: {
                        "name": llm["modelDisplayName"],
                        "limit": {
                            "context": int(llm["contextWindow"]),
                            "output": int(llm["maxOutputTokens"]),
                        },
                    }
                },
            }
        },
        "model": f"{llm['providerName']}/{llm['modelId']}",
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
                    "webfetch": False, "websearch": False, "lsp": False,
                },
            }
        },
    }
    return base64.b64encode(json.dumps(cfg).encode()).decode()


def build_cmd_write_config(config_b64, provider_name, provider_display):
    """PostStart [1]: write-opencode-config."""
    return f"""mkdir -p ~/.config/opencode ~/.local/share/opencode
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
RHOAI_KEY=$(oc get secret rhoai-api-key -n "$NS" -o jsonpath='{{.data.api-key}}' | base64 -d)
python3 -c "
import base64, json, sys, os
cfg = base64.b64decode('{config_b64}').decode()
cfg_obj = json.loads(cfg)
key = sys.argv[1] if len(sys.argv) > 1 else ''
cfg_obj['provider']['{provider_name}']['options']['apiKey'] = key
with open(os.path.expanduser('~/.config/opencode/opencode.json'), 'w') as f:
    json.dump(cfg_obj, f, indent=2)
auth = json.dumps({{'{provider_name}': {{'type': 'api', 'key': key}}}})
with open(os.path.expanduser('~/.local/share/opencode/auth.json'), 'w') as f:
    f.write(auth)
print('OpenCode config written ({provider_display} + workshop prompt + apiKey)')
" "\\$RHOAI_KEY"
"""


def build_cmd_write_skills(repo_url, branch):
    """PostStart [2]: write-opencode-skills."""
    return f"""# Clone workshop repo and copy ALL skills dynamically
REPO_DIR=$(mktemp -d)
git clone --depth 1 --branch {branch} {repo_url} "$REPO_DIR" 2>/dev/null

if [ -d "$REPO_DIR/.opencode/skills" ]; then
  for skill_dir in "$REPO_DIR/.opencode/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    mkdir -p ~/.config/opencode/skills/"$skill_name"
    cp "$skill_dir/SKILL.md" ~/.config/opencode/skills/"$skill_name"/SKILL.md
  done
  SKILL_COUNT=$(ls -d ~/.config/opencode/skills/*/ 2>/dev/null | wc -l)
  echo "OpenCode skills written ($SKILL_COUNT skills)"
fi

rm -rf ~/mcp-dev-workshop
cp -a "$REPO_DIR" ~/mcp-dev-workshop
echo "Workshop project copied to ~/mcp-dev-workshop"
rm -rf "$REPO_DIR"
"""


def build_cmd_start_opencode(base_url):
    """PostStart [4]: start-opencode-web with all fixes."""
    return f"""# Clear stale OpenCode database for clean session state on pod restart
rm -f ~/.local/share/opencode/opencode.db ~/.local/share/opencode/opencode.db-shm ~/.local/share/opencode/opencode.db-wal
# Get credentials
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
OPENCODE_SERVER_PASSWORD=$(oc get secret opencode-web-password -n "$NS" \\
  -o jsonpath='{{.data.password}}' | base64 -d)
export OPENCODE_SERVER_PASSWORD
# Override stale container env vars with correct LLM credentials
RHOAI_KEY=$(oc get secret rhoai-api-key -n "$NS" -o jsonpath='{{.data.api-key}}' | base64 -d)
export OPENAI_API_KEY="$RHOAI_KEY"
export OPENAI_BASE_URL="{base_url}"
printf '#!/bin/sh\\nexit 0\\n' > /tmp/xdg-open && chmod +x /tmp/xdg-open
export PATH="/home/user/.java/current/bin:/tmp:$PATH"
cd /projects/mcp-dev-workshop
nohup opencode web --port 4096 --hostname 0.0.0.0 > /tmp/opencode-web.log 2>&1 &
echo "OpenCode Web started from /projects/mcp-dev-workshop"
"""


def get_current_commands(namespace, dw_name):
    """Read existing DevWorkspace commands from the cluster."""
    try:
        result = subprocess.run(
            ["oc", "get", "devworkspace", dw_name, "-n", namespace,
             "-o", "jsonpath={.spec.template.commands}"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0 and result.stdout:
            return json.loads(result.stdout)
    except Exception:
        pass
    return []


def build_patch(vals, repo_root, namespace, dw_name):
    prompt = read_system_prompt(repo_root)
    llm = vals["llm"]
    workshop = vals["workshop"]

    config_b64 = build_opencode_config_b64(vals, prompt)

    cmd1 = build_cmd_write_config(config_b64, llm["providerName"], llm["providerDisplayName"])
    cmd2 = build_cmd_write_skills(workshop["repo"], workshop["branch"])
    cmd4 = build_cmd_start_opencode(llm["baseURL"])

    current_cmds = get_current_commands(namespace, dw_name)

    # Preserve [0] open-projects-folder and [3] download-opencode-extension
    cmd0 = None
    cmd3_ext = None
    for c in current_cmds:
        if c.get("id") == "open-projects-folder":
            cmd0 = c
        elif c.get("id") == "download-opencode-extension":
            cmd3_ext = c

    if not cmd0:
        cmd0 = {
            "id": "open-projects-folder",
            "exec": {
                "label": "Open /projects as workspace folder",
                "component": "dev-tools",
                "commandLine": 'echo \'{"folders":[{"path":"/projects"}]}\' > /projects/.code-workspace',
            },
        }

    if not cmd3_ext:
        cmd3_ext = {
            "id": "download-opencode-extension",
            "exec": {
                "label": "Download OpenCode Extension",
                "component": "dev-tools",
                "commandLine": (
                    'mkdir -p /tmp/opencode-ext\n'
                    'curl -fsSL "https://open-vsx.org/api/sst-dev/opencode/latest/file/sst-dev.opencode-0.0.13.vsix" \\\n'
                    '  --location -o /tmp/opencode-ext/sst-dev.opencode.vsix\n'
                    'echo "OpenCode extension downloaded"'
                ),
            },
        }

    new_cmds = [
        cmd0,
        {
            "id": "write-opencode-config",
            "exec": {
                "label": "Write Workshop OpenCode Config",
                "component": "dev-tools",
                "commandLine": cmd1,
            },
        },
        {
            "id": "write-opencode-skills",
            "exec": {
                "label": "Clone Workshop Skills",
                "component": "dev-tools",
                "commandLine": cmd2,
            },
        },
        cmd3_ext,
        {
            "id": "start-opencode-web",
            "exec": {
                "label": "Start OpenCode Web UI",
                "component": "dev-tools",
                "commandLine": cmd4,
            },
        },
    ]

    return {
        "spec": {
            "template": {
                "commands": new_cmds,
                "events": {
                    "postStart": [
                        "open-projects-folder",
                        "write-opencode-config",
                        "write-opencode-skills",
                        "download-opencode-extension",
                        "start-opencode-web",
                    ]
                },
            }
        }
    }


def main():
    parser = argparse.ArgumentParser(description="Generate DevWorkspace patch for MCP workshop")
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--devworkspace", default="code-workspace-1")
    parser.add_argument("--values", required=True)
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    vals = read_values(args.values)
    patch = build_patch(vals, repo_root, args.namespace, args.devworkspace)
    print(json.dumps(patch))


if __name__ == "__main__":
    main()
