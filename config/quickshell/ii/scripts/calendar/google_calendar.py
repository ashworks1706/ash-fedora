#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "google-api-python-client>=2.133.0,<3",
#   "google-auth-oauthlib>=1.2.0,<2",
# ]
# ///

"""Small, on-demand Google Calendar cache for the Quickshell sidebar.

This script never runs as a daemon. Quickshell invokes it only for setup or
when the user presses the calendar refresh button.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import sys
import tempfile
import webbrowser
from datetime import UTC, date, datetime, time, timedelta
from pathlib import Path
from typing import Any

from google.auth.exceptions import RefreshError
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/tasks.readonly",
]
CONFIG_DIR = Path.home() / ".config" / "illogical-impulse" / "google-calendar"
CREDENTIALS_PATH = CONFIG_DIR / "credentials.json"
TOKEN_PATH = CONFIG_DIR / "token.json"
CACHE_DIR = Path.home() / ".cache" / "illogical-impulse" / "google-calendar"
CACHE_PATH = CACHE_DIR / "events.json"


def secure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    path.chmod(0o700)


def atomic_json_write(path: Path, payload: dict[str, Any]) -> None:
    secure_directory(path.parent)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, ensure_ascii=False, separators=(",", ":"))
            stream.write("\n")
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


def load_client_credentials(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Could not read OAuth credentials: {error}") from error
    if not isinstance(payload, dict) or not isinstance(payload.get("installed"), dict):
        raise ValueError("The OAuth JSON must be a Google Desktop app credential file.")
    return payload


def discover_downloaded_credentials() -> list[Path]:
    downloads = Path.home() / "Downloads"
    if not downloads.is_dir():
        return []
    candidates = set(downloads.glob("client_secret*.json"))
    candidates.update(downloads.glob("credentials*.json"))
    valid: list[Path] = []
    for candidate in candidates:
        try:
            load_client_credentials(candidate)
        except ValueError:
            continue
        valid.append(candidate)
    return sorted(valid, key=lambda item: item.stat().st_mtime, reverse=True)


def save_token(credentials: Credentials) -> None:
    secure_directory(CONFIG_DIR)
    TOKEN_PATH.write_text(credentials.to_json(), encoding="utf-8")
    TOKEN_PATH.chmod(0o600)


def authenticated_credentials(interactive: bool = False) -> Credentials:
    credentials: Credentials | None = None
    if TOKEN_PATH.exists():
        TOKEN_PATH.chmod(0o600)
        try:
            # Preserve the scopes actually granted in token.json. Passing the
            # desired scopes here would make an old Calendar-only token look
            # as though it already had Tasks access.
            credentials = Credentials.from_authorized_user_file(TOKEN_PATH)
        except (OSError, ValueError):
            credentials = None

    if credentials and credentials.expired and credentials.refresh_token:
        try:
            credentials.refresh(Request())
            save_token(credentials)
        except RefreshError:
            credentials = None

    if credentials and credentials.valid and credentials.has_scopes(SCOPES):
        return credentials

    # An older token may only contain Calendar access.  Force the interactive
    # OAuth flow once when a newly requested read-only scope is missing.
    if credentials and not credentials.has_scopes(SCOPES):
        credentials = None

    if not interactive:
        raise RuntimeError("Google Calendar is not connected. Open calendar setup first.")
    if not CREDENTIALS_PATH.exists():
        raise RuntimeError(f"Missing Google OAuth credentials at {CREDENTIALS_PATH}")

    load_client_credentials(CREDENTIALS_PATH)
    flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_PATH, SCOPES)
    credentials = flow.run_local_server(
        host="127.0.0.1",
        port=0,
        open_browser=True,
        authorization_prompt_message="Opening Google authorization in your browser...",
        success_message="Google Calendar and Tasks connected. You may close this browser tab.",
        prompt="consent",
        include_granted_scopes="true",
    )
    save_token(credentials)
    return credentials


def paged_execute(resource: Any, method: str, **kwargs: Any) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    page_token: str | None = None
    while True:
        request_kwargs = dict(kwargs)
        if page_token:
            request_kwargs["pageToken"] = page_token
        response = getattr(resource, method)(**request_kwargs).execute()
        results.extend(response.get("items", []))
        page_token = response.get("nextPageToken")
        if not page_token:
            return results


def normalize_event(event: dict[str, Any], calendar: dict[str, Any]) -> dict[str, Any]:
    start_data = event.get("start", {})
    end_data = event.get("end", {})
    all_day = "date" in start_data
    start_value = start_data.get("date") or start_data.get("dateTime", "")
    end_value = end_data.get("date") or end_data.get("dateTime", "")
    date_key = start_data.get("date") or str(start_value)[:10]
    return {
        "itemType": "event",
        "id": event.get("id", ""),
        "title": event.get("summary") or "Busy",
        "start": start_value,
        "end": end_value,
        "dateKey": date_key,
        "allDay": all_day,
        "location": event.get("location", ""),
        "description": event.get("description", ""),
        "link": event.get("htmlLink", ""),
        "meetLink": event.get("hangoutLink", ""),
        "calendarId": calendar.get("id", ""),
        "calendarName": calendar.get("summaryOverride") or calendar.get("summary") or "Calendar",
        "color": calendar.get("backgroundColor") or "#4285f4",
    }


def normalize_task(task: dict[str, Any], task_list: dict[str, Any]) -> dict[str, Any]:
    """Represent a dated Google Task using the same agenda shape as an event.

    The Tasks API stores only the date portion of ``due``; any time component
    is discarded by Google.  Keeping it all-day avoids presenting a false
    appointment time in the sidebar.
    """
    due = str(task.get("due", ""))
    date_key = due[:10]
    return {
        "itemType": "task",
        "id": task.get("id", ""),
        "title": task.get("title") or "Untitled task",
        "start": date_key,
        "end": "",
        "dateKey": date_key,
        "allDay": True,
        "location": "",
        "description": task.get("notes", ""),
        "link": "",
        "meetLink": "",
        "calendarId": task_list.get("id", ""),
        "calendarName": task_list.get("title") or "Google Tasks",
        "color": "#8ab4f8",
    }


def event_sort_key(event: dict[str, Any]) -> tuple[str, str, str]:
    # Date-only events/tasks appear before timed appointments for that day.
    all_day_order = "0" if event.get("allDay", False) else "1"
    return (
        str(event.get("dateKey", "")),
        all_day_order,
        str(event.get("start", "")),
    )


def refresh_cache(credentials: Credentials) -> dict[str, Any]:
    socket.setdefaulttimeout(20)
    service = build("calendar", "v3", credentials=credentials, cache_discovery=False)
    calendars = paged_execute(service.calendarList(), "list", showHidden=False)
    visible_calendars = [
        item
        for item in calendars
        if item.get("selected", False) or item.get("primary", False)
    ]

    today = date.today()
    range_start = today - timedelta(days=62)
    range_end = today + timedelta(days=400)
    time_min = datetime.combine(range_start, time.min, UTC).isoformat().replace("+00:00", "Z")
    time_max = datetime.combine(range_end, time.max, UTC).isoformat().replace("+00:00", "Z")

    normalized_events: list[dict[str, Any]] = []
    normalized_calendars: list[dict[str, Any]] = []
    warnings: list[str] = []
    for calendar in visible_calendars:
        calendar_id = calendar.get("id")
        if not calendar_id:
            continue
        normalized_calendars.append(
            {
                "id": calendar_id,
                "name": calendar.get("summaryOverride") or calendar.get("summary") or "Calendar",
                "color": calendar.get("backgroundColor") or "#4285f4",
                "primary": bool(calendar.get("primary", False)),
            }
        )
        try:
            raw_events = paged_execute(
                service.events(),
                "list",
                calendarId=calendar_id,
                timeMin=time_min,
                timeMax=time_max,
                singleEvents=True,
                orderBy="startTime",
                showDeleted=False,
                maxResults=2500,
            )
        except HttpError as error:
            warnings.append(f"{calendar.get('summary', 'Calendar')}: HTTP {error.resp.status}")
            continue
        normalized_events.extend(
            normalize_event(event, calendar)
            for event in raw_events
            if event.get("status") != "cancelled"
        )

    task_service = build("tasks", "v1", credentials=credentials, cache_discovery=False)
    task_lists = paged_execute(task_service.tasklists(), "list", maxResults=100)
    normalized_tasks: list[dict[str, Any]] = []
    normalized_task_lists: list[dict[str, Any]] = []
    for task_list in task_lists:
        task_list_id = task_list.get("id")
        if not task_list_id:
            continue
        normalized_task_lists.append(
            {"id": task_list_id, "name": task_list.get("title") or "Google Tasks"}
        )
        try:
            raw_tasks = paged_execute(
                task_service.tasks(),
                "list",
                tasklist=task_list_id,
                maxResults=100,
                showCompleted=False,
                showDeleted=False,
                showHidden=False,
            )
        except HttpError as error:
            warnings.append(f"Tasks · {task_list.get('title', 'List')}: HTTP {error.resp.status}")
            continue
        for task in raw_tasks:
            due = str(task.get("due", ""))
            if (
                task.get("status") != "completed"
                and len(due) >= 10
                and range_start.isoformat() <= due[:10] <= range_end.isoformat()
            ):
                normalized_tasks.append(normalize_task(task, task_list))

    normalized_events.extend(normalized_tasks)

    normalized_events.sort(key=event_sort_key)
    payload = {
        "schema": 2,
        "generatedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "rangeStart": range_start.isoformat(),
        "rangeEnd": range_end.isoformat(),
        "calendars": normalized_calendars,
        "taskLists": normalized_task_lists,
        "taskCount": len(normalized_tasks),
        "events": normalized_events,
        "warnings": warnings,
    }
    atomic_json_write(CACHE_PATH, payload)
    return payload


def setup(credentials_argument: str | None) -> int:
    secure_directory(CONFIG_DIR)
    print("Google Calendar + Tasks sidebar setup\n")
    source_path: Path | None = None
    if credentials_argument:
        source_path = Path(credentials_argument).expanduser().resolve()
    elif CREDENTIALS_PATH.exists():
        source_path = CREDENTIALS_PATH
    else:
        candidates = discover_downloaded_credentials()
        if candidates:
            print(f"Found a Google Desktop OAuth file:\n  {candidates[0]}")
            answer = input("Use this file? [Y/n]: ").strip().lower()
            if answer in {"", "y", "yes"}:
                source_path = candidates[0]
        if source_path is None:
            print(
                "\nOne-time Google Cloud setup:\n"
                "  1. Create or select a project.\n"
                "  2. Enable the Google Calendar API and Google Tasks API.\n"
                "  3. Configure the OAuth consent screen for External use and add your account.\n"
                "  4. Create an OAuth client ID with application type 'Desktop app'.\n"
                "  5. Download its JSON file.\n\n"
                "The Google Calendar API page is opening in your browser."
            )
            webbrowser.open("https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")
            entered = input("Path to the downloaded OAuth JSON: ").strip()
            if entered:
                source_path = Path(entered).expanduser().resolve()

    if source_path is None or not source_path.exists():
        print("No OAuth credential file was selected.", file=sys.stderr)
        return 2
    try:
        load_client_credentials(source_path)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2

    if source_path != CREDENTIALS_PATH:
        shutil.copy2(source_path, CREDENTIALS_PATH)
    CREDENTIALS_PATH.chmod(0o600)

    try:
        credentials = authenticated_credentials(interactive=True)
        payload = refresh_cache(credentials)
    except Exception as error:  # setup must present a useful message in its terminal
        print(f"\nSetup failed: {error}", file=sys.stderr)
        input("\nPress Enter to close...")
        return 1

    print(
        f"\nConnected successfully. Cached {len(payload['events']) - payload['taskCount']} events "
        f"and {payload['taskCount']} dated tasks from {len(payload['calendars'])} calendars."
    )
    input("Press Enter to close...")
    return 0


def status() -> int:
    payload = {
        "credentialsPresent": CREDENTIALS_PATH.exists(),
        "tokenPresent": TOKEN_PATH.exists(),
        "cachePresent": CACHE_PATH.exists(),
        "credentialsPath": str(CREDENTIALS_PATH),
        "cachePath": str(CACHE_PATH),
    }
    print(json.dumps(payload, separators=(",", ":")))
    return 0


def refresh() -> int:
    try:
        credentials = authenticated_credentials(interactive=False)
        payload = refresh_cache(credentials)
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 2
    print(
        json.dumps(
            {
                "ok": True,
                "events": len(payload["events"]),
                "tasks": payload["taskCount"],
                "calendars": len(payload["calendars"]),
                "generatedAt": payload["generatedAt"],
            },
            separators=(",", ":"),
        )
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    setup_parser = subparsers.add_parser("setup", help="Authorize Google Calendar and create the cache")
    setup_parser.add_argument("credentials", nargs="?", help="Downloaded Desktop OAuth JSON")
    subparsers.add_parser("refresh", help="Refresh the event cache once")
    subparsers.add_parser("status", help="Print local configuration status")
    args = parser.parse_args()

    if args.command == "setup":
        return setup(args.credentials)
    if args.command == "refresh":
        return refresh()
    return status()


if __name__ == "__main__":
    raise SystemExit(main())
