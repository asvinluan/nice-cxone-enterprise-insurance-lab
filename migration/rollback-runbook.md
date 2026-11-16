# Roll-back runbook

## When to roll back

Any one of these, during the window or hypercare:

- Callers cannot reach an agent, or hear dead air or an error.
- Calls are not recorded when they must be.
- Verification fails closed for everyone and agents cannot work around it.
- Service level falls below the agreed floor and cannot be recovered with staffing in 15 minutes.
- Personal data is found where it should not be.
- The cutover lead judges that customers are being harmed.

The roll-back decision belongs to the cutover lead. It does not need a committee.

## How

1. CL says "roll back" on the bridge and writes the time.
2. CR re-points the number from the CXone trunk group back to the Cisco trunk group (named in `number-inventory.csv` as the roll-back target).
3. OPS tells the floor. Agents log in to the Cisco desktop.
4. CL makes a live call from an outside mobile and confirms the call reaches a Cisco agent.
5. ENG preserves evidence: do not delete anything on the CXone side. Export logs and recordings for the review.
6. CL sends the incident notice. If the event meets the notification thresholds in the incident procedure, the compliance contact starts the regulator notification clock (see `governance/incident-runbook.md`).

## Target time

Agree it with the carrier before wave 1. Rehearse it on a test number in wave 0 and record the actual time. The plan is only as good as the rehearsed time.

## What you must NOT do

- Do not "fix forward" for hours while customers wait.
- Do not delete the CXone configuration to "start again". You will need it for the review.
- Do not roll back without telling the floor. Agents who are logged in to the wrong platform take no calls.

## After

Blameless review within 3 business days. What did we see first? How long to notice? How long to decide? How long to roll back? What would have caught it earlier? Update the test plan.
