# Security audits

| Run | Date | Source | Profile | Result |
|---|---|---|---|---|
| [run-1](run-1/REPORT.md) | 2026-10-30 | `917bd08` | standard, source-only | 0 confirmed · 11 needs-validation leads (all remediated after the audited commit) · 1 rejected · 1 coverage unit deferred |
| [run-2](run-2/REPORT.md) | 2026-10-31 | `e6eaf03` | standard, scoped to the redesign diff, source-only | **Incomplete:** 18 unvalidated candidates (verification not funded); 17 fixed test-first after the audited commit, 1 needs hosted-settings checks · 1 coverage unit deferred |

Each run directory holds the human-readable report (`REPORT.md`, `NEEDS-VALIDATION.md`, `FINDINGS-DETAIL.md`) and the
machine-readable records (`findings.json`, `coverage-ledger.json`, `run-metadata.json`), validated with the
audit tooling's findings and coverage-ledger validators. A future run should re-verify the
remediated leads against the current source and execute the bounded local validation plans in a sandbox that can
enforce memory and disk limits.
