#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


DEFAULT_BUNDLE_ID = "fukujusou.openchat.com"
DEFAULT_PROCESS_NAME = "OpenChat"
DEFAULT_TEMPLATE = "Time Profiler"
DEFAULT_TIME_LIMIT = "60s"
DEFAULT_OUTPUT_ROOT = Path("/private/tmp")


class TraceScriptError(Exception):
    pass


@dataclass(frozen=True)
class DeviceCandidate:
    name: str
    os_version: str
    identifier: str


@dataclass(frozen=True)
class PrepareResult:
    device: DeviceCandidate
    app: dict[str, Any] | None
    process: dict[str, Any] | None
    apps_json: Path
    processes_json: Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Collect an xctrace profile from an already configured OpenChat app "
            "on a real iOS device. The script never installs, uninstalls, or clears data."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    doctor = subparsers.add_parser("doctor", help="Check local xctrace/devicectl availability.")
    doctor.add_argument(
        "--skip-devices",
        action="store_true",
        help="Skip device listing; useful while the phone is updating or disconnected.",
    )

    prepare = subparsers.add_parser(
        "prepare",
        help="Check device, installed app, and running OpenChat process without tracing.",
    )
    add_device_args(prepare)
    add_app_args(prepare)
    add_run_dir_args(prepare)

    record = subparsers.add_parser(
        "record",
        help="Attach Time Profiler to the running OpenChat process and save a .trace.",
    )
    add_device_args(record)
    add_app_args(record)
    add_run_dir_args(record)
    record.add_argument(
        "--template",
        default=DEFAULT_TEMPLATE,
        help=f"xctrace template name. Default: {DEFAULT_TEMPLATE!r}.",
    )
    record.add_argument(
        "--time-limit",
        default=DEFAULT_TIME_LIMIT,
        help=f"Recording duration accepted by xctrace, e.g. 45s or 2m. Default: {DEFAULT_TIME_LIMIT}.",
    )
    record.add_argument(
        "--attach",
        help=(
            "Explicit PID or process name to attach. Default: use the running "
            "OpenChat PID discovered by devicectl."
        ),
    )
    record.add_argument(
        "--allow-prompts",
        action="store_true",
        help="Allow xctrace to show prompts. Default uses --no-prompt to fail instead of hanging.",
    )
    record.add_argument(
        "--no-export-toc",
        action="store_true",
        help="Do not export xctrace table-of-contents XML after recording.",
    )
    record.add_argument(
        "--scenario",
        default="long-stream-real-endpoint",
        help="Short scenario label written to capture-notes.md and manifest.json.",
    )

    export = subparsers.add_parser("export", help="Export TOC or custom XPath XML from a .trace.")
    export.add_argument("--trace", required=True, type=Path, help="Path to a .trace package.")
    export.add_argument(
        "--output-dir",
        type=Path,
        help="Directory for exported XML. Default: <trace parent>/exports.",
    )
    export.add_argument(
        "--xpath",
        action="append",
        default=[],
        help="Optional XPath expression to export. Can be passed multiple times.",
    )

    return parser.parse_args()


def add_device_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--device",
        help="Device UDID or name. If omitted, auto-pick the single connected iOS device.",
    )


def add_app_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--bundle-id",
        default=DEFAULT_BUNDLE_ID,
        help=f"Installed app bundle identifier. Default: {DEFAULT_BUNDLE_ID}.",
    )
    parser.add_argument(
        "--process-name",
        default=DEFAULT_PROCESS_NAME,
        help=f"Process executable name. Default: {DEFAULT_PROCESS_NAME}.",
    )


def add_run_dir_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--run-dir",
        type=Path,
        help="Directory for logs, JSON snapshots, manifest, and traces.",
    )
    parser.add_argument(
        "--label",
        default="openchat-long-stream",
        help="Run label used in default output directory and trace file names.",
    )


def main() -> int:
    args = parse_args()
    try:
        if args.command == "doctor":
            doctor(args)
        elif args.command == "prepare":
            prepare(args)
        elif args.command == "record":
            record(args)
        elif args.command == "export":
            export_trace(args)
        else:
            raise TraceScriptError(f"unknown command: {args.command}")
    except TraceScriptError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        return 130
    return 0


