.PHONY: help test-local validate build-image deploy expose connect-mcp test-mcp verify verify-mcp clean antora operator preflight dry-run workshop-deploy workshop-deploy-checluster credentials workshop-undeploy ansible-deploy ansible-dry-run

NAMESPACE ?= $(shell oc project -q 2>/dev/null || echo "my-namespace")
SERVER_NAME ?= stock-market-mcp
MCP_SVC_URL = http://$(SERVER_NAME).$(NAMESPACE).svc:8080/mcp

# ---- Workshop deploy variables ----
LLM_URL       ?=
LLM_API_KEY   ?= EMPTY
MODEL_ID      ?=
USER_PREFIX   ?= user
USER_COUNT    ?= 30

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

test-local: ## Run the MCP server locally with mcp dev (Inspector)
	cd scaffold && uv run mcp dev server.py

validate: ## Validate scaffold files exist and are well-formed
	@echo "==> Checking server.py exists..."
	@test -f scaffold/server.py && echo "PASS: server.py found" || (echo "FAIL: scaffold/server.py not found"; exit 1)
	@echo "==> Checking requirements.txt..."
	@test -f scaffold/requirements.txt && echo "PASS: requirements.txt found" || (echo "FAIL: scaffold/requirements.txt not found"; exit 1)
	@echo "==> Checking Containerfile..."
	@test -f scaffold/Containerfile && echo "PASS: Containerfile found" || (echo "FAIL: scaffold/Containerfile not found"; exit 1)
	@echo "==> Checking deployment.yaml..."
	@test -f scaffold/deployment.yaml && echo "PASS: deployment.yaml found" || (echo "FAIL: scaffold/deployment.yaml not found"; exit 1)
	@echo "==> All checks passed."

build-image: ## Build container image via oc new-build (handles Dockerfile)
	@cd scaffold && if [ -f Containerfile ] && [ ! -f Dockerfile ]; then \
		cp Containerfile Dockerfile; \
		echo "Copied Containerfile → Dockerfile (required by oc build)"; \
	fi
	cd scaffold && oc new-build --binary --name=$(SERVER_NAME) --strategy=docker -n $(NAMESPACE) 2>/dev/null || true
	cd scaffold && oc start-build $(SERVER_NAME) --from-dir=. --follow -n $(NAMESPACE)

deploy: ## Deploy MCP server to OpenShift (build + service + route)
	@cd scaffold && if [ -f deployment.yaml ]; then \
		sed 's|MY_NAMESPACE|$(NAMESPACE)|g' deployment.yaml | oc apply -n $(NAMESPACE) -f -; \
	else \
		oc new-app $(SERVER_NAME) -n $(NAMESPACE); \
	fi
	oc rollout status deployment/$(SERVER_NAME) -n $(NAMESPACE) --timeout=120s

expose: ## Create external route for the MCP server
	@oc get route $(SERVER_NAME) -n $(NAMESPACE) >/dev/null 2>&1 && \
		echo "Route already exists" || \
		oc expose svc/$(SERVER_NAME) --port=8080 -n $(NAMESPACE)
	@echo "Route: http://$$(oc get route $(SERVER_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.host}')/mcp"

connect-mcp: ## Register deployed MCP server in OpenCode
	@opencode mcp add $(SERVER_NAME) --url "$(MCP_SVC_URL)" 2>/dev/null || \
		echo "MCP server already registered or opencode not available"
	@opencode mcp list 2>/dev/null || true
	@echo ""
	@echo "Start a NEW OpenCode session to use the MCP tools."

