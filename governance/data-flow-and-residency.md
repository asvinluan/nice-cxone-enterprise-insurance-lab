# Data flow and residency

| Data | Where it is created | Where it goes | Where it is kept | How long | Protection |
|---|---|---|---|---|---|
| Call audio | Caller to carrier to CXone | Agent; recording store | CXone recording storage; optional copy in the archive bucket | Per retention policy (verify) | Encryption in transit and at rest; access by role |
| Keypad digits (policy number, postcode) | Caller | Studio variable, then API call over HTTPS | Not kept in Studio logs (masked). DynamoDB holds the reference data only | Not stored by the call | Masked capture; no digits in logs |
| Policy and claim reference data | Insurer systems (in the lab: fictional seed) | DynamoDB | Australian region | As long as needed | Customer-managed key; least-privilege roles |
| Case summaries | Studio (fixed text) | API to cases table | Australian region | Per case policy | API refuses card, tax file and Medicare numbers |
| AI questions and answers | Caller/agent | Guard then model then guard | Not stored by the lab code; model provider behaviour must be confirmed | n/a | Local checks + guardrail; no personal data to the model by design |
| Logs and metrics | Lambda, API Gateway | CloudWatch | Australian region | Set by policy (30 days in lab) | No personal data by code and test |

## Questions to put to every vendor, in writing

1. In which country and region is each type of data stored and processed, including backups and support access?
2. Do AI features send data to a model provider? Which one, where, and is it kept or used for training?
3. Which sub-processors can see call audio?
4. How long do you keep recordings and logs after contract end?
5. What attestations do you hold, and can we see the reports?
