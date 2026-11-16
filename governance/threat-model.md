# Threat model (integration layer)

Method: for each part of the data flow, ask what an attacker, a mistake, or an outage could do, then name the control and where the evidence is.

Flow: caller -> carrier -> CXone Studio -> HTTPS -> firewall -> API Gateway -> Lambda -> DynamoDB / Bedrock.

| # | Threat | Where | Control | Evidence |
|---|---|---|---|---|
| T1 | Someone guesses policy numbers to learn which exist | policy_verify | Two-factor (number + postcode); identical answer for unknown and wrong; lock-out counts unknown numbers too | `test_handlers.py`, test plan T14 to T16 |
| T2 | Brute-forcing a postcode for a known policy | policy_verify | Lock-out after repeated failures; lock wording identical | test plan T15 |
| T3 | Replay or retry creates duplicate cases | crm_case | Case id derived from idempotency key; conditional write | test plan T20, T21 |
| T4 | Card or tax file number lands in a CRM note | crm_case | Summary text is fixed in Studio; API rejects summaries with such numbers | test plan T22 |
| T5 | Personal data in logs | all functions | `log()` accepts only named safe fields; tests search output | `test_handlers.py` |
| T6 | Direct calls to the API from the internet | API Gateway | API key; firewall default-block with IP allow-list; throttling | `modules/integration` |
| T7 | Stolen API key | API Gateway | Key kept in the secret store/outputs only; rotate; allow-list limits use; alarms on unusual use | runbook rotation steps |
| T8 | Prompt injection to the AI | guard, ai_answer | Local attack phrases; guardrail prompt-attack filter; AI answers only from approved text; no tools or data access for the model | eval L09 to L11, B05 |
| T9 | AI says something false or makes a promise | ai_answer | Grounding check on output; topic denial on promises; person on any doubt | eval B04, B08, B09 |
| T10 | Guardrail or model outage | guard, ai_answer | Fail closed: caller is sent to a person | test plan T37 to T38 |
| T11 | API outage in the middle of a call | Studio | Per-call fail mode: closed for money/data, open for priority-only lookups; timeouts under Studio's limit | `*.yaml` `failMode` rule in `check_repo.py` |
| T12 | Recordings altered or deleted early | archive bucket | Versioning; optional Object Lock; access logging | `modules/recordings` |
| T13 | Operator error: wrong tenant or account | scripts | Preflight prints the account; apply asks you to retype the tenant; destroy deletes only marked objects named in config | `test_cxone_scripts.sh` |
| T14 | Secrets committed to Git | repo | `.gitignore`; `check_repo.py` secret patterns; CI | `test_check_repo.py` |
| T15 | Cutover harms customers | migration | Wave plan; carrier-level roll-back; go/no-go; hypercare | `migration/` |
| T16 | Vendor change breaks behaviour | CXone / Bedrock | Pinned guardrail version; fixed eval set run before and after changes | `evals/` |

## What this model does not cover

The phone network itself, the vendor's own platform security (rely on their attestations and your contract), agent workstation security, and social engineering of agents. Each needs its own treatment.
