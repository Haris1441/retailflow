"""File landing pipeline: simulate client deliveries, process the inbox once, or watch it.

  python -m landing simulate --scenario delivery|bad-name|bad-count|redeliver|resend
  python -m landing scan  [--trigger-dbt]
  python -m landing watch [--interval 15] [--max-cycles N] [--trigger-dbt]
  python -m landing status
"""

import argparse
import os
import shutil
import time
from contextlib import ExitStack
from functools import partial
from getpass import getpass
from pathlib import Path

from ingestion.bronze import load
from landing import dbt_cloud
from landing.files import control_path
from landing.processor import Landing, scan
from landing.registry import SnowflakeRegistry
from landing.simulator import BronzeTemplates, build_delivery, write_control, write_file


def connect(stack, args, database):
    import snowflake.connector

    credentials = {}
    if args.prompt_snowflake_password:
        credentials["password"] = getpass("Snowflake password: ")
    return stack.enter_context(snowflake.connector.connect(
        **credentials, connection_name=os.getenv("RETAILFLOW_SF_CONNECTION", "retailflow"),
        database=database, schema="CONTROL", paramstyle="pyformat", autocommit=True,
        session_parameters={"TIMEZONE": "UTC", "QUERY_TAG": "retailflow_phase_14"},
    ))


def simulate(args, landing, connection, database):
    inbox = landing.folder("inbox")
    if args.scenario == "bad-name":
        path = inbox / "customers_latest_FINAL.jsonl"
        path.write_text('{"note":"a file the client named by hand"}\n', encoding="utf-8")
        print(f"dropped {path.name}")
        return
    if args.scenario in ("redeliver", "resend"):
        source = landing.folder("archive" if args.scenario == "redeliver" else "error")
        files = sorted(source.rglob("retailco_*.jsonl"), key=lambda path: path.stat().st_mtime)
        if not files:
            raise SystemExit(f"Nothing in {source.name}/ to {args.scenario}")
        latest = files[-1]
        shutil.copy2(latest, inbox / latest.name)
        if args.scenario == "redeliver":
            shutil.copy2(control_path(latest), inbox / control_path(latest).name)
        else:
            # The client fixes the delivery: a correct control file for the same data.
            rows = sum(1 for line in latest.read_text(encoding="utf-8").splitlines() if line.strip())
            write_control(inbox / latest.name, rows)
            latest.unlink()
            control_path(latest).unlink(missing_ok=True)
        print(f"{args.scenario}: {latest.name}")
        return

    templates = BronzeTemplates(connection, database)
    delivery, files = build_delivery(templates)
    for name, rows in files.items():
        wrong = len(rows) + 1 if args.scenario == "bad-count" and "customers" in name else None
        if args.scenario == "bad-count" and wrong is None:
            continue  # the bad-count delivery holds only the broken customers file
        write_file(inbox, name, rows, row_count_override=wrong)
        print(f"dropped {name} ({len(rows)} rows{', control file says ' + str(wrong) if wrong else ''})")
    print(f"batch {delivery.batch_id}")


def run_scan(args, landing, connection, database):
    registry = SnowflakeRegistry(connection, database)
    for name in landing.recover_interrupted():
        print(f"recovered interrupted file {name}")
    loader = partial(load, connection, database=database)
    outcomes = scan(landing=landing, feeds=registry.feeds(), registry=registry, loader=loader)
    for outcome in outcomes:
        print(f"{outcome.status:9} {outcome.file_name}  {outcome.message}")
    loaded = [outcome for outcome in outcomes if outcome.status == "LOADED"]
    if loaded and args.trigger_dbt:
        if dbt_cloud.missing_settings():
            print("dbt trigger skipped, set: " + ", ".join(dbt_cloud.missing_settings()))
        else:
            cause = f"RetailFlow landing: {len(loaded)} file(s) loaded"
            print(f"dbt Cloud job finished: {dbt_cloud.run_job(cause)}")
    elif loaded:
        print("New data in Bronze. Run the dbt build (or pass --trigger-dbt).")
    return outcomes


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--landing-dir", default=os.getenv("RETAILFLOW_LANDING_DIR", "landing_zone"))
    parser.add_argument("--prompt-snowflake-password", action="store_true")
    commands = parser.add_subparsers(dest="command", required=True)
    sim = commands.add_parser("simulate", help="Drop files into the inbox as the client would")
    sim.add_argument("--scenario", default="delivery",
                     choices=("delivery", "bad-name", "bad-count", "redeliver", "resend"))
    for name in ("scan", "watch"):
        command = commands.add_parser(name)
        command.add_argument("--trigger-dbt", action="store_true")
    commands.choices["watch"].add_argument("--interval", type=int, default=15)
    commands.choices["watch"].add_argument("--max-cycles", type=int)
    commands.add_parser("status", help="Latest file registry rows")
    args = parser.parse_args()

    database = os.getenv("RETAILFLOW_SF_DATABASE", "RETAIL_DWH")
    landing = Landing(Path(args.landing_dir))
    if args.command == "simulate" and args.scenario in ("bad-name", "redeliver", "resend"):
        return simulate(args, landing, None, database)

    with ExitStack() as stack:
        connection = connect(stack, args, database)
        if args.command == "simulate":
            simulate(args, landing, connection, database)
        elif args.command == "scan":
            run_scan(args, landing, connection, database)
        elif args.command == "status":
            for row in SnowflakeRegistry(connection, database).recent():
                print(*row, sep=" | ")
        else:
            cycle = 0
            print(f"watching {landing.folder('inbox').resolve()} every {args.interval}s (Ctrl+C stops)")
            try:
                while args.max_cycles is None or cycle < args.max_cycles:
                    cycle += 1
                    if landing.candidates():
                        run_scan(args, landing, connection, database)
                    time.sleep(args.interval)
            except KeyboardInterrupt:
                print("stopped")


if __name__ == "__main__":
    main()
