# Cutover runbook (one number, one window)

Use this for each number. Times are relative to the carrier change, "T". Roles: **CL** cutover lead, **CR** carrier representative, **OPS** operations manager on the floor, **ENG** integration engineer, **SEC** security/compliance contact.

## T minus 5 business days

1. CL: confirm the carrier ticket and window in writing.
2. CL: confirm the weather rule (no severe warning for the window).
3. OPS: confirm agents are trained, logged in on the dry run, and know the roll-back plan.
4. ENG: run `05-health-check` and `14-aws-test-api`. Keep the output.
5. SEC: confirm the register entry and notifications (see `governance/`) are done.

## T minus 1 day

6. ENG: run `01-verify-endpoints` and `03-cxone-plan`. The plan should show 0 to create.
7. CL: send the go/no-go summary. Anyone can say no-go.
8. CR: confirm the roll-back instruction is ready to send.

## T minus 30 minutes: go / no-go

| Check | Required answer |
|---|---|
| Health check | OK |
| Test call to the new path (using a test number on the same trunk group) | Works |
| Agents logged in on the floor | At least the minimum rostered |
| Any open severity 1 or 2 incident | None |
| Weather | No severe warning |
| CR on the line and CL on the line | Yes |

Any "no" is a no-go. Rebook. Do not argue with a no-go.

## T: the change

9. CR: re-point the number to CXone. CL writes the exact time in the log.
10. CL and OPS: make a live call from an outside mobile. Confirm greeting, recording notice, menu, and a queue to a real agent.
11. ENG: watch the API dashboard and alarms.

## T plus 15 minutes: first checkpoint

12. Calls arriving? Answered? Recorded? Agent screen pop opened? Any errors on the dashboard?
13. If anything is wrong and cannot be fixed in 15 minutes: roll back (see `rollback-runbook.md`). The decision is the cutover lead's. Nobody needs permission to roll back inside the window.

## T plus 2 hours, end of day, next morning

14. Repeat the checks. Compare volume and answer rate to the same day last week on Cisco.
15. CL: write the summary: what was done, when, what was seen, what is open.

## Evidence to keep

Carrier ticket; the go/no-go record; test call recordings; dashboard screenshots at T+15 min and end of day; `07-evidence-export` output; the summary.
