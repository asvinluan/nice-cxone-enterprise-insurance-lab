# Runbook: PowerShell (Windows)

Every command to build the Kestrel Insurance NICE CXone lab from a Windows PC. One action per step. After each step there is **You should see**.

If you prefer Bash, use `RUNBOOK-BASH.md`. The two do the same thing and are tested with the same checks.

**Before you start:** read Parts 1 and 2 of `BUILD-MANUAL.md` (a lab tenant, an API user and an access key). **Never run this against a customer's tenant or account.**

Works in Windows PowerShell 5.1 and PowerShell 7. Use PowerShell 7 if you can. (The scripts were run under PowerShell 7 against a mock; under 5.1 they are parse-checked in CI. If something odd happens in 5.1, try 7 first.)

---

## Step 1. Install the tools (once)

Open **PowerShell**. Paste these one at a time. `winget` is built into current Windows.

```powershell
winget install --id Git.Git -e
winget install --id Python.Python.3.12 -e
winget install --id OpenTofu.Tofu -e
winget install --id Amazon.AWSCLI -e
```

Close PowerShell and open it again so the new tools are found. Then:

```powershell
git --version
python --version
tofu version
aws --version
pip install pyyaml jsonschema python-hcl2 pytest
```

**You should see** a version number for each. Python should be 3.12 or newer. (If `python` is not found, try `py`.)

> Prefer HashiCorp Terraform? `winget install --id Hashicorp.Terraform -e`. The scripts use whichever they find, OpenTofu first.

---

## Step 2. Allow scripts to run (once per window)

Windows blocks scripts by default. This allows scripts **for this window only**:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

**You should see** nothing (that means it worked). Run it again in every new window.

---

## Step 3. Go to the repo and set your credentials

Change the path to where you put the repo.

```powershell
cd "$HOME\Downloads\GitHub\nice-cxone-enterprise-insurance-lab"
```

Set the variables. Paste your own values. **They exist only in this window.**

```powershell
$env:CXONE_TENANT_ID         = "your-lab-tenant-name"
$env:CXONE_ACCESS_KEY_ID     = "paste-access-key-id-here"
$env:CXONE_ACCESS_KEY_SECRET = "paste-secret-here"
$env:AWS_PROFILE             = "lab"
$env:AWS_REGION              = "ap-southeast-2"
```

> Do not save these in a file. Do not type them into a script. Do not paste them into chat.

Check the secret is set without showing it:

```powershell
[bool]$env:CXONE_ACCESS_KEY_SECRET
```

It prints `True`.

---

## Step 4. Preflight (changes nothing)

```powershell
.\scripts\powershell\00-preflight.ps1 -Aws
```

**You should see:** `OK  git found`, `OK  python found`, `OK  aws found`, `OK  tofu found`, `OK  Token received for tenant <name>`, `OK  Admin API reachable (your tenant has N skills)`, `OK  AWS credentials work`.

**Check the tenant name and the AWS account are your lab.** If not, close the window.

| If you see | Do this |
|---|---|
| `Set $env:CXONE_TENANT_ID first` | Step 3 was not done in this window |
| `Tenant lookup failed` | Wrong tenant name |
| `Could not get a token` | Wrong access key ID or secret |
| `'git' is not installed` | Step 1, then reopen PowerShell |
| `AWS login not working` | `aws sso login --profile lab` |

---

## Step 5. Offline checks

```powershell
.\scripts\powershell\10-aws-validate.ps1
```

**You should see:** `All checks passed.`, `87 passed`, `OK  Unit tests pass`, `OK  Formatting is clean`, `Success! The configuration is valid.`, `OK  Configuration is valid`.

After this, a file `terraform\.terraform.lock.hcl` exists. **Keep it and commit it.**

---

## Step 6. AWS: plan, apply, seed, test

```powershell
.\scripts\powershell\11-aws-plan.ps1 minimal
```

**You should see** a long list and `Plan: N to add, 0 to change, 0 to destroy.` Read it.

```powershell
.\scripts\powershell\12-aws-apply.ps1 minimal      # asks you to type YES
.\scripts\powershell\13-aws-seed.ps1               # asks you to type YES
.\scripts\powershell\14-aws-test-api.ps1
.\scripts\powershell\05-health-check.ps1
```

**You should see:** `Apply complete!`, then `Loaded 4 items into policies` (and claims, cat_events), then `Passed 12, failed 0.`, then `HTTP 200` and `OK  Integration layer healthy`.

---

## Step 7. CXone: check the paths, plan, apply

```powershell
.\scripts\powershell\01-verify-endpoints.ps1
```

**You should see** an `OK` line for each of seven resources. If one fails, fix `cxone\endpoints.json` and run it again.

