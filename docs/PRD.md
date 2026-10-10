# JAI — Product Requirements Document (PRD)

**Product:** JAI — Jayalakshmi Artificial Intelligence / Private AI Business Platform  
**Reference deployment:** Jayalakshmi Silks Pvt Ltd  
**Document status:** Proposed baseline for implementation  
**Last updated:** 11 October 2026  
**Repository:** https://github.com/binesheb/jai

## 1. Executive summary

JAI is a secure, modular AI business platform that brings business applications, knowledge, analytics and controlled automation into one platform. Jayalakshmi Silks is the first reference deployment; the core must remain reusable by other businesses and support isolated single-tenant deployments as well as multi-tenant deployments where explicitly configured and validated.

The initial infrastructure target is the existing Jayalakshmi AI Server based on AMD Ryzen 5 5600GT. JAI will use a **hybrid AI strategy**: local inference is the default for private and sensitive information, while approved cloud AI may be used for eligible tasks under explicit data-classification and routing policies. The first external business integration is Shopify.

This PRD defines product scope and acceptance requirements. It does not assert that infrastructure has been audited, integrations completed, or production readiness achieved. Those are release gates to be verified.

## 2. Vision and outcomes

Deliver a secure AI platform that can:
- Help customers discover products and obtain accurate support.
- Give authorised staff a single AI-assisted interface for approved business information and workflows.
- Integrate e-commerce and future business systems through maintainable, permission-controlled connectors.
- Improve reporting and operational decisions using traceable source data.
- Run locally on company-controlled infrastructure, with controlled cloud capabilities where justified.
- Evolve into a reusable commercial product without hard-coding Jayalakshmi-specific rules into the core.

### Success outcomes
1. Product answers are grounded in current source catalogue data and link to real product pages.
2. AI cannot bypass user permissions, tenant boundaries or application business rules.
3. Sensitive data is not sent to cloud models by default or through an unreviewed fallback.
4. Integration events can be retried and reconciled without duplicate or silent data loss.
5. Management reports can be traced to authorised source records.
6. Deployment, backup, restore, update and rollback procedures are documented and tested.

## 3. Users and roles

- **Public shopper:** searches products and asks general policy questions without accessing private customer or company data.
- **Verified customer:** may access their own permitted order/support information after an appropriate verification flow.
- **Customer-support agent:** views permitted customer interactions and escalates or resolves enquiries.
- **Sales/marketing user:** uses approved catalogue, campaign and performance tools.
- **Manager/executive:** views authorised dashboards, reports and management summaries.
- **System administrator:** configures integrations, models, access, deployment and monitoring.
- **Auditor/security owner:** reviews access and sensitive-action audit trails.
- **Tenant administrator:** administers only their own tenant, where multi-tenancy is enabled.

RBAC and tenant scope must be enforced in application services and, where applicable, database policies—not merely described in prompts.

## 4. Product scope

### 4.1 Platform core
- Authenticated API and web application.
- User, role, permission and tenant management.
- AI orchestration and model routing.
- Permission-aware tools for business operations.
- Company knowledge and retrieval-augmented generation (RAG).
- Product/document search.
- Audit trail, observability, health checks and administration.
- Secure integration framework and background jobs.
- Backup, restore, configuration and deployment management.

### 4.2 Business modules
- CRM and customer 360.
- Sales and business intelligence.
- Loyalty and rewards.
- Inventory and product intelligence.
- Customer service.
- Marketing workflows.
- Company knowledge assistant.
- Controlled AI business tools.
- Integration APIs.
- Future HR, MIS, IT and showroom intelligence modules, subject to separate requirements and permissions.

### 4.3 Shopify — first integration
Shopify is the first planned external integration. The connector must be independently testable and must not couple core AI orchestration to Shopify-specific API details.

**Initial read-only scope**
- Synchronise product titles, descriptions, handles, variants, prices, images and available permitted metadata.
- Support product search and recommendation based on real catalogue records.
- Link responses to actual Shopify product pages.
- Process verified webhooks, tolerate duplicate delivery and reconcile missed events.
- Respect API versioning, rate limits, pagination and granted scopes.

**Subsequent scope**
- Inventory visibility where permissions and data access permit.
- General customer support based on approved store policies.
- Verified order-status lookup using the minimum necessary customer-data access.
- Analytics based on authorised and reconciled Shopify data.

**Out of scope for the first release**
- Autonomous refunds, cancellations, order edits or payment actions.
- Unverified access to customer orders.
- Unrestricted write access to Shopify.
- Scraping or direct access to Shopify's internal databases.

