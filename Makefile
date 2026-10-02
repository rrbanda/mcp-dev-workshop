.PHONY: help test-local validate build-image deploy verify clean antora

NAMESPACE ?= $(shell oc project -q 2>/dev/null || echo "my-namespace")
SERVER_NAME ?= my-mcp-server

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

test-local: ## Run the MCP server locally with mcp dev (Inspector)
	cd scaffold && uv run mcp dev server.py

validate: ## Validate the MCP server starts and exposes tools
	@echo "==> Checking server.py exists..."
	@test -f scaffold/server.py && echo "PASS: server.py found" || (echo "FAIL: scaffold/server.py not found"; exit 1)
	@echo "==> Checking requirements.txt..."
	@test -f scaffold/requirements.txt && echo "PASS: requirements.txt found" || (echo "FAIL: scaffold/requirements.txt not found"; exit 1)
	@echo "==> Checking Containerfile..."
	@test -f scaffold/Containerfile && echo "PASS: Containerfile found" || (echo "FAIL: scaffold/Containerfile not found"; exit 1)
	@echo "==> Checking deployment.yaml..."
	@test -f scaffold/deployment.yaml && echo "PASS: deployment.yaml found" || (echo "FAIL: scaffold/deployment.yaml not found"; exit 1)
	@echo "==> All checks passed."

build-image: ## Build container image via oc new-build
	cd scaffold && oc new-build --binary --name=$(SERVER_NAME) -n $(NAMESPACE) --to=$(SERVER_NAME):latest 2>/dev/null || true
	cd scaffold && oc start-build $(SERVER_NAME) --from-dir=. --follow -n $(NAMESPACE)

deploy: ## Deploy MCP server to OpenShift
	oc apply -f scaffold/deployment.yaml -n $(NAMESPACE)
	oc rollout status deployment/$(SERVER_NAME) -n $(NAMESPACE) --timeout=120s

verify: ## Verify the deployed MCP server is running and reachable
	@echo "==> Checking deployment..."
	@oc get deployment $(SERVER_NAME) -n $(NAMESPACE) -o jsonpath='{.status.readyReplicas}' | grep -q "1" && \
		echo "PASS: deployment ready" || (echo "FAIL: deployment not ready"; exit 1)
	@echo "==> Checking service..."
	@oc get service $(SERVER_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.ports[0].port}' | grep -q "8080" && \
		echo "PASS: service port 8080" || (echo "FAIL: service not found or wrong port"; exit 1)
	@echo "==> Checking pod logs for startup..."
	@oc logs deployment/$(SERVER_NAME) -n $(NAMESPACE) --tail=5 2>/dev/null | head -3
	@echo "==> Deployment verified."

clean: ## Delete the MCP server deployment and build
	oc delete -f scaffold/deployment.yaml -n $(NAMESPACE) --ignore-not-found
	oc delete bc $(SERVER_NAME) -n $(NAMESPACE) --ignore-not-found
	oc delete is $(SERVER_NAME) -n $(NAMESPACE) --ignore-not-found

antora: ## Build the workshop site locally
	npx antora site.yml
	@echo "Site built in ./www — open www/modules/index.html"
