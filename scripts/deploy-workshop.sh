#!/usr/bin/env bash
#
# Deploy the MCP Developer Workshop for N participants.
#
# What this does (in order):
#   1. Validates prerequisites (oc, helm, yq, htpasswd, python3)
#   2. Creates N DevSpaces via PCA Helm chart (namespaces, RBAC, secrets, DevWorkspaces)
#   3. Configures HTPasswd logins for all N users
#   4. Creates the rhoai-api-key secret in each namespace (same key for all)
#   5. Creates workshop-edit RBAC in each namespace
#   6. Patches each DevWorkspace with workshop config, skills, and startup fixes
#   7. Restarts all DevWorkspaces
#   8. Verifies everything
#
# Prerequisites:
#   - oc CLI authenticated as cluster-admin
#   - helm, yq, htpasswd, python3 (with PyYAML)
#   - PCA repo cloned (for Helm charts) — pass via --pca-repo
#   - RHOAI MaaS API key — pass via --api-key or RHOAI_API_KEY env var
#
# Usage:
#   ./scripts/deploy-workshop.sh \
#     --participants 20 \
#     --pca-repo ~/workspace/private-coding-assistant \
#     --api-key "$RHOAI_API_KEY"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Defaults ────────────────────────────────────────────────────
PARTICIPANTS=1
NS_PREFIX="dev-user"
PCA_REPO=""
API_KEY="${RHOAI_API_KEY:-}"
VALUES_FILE="${REPO_ROOT}/workshop-values.yaml"
AI_NAMESPACE="private-assistant-ai-serving"
DW_NAME="code-workspace-1"
DRY_RUN=false
SKIP_PCA=false

# ── Colours ─────────────────────────────────────────────────────
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; NC='\033[0m'
info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$1"; }
pass()  { printf "${GREEN}[DONE]${NC}  %s\n" "$1"; }
fail()  { printf "${RED}[FAIL]${NC}  %s\n" "$1"; exit 1; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
header() { printf "\n${GREEN}═══════════════════════════════════════════════════════${NC}\n"; printf "${GREEN}  %s${NC}\n" "$1"; printf "${GREEN}═══════════════════════════════════════════════════════${NC}\n\n"; }

# ── CLI Args ────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Required:
  --participants N      Number of workshop participants (e.g. 20)
  --pca-repo PATH       Path to private-coding-assistant repo (for Helm charts)
  --api-key KEY         RHOAI MaaS API key (or set RHOAI_API_KEY env var)

Optional:
  --values FILE         Workshop values file (default: workshop-values.yaml)
  --namespace-prefix P  Namespace prefix (default: dev-user)
  --ai-namespace NS     AI serving namespace (default: private-assistant-ai-serving)
  --skip-pca            Skip PCA DevSpace creation (already deployed)
  --dry-run             Print what would be done, don't apply
  --help                Show this help

Examples:
  # Fresh deploy for 20 users
  $0 --participants 20 --pca-repo ~/workspace/private-coding-assistant --api-key "sk-oai-..."

  # Workshop overlay only (PCA already deployed N=20)
  $0 --participants 20 --pca-repo ~/workspace/private-coding-assistant --api-key "sk-oai-..." --skip-pca
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --participants)       PARTICIPANTS="$2"; shift 2 ;;
        --pca-repo)           PCA_REPO="$2"; shift 2 ;;
        --api-key)            API_KEY="$2"; shift 2 ;;
        --values)             VALUES_FILE="$2"; shift 2 ;;
        --namespace-prefix)   NS_PREFIX="$2"; shift 2 ;;
        --ai-namespace)       AI_NAMESPACE="$2"; shift 2 ;;
        --skip-pca)           SKIP_PCA=true; shift ;;
        --dry-run)            DRY_RUN=true; shift ;;
        --help)               usage ;;
        *)                    fail "Unknown option: $1" ;;
    esac
done

# ═══════════════════════════════════════════════════════════════
# PHASE 0: Validate everything before touching the cluster
# ═══════════════════════════════════════════════════════════════
header "Phase 0: Validating prerequisites"

[[ "$PARTICIPANTS" =~ ^[1-9][0-9]*$ ]] || fail "--participants must be a positive integer (got: $PARTICIPANTS)"
[ -z "$API_KEY" ] && fail "Missing --api-key (or set RHOAI_API_KEY env var)"
[ -f "$VALUES_FILE" ] || fail "Values file not found: $VALUES_FILE"