Use the supported Shopify GraphQL Admin API for permitted administrative data and the Storefront API where appropriate. Subscribe only to required webhooks and verify webhook signatures. Select and pin a supported API version at implementation time. The application must handle access scopes, protected customer data requirements, rate limits and API errors.

### 4.4 Customer-facing AI assistant
- Embed in the Shopify storefront using a small, secure chat interface.
- Answer catalogue and general policy questions from approved, current sources.
- Ask clarifying questions when product intent is ambiguous.
- Clearly distinguish verified facts from recommendations.
- Avoid inventing prices, stock, delivery dates, product attributes or order status.
- Link products and relevant policy pages.
- Escalate low-confidence, sensitive or unresolved cases to human support.
- Apply abuse prevention, rate limiting, output validation and safe error handling.

### 4.5 Management intelligence
- Product and sales performance summaries.
- Inventory and demand insights when reliable source data is available.
- Campaign reporting.
- Natural-language questions over approved, permission-filtered metrics.
- Report lineage: each material figure must be traceable to source records or a documented calculation.
- Role-based dashboard access and export controls.

## 5. AI and model-routing requirements

### 5.1 Hybrid AI policy
Local inference is the default. Cloud inference is optional and must be explicitly configured per task/provider.

Before routing, classify the request and relevant retrieved context. Deny cloud routing when data is restricted, classification is unknown, provider approval is absent, or required sanitisation cannot be assured. No silent fallback from local to cloud is permitted.

Eligible cloud tasks may include generic copy drafting or complex reasoning over minimised, non-sensitive prompts. Provider selection must account for contractual terms, retention, regional processing, data use, cost and availability.

### 5.2 Local inference
- Evaluate Ollama or another suitable runtime through a documented benchmark.
- Select models based on measured latency, quality, memory use, licence and task fit.
- Keep model runtime interfaces on private networks; do not expose unauthenticated inference APIs publicly.
- Support model configuration and rollback without changing business logic.
- Provide deterministic fallback responses for unavailable models where safe.

### 5.3 RAG and grounding
- Index only approved documents and authorised data.
- Preserve tenant, role, source and document permissions during retrieval.
- Show source references when useful.
- Treat retrieved content as untrusted data, never as executable instructions.
- Define document freshness, re-indexing, deletion and retention behaviour.
- Prevent retrieval from leaking data across users or tenants.

### 5.4 Tool execution
The model must never receive unrestricted database administration or arbitrary SQL execution. It may request typed, allowlisted application tools. Each tool must validate input, enforce identity and permission checks, apply business rules, set timeouts and emit audit events. Writes with meaningful customer, financial or operational impact require explicit approval according to policy.

## 6. Reference architecture

Logical request path:

1. Shopify storefront or authenticated JAI web client.
2. HTTPS reverse proxy/API gateway with request validation, rate limiting and authentication.
3. FastAPI application and AI orchestration service.
4. Policy engine for identity, tenant scope, data classification, model routing and tool permissions.
5. Local model runtime and optionally approved cloud AI provider.
6. PostgreSQL with pgvector for application data and retrieval metadata.
7. Background worker/queue for catalogue synchronisation, webhook processing, indexing and reports.
8. External integration adapters, beginning with Shopify.
9. Logs, metrics, audit records, alerts and encrypted backup storage.

### Proposed technology baseline
- **Backend:** Python + FastAPI.
- **Database:** PostgreSQL.
- **Vector search:** pgvector, with PostgreSQL full-text search where appropriate.
- **Deployment:** Docker Compose for the initial single-server deployment; pinned image versions and private service networks.
- **AI runtime:** benchmark-selected local runtime/model.
- **Queue:** add Redis-backed workers where asynchronous workload requires them; Redis is not a substitute for durable business records.
- **Proxy/TLS:** maintained reverse proxy with automated certificate renewal.
- **Observability:** structured application logs, health checks, metrics and actionable alerts.
- **CI:** automated linting, type checks where applicable, unit/integration/security tests and dependency scanning.

Implementation must check the current repository and installed versions before adopting or replacing components. Avoid obsolete or unmaintained dependencies; pin and review upgrades rather than blindly tracking latest versions in production.

## 7. Hosting and infrastructure

### 7.1 Initial host
Use the existing AMD Ryzen 5 5600GT Jayalakshmi AI Server for development and controlled pilot after an audit. Do not assume its GPU, RAM, storage, network, power protection or availability characteristics; record actual specifications before model selection and capacity planning.