test-mcp: ## Test the deployed MCP endpoint (initialize + tools/list)
	@ROUTE=$$(oc get route $(SERVER_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.host}' 2>/dev/null); \
	if [ -z "$$ROUTE" ]; then \
		echo "No route found — testing via internal service..."; \
		SVC_IP=$$(oc get svc $(SERVER_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.clusterIP}' 2>/dev/null); \
		ROUTE="$$SVC_IP:8080"; \
	fi; \
	echo "==> MCP initialize..."; \
	HDRFILE=$$(mktemp); \
	INIT=$$(curl -sD "$$HDRFILE" -X POST "http://$$ROUTE/mcp" \
		-H "Content-Type: application/json" \
		-d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'); \
	echo "$$INIT" | head -c 200; echo; \
	echo "$$INIT" | grep -q '"result"' && echo "PASS: MCP initialize" || echo "FAIL: MCP initialize"; \
	echo "==> MCP tools/list..."; \
	SESSION=$$(grep -i 'mcp-session-id' "$$HDRFILE" | tr -d '\r' | awk '{print $$2}'); \
	rm -f "$$HDRFILE"; \
	TOOLS=$$(curl -s -X POST "http://$$ROUTE/mcp" \
		-H "Content-Type: application/json" \
		-H "Mcp-Session-Id: $$SESSION" \
		-d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'); \
	TOOL_COUNT=$$(echo "$$TOOLS" | grep -o '"name"' | wc -l); \
	echo "Tools found: $$TOOL_COUNT"; \
	[ "$$TOOL_COUNT" -ge 9 ] && echo "PASS: all 9 tools registered" || echo "FAIL: expected 9 tools, got $$TOOL_COUNT"

verify: ## Verify deployment is ready and service is reachable
	@echo "==> Checking deployment..."
	@oc get deployment $(SERVER_NAME) -n $(NAMESPACE) -o jsonpath='{.status.readyReplicas}' | grep -q "1" && \
		echo "PASS: deployment ready" || (echo "FAIL: deployment not ready"; exit 1)
	@echo "==> Checking service..."
	@oc get service $(SERVER_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.ports[0].port}' | grep -q "8080" && \
		echo "PASS: service port 8080" || (echo "FAIL: service not found or wrong port"; exit 1)
	@echo "==> Checking route..."
	@oc get route $(SERVER_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.host}' 2>/dev/null && echo " — PASS: route exists" || echo "WARN: no route (run: make expose)"
	@echo "==> Checking pod logs for startup..."
	@oc logs deployment/$(SERVER_NAME) -n $(NAMESPACE) --tail=5 2>/dev/null | head -3
	@echo "==> Deployment verified."

verify-mcp: verify test-mcp ## Full verification: deployment + MCP protocol test

clean: ## Delete ALL MCP server resources (deployment, build, route, MCP registration)
	oc delete route $(SERVER_NAME) -n $(NAMESPACE) --ignore-not-found
	oc delete -f scaffold/deployment.yaml -n $(NAMESPACE) --ignore-not-found 2>/dev/null || true
	oc delete deployment $(SERVER_NAME) -n $(NAMESPACE) --ignore-not-found 2>/dev/null || true
	oc delete svc $(SERVER_NAME) -n $(NAMESPACE) --ignore-not-found 2>/dev/null || true
	oc delete bc $(SERVER_NAME) -n $(NAMESPACE) --ignore-not-found
	oc delete is $(SERVER_NAME) -n $(NAMESPACE) --ignore-not-found
	@echo "All $(SERVER_NAME) resources cleaned up."

antora: ## Build the workshop site locally
	npx antora site.yml
	@echo "Site built in ./www — open www/modules/index.html"

# ==== Facilitator: Workshop Infrastructure ====

operator: ## Install DevSpaces operator (cluster-admin required)
	oc apply -f deploy/operator.yaml
	@echo "Waiting for DevSpaces operator CSV..."
	@oc wait csv -n openshift-operators \
		-l operators.coreos.com/devspaces.openshift-operators \
		--for=jsonpath='{.status.phase}'=Succeeded --timeout=300s 2>/dev/null || \
		echo "⚠ Operator not ready yet — check: oc get csv -n openshift-operators | grep devspaces"
	@echo "Waiting for DevWorkspace CRD..."
	@for i in $$(seq 1 30); do \
		oc api-resources --api-group=workspace.devfile.io 2>/dev/null | grep -q devworkspaces && break; \
		sleep 10; \
	done
	@oc api-resources --api-group=workspace.devfile.io 2>/dev/null | grep -q devworkspaces && \
		echo "✓ DevWorkspace CRD ready" || echo "⚠ DevWorkspace CRD not found yet"

