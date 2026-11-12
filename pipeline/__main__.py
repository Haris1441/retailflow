"""Run metadata-governed API incremental extraction."""

import argparse
import os
from contextlib import ExitStack
from datetime import datetime, timezone
from getpass import getpass

import httpx
import snowflake.connector

from ingestion.bronze import load
from ingestion.sources import API_KEYS, api_records
from pipeline.control import ControlStore, new_run_id


def required(name, parser):
    value = os.getenv(name)
    if not value:
        parser.error(f"Set {name} in this shell")
    return value


def latest_updated_at(records):
    return max(datetime.fromisoformat(record.updated_at.replace("Z", "+00:00")) for record in records)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    run = subparsers.add_parser("run")
    run.add_argument("--source", choices=("api",), default="api")
    run.add_argument("--entity", choices=API_KEYS, required=True)
    run.add_argument("--load-type", choices=("incremental",), default="incremental")
    run.add_argument("--prompt-snowflake-password", action="store_true")
    status = subparsers.add_parser("status")
    status.add_argument("--entity", choices=API_KEYS)
    status.add_argument("--prompt-snowflake-password", action="store_true")
    args = parser.parse_args()
    database = os.getenv("RETAILFLOW_SF_DATABASE", "RETAIL_DWH")
    credentials = {"password": getpass("Snowflake password: ")} if args.prompt_snowflake_password else {}
    if credentials.get("password") == "":
        parser.error("Snowflake password cannot be empty")

    with ExitStack() as stack:
        connection = stack.enter_context(snowflake.connector.connect(
            **credentials, connection_name=os.getenv("RETAILFLOW_SF_CONNECTION", "retailflow"),
            database=database, schema="CONTROL", paramstyle="pyformat", autocommit=True,
            session_parameters={"TIMEZONE": "UTC", "QUERY_TAG": "retailflow_phase_6"},
        ))
        control = ControlStore(connection, database)
        if args.command == "status":
            with connection.cursor() as cursor:
                sql = f"SELECT SOURCE_SYSTEM, ENTITY, LAST_SUCCESSFUL_WATERMARK, LAST_SUCCESSFUL_RUN_ID FROM {database}.CONTROL.WATERMARKS"
                if args.entity:
                    sql += " WHERE SOURCE_SYSTEM = 'MOCK_API' AND ENTITY = %s"
                    cursor.execute(sql, (args.entity,))
                else:
                    cursor.execute(sql)
                for row in cursor:
                    print(*row, sep=" | ")
            return

        token = required("RETAILFLOW_API_TOKEN", parser)
        config = control.get_entity("MOCK_API", args.entity)
        run_id = new_run_id()
        control.start(run_id, config.source, config.entity, args.load_type.upper())
        try:
            client = stack.enter_context(httpx.Client(base_url="http://127.0.0.1:8000", trust_env=False))
            extracted = list(api_records(client, token, args.entity, "normal"))
            selected = [record for record in extracted if config.extraction_start is None or
                        datetime.fromisoformat(record.updated_at.replace("Z", "+00:00")) >= config.extraction_start]
            result = load(connection, selected, database=database, source="MOCK_API",
                          batch="API_BATCH_001", entity=args.entity)
            control.succeed(run_id, config, latest_updated_at(selected))
        except BaseException as error:
            control.fail(run_id, str(error))
            raise
    print(f"run={run_id} entity={args.entity} start={config.extraction_start} "
          f"extracted={result.extracted} inserted={result.inserted} matched={result.matched}")


if __name__ == "__main__":
    main()
