# JAI Product Roadmap

## Stage 0 — Foundation
- Docker deployment
- secure PostgreSQL + pgvector
- Redis
- configuration management
- health checks
- backup primitives
- application skeleton

## Stage 1 — Commercial POC
- organizations/tenants
- users and RBAC
- CRM
- sales
- loyalty
- dashboard
- local AI chat
- RAG
- controlled data tools
- audit
- synthetic seed data
- installer/health validation

## Stage 2 — Jayalakshmi pilot
- real data import
- POS/ERP connector
- HRONE connector
- showroom configuration
- loyalty policy configuration
- management reporting
- production monitoring
- restore drills

## Stage 3 — Productization
- tenant provisioning
- module enablement
- installer wizard
- deployment profiles
- licensing
- update channel
- rollback
- support diagnostics
- documentation

## Stage 4 — Enterprise
- SSO
- dedicated database/instance mode
- high availability
- advanced audit
- SIEM integrations
- enterprise backup
- GPU/model management
- SLA tooling

## POC acceptance criteria

A clean installation must be able to:
1. create an organization;
2. create an admin;
3. create locations;
4. import or generate sample customers/products/sales;
5. calculate loyalty transactions;
6. display management KPIs;
7. answer a sales question using local AI;
8. answer a company-knowledge question using local RAG;
9. enforce tenant permissions;
10. record audit events;
11. back up the database;
12. restore the backup into a clean environment;
13. pass automated health checks;
14. run without a cloud LLM.
