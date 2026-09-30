# JAI Platform Architecture

JAI separates reusable platform services, business modules, tenant configuration, customer integrations, local AI and deployment concerns.

## Logical layers

```
Client / Browser
      |
      v
Reverse Proxy / TLS
      |
      v
Web UI
      |
      v
API / Application Layer
      |
 +----+----------------+----------------+
 |                     |                |
Core              Business Modules     AI Gateway
 |                     |                |
Identity            CRM/Sales/etc.     Orchestrator
Tenancy             Loyalty            Local LLM
RBAC                Analytics          RAG
Audit               Integrations       Tools
 |                     |                |
 +---------------------+----------------+
                       |
                  Data Services
                       |
          +------------+-------------+
          |                          |
     PostgreSQL + pgvector        Redis
          |
     Object/backup storage
```

## Core services

Identity provides users, organizations, roles, permissions, sessions and MFA state.

Tenancy establishes organization context from authenticated identity. The server must not trust an arbitrary tenant ID supplied by a client.

Business modules include CRM, Sales, Loyalty, Inventory, Analytics, Customer Service, Marketing and Knowledge.

The AI Gateway is the only application boundary allowed to invoke local models. It handles model routing, context assembly, permissions, retrieval, tool authorization and audit.

AI business tools are typed application functions. The LLM never receives direct database administrator credentials.

## Data architecture

PostgreSQL is the transactional system of record. pgvector provides initial semantic retrieval. Redis handles queues, caching and short-lived state. Large documents, exports and backups use object storage.

## Deployment modes

1. Single-company on-premise
2. Multi-tenant private deployment
3. Dedicated customer instance
4. Private cloud
5. JAI Business Box

The same application packages should be deployable in all modes.

## First POC non-goals

- Kubernetes
- distributed databases
- active/active multi-region
- large-scale data warehouse
- custom foundation-model training
