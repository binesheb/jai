# JAI — Jayalakshmi Artificial Intelligence

JAI is the private, modular, multi-agent AI platform for Jayalakshmi.

## One-command Windows installation

On a fresh Windows 11 PC, open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/binesheb/jai/main/install.ps1 | iex
```

The command downloads the current JAI bootstrap from GitHub and executes it with PowerShell.

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
