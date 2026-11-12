# Plays the client on Azure: builds delivery files locally, then uploads them to landing/inbox/,
# data file first and control file last (the control file event is the "delivery complete" signal).
#   powershell -ExecutionPolicy Bypass -File azure\client.ps1 -Scenario delivery|redeliver|bad-name|bad-count|resend
# Local copies of everything sent are kept in landing_zone_client\sent\.
param(
    [ValidateSet('delivery', 'redeliver', 'bad-name', 'bad-count', 'resend')][string]$Scenario = 'delivery'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$state = Get-Content (Join-Path $repo 'azure\deployment.json') -Raw | ConvertFrom-Json
$client = Join-Path $repo 'landing_zone_client'
$outbox = Join-Path $client 'inbox'
$sent = Join-Path $client 'sent'
New-Item -ItemType Directory -Force $outbox, $sent | Out-Null
$python = Join-Path $repo '.venv\Scripts\python.exe'

function Upload([string]$Path) {
    $name = Split-Path -Leaf $Path
    & az storage blob upload --account-name $state.storageAccount -c landing -n "inbox/$name" -f $Path `
        --auth-mode login --overwrite -o none --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Upload of $name failed" }
    Write-Host "uploaded $name"
}

function Send([string]$DataPath) {
    $control = [IO.Path]::ChangeExtension($DataPath, '.ctl')
    Upload $DataPath
    if (Test-Path $control) { Start-Sleep -Seconds 2; Upload $control }
}

function Latest([string]$Entity) {
    $file = Get-ChildItem $sent -Filter "retailco_${Entity}_*.jsonl" | Sort-Object Name | Select-Object -Last 1
    if (-not $file) { throw "Nothing sent yet for $Entity" }
    return $file.FullName
}

Push-Location $repo
try {
    switch ($Scenario) {
        { $_ -in 'delivery', 'bad-count', 'bad-name' } {
            $extra = if ($Scenario -eq 'bad-name') { @() } else { @('--prompt-snowflake-password') }
            & $python -m landing --landing-dir $client @extra simulate --scenario $Scenario
            if ($LASTEXITCODE -ne 0) { throw 'Simulator failed' }
            foreach ($data in Get-ChildItem $outbox -File | Where-Object { $_.Extension -ne '.ctl' } | Sort-Object Name) {
                Send $data.FullName
                Move-Item -Force $data.FullName $sent
                $control = [IO.Path]::ChangeExtension($data.FullName, '.ctl')
                if (Test-Path $control) { Move-Item -Force $control $sent }
            }
        }
        'redeliver' { Send (Latest 'customer_events') }
        'resend' {
            # The client fixes the control file of its last customers delivery and sends both again.
            $data = Latest 'customers'
            $rows = @(Get-Content $data | Where-Object { $_.Trim() }).Count
            $sha = (Get-FileHash $data -Algorithm SHA256).Hash.ToLower()
            $control = [IO.Path]::ChangeExtension($data, '.ctl')
            [ordered]@{ file_name = (Split-Path -Leaf $data); row_count = $rows; sha256 = $sha } |
                ConvertTo-Json | Set-Content -Encoding ascii $control
            Send $data
        }
    }
} finally { Pop-Location }
