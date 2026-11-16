# Runbook: Bash (Linux, macOS, WSL, CI)

Every command to build the Kestrel Insurance NICE CXone lab from a Bash shell. One action per step. After each step there is **You should see**.

If you are on Windows, use `RUNBOOK-POWERSHELL.md` unless you have WSL (Windows Subsystem for Linux). Git Bash alone is not enough: it lacks `jq`.

**Before you start:** read Parts 1 and 2 of `BUILD-MANUAL.md` (a lab tenant, an API user and an access key). **Never run this against a customer's tenant or account.**

---

## Step 1. Install the tools (once)

**Ubuntu, Debian, or WSL:**

```bash
sudo apt-get update
sudo apt-get install -y git curl jq zip unzip python3 python3-pip
# AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
# OpenTofu:   https://opentofu.org/docs/intro/install/   (or HashiCorp Terraform)
pip install --user pyyaml jsonschema python-hcl2 pytest
```

**macOS (Homebrew):**

```bash
brew install git jq python opentofu awscli
pip3 install pyyaml jsonschema python-hcl2 pytest
```

Check:

```bash
git --version; curl --version | head -1; jq --version; python3 --version; tofu version; aws --version
```

**You should see** a version for each. Python should be 3.12 or newer.

> The scripts use OpenTofu if it is installed, otherwise Terraform. Either works.

---

## Step 2. Make the scripts runnable (once)

```bash
cd ~/nice-cxone-enterprise-insurance-lab     # change to where the repo is
chmod +x scripts/bash/*.sh
```

**You should see** no output.

---

## Step 3. Set your credentials

Paste your own values. **They exist only in this shell session.**

```bash
export CXONE_TENANT_ID="your-lab-tenant-name"
export CXONE_ACCESS_KEY_ID="paste-access-key-id-here"
export CXONE_ACCESS_KEY_SECRET="paste-secret-here"
export AWS_PROFILE="lab"
export AWS_REGION="ap-southeast-2"
```

> Typing a secret in a terminal can store it in your shell history. Read it silently instead:
>
> ```bash
> read -rs -p "Secret: " CXONE_ACCESS_KEY_SECRET; export CXONE_ACCESS_KEY_SECRET
> ```

Do not save these in a file in the repo. Do not paste them into chat.

---

## Step 4. Preflight (changes nothing)

```bash
./scripts/bash/00-preflight.sh --aws
```

**You should see:** `OK  curl found`, `OK  jq found`, `OK  python3 found`, `OK  git found`, `OK  aws found`, `OK  tofu found`, `OK  Token received for tenant <name>`, `OK  Admin API reachable (your tenant has N skills)`, and `OK  AWS credentials work`.

**Check the tenant name and the AWS account are your lab.** If not, close the shell.

| If you see | Do this |
|---|---|
| `Set CXONE_TENANT_ID first` | Step 3 was not done in this shell |
| `Tenant lookup failed` | Wrong tenant name |
| `Could not get a token` | Wrong access key ID or secret |
| `'jq' is not installed` | Step 1 |
| `AWS login not working` | `aws sso login --profile lab` |

---

## Step 5. Offline checks

```bash
./scripts/bash/10-aws-validate.sh
```

**You should see:** `All checks passed.`, `87 passed`, `OK  Unit tests pass`, `OK  Formatting is clean`, `Success! The configuration is valid.`, `OK  Configuration is valid`.

After this a file `terraform/.terraform.lock.hcl` exists. **Keep it and commit it.**

---

## Step 6. AWS: plan, apply, seed, test

```bash
./scripts/bash/11-aws-plan.sh minimal
```

**You should see** a long list and `Plan: N to add, 0 to change, 0 to destroy.` Read it.

```bash
./scripts/bash/12-aws-apply.sh minimal      # asks you to type YES
./scripts/bash/13-aws-seed.sh               # asks you to type YES
./scripts/bash/14-aws-test-api.sh
./scripts/bash/05-health-check.sh
```

**You should see:** `Apply complete!`, then `Loaded 4 items into policies` (and claims, cat_events), then `Passed 12, failed 0.`, then `HTTP 200` and `OK  Integration layer healthy`.

---

## Step 7. CXone: check the paths, plan, apply

```bash
./scripts/bash/01-verify-endpoints.sh
```

**You should see** an `OK` line for each of seven resources. If one fails, fix `cxone/endpoints.json` and run it again.

```bash
./scripts/bash/03-cxone-plan.sh
```

**You should see:** `OK  Plan: 53 to create, 0 already exist.` (on an empty tenant)

