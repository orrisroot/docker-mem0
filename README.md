# Self-Hosted Mem0 Multi-User Memory Service

A production-ready Docker Compose deployment configuration for self-hosting a multi-user, persistent memory service using [Mem0](https://github.com/mem0ai/mem0), an integrated GPU-accelerated [Ollama](https://ollama.com/) inference engine, and PostgreSQL with the `pgvector` extension.

---

## 1. System Requirements

Before deploying, ensure the target server meets the following requirements:

- **OS**: Linux (Ubuntu, Debian, Rocky Linux, RHEL, etc.)
- **Container Runtime**: Docker Engine (v24+) & Docker Compose (v2.20+)
- **GPU Acceleration**: NVIDIA GPU with [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed (for GPU inference via Ollama)
- **Utilities**: `git`, `curl`, `openssl`, and optionally `make`

---

## 2. Repository vs Runtime Directory Structure

### Tracked in Git Repository
The core repository only tracks lightweight configuration files:

```
.
├── compose.yaml          # Docker Compose specification
├── .env.example          # Sample environment configuration template
├── .gitignore            # Ignores repo/, volumes/, and .env
├── Makefile              # Management shortcuts (make up, make health, etc.)
└── README.md             # Deployment and operational documentation
```

### Generated at Runtime (Ignored by Git)
During deployment and operation, the following runtime directories are created and automatically ignored by `.gitignore`:

```
.
├── .env                  # Generated secrets (passwords, JWT secret)
├── repo/                 # Cloned upstream Mem0 source repository (git clone)
└── volumes/              # Local disk bind mounts for persistence
    ├── ollama/           # Stored model weights
    ├── postgres/         # PostgreSQL 17 + pgvector database files
    └── history/          # Mem0 operational history
```

---

## 3. Step-by-Step Deployment Guide

Follow these steps on your target server to deploy the entire stack from scratch:

### Step 1: Clone this Deployment Repository
```bash
git clone <your-deployment-repo-url> mem0-service
cd mem0-service
```

### Step 2: Clone the Upstream Mem0 Repository
The `compose.yaml` builds the API server and dashboard from the official Mem0 repository. Clone it into a subfolder named `repo`:

```bash
git clone --depth 1 https://github.com/mem0ai/mem0.git repo
```

### Step 3: Setup Persistent Storage Directories
Create the local bind mount directories on your host filesystem for container persistence:

```bash
mkdir -p volumes/postgres volumes/ollama volumes/history
```

*(Note: The database initialization script `repo/server/init-db.sh` from the cloned Mem0 repository will be automatically mounted to create the `mem0_app` database.)*

### Step 4: Configure Embedding Dimensions in Server Code
By default, upstream Mem0 assumes a 1536-dimensional embedding model (`text-embedding-3-small`). If you plan to use local models like **`bge-m3` (1024-dim)** or **`nomic-embed-text` (768-dim)**, apply this configuration so `repo/server/main.py` reads `MEM0_DEFAULT_EMBEDDER_DIMS` from `.env`:

```bash
# Add MEM0_DEFAULT_EMBEDDER_DIMS support to repo/server/main.py
sed -i '/DEFAULT_EMBEDDER_MODEL =/a DEFAULT_EMBEDDER_DIMS = int(os.environ.get("MEM0_DEFAULT_EMBEDDER_DIMS", "1536"))' repo/server/main.py
sed -i '/"collection_name": POSTGRES_COLLECTION_NAME,/a \            "embedding_model_dims": DEFAULT_EMBEDDER_DIMS,' repo/server/main.py
sed -i 's/"model": DEFAULT_EMBEDDER_MODEL/&, "embedding_dims": DEFAULT_EMBEDDER_DIMS/' repo/server/main.py
```

### Step 5: Configure Environment Secrets (`.env`)
Create your `.env` file from the example template and generate secure random secrets:

```bash
cp .env.example .env
chmod 600 .env

# Generate random secrets and inject into .env
POSTGRES_PW=$(openssl rand -hex 20)
JWT_SEC=$(openssl rand -hex 32)

sed -i "s/your_secure_postgres_password_here/$POSTGRES_PW/" .env
sed -i "s/your_secure_jwt_secret_here/$JWT_SEC/" .env
```

Verify your `.env` settings:
- `MEM0_DEFAULT_LLM_MODEL=qwen2.5:7b`
- `MEM0_DEFAULT_EMBEDDER_MODEL=bge-m3`
- `MEM0_DEFAULT_EMBEDDER_DIMS=1024`
- `OPENAI_BASE_URL=http://ollama:11434/v1`
- `OPENAI_API_KEY=ollama`

### Step 6: Build and Start Containers
Build and launch all services in detached mode:

```bash
docker compose up -d --build
# or using make:
# make up
```

### Step 7: Pull Required Models into Ollama
Download the LLM (for fact extraction) and Embedder (for semantic search) into the bundled Ollama instance:

```bash
# Pull fact-extraction LLM
docker compose exec -T ollama ollama pull qwen2.5:7b

# Pull multilingual embedding model (1024-dim)
docker compose exec -T ollama ollama pull bge-m3

# or using make shortcut:
# make pull-models
```

Verify the downloaded models:
```bash
docker compose exec -T ollama ollama list
```

### Step 8: Initialize Admin Account & API Key
Run the initial seed script to create your administrative account and retrieve your first API key:

```bash
# Execute seed script
cd repo/server && ./scripts/seed.sh && cd ../..
# or using make:
# make seed
```

> [!IMPORTANT]
> The terminal will display the generated **Email**, **Password**, and **API Key**. Store these credentials securely. The API key cannot be displayed again.

### Step 9: Verify Health
Verify that all 4 components are healthy:

```bash
make health
```
Expected output:
```text
Postgres:  OK
Ollama:    OK (GPU)
Mem0 API:  OK (200)
Dashboard: OK (200)
```

---

## 4. Exposed Services & Endpoints

| Service | Container Name | Host Port | Network Exposure | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Mem0 API** | `mem0-mem0-1` | **`8888`** | Public | REST API server (`http://<host>:8888/docs`) |
| **Dashboard** | `mem0-mem0-dashboard-1` | **`3000`** | Public | Web management UI (`http://<host>:3000`) |
| **Ollama** | `mem0-ollama-1` | **`11434`** | Public | Local GPU inference endpoint |
| **PostgreSQL 17** | `mem0-postgres-1` | *None* | Internal Only | `pgvector` store (isolated in `mem0_network`) |

---

## 5. Daily Operations & Management

| Action | `make` Shortcut | Equivalent Docker Compose Command |
| :--- | :--- | :--- |
| **Start stack** | `make up` | `docker compose up -d` |
| **Stop stack** | `make down` | `docker compose down` |
| **Restart stack** | `make restart` | `docker compose restart` |
| **View logs** | `make logs` | `docker compose logs -f` |
| **Check health** | `make health` | Check container endpoints |
| **List models** | `make list-models` | `docker compose exec -T ollama ollama list` |
| **Pull models** | `make pull-models` | `docker compose exec -T ollama ollama pull <model>` |
| **Reset password**| `make reset-admin-password EMAIL=.. PASSWORD=..` | `docker compose exec -T mem0 python scripts/reset_admin_password.py` |
| **Recreate API** | - | `docker compose up -d --force-recreate mem0` |

---

## 6. API Usage Examples

Replace `<your-server-host>` and `<your-api-key>` with your deployment's values.

### Adding Memories (cURL)
```bash
curl -X POST http://<your-server-host>:8888/memories \
  -H "X-API-Key: <your-api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "I specialize in backend engineering using Go and PostgreSQL."}
    ],
    "user_id": "alice"
  }'
```

### Searching Memories (cURL)
```bash
curl -X POST http://<your-server-host>:8888/search \
  -H "X-API-Key: <your-api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What technologies does Alice use?",
    "user_id": "alice"
  }'
```

### Python Integration Example
```python
import requests

API_URL = "http://<your-server-host>:8888"
API_KEY = "<your-api-key>"

headers = {
    "X-API-Key": API_KEY,
    "Content-Type": "application/json"
}

# 1. Add conversation turns
requests.post(
    f"{API_URL}/memories",
    headers=headers,
    json={
        "messages": [{"role": "user", "content": "Production runs on Kubernetes cluster with bge-m3 embeddings."}],
        "user_id": "infra-team"
    }
)

# 2. Semantic Search
res = requests.post(
    f"{API_URL}/search",
    headers=headers,
    json={
        "query": "What embeddings does production use?",
        "user_id": "infra-team"
    }
)
print("Search Results:", res.json())
```
