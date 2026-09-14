#!/usr/bin/env python3
"""Run signed physical-device tests and retain evidence, including failed setup."""
import datetime
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent


def command_output(command, destination, timeout=60):
    try:
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
        destination.write_bytes(result.stdout)
        return result.returncode
    except subprocess.TimeoutExpired as error:
        destination.write_bytes((error.stdout or b"") + b"\nCommand timed out.\n")
        return 124


def run_logged(command, destination, idle_timeout, total_timeout):
    """Only signal the process group created by this invocation."""
    started = last_output = time.monotonic()
    stopped_at = None
    reason = None
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)

    def stop(message):
        nonlocal stopped_at, reason
        if stopped_at is None:
            stopped_at, reason = time.monotonic(), message
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGINT)

    def interrupted(signum, _frame):
        stop(f"Interrupted by signal {signum}")

    previous_handlers = {s: signal.signal(s, interrupted) for s in (signal.SIGINT, signal.SIGTERM)}
    try:
        with destination.open("wb") as log:
            while selector.get_map() or process.poll() is None:
                for key, _ in selector.select(timeout=1):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if data:
                        last_output = time.monotonic()
                        log.write(data)
                        log.flush()
                        sys.stdout.buffer.write(data)
                        sys.stdout.buffer.flush()
                    else:
                        selector.unregister(key.fileobj)
                now = time.monotonic()
                if process.poll() is None:
                    if now - started > total_timeout:
                        stop(f"Exceeded total run limit ({total_timeout}s)")
                    elif now - last_output > idle_timeout:
                        stop(f"No xcodebuild output for {idle_timeout}s; device session may be stalled")
                    if stopped_at is not None and now - stopped_at > 15:
                        os.killpg(process.pid, signal.SIGKILL)
                elif stopped_at is not None and now - stopped_at > 20:
                    break
            status = process.wait(timeout=10)
            if reason:
                log.write(f"\nRunner stopped: {reason}\n".encode())
            return (124 if reason else status), reason
    finally:
        selector.close()
        process.stdout.close()
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)


def main(arguments):
    device = arguments[0] if arguments else "00008030-000948522284802E"
    label = arguments[1] if len(arguments) > 1 else "baseline"
    if not re.fullmatch(r"[A-Za-z0-9_-]+", label):
        raise SystemExit("Run label must contain only letters, digits, hyphens, or underscores.")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = ROOT / "artifacts" / f"{label}-{stamp}"
    output.mkdir(parents=True)
    metadata = {
        "startedAt": stamp, "implementation": "legacy", "requestedDevice": device,
        "destination": f"platform=iOS,id={device}", "configuration": "Debug",
        "fixtures": {"calendar": "gregorian", "locale": "en_US_POSIX", "timeZone": "GMT",
                     "initialDate": "2024-02-14", "bounds": ["2020-01-01", "2030-12-31"],
                     "boundsScenario": ["2024-02-10", "2024-03-20"]},
        "artifacts": str(output), "exitCode": None, "status": "preflight",
    }
    def save():
        (output / "run.json").write_text(json.dumps(metadata, indent=2) + "\n")
    save()
    command_output(["xcodebuild", "-version"], output / "toolchain.txt")
    command_output(["git", "status", "--short"], output / "git-status.txt")
    command_output(["git", "rev-parse", "HEAD"], output / "git-revision.txt")
    preflight = command_output(["xcrun", "devicectl", "device", "info", "details", "--device", device,
                                "--timeout", "20", "--json-output", str(output / "device.json")],
                               output / "device.txt", timeout=30)
    if preflight:
        metadata.update(exitCode=preflight, status="device-unavailable")
        save()
        print(f"Device preflight failed. See {output / 'device.txt'}")
        return preflight
    result_bundle = output / "Tests.xcresult"
    command = ["xcodebuild", "test", "-project", str(ROOT / "Example/CalendarShowcase.xcodeproj"),
               "-scheme", "CalendarShowcase", "-configuration", "Debug",
               "-destination", metadata["destination"], "-destination-timeout", "30",
               "-derivedDataPath", str(ROOT / "artifacts/DerivedData"),
               "-resultBundlePath", str(result_bundle), "-allowProvisioningUpdates",
               "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
               "-default-test-execution-time-allowance", "300", "-maximum-test-execution-time-allowance", "300",
               "DEVELOPMENT_TEAM=MDPX5436J8", "CODE_SIGN_IDENTITY=Apple Development", *arguments[2:]]
    metadata.update(status="running", command=command)
    save()
    status, reason = run_logged(command, output / "build.log",
                                idle_timeout=int(os.environ.get("FSCALENDAR_TEST_IDLE_TIMEOUT", "180")),
                                total_timeout=int(os.environ.get("FSCALENDAR_TEST_TOTAL_TIMEOUT", "1800")))
    metadata.update(exitCode=status, status="passed" if status == 0 else "failed", stopReason=reason)
    if result_bundle.exists():
        summary_path = output / "summary.json"
        export_status = command_output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path",
                                        str(result_bundle), "--format", "json"], summary_path)
        if export_status == 0:
            summary = json.loads(summary_path.read_text())
            metadata["tests"] = {key: summary.get(key) for key in
                                  ("result", "totalTestCount", "passedTests", "failedTests", "skippedTests")}
            metadata["devicesAndConfigurations"] = summary.get("devicesAndConfigurations", [])
        else:
            metadata["resultExportError"] = "Result bundle incomplete; inspect build.log and Tests.xcresult/Staging."
        command_output(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result_bundle),
                        "--output-path", str(output / "attachments")], output / "attachment-export.log")
    if status == 0:
        metadata["demoLaunchExitCode"] = command_output(
            ["xcrun", "devicectl", "device", "process", "launch", "--device", device,
             "--terminate-existing", "com.spbgfs.fscalendar.calendarshowcase"], output / "demo-launch.log")
    save()
    print(json.dumps(metadata, indent=2))
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
