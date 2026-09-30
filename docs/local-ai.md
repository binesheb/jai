# Local AI Architecture

The core JAI AI experience must operate without sending company data to a cloud LLM.

## Runtime

```
Business Application
        |
        v
     AI Gateway
        |
   +----+----+
   |         |
 Local LLM  Embedding Model
   |         |
   +----+----+
        |
      RAG / Tools
```

The AI runtime is abstracted behind the AI Gateway so models can change without changing business applications.

## Model roles

The first POC can use one instruction/chat model and one embedding model. A reranker can be added later.

## Hardware profiles

### Development
- 32 GB RAM
- modern 8-core CPU
- optional NVIDIA GPU

### POC
- 64 GB RAM
- 8–12 CPU cores
- NVIDIA GPU with 16 GB+ VRAM preferred
- 2 TB NVMe

### Production
- 64–128 GB ECC RAM
- 12–24+ CPU cores
- enterprise NVMe
- NVIDIA GPU with 24 GB+ VRAM preferred for larger local models

Exact models and quantization levels are selected through benchmarks on target hardware.

## RAG

Documents are ingested, normalized, chunked, embedded locally, stored with tenant/source metadata, and retrieved with permission filtering.

## AI tools

The model proposes a tool call; the application validates identity, tenant, permission, arguments and operation type before execution.

## Offline mode

Core AI remains usable without Internet access when the local model and data are present. Internet is reserved for optional updates, integrations, license validation where applicable and off-site backups.
