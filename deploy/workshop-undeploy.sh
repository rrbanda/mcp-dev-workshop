#!/usr/bin/env bash
# Undeploy all workshop DevSpaces.
#
# Usage:
#   ./deploy/workshop-undeploy.sh --user-prefix user --user-count 30
#
# Requires: oc, helm (logged in as cluster-admin)
set -euo pipefail

USER_PREFIX="${USER_PREFIX:-user}"
USER_COUNT="${USER_COUNT:-30}"
DELETE_NAMESPACE="${DELETE_NAMESPACE:-1}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --user-prefix)      USER_PREFIX="$2";      shift 2 ;;
    --user-count)       USER_COUNT="$2";       shift 2 ;;
    --keep-namespaces)  DELETE_NAMESPACE="0";   shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

echo "=== MCP Workshop Undeploy ==="

for i in $(seq 1 "$USER_COUNT"); do
  user="${USER_PREFIX}${i}"
  ns="${user}-devspaces"
  release="${ns}-workshop"

  if helm status "$release" -n "$ns" >/dev/null 2>&1; then
    helm uninstall "$release" -n "$ns"
    echo "  ✓ Uninstalled ${release}"
  fi

  if [ "$DELETE_NAMESPACE" = "1" ]; then
    oc delete namespace "$ns" --ignore-not-found --wait=false
    echo "  ✓ Deleted namespace ${ns}"
  fi
done

# Clean up shared resources
if [ "$DELETE_NAMESPACE" = "1" ]; then
  echo "--- Cleaning shared resources ---"
  oc delete namespace opencode-build --ignore-not-found --wait=false
  echo "  ✓ Deleted opencode-build namespace"
fi

echo ""
echo "=== Undeploy complete ==="
