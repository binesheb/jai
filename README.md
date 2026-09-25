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

## Failure logs and automatic incident lifecycle

JAI keeps runtime and installation diagnostics under `C:\\ProgramData\\JAI\\logs\\`. If bootstrap does not complete, the installer reads the failed log and automatically publishes its relevant contents to a GitHub Issue when GitHub authentication is available. The incident number and source log path are stored in `installation-state.json` so Self-Heal can continue the same incident instead of creating duplicates.

Self-Heal reads the incident log, attempts recovery, runs the health check, and then:

- keeps the GitHub Issue open and appends the latest diagnostics when the problem remains unresolved;
- comments on and closes the same Issue when the health check passes;
- removes the resolved incident and self-heal log files only after the resolution has been recorded remotely.

The `logs` directory itself remains available for future diagnostics. Failed logs are not committed to the repository and are not stored in Git because `logs/` is intentionally ignored.

## Automatic GitHub incident reporting

JAI can automatically create a GitHub Issue containing the failed bootstrap/self-heal logs. When the final health check passes, JAI comments on that same incident and closes it as resolved.

During installation JAI automatically installs the GitHub CLI if it is missing and checks whether GitHub is already authenticated. If authentication is missing, JAI automatically starts the GitHub CLI browser/device authentication flow. There is no Y/N confirmation prompt. Complete the GitHub authorization in the browser/device flow when requested.

```powershell
gh auth login --hostname github.com --git-protocol https --web
```

After login, JAI verifies that the authenticated account can write to `binesheb/jai`. The GitHub username and authentication status are recorded in `installation-state.json`; access tokens are never written to the JAI logs or repository.

If authentication cannot be completed, installation continues normally and JAI records a warning. To deliberately skip GitHub authentication, set `JAI_SKIP_GITHUB_AUTH=1` before running the installer. Automatic GitHub incident reporting becomes available as soon as the GitHub CLI is authenticated.

JAI can also use `JAI_GITHUB_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN` for non-interactive environments. These values are read only from the environment and are never intentionally logged.

Incident reports are deliberately truncated when necessary to stay within GitHub Issue size limits. Credentials are not intentionally written to the incident body.

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
