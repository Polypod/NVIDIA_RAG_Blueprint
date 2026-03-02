<!--
  SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0
-->
# Deploy NVIDIA RAG Blueprint with NVIDIA API Catalog NIMs and cuVS Vector DB

Use this documentation to deploy the [NVIDIA RAG Blueprint](readme.md) with Docker Compose using NVIDIA API Catalog-hosted NIM microservices with a cuVS-accelerated vector database. This deployment mode requires only **1 GPU** for the vector database.

This is ideal for:
- Organizations that want to use NVIDIA-hosted AI models
- Development and testing environments
- Users with limited GPU resources
- Quick prototyping without local model deployment

## Architecture Overview

This deployment uses:
- **NVIDIA API Catalog** for all AI NIMs (LLM, Embeddings, Reranker, OCR, etc.)
- **NVIDIA cuVS-accelerated Milvus** vector database on 1 GPU
- **Local infrastructure** (Redis, MinIO) for data management

## Prerequisites

1. **NVIDIA API Key** - Get from [NVIDIA Build](https://build.nvidia.com/)
   ```bash
   export NGC_API_KEY="nvapi-..."
   ```

2. **Docker Engine** with NVIDIA Container Toolkit
   ```bash
   # Install NVIDIA Container Toolkit
   https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
   ```

3. **Docker Compose** (v2.29.1 or later)
   ```bash
   docker compose version
   ```

4. **1 GPU** for cuVS-accelerated vector database

5. **~50GB disk space** for container images and data

## Deployment Steps

### 1. Authenticate with NGC

```bash
echo "${NGC_API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin
```

### 2. Set Environment Variables

Source the NVIDIA-hosted cuVS environment configuration:

```bash
source deploy/compose/nvidia-hosted-cuvs.env
```

This configures:
- All NIMs to use NVIDIA API Catalog endpoints
- cuVS-accelerated Milvus with GPU support
- Single GPU (ID 0) for vector database

### 3. Start Services

Deploy all services with a single command:

```bash
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml up -d
```

Or deploy step by step:

```bash
# Start vector database (Milvus with cuVS)
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml up -d milvus etcd minio redis

# Start ingestor server
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml up -d ingestor-server

# Start RAG server
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml up -d rag-server

# Start frontend
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml up -d rag-frontend
```

### 4. Verify Deployment

Check service health:

```bash
# Check running containers
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

# Check RAG server health (includes NIM status)
curl -X 'GET' 'http://localhost:8081/v1/health?check_dependencies=true' -H 'accept: application/json'

# Check ingestor server health
curl -X 'GET' 'http://localhost:8082/v1/health?check_dependencies=true' -H 'accept: application/json'
```

Expected output for RAG server should show:
```json
{
    "message": "Service is up.",
    "nim": [
        {
            "service": "LLM",
            "status": "healthy",
            "message": "Using NVIDIA API Catalog"
        },
        {
            "service": "Embeddings",
            "status": "healthy",
            "message": "Using NVIDIA API Catalog"
        },
        {
            "service": "Ranking",
            "status": "healthy",
            "message": "Using NVIDIA API Catalog"
        }
    ]
}
```

## Configuration

### Environment Variables

The `nvidia-hosted-cuvs.env` file configures:

| Variable | Description | Default |
|----------|-------------|---------|
| `NVIDIA_API_KEY` | NVIDIA API Key for Catalog access | Required |
| `APP_LLM_SERVERURL` | LLM endpoint (empty = Catalog) | (empty) |
| `APP_EMBEDDINGS_SERVERURL` | Embeddings endpoint | `https://integrate.api.nvidia.com/v1` |
| `APP_RANKING_SERVERURL` | Reranker endpoint | (empty) |
| `VECTORSTORE_GPU_DEVICE_ID` | GPU for cuVS | `0` |
| `APP_VECTORSTORE_INDEXTYPE` | Index type | `GPU_CAGRA` |

### NIMs Using NVIDIA API Catalog

- **LLM**: `nvidia/llama-3.3-nemotron-super-49b-v1.5`
- **Embeddings**: `nvidia/llama-3.2-nv-embedqa-1b-v2`
- **Reranker**: `nvidia/llama-3.2-nv-rerankqa-1b-v2`
- **OCR**: `nemoretriever-ocr`
- **Page Elements**: `nemoretriever-page-elements-v3`
- **Graphic Elements**: `nemoretriever-graphic-elements-v1`
- **Table Structure**: `nemoretriever-table-structure-v1`

## GPU Requirements

This deployment requires only **1 GPU** for the cuVS-accelerated vector database:

| Component | GPU Usage |
|-----------|-----------|
| Milvus (cuVS) | 1 GPU (GPU_CAGRA index) |
| NIMs (LLM, Embeddings, etc.) | None (cloud-hosted) |

## Kubernetes Deployment

For Kubernetes deployments, use the Helm chart with the NVIDIA-hosted cuVS values:

```bash
helm install rag ./deploy/helm/nvidia-blueprint-rag \
  -f deploy/helm/nvidia-blueprint-rag/values-nvidia-hosted-cuvs.yaml \
  --set ngcApiSecret.password=$NGC_API_KEY
```

## Usage

### Access the UI

Open http://localhost:8090 in your browser.

### API Endpoints

- **RAG Server**: http://localhost:8081
- **Ingestor Server**: http://localhost:8082
- **Milvus**: localhost:19530

### Example API Call

```bash
# Query the RAG endpoint
curl -X 'POST' \
  'http://localhost:8081/v1/chat' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {"role": "user", "content": "What is NVIDIA RAG Blueprint?"}
    ]
  }'
```

## Troubleshooting

### Rate Limiting

When using NVIDIA API Catalog, you may encounter rate limiting with large file ingestions (>10 files). To avoid this:
- Use smaller batches
- Consider self-hosted NIMs for production use

### GPU Not Available

If the vector database fails to start:
```bash
# Verify GPU is available
nvidia-smi

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

### Health Check Failures

Check service logs:
```bash
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml logs rag-server
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml logs ingestor-server
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml logs milvus
```

## Stop Services

```bash
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml down
```

To also remove volumes:
```bash
docker compose -f deploy/compose/docker-compose-nvidia-hosted.yaml down -v
```

## Comparison: Self-Hosted vs NVIDIA-Hosted

| Feature | Self-Hosted NIMs | NVIDIA API Catalog |
|---------|------------------|-------------------|
| GPUs Required | Multiple (1 per NIM) | 1 (vector DB only) |
| Initial Setup Time | Long (model download) | Fast (containers only) |
| Latency | Lower (local) | Higher (network) |
| Cost | GPU compute | API calls |
| Rate Limits | None | Per API key |

## Related Topics

- [Deploy with Self-Hosted NIMs](deploy-docker-self-hosted.md)
- [NVIDIA API Catalog Models](https://build.nvidia.com/)
- [cuVS Documentation](https://docs.nvidia.com/cuvs/)
- [Milvus GPU Acceleration](milvus-configuration.md)
- [RAG Pipeline Debugging](debugging.md)
- [Troubleshooting](troubleshooting.md)
