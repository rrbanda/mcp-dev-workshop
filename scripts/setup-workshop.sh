#!/usr/bin/env bash
#
# Facilitator setup script for the MCP Developer Workshop.
#
# Prerequisites:
#   - oc CLI authenticated to the target cluster
#   - Cluster has DevSpaces operator, RHOAI, and GPU operator installed
#   - PCA ai-serving stack is deployed (llm-d + vLLM + MaaS)
#
# Usage:
#   ./scripts/setup-workshop.sh --participants 10 --namespace-prefix dev-user
#
set -euo pipefail

PARTICIPANTS="${PARTICIPANTS:-5}"
NS_PREFIX="${NS_PREFIX:-dev-user}"
AI_NAMESPACE="${AI_NAMESPACE:-ai-serving}"
WORKSHOP_REPO="https://github.com/rrbanda/mcp-dev-workshop.git"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --participants N     Number of participant workspaces (default: 5)
  --namespace-prefix P Namespace prefix (default: dev-user)
  --ai-namespace NS    AI serving namespace (default: ai-serving)
  --help               Show this help

Example:
  $0 --participants 10 --namespace-prefix workshop-user
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --participants) PARTICIPANTS="$2"; shift 2 ;;
        --namespace-prefix) NS_PREFIX="$2"; shift 2 ;;
        --ai-namespace) AI_NAMESPACE="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

info() { printf "\033[36m[INFO]\033[0m %s\n" "$1"; }
pass() { printf "\033[32m[DONE]\033[0m %s\n" "$1"; }
fail() { printf "\033[31m[FAIL]\033[0m %s\n" "$1"; exit 1; }

info "Setting up workshop for $PARTICIPANTS participants"
info "Namespace prefix: $NS_PREFIX"
info "AI namespace: $AI_NAMESPACE"

info "Verifying cluster connectivity..."
oc whoami >/dev/null 2>&1 || fail "Not logged in to cluster. Run 'oc login' first."
CONSOLE=$(oc whoami --show-console 2>/dev/null || echo "unknown")
info "Cluster console: $CONSOLE"

info "Verifying AI serving stack..."
oc get namespace "$AI_NAMESPACE" >/dev/null 2>&1 || fail "Namespace $AI_NAMESPACE not found. Deploy ai-serving first."
VLLM_PODS=$(oc get pods -n "$AI_NAMESPACE" -l app=vllm -o name 2>/dev/null | wc -l | tr -d ' ')
info "vLLM pods in $AI_NAMESPACE: $VLLM_PODS"

info "Verifying DevSpaces operator..."
oc get crd devworkspaces.workspace.devfile.io >/dev/null 2>&1 || fail "DevSpaces CRD not found. Install the operator."

for i in $(seq 1 "$PARTICIPANTS"); do
    USER="${NS_PREFIX}${i}"
    NS="${USER}-devspaces"
    info "--- Setting up participant $i: $USER (namespace: $NS) ---"

    if oc get namespace "$NS" >/dev/null 2>&1; then
        info "Namespace $NS already exists"
    else
        info "Creating namespace $NS"
        oc create namespace "$NS" || fail "Could not create namespace $NS"
    fi

    info "Granting edit role to $USER in $NS"
    oc adm policy add-role-to-user edit "$USER" -n "$NS" 2>/dev/null || true

    info "Granting image-puller from $AI_NAMESPACE"
    oc policy add-role-to-group system:image-puller "system:serviceaccounts:$NS" \
        -n "$AI_NAMESPACE" 2>/dev/null || true

    pass "Participant $USER ready in $NS"
done

cat <<EOF

$(printf '\033[32m')Workshop setup complete!$(printf '\033[0m')

Participants: $PARTICIPANTS
Namespaces:   ${NS_PREFIX}1-devspaces through ${NS_PREFIX}${PARTICIPANTS}-devspaces

Next steps:
  1. Deploy DevWorkspaces for each participant using pca-devspaces chart
     with skills and bash enabled in opencode.json
  2. Share the workshop guide: https://rrbanda.github.io/mcp-dev-workshop/
  3. Provide each participant their login credentials

EOF
