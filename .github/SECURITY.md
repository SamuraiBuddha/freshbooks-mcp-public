# Security Policy

## Supported versions

The `main` branch is the only supported version. Older releases do not
receive security fixes unless explicitly stated in the release notes.

## Reporting a vulnerability

Please report security issues privately. **Do not open a public GitHub issue.**

- Preferred: GitHub Security Advisories ("Report a vulnerability" tab on this repo)
- Alternative: email the maintainer listed in `CODEOWNERS` (or jordan@ebicinc.com if no `CODEOWNERS`)

What to include:
- A description of the issue and the impact
- Steps to reproduce, or a proof-of-concept
- Affected version / commit hash
- Your contact information for follow-up

## Response timeline

| Stage | Target |
|---|---|
| Acknowledge receipt | 3 business days |
| Initial assessment | 10 business days |
| Fix or mitigation in `main` | 30 days for high/critical, 90 days for medium/low |
| Public disclosure | Coordinated with reporter; default 30 days after fix is available |

## Scope

In scope:
- Supply-chain vulnerabilities in declared dependencies
- Secret leaks in this repo's tracked files or history
- Authentication / authorization bypass
- Injection vulnerabilities (XSS, SQLi, command injection)
- Insecure deserialization
- Sensitive data exposure

Out of scope:
- Vulnerabilities in upstream dependencies that have already been disclosed
  upstream (file with the dep maintainer instead)
- Social engineering of the maintainer
- Physical attacks
- Self-XSS, missing security headers on documentation pages
