# Hypercare

Hypercare is the period after each wave when the team watches closely and fixes fast.

| Item | Target |
|---|---|
| Length | Wave 1: 5 business days. Wave 2: 10. Wave 3: 15. Wave 4: 10. |
| Daily stand-up | 15 minutes, 8:30am Melbourne time, with operations, engineering, reporting, and the carrier contact on call |
| Dashboard | API errors, p95 latency, guard blocks, fail-closed counts, queue length, abandon rate, service level |
| Floor walkers | At least one per 10 agents for the first 3 days of each wave |
| Defect handling | Severity 1: fix or roll back in hours. Severity 2: fix within a day. Others: next release |
| Daily numbers | Compare to the same weekday last week on Cisco |
| Exit | Operations, risk and the business sponsor all sign off against the exit criteria in `waves.md` |

## What to watch for

- A rise in "not verified" or "locked" results. Usually keypad capture problems or bad data, not fraud, but check.
- Callers pressing 0 or hanging up at the same menu. The menu is wrong.
- Guard blocks on ordinary questions. The rules are too tight.
- Agent complaints about screen pop or missing data.
- Reports that disagree with the old platform. Find out whose definition is right before anyone panics.

## Handover to business as usual

The BAU runbook, the on-call roster, the dashboards, the alarm routing and the monthly review (eval results, cost, incidents, access review) must exist and be tested before hypercare ends.
