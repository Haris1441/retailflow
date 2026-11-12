# Phase 1 design review

Review the [architecture and conceptual ERD](architecture.md), [source-to-target mapping](source_to_target_mapping.md) and [business rules](business_rules.md). The goal is to agree on fixture contracts before generating data.

From the repository root in PowerShell, run the SQL worked example with the installed Python SQLite shell. Amounts in this example are integer cents. The sample represents a fulfilled order, two items, a failed payment, a successful payment and one completed partial return.

```powershell
$pythonPath = uv --no-cache python find --offline --no-python-downloads 3.13
Get-Content -Raw .\scripts\phase-1-grain.sql | & $pythonPath -m sqlite3
```

Expect one tuple, (100, 5500, 5500, 2000, 3500), in order ID, recognized merchandise, collected cash, merchandise credit and net revenue order. If the shell reports an interpreter error, run the Phase 0 local check and use the full interpreter path. This local example checks the aggregation grain. Source fixture validation runs in Phase 2.

To demonstrate an invalid return in isolation, run the following SQLite query with the same shell. It returns line ID 1 because three units cannot be returned from a line that sold two. In the pipeline, keep the payload in Bronze, record the failed rule, and exclude the invalid return from published metrics.

```powershell
'WITH sold(line_id, qty) AS (VALUES (1, 2)), returned(line_id, qty) AS (VALUES (1, 3)) SELECT sold.line_id FROM sold JOIN returned USING (line_id) WHERE returned.qty > sold.qty;' | & $pythonPath -m sqlite3
```

Phase 1 is done when source ownership, intended grains, financial rules and the starter fixture contract are reviewed and accepted. Production would additionally require owner approval for finance policies, schema change review and service-level thresholds.
