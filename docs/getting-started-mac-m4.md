# Get Started: NVIDIA RAG Blueprint on Mac M4 Pro

This guide gets you running the NVIDIA RAG Blueprint on a **MacBook Pro M4 Pro** (or any Apple Silicon Mac). No NVIDIA GPU is needed — all AI models run in the NVIDIA API Catalog cloud, and the local vector database uses a CPU HNSW index.

> **Note on Rosetta 2:** The NVIDIA Blueprint server images (`rag-server`, `ingestor-server`, `rag-frontend`) are built for `linux/amd64`. Docker Desktop on Apple Silicon runs them via Rosetta 2 translation, which works well for development and testing. Throughput will be lower than on native hardware for CPU-heavy ingestion workloads.

## What You'll Deploy

| Component | Where it runs |
| --------- | ------------- |
| LLM (`nvidia/llama-3.3-nemotron-super-49b-v1.5`) | NVIDIA API Catalog |
| Embeddings (`nvidia/llama-3.2-nv-embedqa-1b-v2`) | NVIDIA API Catalog |
| Reranker (`nvidia/llama-3.2-nv-rerankqa-1b-v2`) | NVIDIA API Catalog |
| Vector DB (Milvus, HNSW CPU index) | Local Mac (CPU) |
| Supporting services (Redis, MinIO) | Local Mac (CPU) |

## Management Script

A convenience script handles setup, deployment, and monitoring:

```bash
chmod +x scripts/rag-mac.sh

export NGC_API_KEY="nvapi-..."

./scripts/rag-mac.sh setup    # check Docker Desktop, NGC login
./scripts/rag-mac.sh start    # source env, deploy, wait for health, print URLs
./scripts/rag-mac.sh status   # containers and API health
./scripts/rag-mac.sh logs     # tail all logs  (or: logs <service-name>)
./scripts/rag-mac.sh stop     # stop services, keep data
./scripts/rag-mac.sh clean    # stop services, remove all data
```

The manual steps below explain each command.

## Prerequisites

- **Mac**: Apple Silicon (M1/M2/M3/M4) — Intel Macs also work (no Rosetta overhead)
- **Docker Desktop for Mac** 4.20+ — [download here](https://www.docker.com/products/docker-desktop/)
  - In Docker Desktop → Settings → Resources: allocate at least **8 CPU**, **16GB RAM**
- **~50GB free disk space**

## Step 1: Get an NVIDIA API Key

1. Go to [https://org.ngc.nvidia.com/setup/api-keys](https://org.ngc.nvidia.com/setup/api-keys)
2. Click **Generate Personal Key**
3. Name it, set expiration to **Never Expire**, and select **NGC Catalog** + **Public API Endpoints**
4. Export the key:

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

```bash
source deploy/compose/mac-m4.env
docker compose -f deploy/compose/docker-compose-mac.yaml up -d
```

On first run Docker will pull images (~10–15 min on a fast connection). The amd64 images are pulled and translated by Rosetta automatically — no manual steps needed.

## Step 5: Verify the Deployment

```bash
# Check all containers are running
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

# Check RAG server health
curl -s 'http://localhost:8081/v1/health?check_dependencies=true' | python3 -m json.tool

# Check ingestor server health
curl -s 'http://localhost:8082/v1/health?check_dependencies=true' | python3 -m json.tool
```

A healthy response looks like:

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

### Using the Web UI

1. Open [http://localhost:8090](http://localhost:8090)
2. Click **New Collection** and upload documents (PDF, DOCX, PPTX, TXT, MD, HTML, PNG, JPEG, MP3, WAV, MP4)
3. Select the collection and ask a question

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

Docker Desktop on Mac binds published ports to `0.0.0.0`, and the frontend reverse-proxies all backend calls internally — so other devices on your network only need port 8090.

```bash
# Find your Mac's IP
ipconfig getifaddr en0    # Wi-Fi
ipconfig getifaddr en1    # Ethernet (if connected)
```

Then open `http://<your-mac-ip>:8090` from another device. No firewall changes needed on macOS for local network traffic — Docker Desktop handles port binding.

## Stop / Clean Up

```bash
# Stop services (keeps data)
docker compose -f deploy/compose/docker-compose-mac.yaml down

# Stop and remove all data
docker compose -f deploy/compose/docker-compose-mac.yaml down -v
```

## Docker Desktop Resource Tuning

For better performance during ingestion, increase Docker Desktop's resource limits:

1. Docker Desktop → Settings → Resources
2. **CPUs**: 8 or more (M4 Pro has plenty of efficiency cores)
3. **Memory**: 16GB minimum, 24GB recommended for parallel ingestion
4. **Swap**: 4GB
5. Apply & Restart

## Troubleshooting

### Containers exit immediately on Apple Silicon

Add the `platform: linux/amd64` hint is already set in the compose file, but if you see `exec format error`, make sure Rosetta is installed:

```bash
softwareupdate --install-rosetta --agree-to-license
```

### Milvus fails to start

Check for memory issues — Milvus needs ~2GB RAM minimum:

```bash
docker compose -f deploy/compose/docker-compose-mac.yaml logs milvus
```

If Docker Desktop's memory limit is too low, increase it in Settings → Resources.

### API key errors

Make sure the key is exported before sourcing the env file:

```bash
echo $NGC_API_KEY   # must not be empty
source deploy/compose/mac-m4.env
```

### Rate limiting on ingestion

NVIDIA API Catalog enforces per-key rate limits. Process files in small batches of 5–10 at a time.

### View logs for any service

```bash
docker compose -f deploy/compose/docker-compose-mac.yaml logs -f rag-server
docker compose -f deploy/compose/docker-compose-mac.yaml logs -f ingestor-server
```

## Differences from the RTX 4070 Deployment

| | Mac M4 Pro | RTX 4070 (Ubuntu) |
| - | ---------- | ----------------- |
| Vector DB index | HNSW (CPU) | GPU_CAGRA (CUDA) |
| Milvus image | `milvusdb/milvus:v2.6.5` | `milvusdb/milvus:v2.6.5-gpu` |
| Server images | amd64 via Rosetta | native amd64 |
| AI NIMs | NVIDIA API Catalog | NVIDIA API Catalog |
| GPU required | No | Yes (1 GPU for vector DB) |
| Best for | Development, testing | Higher throughput workloads |

## Next Steps

- [Full deployment reference](deploy-docker-nvidia-hosted-cuvs.md)
- [RTX 4070 guide](getting-started-nvidia-hosted.md) (GPU-accelerated vector DB)
- [API reference — RAG server](api-rag.md)
- [API reference — Ingestor server](api-ingestor.md)
- [Configure models and settings](change-model.md)