### 7.2 Required preflight audit
- CPU, RAM, GPU/VRAM, storage capacity/health and free disk.
- Operating system, Docker/WSL configuration and running services.
- Current ports, firewall, DNS, TLS and internet exposure.
- Backup destination, encryption and restore test.
- UPS and safe restart behaviour.
- Model latency, concurrent requests, memory use and thermal stability.
- Expected traffic and recovery-time/recovery-point requirements.

### 7.3 Deployment constraints
- Database and model runtime are not publicly exposed.
- Only necessary gateway ports are reachable externally.
- Use encrypted off-host backups and test restoration.
- Apply security updates and controlled application/model upgrades.
- A single host is a single point of failure. Production availability requirements may require a separate backup host or later high-availability design.
- Do not buy a GPU or replacement server until measured pilot workloads demonstrate the need.

## 8. Security, privacy and compliance

Mandatory controls:
- TLS for external connections and secure service-to-service communication where appropriate.
- Least-privilege service accounts and minimal Shopify scopes.
- MFA for privileged users and secure session management.
- Secrets stored outside Git and client-side bundles; documented rotation and revocation.
- Input validation, output encoding, CSRF protection where relevant, and protection against injection and SSRF.
- Tenant isolation in queries, tools, retrieval, caches, jobs, logs and exports.
- Verified webhook signatures, replay/duplicate handling and idempotent processing.
- Rate limits, quotas, timeouts and abuse monitoring.
- Audit logs for authentication, permission changes, sensitive reads and business writes; redact tokens and unnecessary personal data.
- Encrypted backups, retention policy and tested restore.
- Dependency, container and secret scanning in CI.
- Threat modelling and security testing before public launch.
- Documented incident response and access revocation procedure.
- Data minimisation, retention/deletion rules and appropriate governance for customer and employee information.

AI-specific controls:
- Prompt-injection and malicious-document testing.
- Treat customer input, web content, product descriptions and retrieved documents as untrusted.
- No direct model-to-database credentials.
- No unreviewed autonomous actions with financial or account impact.
- Prevent private data from entering prompts, logs or external providers without an approved basis.
- Red-team tests for cross-user and cross-tenant data leakage.

## 9. Non-functional requirements

- **Correctness:** product, price and order facts must come from authorised source systems, not model memory.
- **Security:** access denied by default; all protected data access is authorised and scoped.
- **Reliability:** retries are bounded, idempotent and observable; failed syncs can be reconciled.
- **Performance:** define measurable latency and concurrency targets after baseline load testing; do not promise unsupported model performance.
- **Maintainability:** modular connectors, migrations, documented interfaces, automated tests and versioned configuration.
- **Portability:** Docker-packaged services and documented Windows/Linux deployment paths, without assuming identical inference performance across hosts.
- **Observability:** health status, error rates, queue depth, model latency, token/cost use where applicable, sync freshness and disk usage.
- **Recoverability:** documented backup schedule and agreed recovery targets validated through drills.
- **Accessibility and usability:** responsive customer widget, clear errors, keyboard-accessible controls and human escalation.
- **Cost control:** per-provider limits, usage metrics, model routing policy and alerts.

Numeric service-level targets must be approved after measuring the actual host and pilot traffic.

## 10. Delivery roadmap

Indicative schedule for a focused small team; dates depend on repository state, access, integration complexity and test results.

### Phase 1 — Infrastructure and security baseline (Week 1)
- Audit server and repository.
- Document network boundary, ports, services and current deployment.
- Configure secrets, TLS, backups, restore test and CI baseline.
- Benchmark host capacity.

**Gate:** secure deployment and tested recovery procedure.

### Phase 2 — AI core and data layer (Weeks 2–3)
- FastAPI service boundaries, migrations and tenant-aware data model.
- Authentication/RBAC and audit events.
- Local inference benchmark and explicit model router.
- RAG and typed tool framework.

**Gate:** local operation works; unauthorised access and tools are blocked.

### Phase 3 — Shopify read-only connector (Weeks 3–4)
- Create/configure Shopify app and minimum scopes.
- Catalogue sync, webhook verification, retry/idempotency and reconciliation.
- Product search API and storefront widget.

**Gate:** answers link to real products and catalogue sync is observable and recoverable.

### Phase 4 — Support and governed hybrid routing (Weeks 5–6)
- Approved knowledge base and customer support.
- Verified order-status flow only if access and verification design pass review.
- Human escalation and cloud data policy.
- Prompt-injection and privacy tests.

