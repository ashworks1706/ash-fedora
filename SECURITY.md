# Security Policy

## Reporting

If you find exposed credentials, hardcoded tokens, or sensitive paths:

1. Do not open a public issue with the secret value.
2. Open a private report with redacted evidence.

## Secret handling rules

- Never commit:
  - API keys
  - OAuth tokens
  - password files
  - private SSH keys
- Keep local secrets only in:
  - `~/.config/quickshell/ii/secrets/`

Run this before pushing:

```bash
rg -n "github_pat_|ghp_|glpat-|AIza|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|token\\s*[:=]" .
```
