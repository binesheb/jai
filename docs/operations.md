# JAI Operations

GitHub is the source of truth for application code, infrastructure, tests and deployment configuration.

The Windows AI server is a deployment target. Application changes belong in Git.

Deployment loop:
1. Pull approved revision.
2. Validate configuration.
3. Build/test.
4. Start/update services.
5. Run health checks.
6. Collect logs/metrics.
7. Roll back failed deployments where safe.
8. Create a GitHub issue for unresolved failures.

Destructive operations require explicit approval.
