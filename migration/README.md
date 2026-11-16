# Migration pack: Cisco contact centre to NICE CXone

This folder is the working material for moving calls from a Cisco contact centre (UCCE/CVP/Finesse or Webex Contact Center) to NICE CXone. Everything in it is fictional lab material. Use it as a template, not as a record of a real migration.

| File | What it is |
|---|---|
| `number-inventory.csv` | Every phone number: where it goes now, where it goes after, which wave, and the roll-back target |
| `cisco-to-cxone-mapping.csv` | Cisco concept to CXone concept, what changes, and the trap in each |
| `test-plan.csv` | 45 numbered test cases with expected results and the evidence to keep |
| `risk-register.csv` | The ten risks that matter most, with early warning signs |
| `waves.md` | The wave plan, with entry and exit criteria |
| `cutover-runbook.md` | The hour-by-hour plan for one cutover |
| `rollback-runbook.md` | When and how to go back |
| `hypercare.md` | The weeks after cutover |

The long explanation is in `docs/MIGRATION-PROCEDURE.md`.

## The idea in one paragraph

Do not switch everything at once. Move one phone number at a time, smallest and safest first. The control that makes this safe is at the **carrier**: the carrier decides which platform a number rings. Pointing a number at CXone, and pointing it back at Cisco, are both a carrier change. So the roll-back is a rehearsed phone call to the carrier, not a rebuild. Keep Cisco running until every wave has been stable for long enough that the business agrees to switch it off.
