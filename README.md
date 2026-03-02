<h1>NVIDIA RAG Blueprint</h1>

> **Source:** This repository is based on the [NVIDIA AI Blueprints RAG Blueprint](https://github.com/NVIDIA-AI-Blueprints/rag).
> Refer to the upstream repository for the full feature list, NIM details, deployment options, and official documentation.

Retrieval-Augmented Generation (RAG) combines the reasoning power of large language models with
real-time retrieval from trusted data sources, grounding AI responses in your own knowledge and
reducing hallucinations.

## What's Added Here

On top of the upstream NVIDIA RAG Blueprint, this repository adds hardware-specific getting-started guides and management scripts for getting up and running quickly without needing to read the full documentation.

| Addition | Description |
| -------- | ----------- |
| [docs/getting-started-nvidia-hosted.md](docs/getting-started-nvidia-hosted.md) | Guide for **Core i9 + RTX 4070** — NVIDIA API Catalog NIMs + local cuVS GPU vector database |
| [scripts/rag-nvidia-hosted.sh](scripts/rag-nvidia-hosted.sh) | Management script for the RTX 4070 setup |
| [docs/getting-started-mac-m4.md](docs/getting-started-mac-m4.md) | Guide for **MacBook Pro M4 Pro** (Apple Silicon) — NVIDIA API Catalog NIMs + CPU Milvus, no GPU required |
| [scripts/rag-mac.sh](scripts/rag-mac.sh) | Management script for the Mac setup |

All guides share the same command pattern:

```bash
export NGC_API_KEY="nvapi-..."
./scripts/rag-<platform>.sh setup    # check prerequisites, NGC login
./scripts/rag-<platform>.sh start    # deploy, wait for health, print URLs
./scripts/rag-<platform>.sh status   # containers, API health, resource usage
./scripts/rag-<platform>.sh logs     # tail logs (or: logs <service-name>)
./scripts/rag-<platform>.sh stop     # stop, keep data
./scripts/rag-<platform>.sh clean    # stop, remove all data
```

## Quick Start

### RTX 4070 (Ubuntu) — GPU-accelerated vector DB

```bash
git clone https://github.com/NVIDIA-AI-Blueprints/rag.git && cd rag
export NGC_API_KEY="nvapi-..."
chmod +x scripts/rag-nvidia-hosted.sh
./scripts/rag-nvidia-hosted.sh setup && ./scripts/rag-nvidia-hosted.sh start
```

See [docs/getting-started-nvidia-hosted.md](docs/getting-started-nvidia-hosted.md).

### Mac M4 Pro (Apple Silicon) — CPU vector DB, no GPU needed

```bash
git clone https://github.com/NVIDIA-AI-Blueprints/rag.git && cd rag
export NGC_API_KEY="nvapi-..."
chmod +x scripts/rag-mac.sh
./scripts/rag-mac.sh setup && ./scripts/rag-mac.sh start
```

See [docs/getting-started-mac-m4.md](docs/getting-started-mac-m4.md).

Then open <http://localhost:8090> in your browser.

## Architecture

  <p align="center">
  <img src="./docs/assets/arch_diagram.png" width="750">
  </p>

Both deployments route all AI workloads (LLM, embeddings, reranker, OCR) to NVIDIA-hosted NIMs. The difference is the local vector database: GPU_CAGRA on the RTX 4070, HNSW (CPU) on Mac.

## Full Documentation

For deployment options, configuration, customization, and Kubernetes/Helm guides, refer to the upstream:

- [NVIDIA RAG Blueprint — full docs](https://github.com/NVIDIA-AI-Blueprints/rag/tree/main/docs)
- [Self-hosted NIM deployment](docs/deploy-docker-self-hosted.md)
- [NVIDIA API Catalog + cuVS deployment](docs/deploy-docker-nvidia-hosted-cuvs.md)
- [Helm/Kubernetes deployment](docs/deploy-helm.md)
- [Troubleshooting](docs/troubleshooting.md)

## Blog Posts

- [NVIDIA NeMo Retriever Delivers Accurate Multimodal PDF Data Extraction 15x Faster](https://developer.nvidia.com/blog/nvidia-nemo-retriever-delivers-accurate-multimodal-pdf-data-extraction-15x-faster/)
- [Finding the Best Chunking Strategy for Accurate AI Responses](https://developer.nvidia.com/blog/finding-the-best-chunking-strategy-for-accurate-ai-responses/)

## Contributing

To open a GitHub issue or pull request, see the [contributing guidelines](./CONTRIBUTING.md).

## License

This NVIDIA AI Blueprint is licensed under the [Apache License, Version 2.0](./LICENSE).
This project downloads and installs additional third-party open source software projects and containers.
Review [the license terms of these open source projects](./LICENSE-3rd-party.txt) before use.

Use of the models is governed by the [NVIDIA AI Foundation Models Community License](https://docs.nvidia.com/ai-foundation-models-community-license.pdf).

## Terms of Use

This blueprint is governed by the [NVIDIA Software License Agreement](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-software-license-agreement/) and the [Product Specific Terms for AI Products](https://www.nvidia.com/en-us/agreements/enterprise-software/product-specific-terms-for-ai-products/).
Models are governed by the [NVIDIA Community Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-community-models-license/).
The [NVIDIA RAG dataset](./data/multimodal/) is governed by the [NVIDIA Asset License Agreement](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/data/LICENSE.DATA).

The following models built with Llama are governed by the [Llama 3.2 Community License](https://www.llama.com/llama3_2/license/): `nvidia/llama-3.2-nv-embedqa-1b-v2`, `nvidia/llama-3.2-nv-rerankqa-1b-v2`, `llama-3.2-nemoretriever-1b-vlm-embed-v1`.
The `llama-3.3-nemotron-super-49b-v1.5` model is governed by the [Llama 3.3 Community License](https://github.com/meta-llama/llama-models/blob/main/models/llama3_3/LICENSE). Built with Llama.
Apache 2.0 applies to NVIDIA Ingest and the `nemoretriever-page-elements-v2`, `nemoretriever-table-structure-v1`, `nemoretriever-graphic-elements-v1`, `paddleocr`, and `nemoretriever-ocr-v1` models.
