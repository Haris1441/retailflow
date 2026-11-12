-- Phase 14 on Azure · Snowflake side. Run in Snowsight as ACCOUNTADMIN, one part at a time.
-- Prerequisite: file_ingestion.sql (FILE_CONFIG, FILE_REGISTRY) has run.
--
-- Flow: a file lands in the Azure container landing/inbox/ -> Event Grid -> the ADF trigger calls
-- CONTROL.PROCESS_LANDED_FILE(<blob name>) through the service user RETAILFLOW_ADF_USER. The
-- procedure reads the file from the external stage below, and applies the same contract as the
-- local landing package. It matches the FILE_CONFIG regex, checks the control file (row count,
-- SHA-256), skips content already loaded, MERGEs into Bronze with an audit row in one
-- transaction, and records the attempt in FILE_REGISTRY. ADF then moves the files to archive/
-- or error/ according to the returned status.
USE ROLE ACCOUNTADMIN;
USE DATABASE RETAIL_DWH;

------------------------------------------------------------------------------------------------
-- PART A · Storage integration: lets Snowflake read the container without any stored key.
------------------------------------------------------------------------------------------------
CREATE STORAGE INTEGRATION IF NOT EXISTS AZURE_LANDING_INT
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'AZURE'
    ENABLED = TRUE
    AZURE_TENANT_ID = '<AZURE_TENANT_ID>'
    STORAGE_ALLOWED_LOCATIONS = ('azure://<STORAGE_ACCOUNT>.blob.core.windows.net/landing/');