def doctor(args: argparse.Namespace) -> None:
    print("Checking xctrace templates...")
    templates = run_capture(["xcrun", "xctrace", "list", "templates"])
    require_contains(templates.stdout, DEFAULT_TEMPLATE, "xctrace template")
    print(f"  found template: {DEFAULT_TEMPLATE}")

    print("Checking xctrace instruments...")
    instruments = run_capture(["xcrun", "xctrace", "list", "instruments"])
    for instrument in ["Time Profiler", "SwiftUI", "Hitches"]:
        if instrument in instruments.stdout:
            print(f"  found instrument: {instrument}")

    print("Checking devicectl...")
    run_capture(["xcrun", "devicectl", "--version"])
    print("  devicectl is available")

    if args.skip_devices:
        print("Skipped device listing.")
        return

    candidates = list_device_candidates()
    if not candidates:
        print("No connected iOS device candidates found.")
        return

    print("Connected iOS device candidates:")
    for device in candidates:
        print(f"  {device.name} ({device.os_version}) {device.identifier}")


def prepare(args: argparse.Namespace) -> None:
    run_dir = ensure_run_dir(args.run_dir, args.label)
    result = collect_prepare_result(args, run_dir)
    print_prepare_result(result, args.bundle_id, args.process_name)
    write_prepare_manifest(run_dir, args, result)
    print(f"Run files: {run_dir}")


def record(args: argparse.Namespace) -> None:
    validate_duration(args.time_limit)
    run_dir = ensure_run_dir(args.run_dir, args.label)
    result = collect_prepare_result(args, run_dir)
    print_prepare_result(result, args.bundle_id, args.process_name)

    if result.app is None:
        raise TraceScriptError(
            f"{args.bundle_id} is not installed on {result.device.name}. "
            "Install/open the already configured app before recording."
        )

    attach_target = args.attach or process_identifier(result.process)
    if attach_target is None:
        raise TraceScriptError(
            "OpenChat is installed but not currently running. Open the configured app "
            "on the phone, navigate to the chat screen, then rerun the record command."
        )

    trace_path = run_dir / f"{sanitize_label(args.label)}.trace"
    notes_path = write_capture_notes(run_dir, args, result)
    command = [
        "xcrun",
        "xctrace",
        "record",
        "--template",
        args.template,
        "--device",
        result.device.identifier,
        "--attach",
        str(attach_target),
        "--time-limit",
        args.time_limit,
        "--output",
        str(trace_path),
    ]
    if not args.allow_prompts:
        command.append("--no-prompt")

    print("")
    print("Ready to record.")
    print("  1. Keep OpenChat in the target conversation.")
    print("  2. Start the long streaming response immediately after xctrace begins.")
    print("  3. Avoid changing settings during the capture unless that is the scenario.")
    print(f"Capture notes template: {notes_path}")
    print("")
    run_streaming(command, run_dir / "record.log")

    toc_path = None
    if not args.no_export_toc:
        toc_path = export_toc(trace_path, run_dir)

    manifest = {
        "scenario": args.scenario,
        "bundle_id": args.bundle_id,
        "process_name": args.process_name,
        "device": result.device.__dict__,
        "template": args.template,
        "time_limit": args.time_limit,
        "attach": str(attach_target),
        "trace": str(trace_path),
        "toc": str(toc_path) if toc_path else None,
        "apps_json": str(result.apps_json),
        "processes_json": str(result.processes_json),
        "record_command": command,
    }
    write_json(run_dir / "manifest.json", manifest)
    print("")
    print(f"Trace saved: {trace_path}")
    if toc_path:
        print(f"TOC exported: {toc_path}")
    print(f"Manifest: {run_dir / 'manifest.json'}")


def export_trace(args: argparse.Namespace) -> None:
    trace_path = args.trace
    if not trace_path.exists():
        raise TraceScriptError(f"trace path does not exist: {trace_path}")
    output_dir = args.output_dir or trace_path.parent / "exports"
    output_dir.mkdir(parents=True, exist_ok=True)
    toc_path = export_toc(trace_path, output_dir)
    print(f"TOC exported: {toc_path}")

    for index, xpath in enumerate(args.xpath, start=1):
        output_path = output_dir / f"xpath-{index}.xml"
        run_capture(
            [
                "xcrun",
                "xctrace",
                "export",
                "--input",
                str(trace_path),
                "--xpath",
                xpath,
                "--output",
                str(output_path),
            ]
        )
        print(f"XPath {index} exported: {output_path}")


