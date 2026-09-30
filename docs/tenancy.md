# Tenancy and Data Isolation

JAI must prevent one company from accessing another company's data.

## Tenant identity

The authenticated request establishes organization context:

```
Authenticated user
        |
        v
Membership
        |
        v
Organization / Tenant
        |
        v
Authorized resources
```

Never trust a tenant identifier supplied only by a browser form, URL or request body.

## Database isolation levels

### Level 1 — Shared database
Lower-cost multi-tenant deployments use organization-scoped records and strict authorization.

### Level 2 — Separate database
For customers requiring stronger logical isolation.

### Level 3 — Dedicated instance
For high-security or enterprise customers.

## Row-level security

PostgreSQL Row Level Security should be evaluated for sensitive shared-database tables. RLS is an additional control and does not replace application authorization.

## AI isolation

AI retrieval is tenant-scoped. A knowledge search can retrieve only documents the authenticated identity is authorized to access. Embeddings retain the ownership metadata of their source documents.

## Audit

Sensitive actions record organization, actor, action, resource, timestamp, outcome and correlation ID. Secrets must not be written to audit logs.
