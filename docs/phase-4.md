# Phase 4 · Local mock REST source

The API represents an independent web storefront. Each of the five collections has eight deterministic records. All transactional identities are API-prefixed. Products API-PRODUCT-1 and API-PRODUCT-2 map to BigQuery catalog IDs 1 and 2. API-WEB-US maps to BigQuery store 2. The payments collection owns cash events. Nested order payments carry references for enrichment. Amounts are decimal strings to preserve exact values across JSON.

## Run locally

From the repository root in PowerShell, create the environment and install requirements if needed.

```powershell
uv --no-cache venv --offline --no-python-downloads --python 3.13 .venv
uv --no-cache pip install --python .venv/Scripts/python.exe -r api/requirements.txt
.\.venv\Scripts\python.exe -m pytest -q api/tests
```

In the first PowerShell terminal, use a local development token and start the loopback server.

```powershell
$env:RETAILFLOW_API_TOKEN = 'retailflow-local-demo'
.\.venv\Scripts\python.exe -m uvicorn api.app.main:app --host 127.0.0.1 --port 8000
```

Open http://127.0.0.1:8000/docs and use **Authorize** with the same token, or use a second PowerShell terminal at the repo root.

```powershell
$env:RETAILFLOW_API_TOKEN = 'retailflow-local-demo'
$headers = @{Authorization = "Bearer $env:RETAILFLOW_API_TOKEN"}
Invoke-RestMethod -Headers $headers -Uri 'http://127.0.0.1:8000/api/v1/orders/API-ORDER-001' |
    ConvertTo-Json -Depth 10
.\.venv\Scripts\python.exe -m api.app.client orders
.\.venv\Scripts\python.exe -m api.app.client orders --scenario rate_limit
.\.venv\Scripts\python.exe -m api.app.client orders --scenario server_error
.\.venv\Scripts\python.exe -m api.app.client orders --scenario duplicate
.\.venv\Scripts\python.exe -m api.app.client orders --scenario empty
.\.venv\Scripts\python.exe -m api.app.client orders --updated-since '2025-01-15T00:00:00Z'
.\.venv\Scripts\python.exe -m api.app.client orders --scenario malformed
```

| Scenario | Expected result |
| --- | --- |
| Order detail | Two distinct line IDs for one product, one nested discount, one shipment and one payment reference. Header and successful payment each total USD 26.00. |
| Normal, rate limit, server error | Eight deliveries and eight distinct keys each. The client retries the initial 429 or 500 and follows the next page. |
| Duplicate | Ten deliveries and eight distinct keys with the default page size. Preserve deliveries for later reconciliation. |
| Empty | Zero deliveries. |
| Updated since | One delivery for API-ORDER-001. The January 2 order has a January 15 update and is included at the exact lower boundary. |
| Malformed | Client raises a page-specific error for a missing business key. A future ingestion runner must avoid advancing its checkpoint after this failure. |

## Contract and troubleshooting

Collections are /api/v1/orders, /api/v1/customers, /api/v1/payments, /api/v1/events and /api/v1/inventory. Use page starting at 1 and page_size from 1 to 100. Responses include items, page, page_size, next_page and total_records. In the duplicate scenario, an extra boundary record can make a page exceed page_size. total_records counts the underlying filtered rows. Sort by UTC updated_at and business key. updated_since is inclusive and requires an offset.

The first page and first attempt return the simulated fault in rate_limit or server_error mode. The test client sends X-Fixture-Attempt so recovery is deterministic. Requests time out after five seconds and get up to three attempts on transport errors and selected transient statuses. Backoff starts at half a second and respects the mock server's numeric Retry-After within a five-second cap.

A 401 means the token is missing or differs between terminals. A 503 on a normal request means the server environment has no token. A 422 points to invalid query input such as a timestamp without an offset. A connection failure usually means the server stopped or could not bind to port 8000. Stop a server you started with Ctrl+C.

Stable page numbers are sufficient for these immutable fixtures. A production API with concurrent writes needs a snapshot token or cursor with stable bounds, a documented retry and rate-limit policy, secure credentials and observability. Persist extraction state and publish only after a whole page sequence and its reconciliation pass.

## Definition of done

The endpoint tests pass and the local smoke commands return their expected outcomes. Source ownership and nested grains are documented. Snowflake integration begins in Phase 5 after confirmation. [FastAPI testing reference](https://fastapi.tiangolo.com/tutorial/testing/)
