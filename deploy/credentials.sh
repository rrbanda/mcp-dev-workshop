#!/usr/bin/env bash
# Generate credentials cards for workshop participants.
#
# Usage:
#   ./deploy/credentials.sh --user-prefix user --user-count 30
#
# Requires: oc (logged in as cluster-admin)
set -euo pipefail

USER_PREFIX="${USER_PREFIX:-user}"
USER_COUNT="${USER_COUNT:-30}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --user-prefix) USER_PREFIX="$2"; shift 2 ;;
    --user-count)  USER_COUNT="$2";  shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

CONSOLE_URL=$(oc whoami --show-console 2>/dev/null || echo "https://console-openshift-console.apps.<cluster>")

echo "================================================================"
echo "  MCP Workshop Credentials"
echo "  Console: ${CONSOLE_URL}"
echo "================================================================"
echo ""

for i in $(seq 1 "$USER_COUNT"); do
  user="${USER_PREFIX}${i}"
  ns="${user}-devspaces"
  oc_pass=$(oc get secret opencode-web-password -n "$ns" \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "N/A — workspace not deployed")
  echo "--- ${user} ---"
  echo "  Console URL:           ${CONSOLE_URL}"
  echo "  Username:              ${user}"
  echo "  OpenCode Web Password: ${oc_pass}"
  echo ""
done
