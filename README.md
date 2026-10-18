# JAI — Private AI Business Platform

JAI is a **private, deployable AI business platform** designed to run inside a company's own infrastructure.

It began as the Jayalakshmi Artificial Intelligence (JAI) project. The product direction is now broader: Jayalakshmi is the reference deployment, while the platform is designed from the start to be reusable by other companies.

## Product vision

JAI combines business applications, analytics, knowledge, automation and local AI in one controlled platform:

- CRM and customer 360
- Sales and business analytics
- Loyalty and rewards
- Inventory and product intelligence
- Customer service
- Marketing workflows
- Company knowledge / RAG
- AI business assistant
- Controlled AI data tools
- Audit, security and administration
- Integration APIs
- Repeatable on-premise/private-cloud deployment

### Local-first AI

The core product is designed for **local AI inference**. Customer and business data does not need to leave the customer's environment.

Cloud AI providers are not required for the core AI workflow.

## Product model

JAI is a **multi-tenant-capable product platform**.

A deployment can host one company in an isolated single-tenant installation, or multiple isolated organizations where the deployment model and security requirements permit it.

The tenant boundary applies to users, locations, customers, employees, products, sales, loyalty, documents, AI context, audit records and integrations.

For high-security deployments, a dedicated database or dedicated JAI instance can be used per customer.

## Reference deployment: Jayalakshmi

Jayalakshmi Silks is the first reference business for the platform.

The reference deployment will validate multi-showroom retail, CRM, loyalty, sales analytics, management dashboards, local AI, internal knowledge search, controlled AI tools and secure integrations.

Jayalakshmi-specific configuration belongs outside the reusable core.

## Architecture

```
                         JAI PLATFORM
                              |
                 +------------+------------+
                 |                         |
             Business API             AI Gateway
                 |                         |
       +---------+---------+        +------+------+
       |         |         |        |             |
      CRM      Sales     Loyalty   Local LLM     RAG
       |         |         |        |             |
       +---------+---------+        +------+------+
                 |                         |
                 +------------+------------+
                              |
                         PostgreSQL
                         + pgvector
                              |
                         Redis / Jobs
                              |
                    Object / Backup Storage
```

The application layer is authoritative for business operations. The AI layer uses controlled, permission-aware tools and must not be treated as an unrestricted database administrator.

## Security principles

1. PostgreSQL is private and is not exposed directly to the Internet.
2. AI receives only the data and tools allowed by the authenticated user's permissions.
3. Business writes require explicit application tools and validation.
4. Secrets never belong in Git.
5. Audit logging is enabled for sensitive operations.
6. Backups are encrypted and restoration is tested.
7. Tenant isolation is enforced in the application and database layers.
8. Local AI is the default for sensitive business data.
9. Production deployments should use least privilege and MFA for privileged users.
10. Customer data is never used for product development without an explicit, appropriate data-governance basis.

## Deployment

The current repository contains a Windows-first bootstrap because the first reference environment is Windows. The product target is broader:

- Windows
- Linux
- private cloud
- dedicated AI Business Box hardware

Docker is the primary application packaging boundary.

### Windows bootstrap

PowerShell as Administrator:

```powershell
irm https://raw.githubusercontent.com/binesheb/jai/main/install.ps1 | iex
```

The installer is designed to be resumable and records installation state locally.

## Development roadmap

### POC
- Secure Docker foundation
- PostgreSQL + pgvector
- Redis
- Tenant model
- Authentication and RBAC
- CRM
- Sales data
- Loyalty engine
- Management dashboard
- Local LLM runtime
- Local RAG
- Controlled AI business tools
- Audit log
- Backup/restore validation

### Pilot
- Real Jayalakshmi data migration
- POS/ERP integration
- HRMS integration
- WhatsApp/Meta integration
- Customer service
- production monitoring
- performance testing
- security review

### Product
- Self-service installer
- tenant provisioning
- module licensing
- update/rollback
- health monitoring
- enterprise SSO
- high availability options
- dedicated-customer deployments
- AI model management

## Repository structure

```
docs/
  architecture.md
  security.md
  tenancy.md
  local-ai.md
  product-roadmap.md

database/
  migrations/
  seeds/

apps/
  api/
  web/

services/
  ai/
  workers/
  integrations/

deploy/
  docker/
  windows/
  linux/

scripts/
  install/
  health/
  backup/
```

## Current status

**POC foundation — architecture and deployment work in progress.**

The existing bootstrap, Docker infrastructure, health checks and self-healing mechanisms are being retained and evolved into the reusable product platform.

## License

See [LICENSE](LICENSE).
