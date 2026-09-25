# JAI AI Incident Review Protocol

This document defines how ChatGPT should handle JAI incidents.

## Evidence first

The authoritative diagnostic evidence is the uploaded log set under:
`logs/incidents/<HOST>/`

Read all relevant logs, not only the Issue excerpt. Treat the Issue body as an index and summary.

## Review sequence

1. Read the complete incident logs.
2. Identify the first meaningful failure and distinguish it from downstream errors.
3. Inspect the relevant JAI source, configuration, workflows and recent commits.
4. Check CI and related Issues/PRs.
5. Classify the cause as a JAI defect, dependency/infrastructure issue, Windows/WSL/Docker issue, authentication/network issue, or insufficient diagnostics.
6. For a JAI repository defect, create a small focused PR.
7. For an environmental/user-action issue, update the Issue with exact remediation instead of changing unrelated code.
8. Verify the change with CI/tests.
9. Comment on the incident with evidence, root cause, files changed, validation and remaining local-machine validation.
10. Never claim a local Windows machine was repaired unless a tool actually verified it.

## PR rules

- One root cause per PR where practical.
- No unrelated refactors.
- Preserve detailed logging and automatic incident handling.
- Never commit secrets or raw credentials.
- Do not remove diagnostic evidence before resolution.

## Security

Uploaded logs are redacted for common credential patterns, but treat them as potentially sensitive. Never reproduce secrets in Issues, PRs or comments.

## Resolution

Repository resolution requires the relevant PR/commit to pass CI. Local-machine resolution is a separate validation step.
