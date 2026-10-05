.PHONY: up down restart clean logs build health seed reset-admin-password prune-logs pull-models list-models

API_URL ?= http://localhost:8888
DASHBOARD_URL ?= http://localhost:3000
LLM_MODEL ?= qwen2.5:7b
EMBEDDER_MODEL ?= bge-m3

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
	@test "$$(curl -s -o /dev/null -w '%{http_code}' "$(API_URL)/docs")" = "200" && echo "OK (200)" || echo "Down"
	@echo -n "Dashboard: "
	@test "$$(curl -s -o /dev/null -w '%{http_code}' "$(DASHBOARD_URL)/api/health")" = "200" && echo "OK (200)" || echo "Down"

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
