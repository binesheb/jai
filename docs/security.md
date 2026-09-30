# JAI Security Baseline

## Network

- PostgreSQL and Redis are private services.
- Only the application/reverse-proxy boundary accepts user traffic.
- Administrative access is restricted to trusted networks.

## Identity

- Passwords use modern password hashing.
- Privileged accounts require MFA in production.
- Sessions have expiry and revocation.
- RBAC follows least privilege.

## Database

Separate credentials are required for migration/admin, application, analytics/read-only and AI read-only operations.

The AI service must never use a PostgreSQL superuser.

## Secrets

Secrets are supplied through environment or secret-management mechanisms. Never commit passwords, API keys, private keys, database dumps, customer data or authentication tokens.

## AI security

AI output is not authoritative for price, stock, payroll, financial balances, policy or permissions.

Authoritative values come from application services and databases. AI writes require typed tools with authorization, validation and audit.

## Data protection

- Encrypt backups.
- Use TLS for network traffic.
- Use encrypted storage where appropriate.
- Minimize sensitive model context.
- Prefer local models for sensitive business data.

## Backup and recovery

Production requires automated backups, off-server copies, retention policy, restore tests and a documented recovery procedure.

## Logging

Logs must not become a secondary source of sensitive-data leakage. Credentials, authorization headers and secrets must be redacted before diagnostic publication.

## Supply chain

Pin production image versions, scan dependencies/images, keep supported versions current and verify release artifacts where practical.

## Security testing

Before real customer data:
- dependency scanning
- container scanning
- authentication and authorization tests
- tenant-isolation tests
- backup restore test
- AI prompt-injection/tool-authorization tests
- basic penetration test