**Gate:** restricted data cannot reach unapproved cloud routes; sensitive actions are blocked or approved.

### Phase 5 — Analytics and dashboard (Weeks 7–8)
- Authorised sales/product reporting.
- Reconciliation tests and report lineage.
- Staff dashboard, job monitoring and operational alerts.

**Gate:** figures reconcile to source records and roles are enforced.

### Phase 6 — Pilot and production release (Weeks 9–10)
- Load, failure, security and recovery testing.
- Limited-audience rollout, support runbook and incident procedure.
- Measure accuracy, latency, uptime, escalation and resource use.
- Release approval by accountable business and technical owners.

**Gate:** all blocking tests pass and rollback is rehearsed.

### Later roadmap
- CRM/customer 360, loyalty and rewards.
- POS/ERP and inventory integrations.
- WhatsApp/Meta and Google Reviews.
- HRMS, MIS, IT and showroom intelligence agents.
- Tenant provisioning, licensing, self-service installation and high-availability options.

## 11. Acceptance criteria and release gates

Production release requires all of the following:
1. Product searches return current catalogue-backed data and valid links.
2. Price, availability and order-status claims are not fabricated.
3. Customer and staff data access is scoped and tested.
4. Cloud routing is explicit, logged and denied for restricted/unknown classifications.
5. Shopify webhook signatures are verified and duplicate events do not create duplicate effects.
6. Synchronisation failures are visible and recoverable through retry/reconciliation.
7. AI tools enforce permissions and business rules independently of prompt instructions.
8. Prompt-injection, secret leakage and cross-tenant tests pass.
9. Backups are encrypted and a restoration drill succeeds.
10. Monitoring, alerts, runbooks, dependency review and rollback are in place.
11. Management metrics reconcile to authoritative records.
12. Business owner and technical owner sign off on pilot evidence.

## 12. Measurement

Record a baseline and track:
- Catalogue sync freshness and error/reconciliation rate.
- Product-search relevance and factual accuracy on a curated test set.
- Customer-support resolution and human escalation rates.
- Response latency and concurrent-user performance.
- Local/cloud routing percentage and cloud spend.
- Model/resource saturation, service availability and recovery outcomes.
- Security test findings and time to remediate.
- Management report reconciliation accuracy.

Targets are set after the first baseline; no unsupported accuracy or uptime promise is implied by this PRD.

## 13. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Existing server lacks inference capacity | Benchmark smaller models; optimise; upgrade only on measured evidence |
| Host outage stops all services | Off-host backups, restore drills, documented recovery and later redundancy |
| Shopify API changes or throttling | Versioned APIs, rate-limit handling, retries and contract tests |
| Stale or incorrect product data | Webhooks plus reconciliation and freshness indicators |
| Sensitive data sent to cloud AI | Default local routing, classification, minimisation and deny-by-default policy |
| Prompt injection causes unsafe action | Typed tools, independent authorisation, validation and human approval |
| Cross-tenant data leak | Tenant-scoped queries/retrieval/cache/jobs and adversarial tests |
| Scope expands too quickly | Shopify read-only pilot first; each later module has its own acceptance gate |

## 14. Decisions and assumptions

**Approved direction**
- JAI remains a reusable, multi-tenant-capable private AI business platform; Jayalakshmi is its reference deployment.
- Initial pilot uses the existing AMD Ryzen 5 5600GT server, subject to audit.
- Hybrid AI is adopted with local-first processing and explicit cloud-routing controls.
- Shopify is the first external integration.
- Shopify work begins read-only with product catalogue search before customer/order workflows.
- Security, permissions, auditability, recovery and test evidence are release requirements.

**Still to verify**
- Exact server hardware, operating system, Docker state and public endpoint design.
- Shopify store/app configuration, API scopes and protected-data eligibility.
- Chosen local model/runtime after benchmarks.
- Required concurrency, latency, recovery targets and production availability.
- Approved cloud provider, contractual terms and permitted data classes.
- Availability of source data for sales, inventory and management reporting.

## 15. Related documentation

Keep this PRD aligned with:
- `docs/architecture.md` — service boundaries and deployment architecture.
- `docs/security.md` — threat model, controls and release checks.
- `docs/tenancy.md` — tenant isolation and data boundaries.
- `docs/local-ai.md` — local inference and model-routing policy.
- `docs/product-roadmap.md` — phased delivery and later modules.

Where a related document conflicts with this PRD, resolve the conflict explicitly in a reviewed change rather than silently weakening a security requirement.
