$tools = 'git', 'uv', 'gcloud', 'bq', 'snow', 'dbt', 'code'
Write-Output "PowerShell $($PSVersionTable.PSVersion)"

foreach ($tool in $tools) {
    if (Get-Command $tool -ErrorAction SilentlyContinue) {
        Write-Output "[$tool]"
        & $tool --version
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "$tool version check failed with exit code $LASTEXITCODE."
        }
    } else {
        Write-Output "$tool is unavailable on PATH"
    }
}

if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-Output '[Installed Python interpreters]'
    & uv --no-cache python list --only-installed --offline
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Python discovery failed with exit code $LASTEXITCODE."
    }
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    & python --version
} else {
    Write-Output 'Python is unavailable on PATH'
}
