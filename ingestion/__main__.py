"""Run one full baseline scope or one explicit fixture change batch."""

import argparse
import os
from contextlib import ExitStack
from getpass import getpass

from ingestion.bronze import load
from ingestion.sources import API_KEYS, BIGQUERY_KEYS, api_records, bigquery_records


def required(name, parser):
    value = os.getenv(name)
    if not value:
        parser.error(f"Set {name} in this shell")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", choices=("bigquery", "api"))
    parser.add_argument("--batch", choices=[f"BATCH_{n:03}" for n in range(1, 9)],
                        default="BATCH_001")
    parser.add_argument("--entity")
    parser.add_argument("--scenario", choices=("normal", "duplicate"), default="normal")
    parser.add_argument("--chunk-size", type=int, default=250, choices=range(1, 501),
                        metavar="1-500")
    parser.add_argument("--prompt-snowflake-password", action="store_true",
                        help="Read the Snowflake password without echoing it")
    parser.add_argument("--prompt-snowflake-passcode", action="store_true",
                        help="Read the Snowflake MFA passcode without echoing it")
    args = parser.parse_args()
    keys = BIGQUERY_KEYS if args.source == "bigquery" else API_KEYS
    if args.entity and args.entity not in keys:
        parser.error(f"Unknown entity for {args.source}")
    if args.batch != "BATCH_001" and (args.source == "api" or args.entity):
        parser.error("Change batches are whole-batch BigQuery loads")
    if args.source == "bigquery" and args.scenario != "normal":
        parser.error("The duplicate scenario is available for API loads")

    import snowflake.connector

    database = os.getenv("RETAILFLOW_SF_DATABASE", "RETAIL_DWH")
    with ExitStack() as stack:
        if args.source == "bigquery":
            from google.cloud import bigquery

            project = required("RETAILFLOW_BQ_PROJECT", parser)
            dataset = os.getenv("RETAILFLOW_BQ_DATASET", "retailflow_source")
            location = os.getenv("RETAILFLOW_BQ_LOCATION", "US")
            max_bytes = int(os.getenv("RETAILFLOW_BQ_MAX_BYTES", "1073741824"))
            if max_bytes <= 0:
                parser.error("RETAILFLOW_BQ_MAX_BYTES must be positive")
            client = bigquery.Client(project=project, location=location)
            stack.callback(client.close)
            source, batch = "BIGQUERY", args.batch
            records = bigquery_records(client, project, dataset, location, batch, args.entity, max_bytes)
        else:
            import httpx

            token = required("RETAILFLOW_API_TOKEN", parser)
            client = stack.enter_context(httpx.Client(base_url="http://127.0.0.1:8000", trust_env=False))
            source, batch = "MOCK_API", "API_BATCH_001"
            records = api_records(client, token, args.entity, args.scenario)

        credentials = {}
        if args.prompt_snowflake_password:
            credentials["password"] = getpass("Snowflake password: ")
            if not credentials["password"]:
                parser.error("Snowflake password cannot be empty")
        if args.prompt_snowflake_passcode:
            credentials["passcode"] = getpass("Snowflake MFA passcode: ")
            if not credentials["passcode"]:
                parser.error("Snowflake MFA passcode cannot be empty")
        connection = stack.enter_context(snowflake.connector.connect(
            **credentials,
            connection_name=os.getenv("RETAILFLOW_SF_CONNECTION", "retailflow"),
            database=database, schema="BRONZE", paramstyle="pyformat", autocommit=True,
            session_parameters={"TIMEZONE": "UTC", "QUERY_TAG": "retailflow_phase_5"},
        ))
        result = load(connection, records, database=database, source=source, batch=batch,
                      entity=args.entity, chunk_size=args.chunk_size)
    print(f"run={result.run_id} source={source} batch={batch} "
          f"extracted={result.extracted} distinct={result.distinct} "
          f"inserted={result.inserted} matched={result.matched}")


if __name__ == "__main__":
    main()
