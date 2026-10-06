.PHONY: up down restart clean logs build health seed reset-admin-password prune-logs pull-models list-models patch

-include .env
export

API_PORT ?= $(or $(MEM0_PORT),8888)
DASHBOARD_PORT ?= 3000
API_SUBPATH ?= $(MEM0_ROOT_PATH)
DASHBOARD_SUBPATH ?= $(DASHBOARD_BASE_PATH)

API_URL ?= $(or $(API_URL),$(DASHBOARD_API_URL),http://localhost:$(API_PORT)$(API_SUBPATH))
DASHBOARD_URL ?= $(or $(DASHBOARD_URL),http://localhost:$(DASHBOARD_PORT)$(DASHBOARD_SUBPATH))
LLM_MODEL ?= $(or $(MEM0_DEFAULT_LLM_MODEL),qwen2.5:7b)
EMBEDDER_MODEL ?= $(or $(MEM0_DEFAULT_EMBEDDER_MODEL),bge-m3)

patch:
	@chmod +x scripts/patch-repo.sh && ./scripts/patch-repo.sh

up:
	docker compose up -d
	@echo "Mem0 stack is starting..."
	@echo "  Dashboard: $(DASHBOARD_URL)"
	@echo "  API Docs:  $(API_URL)/docs"

down:
	docker compose down

restart:
	docker compose restart

clean:
	docker compose down -v

logs:
	docker compose logs -f

build:
	docker compose build

health:
	@echo -n "Postgres:  "
	@docker compose exec -T postgres pg_isready -q && echo "OK" || echo "Down"
	@echo -n "Ollama:    "
	@docker compose exec -T ollama ollama list >/dev/null 2>&1 && echo "OK (GPU)" || echo "Down"
	@echo -n "Mem0 API:  "
	@code=$$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$(API_PORT)/docs"); \
	if [ "$$code" = "200" ]; then echo "OK (200)"; else \
	  code=$$(curl -s -o /dev/null -w '%{http_code}' "$(API_URL)/docs"); \
	  [ "$$code" = "200" ] && echo "OK (200)" || echo "Down ($$code)"; \
	fi
	@echo -n "Dashboard: "
	@code=$$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$(DASHBOARD_PORT)$(DASHBOARD_SUBPATH)/api/health"); \
	if [ "$$code" = "200" ]; then echo "OK (200)"; else \
	  code=$$(curl -s -o /dev/null -w '%{http_code}' "$(DASHBOARD_URL)/api/health"); \
	  [ "$$code" = "200" ] && echo "OK (200)" || echo "Down ($$code)"; \
	fi

pull-models:
	@echo "Pulling LLM model ($(LLM_MODEL))..."
	docker compose exec -T ollama ollama pull $(LLM_MODEL)
	@echo "Pulling Embedder model ($(EMBEDDER_MODEL))..."
	docker compose exec -T ollama ollama pull $(EMBEDDER_MODEL)
	@echo "Models loaded successfully:"
	@docker compose exec -T ollama ollama list

list-models:
	docker compose exec -T ollama ollama list

seed:
	@cd repo/server && API_URL="$(API_URL)" DASHBOARD_URL="$(DASHBOARD_URL)" ./scripts/seed.sh

reset-admin-password:
	@test -n "$(EMAIL)" || (echo "usage: make reset-admin-password EMAIL=<email> PASSWORD=<password>" && exit 2)
	@test -n "$(PASSWORD)" || (echo "usage: make reset-admin-password EMAIL=<email> PASSWORD=<password>" && exit 2)
	@docker compose exec -T -e EMAIL="$(EMAIL)" -e PASSWORD="$(PASSWORD)" -e PYTHONPATH=/app mem0 python scripts/reset_admin_password.py

prune-logs:
	@docker compose exec -T -e REQUEST_LOG_RETENTION_DAYS="30" -e PYTHONPATH=/app mem0 python scripts/prune_request_logs.py