def collect_prepare_result(args: argparse.Namespace, run_dir: Path) -> PrepareResult:
    device = resolve_device(args.device)
    apps_json = run_dir / "device-apps.json"
    processes_json = run_dir / "device-processes.json"

    run_capture(
        [
            "xcrun",
            "devicectl",
            "device",
            "info",
            "apps",
            "--device",
            device.identifier,
            "--bundle-id",
            args.bundle_id,
            "--columns",
            "*",
            "--json-output",
            str(apps_json),
        ],
        log_path=run_dir / "device-apps.log",
    )
    app_json = read_json(apps_json)
    app = find_installed_app(app_json, args.bundle_id)

    run_capture(
        [
            "xcrun",
            "devicectl",
            "device",
            "info",
            "processes",
            "--device",
            device.identifier,
            "--columns",
            "*",
            "--json-output",
            str(processes_json),
        ],
        log_path=run_dir / "device-processes.log",
    )
    process_json = read_json(processes_json)
    process = find_process(process_json, args.process_name, app)

    return PrepareResult(
        device=device,
        app=app,
        process=process,
        apps_json=apps_json,
        processes_json=processes_json,
    )


def print_prepare_result(result: PrepareResult, bundle_id: str, process_name: str) -> None:
    print(f"Device: {result.device.name} ({result.device.os_version}) {result.device.identifier}")
    if result.app is None:
        print(f"Installed app: not found ({bundle_id})")
    else:
        app_path = normalize_possible_url(first_present(result.app, ["path", "url", "bundleURL", "bundlePath"]))
        print(f"Installed app: found ({bundle_id})")
        if app_path:
            print(f"  path: {app_path}")

    if result.process is None:
        print(f"Running process: not found ({process_name})")
    else:
        print(f"Running process: found PID {process_identifier(result.process)}")
        executable = normalize_possible_url(first_present(result.process, ["executable", "executablePath", "path"]))
        if executable:
            print(f"  executable: {executable}")


def write_prepare_manifest(run_dir: Path, args: argparse.Namespace, result: PrepareResult) -> None:
    write_json(
        run_dir / "prepare-manifest.json",
        {
            "bundle_id": args.bundle_id,
            "process_name": args.process_name,
            "device": result.device.__dict__,
            "app_found": result.app is not None,
            "process_pid": process_identifier(result.process),
            "apps_json": str(result.apps_json),
            "processes_json": str(result.processes_json),
        },
    )


def write_capture_notes(run_dir: Path, args: argparse.Namespace, result: PrepareResult) -> Path:
    notes_path = run_dir / "capture-notes.md"
    notes = f"""# OpenChat Long Stream Device Trace

- Scenario: {args.scenario}
- Device: {result.device.name} ({result.device.os_version}) {result.device.identifier}
- Bundle id: {args.bundle_id}
- Template: {args.template}
- Time limit: {args.time_limit}
- Background state: TODO on/off/current setting
- Conversation state: TODO normal/stage, approximate loaded history length
- Reproduction: TODO prompt/action used to trigger the long streaming response
- Visible symptom: TODO stutter timing, e.g. early stream / after N chars / finalization
- Privacy note: do not paste API keys, endpoint secrets, or private message content here
"""
    notes_path.write_text(notes, encoding="utf-8")
    return notes_path


def export_toc(trace_path: Path, output_dir: Path) -> Path:
    toc_path = output_dir / "trace-toc.xml"
    run_capture(
        [
            "xcrun",
            "xctrace",
            "export",
            "--input",
            str(trace_path),
            "--toc",
            "--output",
            str(toc_path),
        ],
        log_path=output_dir / "export-toc.log",
    )
    return toc_path


def resolve_device(device_arg: str | None) -> DeviceCandidate:
    candidates = list_device_candidates()
    if device_arg:
        for candidate in candidates:
            if device_arg in {candidate.identifier, candidate.name}:
                return candidate
        return DeviceCandidate(name=device_arg, os_version="unknown", identifier=device_arg)

    if not candidates:
        raise TraceScriptError(
            "no connected iOS device found. Connect/unlock the phone, finish any OS update, "
            "then rerun prepare."
        )
    if len(candidates) > 1:
        lines = "\n".join(
            f"  {candidate.name} ({candidate.os_version}) {candidate.identifier}"
            for candidate in candidates
        )
        raise TraceScriptError(f"multiple iOS devices found; pass --device explicitly:\n{lines}")
    return candidates[0]


def list_device_candidates() -> list[DeviceCandidate]:
    result = run_capture(["xcrun", "xctrace", "list", "devices"])
    return parse_xctrace_devices(result.stdout)


