# Phase 14 on Azure: landing storage, Key Vault, Data Factory, pipeline and event trigger.
# Run after "az login". Safe to rerun: every step creates or updates in place.
#   powershell -ExecutionPolicy Bypass -File azure\deploy.ps1
# Names are saved to azure\deployment.json (no secrets in it).
param(
    [string]$Location = 'eastus',
    [string]$ResourceGroup = 'rg-retailflow',
    [string]$SnowflakeAccount = 'QREFHIF-KF84029'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateFile = Join-Path $root 'deployment.json'

function Az {
    $output = & az @args
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed with exit code $LASTEXITCODE" }
    return $output
}

function Retry([scriptblock]$Block, [string]$What) {
    for ($i = 1; $i -le 12; $i++) {
        try { return & $Block } catch {
            if ($i -eq 12) { throw }
            Write-Host "  waiting for $What (role assignments can take a minute)..."
            Start-Sleep -Seconds 15
        }
    }
}

function Grant([string]$Assignee, [string]$PrincipalType, [string]$Role, [string]$Scope) {
    $existing = Az role assignment list --assignee $Assignee --role $Role --scope $Scope --query "length(@)" -o tsv
    if ($existing -eq '0') {
        Retry { Az role assignment create --assignee-object-id $Assignee --assignee-principal-type $PrincipalType --role $Role --scope $Scope -o none } "role $Role"
    }
}

# Names stay the same on reruns.
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    $suffix = $state.suffix
} else {
    $suffix = -join ((97..122) + (48..57) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
}
$storage = "stretailflow$suffix"
$vault = "kv-retailflow-$suffix"
$factory = "adf-retailflow-$suffix"

$account = Az account show -o json | ConvertFrom-Json
$subscription = $account.id
$tenant = $account.tenantId
$me = Az ad signed-in-user show --query id -o tsv
Write-Host "Subscription $($account.name) ($subscription), tenant $tenant"

Write-Host '1/7 Resource providers'
foreach ($provider in 'Microsoft.Storage', 'Microsoft.KeyVault', 'Microsoft.DataFactory', 'Microsoft.EventGrid') {
    Az provider register --namespace $provider --wait -o none
}

Write-Host "2/7 Resource group $ResourceGroup ($Location)"
Az group create -n $ResourceGroup -l $Location -o none

Write-Host "3/7 Storage $storage (ADLS Gen2, container landing with inbox, archive, error)"
Az storage account create -n $storage -g $ResourceGroup -l $Location --sku Standard_LRS --kind StorageV2 `
    --hns true --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false -o none
$storageId = Az storage account show -n $storage -g $ResourceGroup --query id -o tsv
Grant $me 'User' 'Storage Blob Data Contributor' $storageId
Retry { Az storage fs create -n landing --account-name $storage --auth-mode login -o none 2>$null } 'storage access'
foreach ($folder in 'inbox', 'archive', 'error') {
    Retry { Az storage fs directory create -n $folder -f landing --account-name $storage --auth-mode login -o none } 'storage access'
}

Write-Host "4/7 Key Vault $vault (RBAC)"
$vaultExists = Az keyvault list -g $ResourceGroup --query "[?name=='$vault'] | length(@)" -o tsv
if ($vaultExists -eq '0') {
    Az keyvault create -n $vault -g $ResourceGroup -l $Location --enable-rbac-authorization true -o none
}
$vaultId = Az keyvault show -n $vault --query id -o tsv
Grant $me 'User' 'Key Vault Secrets Officer' $vaultId

Write-Host "5/7 Data Factory $factory (system-assigned identity)"
$base = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$ResourceGroup/providers/Microsoft.DataFactory/factories/$factory"
$api = 'api-version=2018-06-01'
$factoryBody = Join-Path $env:TEMP 'retailflow-factory.json'
@{ location = $Location; identity = @{ type = 'SystemAssigned' } } | ConvertTo-Json | Set-Content -Encoding ascii $factoryBody
Az rest --method put --url "$base`?$api" --body "@$factoryBody" -o none
$identity = Az rest --method get --url "$base`?$api" --query identity.principalId -o tsv
Grant $identity 'ServicePrincipal' 'Storage Blob Data Contributor' $storageId
Grant $identity 'ServicePrincipal' 'Key Vault Secrets User' $vaultId

Write-Host '6/7 Linked services, dataset, pipeline, trigger'
$values = @{ '{{STORAGE_ACCOUNT}}' = $storage; '{{KEY_VAULT}}' = $vault; '{{SNOWFLAKE_ACCOUNT}}' = $SnowflakeAccount; '{{STORAGE_ID}}' = $storageId }
$objects = @(
    @('linkedservices', 'ls_keyvault'), @('linkedservices', 'ls_landing'), @('linkedservices', 'ls_snowflake'),
    @('datasets', 'ds_landing_file'), @('pipelines', 'pl_ingest_landed_file'), @('triggers', 'tr_landing_inbox')
)
foreach ($object in $objects) {
    $kind, $name = $object
    if ($kind -eq 'triggers') {
        $runtime = Az rest --method get --url "$base/triggers/$name`?$api" --query properties.runtimeState -o tsv 2>$null
        if ($runtime -eq 'Started') { Write-Host "  $name is running; stop it to redeploy (azure\trigger.ps1 stop)"; continue }
    }
    $text = Get-Content (Join-Path $root "adf\$name.json") -Raw
    foreach ($key in $values.Keys) { $text = $text.Replace($key, $values[$key]) }
    $body = Join-Path $env:TEMP "retailflow-$name.json"
    Set-Content -Path $body -Value $text -Encoding ascii
    Az rest --method put --url "$base/$kind/$name`?$api" --body "@$body" -o none
    Write-Host "  $kind/$name"
}

Write-Host '7/7 Saving azure\deployment.json'
[ordered]@{
    suffix = $suffix; location = $Location; resourceGroup = $ResourceGroup; subscription = $subscription
    tenant = $tenant; storageAccount = $storage; keyVault = $vault; dataFactory = $factory
    snowflakeStageUrl = "azure://$storage.blob.core.windows.net/landing/inbox/"
} | ConvertTo-Json | Set-Content -Encoding ascii $stateFile

Write-Host ''
Write-Host "Done. For sql\snowflake\01_control\azure_landing.sql use:"
Write-Host "  AZURE_TENANT_ID  $tenant"
Write-Host "  STORAGE_ACCOUNT  $storage"
