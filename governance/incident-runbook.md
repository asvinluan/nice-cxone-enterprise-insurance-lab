# Incident runbook

Clocks below are the ones the design should be built around (verify each against the current regulation and your own contracts).

## Severity

| Sev | Meaning | Example | First response |
|---|---|---|---|
| 1 | Customers cannot reach us, or data may be exposed | All lines down; personal data found in logs | Bridge in 10 minutes; consider roll-back |
| 2 | Major degradation | Verify API failing closed for everyone | Bridge in 30 minutes |
| 3 | Minor | One queue misrouting | Next business day |

## Platform or integration outage

1. Check `05-health-check` and the dashboard.
2. If the API is down: Studio's fail modes keep callers moving (money and data steps fail closed to a person; priority lookups fail open). Agents take more calls: tell the floor.
3. If CXone itself is down: carrier-level re-point to the roll-back target if the outage is expected to be long (per `rollback-runbook.md`).
4. Record times: detected, declared, mitigated, resolved.
5. Decide if regulator notification applies (below).

## Data incident (possible exposure of personal information)

1. Contain: stop the flow that is leaking; keep evidence; do not delete logs.
2. Security lead assesses: what, whose, how many, how serious.
3. If an eligible data breach under the Notifiable Data Breaches scheme is suspected, assess "as soon as practicable" and within 30 days at most (verify), and notify when required.
4. If the incident is an information security incident that APRA's standard requires to be notified, the clock is 72 hours from becoming aware (CPS 234) (verify).

## APRA notification clocks (verify all)

| Trigger | Clock |
|---|---|
| Operational risk incident likely to have a material financial impact, or a material impact on critical operations (CPS 230) | Notify within 72 hours |
| Activating the business continuity plan in response to a disruption of a critical operation (CPS 230) | Notify within 24 hours |
| Material information security incident (CPS 234) | Notify within 72 hours |
| Entering into or materially changing an agreement for a material service provider (CPS 230) | Notify within 20 business days |

## Catastrophe mode

1. Incident manager decides: severe weather event, expected call surge.
2. ENG runs `06-cat-mode on` (confirms by typing ON). Write the time.
3. Check: one live call to a main number hears the event message and reaches the CAT queue.
4. OPS moves CAT Surge Pool agents; supervisors watch callbacks.
5. Update the website banner; point customers to the faster digital channel.
6. When volumes fall: `06-cat-mode off`. Check one live call.
7. Review within 5 business days: queue times, callback completion, abandon rate, lessons.

## Communications

One person speaks for the incident. Customers get plain facts: what happened, what we are doing, what they should do, when we will update.
