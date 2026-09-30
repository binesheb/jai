# JAI Commercial POC

## Objective

Demonstrate that JAI can be installed privately and provide a reusable business foundation without sending business data to a cloud LLM.

## Required demo flow

1. Install the stack on a clean supported machine.
2. Start PostgreSQL/pgvector, Redis and API.
3. Create an organization.
4. Create locations and users.
5. Load synthetic customers, products and sales.
6. Calculate loyalty balances and transactions.
7. Display management KPIs.
8. Ask the local AI for a sales analysis.
9. Search a company document with local RAG.
10. Verify tenant isolation.
11. Inspect audit events.
12. Back up the database.
13. Restore the backup to a clean environment.
14. Run the same deployment with Internet access disabled after installation.

## Data policy

The POC must use synthetic or explicitly approved test data. Do not import real customer or employee records until security and restore testing are complete.

## POC hardware

Recommended:

- 64 GB RAM
- 8–12 CPU cores
- 2 TB NVMe
- NVIDIA GPU with 16 GB+ VRAM preferred

The exact local model is selected after benchmarking the target GPU and RAM.

## Completion gate

The POC is not considered complete merely because the containers start. It must pass functional, security, tenant-isolation, AI-tool authorization and backup/restore tests.