preflight: ## Run pre-flight checks (LLM_URL=, MODEL_ID= optional)
	LLM_URL="$(LLM_URL)" MODEL_ID="$(MODEL_ID)" deploy/preflight.sh

dry-run: ## Helm dry-run for first user (LLM_URL=, MODEL_ID= required)
	@if [ -z "$(LLM_URL)" ]; then echo "ERROR: LLM_URL is required"; exit 1; fi
	@if [ -z "$(MODEL_ID)" ]; then echo "ERROR: MODEL_ID is required"; exit 1; fi
	helm template $(USER_PREFIX)1-devspaces-workshop chart/ \
		--namespace $(USER_PREFIX)1-devspaces \
		--set llm.baseUrl=$(LLM_URL) \
		--set llm.apiKey=$(LLM_API_KEY) \
		--set llm.modelId=$(MODEL_ID) \
		--set user.name=$(USER_PREFIX)1 \
		--set cheCluster.create=true
	@echo ""
	@echo "--- Dry run complete — review the YAML above before deploying ---"

workshop-deploy: ## Deploy workshop DevSpaces for N participants (LLM_URL=, MODEL_ID= required)
	@if [ -z "$(LLM_URL)" ]; then echo "ERROR: LLM_URL is required"; exit 1; fi
	@if [ -z "$(MODEL_ID)" ]; then echo "ERROR: MODEL_ID is required"; exit 1; fi
	LLM_URL="$(LLM_URL)" LLM_API_KEY="$(LLM_API_KEY)" MODEL_ID="$(MODEL_ID)" \
		USER_PREFIX="$(USER_PREFIX)" USER_COUNT="$(USER_COUNT)" \
		CHART_DIR=chart \
		deploy/workshop-deploy.sh

workshop-deploy-checluster: ## Deploy with CheCluster creation (first time on bare cluster)
	@if [ -z "$(LLM_URL)" ]; then echo "ERROR: LLM_URL is required"; exit 1; fi
	@if [ -z "$(MODEL_ID)" ]; then echo "ERROR: MODEL_ID is required"; exit 1; fi
	LLM_URL="$(LLM_URL)" LLM_API_KEY="$(LLM_API_KEY)" MODEL_ID="$(MODEL_ID)" \
		USER_PREFIX="$(USER_PREFIX)" USER_COUNT="$(USER_COUNT)" \
		CREATE_CHECLUSTER=true CHART_DIR=chart \
		deploy/workshop-deploy.sh

credentials: ## Generate credentials cards for all participants
	USER_PREFIX="$(USER_PREFIX)" USER_COUNT="$(USER_COUNT)" \
		deploy/credentials.sh

workshop-undeploy: ## Remove all workshop DevSpaces and namespaces
	USER_PREFIX="$(USER_PREFIX)" USER_COUNT="$(USER_COUNT)" \
		deploy/workshop-undeploy.sh

# ==== Ansible (alternative to shell scripts) ====

ansible-deploy: ## Deploy via Ansible playbook (requires deploy/vars.yml)
	@test -f deploy/vars.yml || (echo "ERROR: deploy/vars.yml not found. Copy deploy/vars.example.yml and fill in values."; exit 1)
	ansible-playbook deploy/playbook.yml -e @deploy/vars.yml

ansible-dry-run: ## Ansible dry-run — check mode, no changes (requires deploy/vars.yml)
	@test -f deploy/vars.yml || (echo "ERROR: deploy/vars.yml not found. Copy deploy/vars.example.yml and fill in values."; exit 1)
	ansible-playbook deploy/playbook.yml -e @deploy/vars.yml --check -v
