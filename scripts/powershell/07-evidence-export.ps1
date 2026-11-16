# Collects non-secret evidence into evidence\<timestamp>\ with a SHA-256 manifest.
# Safe to hand to an auditor. Never contains tokens, keys, account ids or personal data.
. (Join-Path $PSScriptRoot 'lib.ps1')

$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$out = Join-Path $script:RepoRoot "evidence\$stamp"
New-Item -ItemType Directory -Path $out -Force | Out-Null

$py = 'python'; if (-not (Get-Command python -ErrorAction SilentlyContinue)) { $py = 'python3' }
$git = ''; try { $git = (& git -C $script:RepoRoot rev-parse --short HEAD 2>$null) } catch { }
if (-not $git) { $git = 'not a git repo' }
@("created_utc: $stamp", "git_commit: $git", ("python: " + (& $py --version 2>&1)), ("powershell: " + $PSVersionTable.PSVersion)) | Set-Content -Path (Join-Path $out 'environment.txt')

Push-Location $script:RepoRoot
try {
    (& $py tools/check_repo.py 2>&1) | Set-Content -Path (Join-Path $out 'repo-check.txt')
    Push-Location (Join-Path $script:RepoRoot 'app')
    try { (& $py -m pytest -q -p no:cacheprovider 2>&1) | Set-Content -Path (Join-Path $out 'unit-tests.txt') } finally { Pop-Location }

    $lines = @()
    foreach ($dir in @('cxone', 'openapi', 'terraform', 'app')) {
        Get-ChildItem -Path $dir -Recurse -File |
            Where-Object { $_.FullName -notmatch '[\\/]\.terraform[\\/]|__pycache__|\.pyc$' } |
            Sort-Object FullName |
            ForEach-Object {
                $rel = $_.FullName.Substring($script:RepoRoot.Length + 1).Replace('\', '/')
                $lines += ("{0}  {1}" -f (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash.ToLower(), $rel)
            }
    }
    $lines | Set-Content -Path (Join-Path $out 'file-hashes.txt')
} finally { Pop-Location }

if ($env:CXONE_TENANT_ID -and $env:CXONE_ACCESS_KEY_ID -and $env:CXONE_ACCESS_KEY_SECRET) {
    Connect-Cx | Out-Null
    $rows = foreach ($r in @('skills', 'teams', 'hoursOfOperation', 'dispositions', 'unavailableCodes', 'pointsOfContact')) { "{0}`t{1}" -f $r, @(Get-LabObjects $r).Count }
    $rows | Set-Content -Path (Join-Path $out 'cxone-lab-object-counts.tsv')
    Write-Ok 'CXone object counts included'
} else { Write-Info 'No CXone login in this window: object counts skipped.' }

Get-ChildItem -Path $out -File | Where-Object { $_.Name -ne 'MANIFEST.sha256' } |
    ForEach-Object { "{0}  {1}" -f (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash.ToLower(), $_.Name } |
    Set-Content -Path (Join-Path $out 'MANIFEST.sha256')
Write-Ok "Evidence written to evidence\$stamp"
Write-Info 'It is in .gitignore. Review it before you share it.'