```powershell
.\scripts\powershell\03-cxone-plan.ps1
```

**You should see:** `OK  Plan: 53 to create, 0 already exist.` (on an empty tenant)

```powershell
.\scripts\powershell\04-cxone-apply.ps1
```

It asks you to retype the tenant name, then type `YES`. **You should see:** `OK  Created 53, already existed 0, failed 0.`

Run the plan again. **You should see** `Plan: 0 to create, 53 already exist.` That is how you know it is safe to repeat.

---

## Step 8. Inventory

```powershell
.\scripts\powershell\02-cxone-inventory.ps1
```

**You should see** counts (skills 11, teams 12, hoursOfOperation 5, dispositions 9, unavailableCodes 8, pointsOfContact 8, total 53) and the list of eight points of contact.

Now build the six Studio scripts (`BUILD-MANUAL.md`, Part 7), then run the phone tests (Part 8).

---

## Step 9. The catastrophe drill

```powershell
.\scripts\powershell\06-cat-mode.ps1 status
.\scripts\powershell\06-cat-mode.ps1 on        # type ON
# make a live call: you should hear the event message first
.\scripts\powershell\06-cat-mode.ps1 off       # type OFF
```

**You should see:** `Emergency flag now: false`, then `CAT mode is now on at <time>`, then `CAT mode is now off at <time>`.

---

## Step 10. Evidence (optional, for your portfolio)

```powershell
.\scripts\powershell\07-evidence-export.ps1
```

**You should see** `OK  Evidence written to evidence\<timestamp>`. It holds tool versions, test results, repo-check output, file hashes and object counts, plus a manifest. It contains no secrets or personal data. Look before you share. The folder is already in `.gitignore`.

---

## Step 11. Tear down

```powershell
.\scripts\powershell\02-cxone-inventory.ps1
.\scripts\powershell\09-cxone-destroy.ps1      # lists first; type DESTROY
.\scripts\powershell\19-aws-destroy.ps1 minimal   # type DESTROY
.\scripts\powershell\02-cxone-inventory.ps1
```

**You should see** the objects listed before deletion, `OK  Destroyed.`, and in the last inventory a total of 0.

Then check your AWS billing page and your CXone contract for anything that remains. Studio scripts you made by hand are not removed by these scripts.

---

## Step 12. Put it on GitHub

```powershell
python tools\check_repo.py
git init -b main
git add .
git status
```

Read the list. **You must not see** `.tfstate`, `.tfplan`, `.env`, `backend.tf`, `terraform.tfvars` or `evidence\`. If you do, stop and fix `.gitignore`.

```powershell
git commit -m "Initial commit: NICE CXone enterprise insurance lab"
git remote add origin https://github.com/<you>/nice-cxone-enterprise-insurance-lab.git
git push -u origin main
```

**You should see** your files on GitHub and, within a minute or two, the **Actions** tab running the checks.

---

## What each script does

| Script | Purpose | Changes anything |
|---|---|---|
| `00-preflight.ps1` | Tools, logins, tenant name | No |
| `01-verify-endpoints.ps1` | Read-only check of the CXone API paths | No |
| `02-cxone-inventory.ps1` | Counts lab objects in CXone | No |
| `03-cxone-plan.ps1` | Shows what apply would create | No |
| `04-cxone-apply.ps1` | Creates what is missing in CXone | **Yes** |
| `05-health-check.ps1` | Calls the API's /health | No |
| `06-cat-mode.ps1` | Reads or flips the catastrophe switch | **Yes** (on / off) |
| `07-evidence-export.ps1` | Collects non-secret evidence | Writes local files |
| `09-cxone-destroy.ps1` | Deletes lab-marked CXone objects | **Yes** |
| `10-aws-validate.ps1` | Offline checks | No |
| `11-aws-plan.ps1` | Plans the AWS build | No |
| `12-aws-apply.ps1` | Builds AWS from the saved plan | **Yes** |
| `13-aws-seed.ps1` | Loads fictional data | **Yes** |
| `14-aws-test-api.ps1` | Smoke tests the API | Creates a test case |
| `19-aws-destroy.ps1` | Deletes the AWS stack | **Yes** |
| `lib.ps1` | Shared helpers, not run directly | No |

All scripts stop at the first failure. They never print the secret, the token or the API key.

**Common errors:**

| What you see | Meaning | Fix |
|---|---|---|
| `running scripts is disabled on this system` | Step 2 was not done | Run Step 2 in this window |
| `python is not recognized` | Python not installed or not on the path | Step 1, reopen PowerShell, or use `py` |
| `Files are not formatted` | Formatting only | `tofu fmt -recursive` in `terraform` |

More: `BUILD-MANUAL.md`, Part 12.
