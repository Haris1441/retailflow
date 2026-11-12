# Start, stop or show the ADF storage event trigger.
#   powershell -ExecutionPolicy Bypass -File azure\trigger.ps1 start|stop|status
param([ValidateSet('start', 'stop', 'status')][string]$Action = 'status')
$ErrorActionPreference = 'Stop'
$state = Get-Content (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'deployment.json') -Raw | ConvertFrom-Json
$url = "https://management.azure.com/subscriptions/$($state.subscription)/resourceGroups/$($state.resourceGroup)" +
       "/providers/Microsoft.DataFactory/factories/$($state.dataFactory)/triggers/tr_landing_inbox"
if ($Action -ne 'status') {
    & az rest --method post --url "$url/$Action`?api-version=2018-06-01" -o none
    if ($LASTEXITCODE -ne 0) { throw "Trigger $Action failed" }
}
& az rest --method get --url "$url`?api-version=2018-06-01" --query properties.runtimeState -o tsv