```bash
./scripts/bash/04-cxone-apply.sh
```

It asks you to retype the tenant name, then type `YES`. **You should see:** `OK  Created 53, already existed 0, failed 0.`

Run the plan again. **You should see** `Plan: 0 to create, 53 already exist.` That is how you know it is safe to repeat.

---

## Step 8. Inventory

```bash
./scripts/bash/02-cxone-inventory.sh
```

**You should see** counts (skills 11, teams 12, hoursOfOperation 5, dispositions 9, unavailableCodes 8, pointsOfContact 8, total 53) and the list of eight points of contact.

Now build the six Studio scripts (`BUILD-MANUAL.md`, Part 7), then run the phone tests (Part 8).

---

## Step 9. The catastrophe drill

```bash
./scripts/bash/06-cat-mode.sh status
./scripts/bash/06-cat-mode.sh on        # type ON
# make a live call: you should hear the event message first
./scripts/bash/06-cat-mode.sh off       # type OFF
```

**You should see:** `Emergency flag now: false`, then `CAT mode is now on at <time>`, then `CAT mode is now off at <time>`.

---

## Step 10. Evidence (optional, for your portfolio)

```bash
./scripts/bash/07-evidence-export.sh
```

**You should see** `OK  Evidence written to evidence/<timestamp>`. It holds tool versions, test results, repo-check output, file hashes and object counts, plus a manifest. It contains no secrets or personal data. Look at it before you share it. The folder is already in `.gitignore`.

---

## Step 11. Tear down

```bash
./scripts/bash/02-cxone-inventory.sh
./scripts/bash/09-cxone-destroy.sh      # lists first; type DESTROY
./scripts/bash/19-aws-destroy.sh minimal   # type DESTROY
./scripts/bash/02-cxone-inventory.sh
```

**You should see** the objects listed before deletion, `OK  Destroyed.`, and in the last inventory a total of 0.

Then check your AWS billing page and your CXone contract for anything that remains. Studio scripts you made by hand are not removed by these scripts.

---

## Step 12. Put it on GitHub

```bash
python3 tools/check_repo.py
git init -b main
git add .
git status
```

Read the list. **You must not see** `.tfstate`, `.tfplan`, `.env`, `backend.tf`, `terraform.tfvars` or `evidence/`. If you do, stop and fix `.gitignore`.

```bash
git commit -m "Initial commit: NICE CXone enterprise insurance lab"
git remote add origin https://github.com/<you>/nice-cxone-enterprise-insurance-lab.git
git push -u origin main
```

**You should see** your files on GitHub and, within a minute or two, the **Actions** tab running the checks.

---

## Run the same checks CI runs

```bash
shellcheck -x scripts/bash/*.sh scripts/tests/*.sh scripts/tests/shims/*
python3 tools/check_repo.py
python3 -m pytest app tools -q
python3 tools/run_ai_eval.py
bash scripts/tests/test_cxone_scripts.sh bash
bash scripts/tests/test_aws_scripts.sh bash
( cd terraform && tofu fmt -check -recursive && tofu init -backend=false && tofu validate )
```

---

## What each script does

| Script | Purpose | Changes anything |
|---|---|---|
| `00-preflight.sh` | Tools, logins, tenant name | No |
| `01-verify-endpoints.sh` | Read-only check of the CXone API paths | No |
| `02-cxone-inventory.sh` | Counts lab objects in CXone | No |
| `03-cxone-plan.sh` | Shows what apply would create | No |
| `04-cxone-apply.sh` | Creates what is missing in CXone | **Yes** |
| `05-health-check.sh` | Calls the API's /health | No |
| `06-cat-mode.sh` | Reads or flips the catastrophe switch | **Yes** (on / off) |
| `07-evidence-export.sh` | Collects non-secret evidence | Writes local files |
| `09-cxone-destroy.sh` | Deletes lab-marked CXone objects | **Yes** |
| `10-aws-validate.sh` | Offline checks | No |
| `11-aws-plan.sh` | Plans the AWS build | No |
| `12-aws-apply.sh` | Builds AWS from the saved plan | **Yes** |
| `13-aws-seed.sh` | Loads fictional data | **Yes** |
| `14-aws-test-api.sh` | Smoke tests the API | Creates a test case |
| `19-aws-destroy.sh` | Deletes the AWS stack | **Yes** |
| `lib.sh` | Shared helpers, sourced not run | No |

All scripts stop at the first failure (`set -euo pipefail`). They never print the secret, the token or the API key.

**Common errors:** see `BUILD-MANUAL.md`, Part 12.
