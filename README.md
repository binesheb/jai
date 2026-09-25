# JAI — Jayalakshmi Artificial Intelligence

JAI is the private, modular, multi-agent AI platform for Jayalakshmi.

## One-command Windows installation

On a fresh Windows 11 PC, open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/binesheb/jai/main/install.ps1 | iex
```

The command downloads the current JAI bootstrap from GitHub and executes it with PowerShell.

The bootstrap prints detailed live progress to the PowerShell window and writes a timestamped full log under `C:\ProgramData\JAI\logs\`.

The bootstrap is **resumable**. If WSL, Docker Desktop, or Windows requires a restart, JAI stops cleanly, preserves installation state, and tells you to restart and run the same command again. It records which prerequisites JAI installed so the uninstaller can avoid removing software that was already present.

After prerequisites are ready, the bootstrap creates a local `.env` with a generated PostgreSQL password, validates Docker Compose, pulls the infrastructure images, starts PostgreSQL/pgvector and Redis, and records the deployed Git revision. The `.env` file stays local and is never committed.

## Automatic error recovery

JAI includes a **Self-Heal engine**. When bootstrap, Docker, WSL, Compose, or service startup encounters a recoverable failure, JAI can automatically:

- refresh the Windows environment PATH;
- restart Docker Desktop when the engine is unavailable;
- restart the WSL runtime when WSL is unhealthy;
- re-check the Docker engine;
- retry Docker image pulls with progressive delays;
- recreate JAI services with `docker compose up -d --remove-orphans`;
- run the full JAI health check again;
- write a separate timestamped self-heal log.

Run Self-Heal manually from an Administrator PowerShell:

```powershell
irm https://raw.githubusercontent.com/binesheb/jai/main/scripts/selfheal.ps1 | iex
```

Self-Heal is deliberately conservative: it repairs JAI's own runtime and containers, but does not blindly uninstall software, delete unrelated Docker data, or modify business data.

`C:\\ProgramData\\JAI\\logs\\` contains the bootstrap, health-check, doctor and self-heal logs.

The bootstrap is designed to:
- detect the Windows environment;
- verify/install required prerequisites;
- prepare WSL2 and Docker;
- clone or update the JAI repository;
- prepare local configuration;
- start JAI infrastructure;
- run health checks;
- record installation logs.

> **Security:** Review the installer source before executing a remote `irm ... | iex` command. Never place passwords, API keys or other secrets in GitHub.

## Goals

- Local-first AI inference where practical
- Controlled access to company data and business tools
- Product image matching and price/stock retrieval
- Generic FAQ, company knowledge and AI instructions
- WhatsApp/Meta customer conversations
- Google Reviews and reputation management
- HR, MIS, knowledge, IT and customer-service agents
- Interactive analytics, logs, traces and audit history
- Automated health checks, diagnostics, updates and rollback
- GitHub as the source of truth

## Operating model

**GitHub is the source of truth. The PC is a deployment target.**

JAI should be reproducible from a fresh machine and should progressively automate installation, configuration, testing, deployment, monitoring, diagnostics and recovery.

## Safety

AI must not invent authoritative prices, stock, payroll values or policy facts. Business writes require controlled tools and permissions. Secrets never belong in Git.

## Repository

```
docs/                  Architecture, operations and roadmap
scripts/               Health, update and diagnostic automation
install.ps1             One-command Windows bootstrap
docker-compose.yml      Core infrastructure
.github/workflows/      Automated validation
```

## One-command uninstall

Run **PowerShell as Administrator**:

```powershell
irm https://raw.githubusercontent.com/binesheb/jai/main/uninstall.ps1 | iex
```

The uninstaller requires an explicit `REMOVE-JAI` confirmation, stops JAI Docker resources, removes JAI volumes/data/configuration/logs, removes JAI-specific scheduled tasks and environment variables, and removes Git/Docker Desktop **only when JAI recorded that it installed them**. Shared Windows components such as WSL are preserved.

The installer records what it installed in `C:\\ProgramData\\JAI\\installation-state.json` so uninstall can avoid removing software that was already present on the PC.
