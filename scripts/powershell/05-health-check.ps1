# Calls the AWS integration layer's /health. Changes nothing. Never prints the API key.
# Reads the URL and key from the OpenTofu outputs, or from KESTREL_API_URL / KESTREL_API_KEY.
. (Join-Path $PSScriptRoot 'lib.ps1')

$url = $env:KESTREL_API_URL
if (-not $url) {
    Push-Location $script:TfDir
    try { $url = (& (Get-TfBin) output -raw api_url) } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0 -or -not $url) { Stop-Fail 'Set KESTREL_API_URL, or apply the AWS side first (12-aws-apply.ps1).' }
}
$key = $env:KESTREL_API_KEY
if (-not $key) { Push-Location $script:TfDir; try { $key = (& (Get-TfBin) output -raw api_key_value) } finally { Pop-Location } }

$code = 0; $text = ''
try {
    $r = Invoke-WebRequest -Method Get -Uri ($url.TrimEnd('/') + '/health') -Headers @{ 'x-api-key' = $key } -UseBasicParsing
    $code = [int]$r.StatusCode; $text = [string]$r.Content
} catch {
    $code = Get-HttpStatus $_; $text = Get-HttpErrorText $_
}
$key = $null
Write-Host "HTTP $code"
try { $text | ConvertFrom-Json | ConvertTo-Json -Depth 5 } catch { Write-Host $text }
if ($code -ne 200) { Stop-Fail 'The integration layer is not healthy.' }
Write-Ok 'Integration layer healthy'