DESC STORAGE INTEGRATION AZURE_LANDING_INT;
-- Copy two values from the result:
--   AZURE_CONSENT_URL           open it, sign in to Azure and accept (creates Snowflake's app in your tenant)
--   AZURE_MULTI_TENANT_APP_NAME the part before the underscore is the app name to grant access to
-- Then the storage role assignment is done from the Azure CLI (docs/phase-14-azure.md, step 4).

------------------------------------------------------------------------------------------------
-- PART B · Stage, procedure and the ADF service user. Run after the consent and role assignment.
------------------------------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS CONTROL.AZURE_INBOX
    URL = 'azure://<STORAGE_ACCOUNT>.blob.core.windows.net/landing/inbox/'
    STORAGE_INTEGRATION = AZURE_LANDING_INT
    COMMENT = 'Phase 14: client files delivered to the Azure landing container';

LIST @CONTROL.AZURE_INBOX;   -- must run without an access error (an empty result is fine)

CREATE OR REPLACE PROCEDURE CONTROL.PROCESS_LANDED_FILE(BLOB_NAME VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'simplejson')
HANDLER = 'run'
EXECUTE AS CALLER
COMMENT = 'Phase 14: validate and load one landed file. Returns status and the files ADF should move.'
AS
$$
import hashlib
import json
import re
from datetime import datetime, timezone
from uuid import uuid4

import simplejson
from snowflake.snowpark.files import SnowflakeFile

DB = "RETAIL_DWH"
STAGE = f"@{DB}.CONTROL.AZURE_INBOX"
REGISTRY = f"{DB}.CONTROL.FILE_REGISTRY"
TARGET = f"{DB}.BRONZE.SOURCE_RECORDS"
AUDIT = f"{DB}.AUDIT.BRONZE_LOAD_RUNS"
EVENT_FIELDS = ("event_timestamp", "order_date", "payment_timestamp", "requested_at", "applied_at", "created_at")
ENVELOPE = ("entity", "source_record_id", "business_key", "operation", "effective_at",
            "source_available_at", "payload")
OPERATIONS = {"INSERT", "UPDATE", "DELETE"}
COLUMNS = ("SOURCE_SYSTEM, ENTITY, SOURCE_RECORD_ID, BUSINESS_KEY, BATCH_ID, SOURCE_OPERATION, "
           "SOURCE_EVENT_AT, SOURCE_UPDATED_AT, SOURCE_EFFECTIVE_AT, SOURCE_AVAILABLE_AT, "
           "EXTRACTED_AT, RUN_ID, RECORD_HASH, RAW_PAYLOAD")
IDENTITY = ("t.SOURCE_SYSTEM = s.SOURCE_SYSTEM AND t.ENTITY = s.ENTITY "
            "AND t.SOURCE_RECORD_ID = s.SOURCE_RECORD_ID")


class Rejected(Exception):
    pass


def read_bytes(name):
    try:
        with SnowflakeFile.open(f"{STAGE}/{name}", "rb", require_scoped_url=False) as handle:
            return handle.read()
    except Exception:
        return None


def outcome(status, message, files, **extra):
    return {"status": status, "message": message, "files": files, **extra}


def sql(session, text, params=None):
    return session.sql(text, params=params).collect()


def start(session, name, sha, size, feed=None, batch=None):
    attempt = uuid4().hex
    sql(session, f"""INSERT INTO {REGISTRY} (ATTEMPT_ID, FILE_NAME, FILE_SHA256, FILE_SIZE_BYTES, FEED_NAME,
                     SOURCE_SYSTEM, ENTITY, BATCH_ID, STATUS) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'RECEIVED')""",
        [attempt, name, sha, size, feed[0] if feed else None, feed[1] if feed else None,
         feed[2] if feed else None, batch])
    return attempt


def finish(session, attempt, status, message=None, counts=(None, None, None, None)):
    sql(session, f"""UPDATE {REGISTRY} SET STATUS = ?, ERROR_MESSAGE = ?, EXTRACTED_ROWS = ?, INSERTED_ROWS = ?,
                     MATCHED_ROWS = ?, RUN_ID = ?, FINISHED_AT = CURRENT_TIMESTAMP() WHERE ATTEMPT_ID = ?""",
        [status, (message or None) and message[:4000], *counts, attempt])


def to_rows(data, entity, source, batch, expected):
    rows, now = [], datetime.now(timezone.utc).isoformat()
    for number, line in enumerate(data.decode("utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = simplejson.loads(line, use_decimal=True)
            missing = [field for field in ENVELOPE if field not in row]
            if missing:
                raise ValueError("missing " + ", ".join(missing))
            if row["entity"] != entity:
                raise ValueError(f"entity {row['entity']} does not belong to this feed")
            if row["operation"] not in OPERATIONS:
                raise ValueError(f"unknown operation {row['operation']}")
            payload = simplejson.dumps(row["payload"], sort_keys=True, use_decimal=True, separators=(",", ":"))
            parsed = json.loads(payload)
            if not isinstance(parsed, dict) or not row["source_record_id"] or not row["business_key"]:
                raise ValueError("invalid envelope")
            event_at = next((parsed[f] for f in EVENT_FIELDS if parsed.get(f)), None)
            updated_at = parsed.get("updated_at")
            key, operation = str(row["business_key"]), row["operation"]
            effective_at, available_at = row["effective_at"], row["source_available_at"]
            # Same record hash as the local loader (ingestion.sources.Record.digest).
            metadata = (key, batch, operation, event_at, updated_at, effective_at, available_at,
                        simplejson.loads(payload, use_decimal=True))
            digest = hashlib.sha256(simplejson.dumps(metadata, sort_keys=True, use_decimal=True).encode()).hexdigest()
            rows.append((source, entity, str(row["source_record_id"]), key, batch, operation, event_at,
                         updated_at, effective_at, available_at, now, digest, payload))
        except (ValueError, TypeError) as error:
            raise Rejected(f"Line {number}: {error}")
    if not rows:
        raise Rejected("The file has no records")
    if expected is not None and len(rows) != expected:
        raise Rejected(f"Control file promises {expected} rows, the file has {len(rows)}")
    return rows


def load(session, rows, source, batch, entity):
    run_id = uuid4().hex
    stage = f"{DB}.BRONZE.TMP_LANDING_{run_id.upper()}"
    unique = (f"SELECT * FROM {stage} QUALIFY ROW_NUMBER() OVER (PARTITION BY SOURCE_SYSTEM, ENTITY, "
              f"SOURCE_RECORD_ID ORDER BY EXTRACTED_AT) = 1")
    sql(session, f"""CREATE TEMPORARY TABLE {stage} (SOURCE_SYSTEM VARCHAR, ENTITY VARCHAR, SOURCE_RECORD_ID VARCHAR,
        BUSINESS_KEY VARCHAR, BATCH_ID VARCHAR, SOURCE_OPERATION VARCHAR, SOURCE_EVENT_AT VARCHAR,
        SOURCE_UPDATED_AT VARCHAR, SOURCE_EFFECTIVE_AT VARCHAR, SOURCE_AVAILABLE_AT VARCHAR, EXTRACTED_AT VARCHAR,
        RUN_ID VARCHAR, RECORD_HASH VARCHAR, RAW_PAYLOAD VARCHAR)""")
    for chunk_start in range(0, len(rows), 200):
        chunk = rows[chunk_start:chunk_start + 200]
        values = ", ".join(["(" + ", ".join(["?"] * 14) + ")"] * len(chunk))
        params = [value for row in chunk for value in (*row[:11], run_id, *row[11:])]
        sql(session, f"INSERT INTO {stage} ({COLUMNS}) VALUES {values}", params)
    sql(session, "BEGIN")
    try:
        staged, distinct, conflicts = sql(session, f"""SELECT COALESCE(SUM(copies), 0), COUNT(*), COUNT_IF(hashes <> 1)
            FROM (SELECT COUNT(*) AS copies, COUNT(DISTINCT RECORD_HASH) AS hashes FROM {stage}
                  GROUP BY SOURCE_SYSTEM, ENTITY, SOURCE_RECORD_ID)""")[0]
        if staged != len(rows) or conflicts:
            raise Rejected("Incomplete or conflicting deliveries inside the file")
        matched, conflicts = sql(session, f"""SELECT COUNT(*), COUNT_IF(t.RECORD_HASH <> s.RECORD_HASH)
            FROM ({unique}) AS s JOIN {TARGET} AS t ON {IDENTITY}""")[0]
        if conflicts:
            raise Rejected("Bronze already contains a different image for a source record ID")
        inserted = sql(session, f"""MERGE INTO {TARGET} AS t USING ({unique}) AS s ON {IDENTITY}
            WHEN NOT MATCHED THEN INSERT ({COLUMNS}) VALUES (
                s.SOURCE_SYSTEM, s.ENTITY, s.SOURCE_RECORD_ID, s.BUSINESS_KEY, s.BATCH_ID, s.SOURCE_OPERATION,
                TO_TIMESTAMP_TZ(s.SOURCE_EVENT_AT), TO_TIMESTAMP_TZ(s.SOURCE_UPDATED_AT),
                TO_TIMESTAMP_TZ(s.SOURCE_EFFECTIVE_AT), TO_TIMESTAMP_TZ(s.SOURCE_AVAILABLE_AT),
                TO_TIMESTAMP_TZ(s.EXTRACTED_AT), s.RUN_ID, s.RECORD_HASH, PARSE_JSON(s.RAW_PAYLOAD))""")[0][0]
        landed, conflicts = sql(session, f"""SELECT COUNT(*), COUNT_IF(t.RECORD_HASH <> s.RECORD_HASH)
            FROM ({unique}) AS s JOIN {TARGET} AS t ON {IDENTITY}""")[0]
        if landed != distinct or matched + inserted != distinct or conflicts:
            raise Rejected("Bronze reconciliation failed")
        sql(session, f"""INSERT INTO {AUDIT} (RUN_ID, SOURCE_SYSTEM, BATCH_ID, ENTITY_SCOPE, EXTRACTED_COUNT,
            DISTINCT_COUNT, INSERTED_COUNT, MATCHED_COUNT) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            [run_id, source, batch, entity, len(rows), distinct, inserted, matched])
        sql(session, "COMMIT")
    except BaseException:
        sql(session, "ROLLBACK")
        raise
    return len(rows), inserted, matched, run_id


def run(session, blob_name):
    name = blob_name.rsplit("/", 1)[-1]
    feeds = [(r[0], r[1], r[2], re.compile(r[3]), bool(r[4])) for r in sql(session, f"""
        SELECT FEED_NAME, SOURCE_SYSTEM, ENTITY, FILE_PATTERN, REQUIRES_CONTROL_FILE
        FROM {DB}.CONTROL.FILE_CONFIG WHERE IS_ENABLED""")]

    # The control file is the "delivery complete" signal. A data file event only checks the name.
    if name.endswith(".ctl"):
        data_name, control_name = name[:-4] + ".jsonl", name
    else:
        data_name, control_name = name, name.rsplit(".", 1)[0] + ".ctl"

    data = read_bytes(data_name)
    if data is None:
        return outcome("WAITING", f"Data file {data_name} is not in the inbox", [])
    sha, size = hashlib.sha256(data).hexdigest(), len(data)
    control = read_bytes(control_name)
    files = [data_name] + ([control_name] if control is not None else [])

    hits = [feed for feed in feeds if feed[3].fullmatch(data_name)]
    if len(hits) != 1:
        reason = "File name matches no enabled feed pattern" if not hits else "File name matches more than one feed"
        attempt = start(session, data_name, sha, size)
        finish(session, attempt, "REJECTED", reason)
        return outcome("REJECTED", reason, files)
    feed = hits[0]
    if feed[4] and (control is None or not name.endswith(".ctl")):
        return outcome("WAITING", "Waiting for the control file event", [])

    batch = "BATCH_" + feed[3].fullmatch(data_name)["batch_ts"]
    attempt = start(session, data_name, sha, size, feed, batch)
    try:
        already = sql(session, f"SELECT FILE_NAME FROM {REGISTRY} WHERE FILE_SHA256 = ? AND STATUS = 'LOADED' LIMIT 1", [sha])
        if already:
            message = f"Identical content already loaded as {already[0][0]}"
            finish(session, attempt, "SKIPPED", message)
            return outcome("SKIPPED", message, files, batch_id=batch)
        expected = None
        if control is not None:
            try:
                body = json.loads(control.decode("utf-8"))
                promised = (str(body["file_name"]), int(body["row_count"]), str(body["sha256"]).lower())
            except (ValueError, KeyError, TypeError) as error:
                raise Rejected(f"Unreadable control file: {error}")
            if promised[0] != data_name:
                raise Rejected(f"Control file names {promised[0]}, not {data_name}")
            if promised[2] != sha:
                raise Rejected("Checksum differs from the control file: the file is incomplete or changed")
            expected = promised[1]
        sql(session, f"UPDATE {REGISTRY} SET EXPECTED_ROWS = ? WHERE ATTEMPT_ID = ?", [expected, attempt])
        rows = to_rows(data, feed[2], feed[1], batch, expected)
        counts = load(session, rows, feed[1], batch, feed[2])
    except Exception as error:
        finish(session, attempt, "FAILED", str(error))
        return outcome("FAILED", str(error), files, batch_id=batch)
    finish(session, attempt, "LOADED", None, counts)
    return outcome("LOADED", f"run {counts[3]}", files, batch_id=batch, extracted=counts[0],
                   inserted=counts[1], matched=counts[2], run_id=counts[3])
$$;

-- The ADF service user. Key pair only (no password). Generate the key on your PC, keep the
-- private key out of Git and chat (docs/phase-14-azure.md, step 5), and paste only the PUBLIC
-- key body below.
CREATE USER IF NOT EXISTS RETAILFLOW_ADF_USER
    TYPE = SERVICE
    DEFAULT_ROLE = RETAILFLOW_LOADER
    DEFAULT_WAREHOUSE = RETAILFLOW_WH
    DEFAULT_NAMESPACE = RETAIL_DWH.CONTROL
    COMMENT = 'Azure Data Factory: calls CONTROL.PROCESS_LANDED_FILE';
ALTER USER RETAILFLOW_ADF_USER SET RSA_PUBLIC_KEY = '<PUBLIC_KEY_BODY_WITHOUT_HEADER_LINES>';
GRANT ROLE RETAILFLOW_LOADER TO USER RETAILFLOW_ADF_USER;

-- The loader role already writes Bronze, the audit and the registry. It also needs the stage
-- and the procedure.
GRANT USAGE ON INTEGRATION AZURE_LANDING_INT TO ROLE RETAILFLOW_LOADER;
GRANT USAGE ON STAGE CONTROL.AZURE_INBOX TO ROLE RETAILFLOW_LOADER;
GRANT USAGE ON PROCEDURE CONTROL.PROCESS_LANDED_FILE(VARCHAR) TO ROLE RETAILFLOW_LOADER;

-- Smoke test with an empty inbox: expect {"status": "WAITING", ...}
CALL CONTROL.PROCESS_LANDED_FILE('retailco_customers_20000101T000000_001.ctl');
