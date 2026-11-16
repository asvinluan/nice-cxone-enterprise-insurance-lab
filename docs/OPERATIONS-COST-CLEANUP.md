# Operations, cost and clean-up

How to run the lab safely, what it costs, and how to remove it. Prices change: **check the provider's pricing page before you build**. Figures below are rough and marked (verify).

---

## 1. What costs money

| Item | When it costs | Rough scale | Controls |
|---|---|---|---|
| **CXone tenant** | Licences and usage by contract | Not self-service; ask your partner or employer (verify) | Use a lab tenant already provided |
| **Firewall (WAF)** on the API | Every month, plus per request | About 10 USD a month with the rules used (verify) | `enable_waf = false` in `minimal`; turn on for anything real |
| **KMS key** | Every month, plus calls | About 1 USD a month per key (verify) | Delete when finished (it has a waiting period) |
| **CloudWatch dashboard** | Every month | A few USD (verify) | `enable_dashboard = false` |
| **CloudWatch logs and alarms** | Per GB stored; per alarm | Cents at lab volume | Short retention (`log_retention_days`) |
| **API Gateway, Lambda, DynamoDB** | Per request / per use | Pennies at lab volume | On-demand tables |
| **Bedrock model use** | Per input and output token | Depends on the model (verify) | Leave `bedrock_model_id` empty until needed |
| **Bedrock guardrail** | Per text unit checked (verify) | Small at lab volume | `enable_guardrail = false` in `minimal` |
| **S3 archive** | Per GB stored | Small | Short retention; no Object Lock in the lab |
| **Object Lock and DR replication** | Storage doubles; locked objects cannot be deleted early | Higher; risky | Keep **off** in a throwaway lab |
| **Data transfer** | Between regions | Small | DR replication off in the lab |

**First, set a budget alarm** in the AWS account (for example 20 USD a month with an email). Do it before the first apply.

---

## 2. Running it day to day (the lab, as if it were real)

### 2.1 What to watch

| Signal | Where | Meaning |
|---|---|---|
| Function errors | CloudWatch alarm | A bug or a bad deploy |
| API 5xx | Alarm | Platform or function trouble |
| Slow responses (p99) | Alarm | Calls may time out in Studio |
| Firewall blocks | Alarm | Someone is calling from an unlisted address, or the platform's addresses changed |
| Guard blocks (spike) | Alarm | Attack, or rules too tight |
| Guard errors | Alarm | The AI path is failing closed |
| Verification lock-outs | Alarm | Keypad problem or an attack |

### 2.2 Routine tasks

| Task | How often | How |
|---|---|---|
| Health check | Daily | `05-health-check` |
| Run the AI eval set | Before every change; weekly | `tools/run_ai_eval.py --url ...` |
| Rotate the API key | Every 90 days (set your own policy) | Re-apply with a new key; update Studio; test; revoke the old key |
| Review who has access | Monthly | CXone roles; AWS roles; GitHub |
| Review cost | Monthly | Billing console |
| Roll-back rehearsal | Quarterly | Carrier |
| DR rehearsal | Half-yearly | `governance/dr-and-bcp.md` |
| Evidence export | At each release | `07-evidence-export` |

### 2.3 Troubleshooting order (stop when you find it)

1. Is it the **platform**? (CXone status, tenant health)
2. Is it the **carrier**? (calls not arriving; trunk status; ask the carrier)
3. Is it the **script**? (menu, branch, timeout; use Studio trace)
4. Is it the **API**? (`05-health-check`, alarms, logs)
5. Is it the **data**? (the reference table has the record?)
6. Is it the **agent**? (login, skills, unavailable code)

---

## 3. Clean-up (in this order)

1. Phone test number bindings you created by hand: remove.
2. Studio scripts you created by hand: delete or archive the exports first.
3. CXone settings: `09-cxone-destroy`. It lists, then waits for `DESTROY`.
4. AWS: `19-aws-destroy minimal` (or the environment you used).
5. If you used Object Lock: locked objects stay until retention ends. This is why the lab keeps it off.
6. KMS keys: scheduled deletion has a waiting period. Confirm in the console.
7. CloudWatch log groups: confirm deletion.
8. Check the billing console two days later for stragglers.
9. Check GitHub: no secrets, no `evidence/`, no state files.

**Verify clean-up worked:** `02-cxone-inventory` shows 0 lab objects; `tofu state list` (in `terraform`) is empty; the billing console shows no new daily charges.

---

## 4. Safety rules (the short version)

- Lab tenant, lab account, fictional data. Always.
- Secrets in environment variables only.
- Read the plan before you apply.
- Retype the tenant name; type the word.
- If a number must change, a carrier ticket first.
- Do not publish anything you have not read.
