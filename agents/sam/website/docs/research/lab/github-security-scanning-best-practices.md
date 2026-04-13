# GitHub Security Scanning Best Practices — Nel Research

**Date**: 2026-04-13T02:45:00-06:00  
**Agent**: Nel (QA/Security)  
**Context**: Automated security scanning for public GitHub repo + Vercel deployment  
**Status**: Implemented in Nel QA cycle Phase 2.5

---

## Top 20 API Key Regex Patterns

1. `sk-ant-api03-[a-zA-Z0-9]{95}` — Anthropic
2. `sk-[a-zA-Z0-9]{20,}` — OpenAI
3. `AKIA[0-9A-Z]{16}` — AWS Access Key
4. `ghp_[a-zA-Z0-9]{36}` — GitHub Classic PAT
5. `github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}` — GitHub Fine-grained PAT
6. `vercel_[a-zA-Z0-9]{24}` — Vercel Token
7. `Bearer\s+[a-zA-Z0-9\-._~+/]+=*` — Generic Bearer Token
8. `sv_live_[a-zA-Z0-9]{32}` — Stripe Live Key
9. `sk_live_[a-zA-Z0-9]{24}` — Stripe Secret Key
10. `xai-[a-zA-Z0-9]{20,}` — xAI
11. `-----BEGIN RSA PRIVATE KEY-----` — RSA Key
12. `-----BEGIN PRIVATE KEY-----` — PKCS#8 Key
13. `postgres://[a-zA-Z0-9]+:[a-zA-Z0-9]+@` — Database URL
14. `mongodb\+srv://[a-zA-Z0-9]+:[a-zA-Z0-9]+@` — MongoDB
15. `api[_-]?key[=:]\s*[a-zA-Z0-9_-]+` — Generic API Key
16. `aws[_-]?secret[_-]?access[_-]?key` — AWS Secret
17. `Authorization:\s*Bearer\s+[a-zA-Z0-9\-._]+` — HTTP Bearer
18. `NEXT_PUBLIC_.*SECRET` — Vercel public env misuse
19. `mysql://[a-zA-Z0-9]+:[a-zA-Z0-9]+@` — MySQL connection
20. High-entropy 32+ char strings near keyword context — requires entropy validation

## Cipher.sh Coverage vs Gaps

**Currently covered:** Gitleaks (150+ patterns), TruffleHog (800+ patterns), filesystem perms, .env gitignore, founder token, grok/sk/xai patterns.

**Gaps identified:**
- NEXT_PUBLIC_ prefix misuse (secrets as public Vercel vars)
- Build log scanning (Vercel/GitHub Actions logs can expose vars)
- Custom database connection strings beyond postgres/mongo
- API endpoint leak detection (hardcoded internal admin URLs)
- Entropy threshold tuning for custom token detection
- Secret rotation tracking (audit trail for key changes)

## Implementation

New Phase 2.5 added to nel-qa-cycle.sh. Runs q6h. 9 scan types:
1. Tracked file secret patterns (grep-based)
2. Git history leak detection
3. Gitignore coverage verification
4. Config file exposure check
5. JavaScript hardcoded credentials
6. Base64 encoded secret detection
7. GitHub Actions advisory checks
8. .secrets directory integrity
9. Vercel deployment security

## Sources

- Gitleaks default config (github.com/gitleaks/gitleaks)
- Secrets Patterns DB (github.com/mazen160/secrets-patterns-db)
- GitHub supported secret scanning patterns (docs.github.com)
- Vercel NEXT_PUBLIC_ exposure case study (cremit.io)
- TruffleHog vs Gitleaks comparison (appsecsanta.com)