if [ "$SKIP_PCA" = false ]; then
    [ -z "$PCA_REPO" ] && fail "Missing --pca-repo (path to private-coding-assistant)"
    [ -d "$PCA_REPO/charts/pca-devspaces" ] || fail "PCA charts not found at $PCA_REPO/charts/pca-devspaces"
    [ -f "$PCA_REPO/deploy_existing_openshift/values-devspaces.yaml" ] || fail "PCA values not found"
fi

for tool in oc helm python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required but not found"
done

if [ "$SKIP_PCA" = false ]; then
    for tool in yq htpasswd; do
        command -v "$tool" >/dev/null 2>&1 || fail "$tool is required for PCA deploy (install it or use --skip-pca)"
    done
fi

python3 -c "import yaml" 2>/dev/null || fail "Python PyYAML is required: pip3 install pyyaml"

oc whoami >/dev/null 2>&1 || fail "Not logged in to OpenShift. Run 'oc login' first."
CLUSTER=$(oc whoami --show-server 2>/dev/null)

info "Participants:  $PARTICIPANTS"
info "Cluster:       $CLUSTER"
info "PCA repo:      ${PCA_REPO:-N/A (--skip-pca)}"
info "Values:        $VALUES_FILE"
info "API key:       ${API_KEY:0:8}...$(echo "$API_KEY" | tail -c 5)"
info "AI namespace:  $AI_NAMESPACE"
[ "$DRY_RUN" = true ] && warn "DRY RUN — no changes will be applied"

pass "Prerequisites validated"

# ═══════════════════════════════════════════════════════════════
# PHASE 1: Create DevSpaces via PCA Helm chart
# ═══════════════════════════════════════════════════════════════
if [ "$SKIP_PCA" = false ]; then
    header "Phase 1: Creating $PARTICIPANTS DevSpaces via PCA"

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would run: make devspace-deploy-existing-openshift N=$PARTICIPANTS"
        info "[DRY RUN] Would run: make setup-idp"
    else
        cd "$PCA_REPO"
        info "Deploying $PARTICIPANTS DevSpaces (parallel)..."
        make devspace-deploy-existing-openshift N="$PARTICIPANTS"
        pass "DevSpaces deployed"

        info "Configuring HTPasswd logins..."
        make setup-idp
        pass "HTPasswd IDP configured"

        cd "$REPO_ROOT"
    fi
else
    header "Phase 1: Skipped (--skip-pca)"
    info "Assuming PCA already deployed $PARTICIPANTS DevSpaces"
fi

# ═══════════════════════════════════════════════════════════════
# PHASE 2: Wait for all DevWorkspaces to be Running
# ═══════════════════════════════════════════════════════════════
header "Phase 2: Waiting for DevWorkspaces to be Running"

