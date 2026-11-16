# Recovery objectives and rehearsal

Numbers below are **lab examples**. Real tolerance levels are set by the insurer's board-approved process.

| Capability | Tolerance (max time disrupted) | Recovery approach | Rehearsal |
|---|---|---|---|
| Inbound claims calls reach a person | 15 minutes of degraded service; 2 hours of total loss | If the platform fails: carrier re-point to roll-back path; if the integration fails: fail-closed/open design keeps calls moving | Roll-back rehearsal each quarter |
| Policy verification by phone | 4 hours (callers go to a person meanwhile) | Fail closed to a person; fix or fail over the API | Fail-over rehearsal each half-year |
| Case creation | 4 hours | Agents create cases by hand; replay after recovery using idempotency keys | Replay test |
| Recordings available | 24 hours | Archive bucket replicated to the DR region (Melbourne) when enabled | Restore test each half-year |
| AI self-service | 24 hours | Switch off; every path already ends at a person | Switch-off test |

## Primary and DR regions

Primary: Sydney (ap-southeast-2). DR: Melbourne (ap-southeast-4). Both are in Australia. The lab replicates the archive bucket only; a full active/passive API stack in the DR region is a design option (second `tofu` workspace with the same modules), with a DNS or CXone configuration switch.

## RPO and RTO language

- **RPO** (how much data you can lose): archive replication is asynchronous, so the lab RPO for recordings is minutes to hours (verify against the replication SLA). Reference tables are rebuilt from the system of record.
- **RTO** (how long to recover): see the tolerance column.

## Rehearsal record (fill in after each rehearsal)

Date, scenario, time to detect, time to decide, time to recover, what broke, what we changed.
