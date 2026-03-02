# Get Started: NVIDIA RAG Blueprint on RTX 4070

This guide gets you running the NVIDIA RAG Blueprint on a **Core i9 + RTX 4070** workstation. The RTX 4070's 12GB VRAM is dedicated entirely to the local GPU-accelerated vector database — all AI models (LLM, embeddings, reranker) run in the NVIDIA API Catalog cloud, so you're up and running in under 10 minutes with no model downloads.

## What You'll Deploy

| Component | Where it runs |
| --------- | ------------- |
| LLM (`nvidia/llama-3.3-nemotron-super-49b-v1.5`) | NVIDIA API Catalog |
| Embeddings (`nvidia/llama-3.2-nv-embedqa-1b-v2`) | NVIDIA API Catalog |
| Reranker (`nvidia/llama-3.2-nv-rerankqa-1b-v2`) | NVIDIA API Catalog |
| Vector DB (Milvus + cuVS GPU_CAGRA index) | Local RTX 4070 |
| Supporting services (Redis, MinIO) | Local CPU |

## Management Script

A convenience script handles setup, deployment, and monitoring in one place:

```bash
# Make executable once
chmod +x scripts/rag-nvidia-hosted.sh

export NGC_API_KEY="nvapi-..."

./scripts/rag-nvidia-hosted.sh setup    # check prerequisites, install toolkit, NGC login
./scripts/rag-nvidia-hosted.sh start    # source env, deploy, wait for health, print URLs
./scripts/rag-nvidia-hosted.sh status   # containers, API health, GPU usage
./scripts/rag-nvidia-hosted.sh logs     # tail all logs  (or: logs <service-name>)
./scripts/rag-nvidia-hosted.sh stop     # stop services, keep data
./scripts/rag-nvidia-hosted.sh clean    # stop services, remove all data
```

The manual steps below explain what each command does if you prefer to run them yourself.

## Prerequisites

- **OS**: Ubuntu 22.04 recommended (or WSL2 on Windows)
- **GPU**: RTX 4070 (12GB VRAM) with latest NVIDIA drivers — `nvidia-smi` must work
- **Docker Engine** 24.0+ with [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- **Docker Compose** v2.29.1 or later (`docker compose version`)
- **~50GB free disk space**

## Step 1: Get an NVIDIA API Key

1. Go to [https://org.ngc.nvidia.com/setup/api-keys](https://org.ngc.nvidia.com/setup/api-keys)
2. Click **Generate Personal Key**
3. Name it, set expiration to **Never Expire**, and select **NGC Catalog** + **Public API Endpoints**
4. Copy the key and export it in your terminal:

```bash
export NGC_API_KEY="nvapi-..."
```

## Step 2: Authenticate with the NGC Container Registry

```bash
echo "${NGC_API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin
```

## Step 3: Clone the Repository

```bash
git clone https://github.com/NVIDIA-AI-Blueprints/rag.git
cd rag
```

## Step 4: Configure and Deploy

Source the NVIDIA-hosted cuVS environment file, then start all services:

```bash
source deploy/compose/nvidia-hosted-cuvs.env
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml up -d
```

This starts Milvus (cuVS/GPU), etcd, MinIO, Redis, the ingestor server, RAG server, and the frontend UI.

First-time startup takes **5–10 minutes** while Docker pulls container images. No model downloads are required.

## Step 5: Verify the Deployment

```bash
# Check all containers are running
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

# Check RAG server health
curl -s 'http://localhost:8081/v1/health?check_dependencies=true' | python3 -m json.tool

# Check ingestor server health
curl -s 'http://localhost:8082/v1/health?check_dependencies=true' | python3 -m json.tool
```

A healthy RAG server response looks like:

```json
{
    "message": "Service is up.",
    "nim": [
        {"service": "LLM", "status": "healthy", "message": "Using NVIDIA API Catalog"},
        {"service": "Embeddings", "status": "healthy", "message": "Using NVIDIA API Catalog"},
        {"service": "Ranking", "status": "healthy", "message": "Using NVIDIA API Catalog"}
    ]
}
```

## Step 6: Ingest Documents and Query

### Using the Web UI (easiest)

1. Open [http://localhost:8090](http://localhost:8090) in your browser
2. Click **New Collection** and upload your documents
3. Supported formats: PDF, DOCX, PPTX, TXT, MD, HTML, PNG, JPEG, MP3, WAV, MP4
4. Select the collection and ask a question

### Using the API

Upload a document:

```bash
curl -X POST 'http://localhost:8082/v1/documents' \
  -H 'accept: application/json' \
  -F 'file=@/path/to/your/document.pdf'
```

Query your documents:

```bash
curl -X POST 'http://localhost:8081/v1/chat' \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [{"role": "user", "content": "Summarize the key points in my document."}]
  }'
```

## Service URLs

| Service | URL |
| ------- | --- |
| Web UI | <http://localhost:8090> |
| RAG Server API | <http://localhost:8081> |
| Ingestor Server API | <http://localhost:8082> |
| Milvus (vector DB) | `localhost:19530` |

## Network Access (Serve to Other Devices)

Docker already binds all ports to `0.0.0.0`, and the frontend runs a server-side reverse proxy that resolves the backend services internally — so remote browsers only need to reach **port 8090**. You don't need to reconfigure any API URLs.

### 1. Find Your Machine's IP

```bash
hostname -I | awk '{print $1}'
```

Use this IP (e.g., `192.168.1.50`) when accessing from other devices.

### 2. Open the Firewall

```bash
# Web UI (required)
sudo ufw allow 8090/tcp

# Direct API access from other machines (optional)
sudo ufw allow 8081/tcp   # RAG server
sudo ufw allow 8082/tcp   # Ingestor server

sudo ufw reload
sudo ufw status
```

### 3. Access from Other Devices

Replace `192.168.1.50` with your actual IP:

| What | URL |
| ---- | --- |
| Web UI | `http://192.168.1.50:8090` |
| RAG Server API | `http://192.168.1.50:8081` |
| Ingestor Server API | `http://192.168.1.50:8082` |

The frontend proxies all `/api/*` calls back through Docker's internal network to the backend services, so **no extra configuration is needed** — just open the browser on another device and go.

> **Note:** This exposes services on your local network without authentication. Only do this on a trusted private network.

## Stop / Clean Up

```bash
# Stop services (keeps data volumes)
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml down

# Stop and remove all data
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml down -v
```

## Troubleshooting

### GPU not detected in containers

```bash
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

### Milvus fails to start

Check logs for GPU memory errors (RTX 4070 needs ~2–4GB free VRAM for the cuVS index):

```bash
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml logs milvus
```

### API key errors

The env file maps `NGC_API_KEY` → `NVIDIA_API_KEY`. Make sure the key is exported *before* sourcing the env file:

```bash
echo $NGC_API_KEY   # must not be empty
source deploy/compose/nvidia-hosted-cuvs.env
```

### Rate limiting on ingestion

The NVIDIA API Catalog enforces per-key rate limits. If ingesting many files, process them in smaller batches of 5–10 files at a time.

### View logs for any service

```bash
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml logs -f rag-server
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml logs -f ingestor-server
```

## Next Steps

- [Full deployment reference](deploy-docker-nvidia-hosted-cuvs.md)
- [Switch to self-hosted NIMs](deploy-docker-self-hosted.md) (requires 4–5 GPUs)
- [API reference — RAG server](api-rag.md)
- [API reference — Ingestor server](api-ingestor.md)
- [Configure models and settings](change-model.md)