if [ "$DRY_RUN" = false ]; then
    MAX_WAIT=300  # 5 minutes
    WAITED=0
    while true; do
        ALL_RUNNING=true
        for i in $(seq 1 "$PARTICIPANTS"); do
            NS="${NS_PREFIX}${i}-devspaces"
            STATE=$(oc get devworkspace "$DW_NAME" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
            if [ "$STATE" != "Running" ]; then
                ALL_RUNNING=false
                break
            fi
        done

        if [ "$ALL_RUNNING" = true ]; then
            pass "All $PARTICIPANTS DevWorkspaces are Running"
            break
        fi

        if [ "$WAITED" -ge "$MAX_WAIT" ]; then
            warn "Timeout after ${MAX_WAIT}s — some DevWorkspaces not Running yet"
            for i in $(seq 1 "$PARTICIPANTS"); do
                NS="${NS_PREFIX}${i}-devspaces"
                STATE=$(oc get devworkspace "$DW_NAME" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                [ "$STATE" != "Running" ] && warn "  $NS: $STATE"
            done
            fail "Cannot proceed until all DevWorkspaces are Running"
        fi

        printf "."
        sleep 10
        WAITED=$((WAITED + 10))
    done
else
    info "[DRY RUN] Would wait for all DevWorkspaces to reach Running state"
fi

# ═══════════════════════════════════════════════════════════════
# PHASE 3: Create secrets + RBAC + patch DevWorkspaces
# ═══════════════════════════════════════════════════════════════
header "Phase 3: Applying workshop overlay to $PARTICIPANTS DevWorkspaces"

FAILED_USERS=()
LOG_DIR=$(mktemp -d)

apply_workshop_overlay() {
    local i="$1"
    local user="${NS_PREFIX}${i}"
    local ns="${user}-devspaces"
    local log="${LOG_DIR}/${user}.log"

    {
        echo "=== $user ($ns) ==="

        # 3a. Create rhoai-api-key secret (same key for all)
        if oc get secret rhoai-api-key -n "$ns" >/dev/null 2>&1; then
            oc delete secret rhoai-api-key -n "$ns"
        fi
        oc create secret generic rhoai-api-key \
            --from-literal=api-key="$API_KEY" \
            -n "$ns"
        echo "  Secret created"

        # 3b. Create workshop-edit RBAC
        if ! oc get rolebinding workshop-edit -n "$ns" >/dev/null 2>&1; then
            oc create rolebinding workshop-edit \
                --clusterrole=edit \
                --group="system:serviceaccounts:${ns}" \
                -n "$ns"
            echo "  RBAC created"
        else
            echo "  RBAC exists"
        fi

        # 3c. Generate and apply DevWorkspace patch
        PATCH=$(python3 "${REPO_ROOT}/scripts/generate-dw-patch.py" \
            --namespace "$ns" \
            --devworkspace "$DW_NAME" \
            --values "$VALUES_FILE")

        echo "$PATCH" | oc patch devworkspace "$DW_NAME" -n "$ns" \
            --type merge --patch-file /dev/stdin
        echo "  DevWorkspace patched"

    } > "$log" 2>&1

    return $?
}

if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would create rhoai-api-key secret in $PARTICIPANTS namespaces (same key)"
    info "[DRY RUN] Would create workshop-edit RBAC in $PARTICIPANTS namespaces"
    info "[DRY RUN] Would patch $PARTICIPANTS DevWorkspaces"
else
    PIDS=()
    for i in $(seq 1 "$PARTICIPANTS"); do
        apply_workshop_overlay "$i" &
        PIDS+=("$!")
    done

    # Wait for all patches to complete
    for idx in "${!PIDS[@]}"; do
        i=$((idx + 1))
        user="${NS_PREFIX}${i}"
        if wait "${PIDS[$idx]}"; then
            pass "$user"
        else
            warn "$user FAILED"
            FAILED_USERS+=("$user")
        fi
    done

    if [ ${#FAILED_USERS[@]} -gt 0 ]; then
        warn "Failed users: ${FAILED_USERS[*]}"
        warn "Logs in: $LOG_DIR"
        for u in "${FAILED_USERS[@]}"; do
            echo "--- $u ---"
            cat "${LOG_DIR}/${u}.log"
        done
    fi
fi

# ═══════════════════════════════════════════════════════════════
# PHASE 4: Restart all DevWorkspaces
# ═══════════════════════════════════════════════════════════════
header "Phase 4: Restarting $PARTICIPANTS DevWorkspaces"

if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would stop all DevWorkspaces, wait, then start them"
else
    # Stop all
    info "Stopping all DevWorkspaces..."
    for i in $(seq 1 "$PARTICIPANTS"); do
        NS="${NS_PREFIX}${i}-devspaces"
        oc patch devworkspace "$DW_NAME" -n "$NS" \
            --type merge -p '{"spec":{"started":false}}' 2>/dev/null &
    done
    wait
    pass "Stop signals sent"

    # Wait for all to stop
    info "Waiting for all to stop..."
    sleep 10
    for attempt in $(seq 1 20); do
        ALL_STOPPED=true
        for i in $(seq 1 "$PARTICIPANTS"); do
            NS="${NS_PREFIX}${i}-devspaces"
            STATE=$(oc get devworkspace "$DW_NAME" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            if [ "$STATE" != "Stopped" ] && [ "$STATE" != "Failed" ]; then
                ALL_STOPPED=false
                break
            fi
        done
        if [ "$ALL_STOPPED" = true ]; then
            pass "All DevWorkspaces stopped"
            break
        fi
        printf "."
        sleep 5
    done

    # Start all
    info "Starting all DevWorkspaces..."
    for i in $(seq 1 "$PARTICIPANTS"); do
        NS="${NS_PREFIX}${i}-devspaces"
        oc patch devworkspace "$DW_NAME" -n "$NS" \
            --type merge -p '{"spec":{"started":true}}' 2>/dev/null &
    done
    wait
    pass "Start signals sent"

    # Wait for Running
    info "Waiting for all to be Running (this takes 2-5 minutes)..."
    MAX_WAIT=600  # 10 minutes for 20 pods
    WAITED=0
    while true; do
        RUNNING=0
        for i in $(seq 1 "$PARTICIPANTS"); do
            NS="${NS_PREFIX}${i}-devspaces"
            STATE=$(oc get devworkspace "$DW_NAME" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            [ "$STATE" = "Running" ] && RUNNING=$((RUNNING + 1))
        done

        printf "\r  Running: %d/%d" "$RUNNING" "$PARTICIPANTS"

        if [ "$RUNNING" -eq "$PARTICIPANTS" ]; then
            echo ""
            pass "All $PARTICIPANTS DevWorkspaces are Running"
            break
        fi

        if [ "$WAITED" -ge "$MAX_WAIT" ]; then
            echo ""
            warn "Timeout — $RUNNING/$PARTICIPANTS running after ${MAX_WAIT}s"
            break
        fi

        sleep 10
        WAITED=$((WAITED + 10))
    done
fi

# ═══════════════════════════════════════════════════════════════
# PHASE 5: Verify
# ═══════════════════════════════════════════════════════════════
header "Phase 5: Verification"

if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would verify all $PARTICIPANTS workspaces"
else
    sleep 15  # Give postStart commands time to run

    VERIFIED=0
    ISSUES=()
    for i in $(seq 1 "$PARTICIPANTS"); do
        user="${NS_PREFIX}${i}"
        ns="${user}-devspaces"
        pod=$(oc get pods -n "$ns" --no-headers 2>/dev/null | grep workspace | grep Running | awk '{print $1}' | head -1)

        if [ -z "$pod" ]; then
            ISSUES+=("$user: no running pod")
            continue
        fi

        # Check skills installed
        SKILL_COUNT=$(oc exec -n "$ns" "$pod" -c dev-tools -- \
            bash -c 'ls -d ~/.config/opencode/skills/*/ 2>/dev/null | wc -l' 2>/dev/null || echo "0")

        # Check OpenCode process
        OC_RUNNING=$(oc exec -n "$ns" "$pod" -c dev-tools -- \
            pgrep -x opencode 2>/dev/null | tail -1 || echo "")

        # Check can build
        CAN_BUILD=$(oc exec -n "$ns" "$pod" -c dev-tools -- \
            oc auth can-i create builds 2>/dev/null || echo "no")

        if [ "$SKILL_COUNT" -ge 9 ] && [ -n "$OC_RUNNING" ] && [ "$CAN_BUILD" = "yes" ]; then
            VERIFIED=$((VERIFIED + 1))
        else
            ISSUES+=("$user: skills=$SKILL_COUNT opencode=${OC_RUNNING:-stopped} builds=$CAN_BUILD")
        fi
    done

    pass "Verified: $VERIFIED / $PARTICIPANTS"

    if [ ${#ISSUES[@]} -gt 0 ]; then
        warn "Issues (postStart may still be running — retry in 30s):"
        for issue in "${ISSUES[@]}"; do
            warn "  $issue"
        done
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
header "Workshop Setup Complete"

cat << EOF
  Participants: $PARTICIPANTS
  Namespaces:   ${NS_PREFIX}1-devspaces … ${NS_PREFIX}${PARTICIPANTS}-devspaces
  Logins:       ${NS_PREFIX}1 / Dev1@PCA2026!  …  ${NS_PREFIX}${PARTICIPANTS} / Dev${PARTICIPANTS}@PCA2026!

  LLM endpoint: $(python3 -c "import yaml; print(yaml.safe_load(open('$VALUES_FILE'))['llm']['baseURL'])" 2>/dev/null)
  Model:        $(python3 -c "import yaml; print(yaml.safe_load(open('$VALUES_FILE'))['llm']['modelDisplayName'])" 2>/dev/null)
  API key:      shared across all namespaces (from rhoai-api-key secret)

  How participants access their workspace:
    1. Log in to OpenShift console with their credentials
    2. Open DevSpaces dashboard
    3. Click on code-workspace-1
    4. Navigate to port 4096 (OpenCode Web)
    5. Enter the OpenCode Web password:
       oc get secret opencode-web-password -n <ns> -o jsonpath='{.data.password}' | base64 -d

  To tear down:
    cd $PCA_REPO
    make devspace-undeploy-existing-openshift N=$PARTICIPANTS DELETE_NAMESPACE=1
EOF

[ ${#FAILED_USERS[@]:-0} -gt 0 ] && exit 1

rm -rf "$LOG_DIR"
exit 0