def parse_xctrace_devices(output: str) -> list[DeviceCandidate]:
    candidates: list[DeviceCandidate] = []
    in_devices = False
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if line == "== Devices ==":
            in_devices = True
            continue
        if line.startswith("== ") and line != "== Devices ==":
            in_devices = False
            continue
        if not in_devices or not line:
            continue

        match = re.match(r"(.+?) \(([^()]+)\) \(([A-Fa-f0-9-]+)\)$", line)
        if not match:
            continue
        name, os_version, identifier = match.groups()
        if not re.match(r"\d", os_version):
            continue
        candidates.append(
            DeviceCandidate(name=name, os_version=os_version, identifier=identifier)
        )
    return candidates


def find_installed_app(data: Any, bundle_id: str) -> dict[str, Any] | None:
    for item in walk_dicts(data):
        value = first_present(item, ["bundleIdentifier", "bundleID", "bundleId"])
        if value == bundle_id:
            return item
    return None


def find_process(
    data: Any,
    process_name: str,
    app: dict[str, Any] | None,
) -> dict[str, Any] | None:
    app_path = None
    if app:
        app_path = normalize_possible_url(first_present(app, ["path", "url", "bundleURL", "bundlePath"]))

    candidates: list[dict[str, Any]] = []
    for item in walk_dicts(data):
        pid = process_identifier(item)
        if pid is None:
            continue
        executable = normalize_possible_url(first_present(item, ["executable", "executablePath", "path"]))
        if not executable:
            continue
        basename = Path(executable).name
        if basename == process_name:
            candidates.append(item)
            continue
        if app_path and executable.startswith(app_path.rstrip("/") + "/"):
            candidates.append(item)
            continue
        if f"/{process_name}.app/{process_name}" in executable:
            candidates.append(item)

    if not candidates:
        return None
    exact = [
        candidate
        for candidate in candidates
        if Path(
            normalize_possible_url(first_present(candidate, ["executable", "executablePath", "path"]))
            or ""
        ).name
        == process_name
    ]
    return (exact or candidates)[0]


def walk_dicts(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_dicts(child)


def process_identifier(process: dict[str, Any] | None) -> int | str | None:
    if not process:
        return None
    return first_present(process, ["processIdentifier", "pid", "PID"])


def first_present(data: dict[str, Any], keys: list[str]) -> Any:
    for key in keys:
        if key in data and data[key] not in (None, ""):
            return data[key]
    return None


def normalize_possible_url(value: Any) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    if value.startswith("file://"):
        return urlparse(value).path
    return value


def ensure_run_dir(run_dir: Path | None, label: str) -> Path:
    if run_dir is None:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        run_dir = DEFAULT_OUTPUT_ROOT / f"{sanitize_label(label)}-{stamp}"
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def sanitize_label(label: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9_.-]+", "-", label.strip()).strip("-")
    return sanitized or "openchat-trace"


def validate_duration(value: str) -> None:
    if not re.match(r"^\d+(ms|s|m|h)$", value):
        raise TraceScriptError(
            f"invalid --time-limit {value!r}; expected xctrace duration like 45s, 2m, or 500ms"
        )


def require_contains(haystack: str, needle: str, label: str) -> None:
    if needle not in haystack:
        raise TraceScriptError(f"required {label} not found: {needle}")


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise TraceScriptError(f"missing JSON output: {path}") from error
    except json.JSONDecodeError as error:
        raise TraceScriptError(f"invalid JSON output: {path}: {error}") from error


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")


def run_capture(
    command: list[str],
    log_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    printable = shlex.join(command)
    result = subprocess.run(command, capture_output=True, text=True)
    if log_path:
        log_path.write_text(
            f"$ {printable}\n\n# stdout\n{result.stdout}\n\n# stderr\n{result.stderr}",
            encoding="utf-8",
        )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise TraceScriptError(f"command failed ({result.returncode}): {printable}\n{detail}")
    return result


def run_streaming(command: list[str], log_path: Path) -> None:
    printable = shlex.join(command)
    print(f"$ {printable}")
    with log_path.open("w", encoding="utf-8") as log_file:
        log_file.write(f"$ {printable}\n\n")
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="")
            log_file.write(line)
        return_code = process.wait()
        if return_code != 0:
            raise TraceScriptError(f"record command failed ({return_code}); see {log_path}")


if __name__ == "__main__":
    sys.exit(main())
