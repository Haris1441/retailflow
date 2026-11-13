# Runs dbt Core from the project venv through the signed python.exe.
# Windows Smart App Control can block the unsigned dbt.exe launcher that pip creates;
# calling dbt's entry point through Python avoids it. Arguments pass straight to dbt.
#   .\scripts\dbt.ps1 --version
#   .\scripts\dbt.ps1 build --select tag:staging          (run from dbt_retailflow\ or pass --project-dir)
$python = Join-Path (Split-Path -Parent $PSScriptRoot) '.venv\Scripts\python.exe'
& $python -c "import sys; from dbt.cli.main import cli; sys.argv[0] = 'dbt'; cli()" @args
exit $LASTEXITCODE
