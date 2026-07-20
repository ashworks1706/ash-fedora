#!/usr/bin/env python3
import argparse
import datetime as dt
import html
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request

GRAPHQL_ENDPOINT = "https://api.github.com/graphql"
PUBLIC_ENDPOINT = "https://github.com/users/{username}/contributions?from={start}&to={end}"


def trim_file_url(path):
    if path.startswith("file://"):
        return path[7:]
    return path


def read_token(path):
    if not path:
        return ""
    path = os.path.expanduser(trim_file_url(path))
    try:
        with open(path, "r", encoding="utf-8") as token_file:
            return token_file.read().strip()
    except FileNotFoundError:
        return ""


def request_json(url, payload=None, headers=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers or {}, method="POST" if data else "GET")
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def request_text(url, headers=None):
    request = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read().decode("utf-8", errors="replace")


def monday_for(date):
    return date - dt.timedelta(days=date.weekday())


def empty_days(start, end):
    days = {}
    current = start
    while current <= end:
        days[current.isoformat()] = 0
        current += dt.timedelta(days=1)
    return days


def weeks_from_days(days, start, end, max_weeks):
    first_monday = monday_for(start)
    weeks = []
    current = first_monday
    while current <= end:
        week_days = []
        for offset in range(7):
            day = current + dt.timedelta(days=offset)
            if start <= day <= end:
                count = int(days.get(day.isoformat(), 0))
                week_days.append({"date": day.isoformat(), "count": count, "level": level_for_count(count)})
            else:
                week_days.append({"date": day.isoformat(), "count": 0, "level": 0})
        weeks.append({"days": week_days})
        current += dt.timedelta(days=7)
    return weeks[-max_weeks:]


def level_for_count(count):
    if count <= 0:
        return 0
    if count <= 2:
        return 1
    if count <= 5:
        return 2
    if count <= 10:
        return 3
    return 4


def fetch_graphql(username, token, weeks):
    today = dt.date.today()
    start = monday_for(today - dt.timedelta(weeks=weeks - 1))
    query = """
    query($login: String!, $from: DateTime!, $to: DateTime!) {
      user(login: $login) {
        contributionsCollection(from: $from, to: $to) {
          contributionCalendar {
            totalContributions
            weeks {
              contributionDays {
                date
                contributionCount
                contributionLevel
              }
            }
          }
        }
      }
    }
    """
    payload = {
        "query": query,
        "variables": {
            "login": username,
            "from": f"{start.isoformat()}T00:00:00Z",
            "to": f"{today.isoformat()}T23:59:59Z",
        },
    }
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": "quickshell-github-contribution-widget",
    }
    response = request_json(GRAPHQL_ENDPOINT, payload, headers)
    if response.get("errors"):
        raise RuntimeError(response["errors"][0].get("message", "GitHub GraphQL error"))
    user = response.get("data", {}).get("user")
    if not user:
        raise RuntimeError(f"GitHub user not found: {username}")
    calendar = user["contributionsCollection"]["contributionCalendar"]
    normalized_weeks = []
    for week in calendar["weeks"][-weeks:]:
        normalized_days = []
        for day in week["contributionDays"]:
            count = int(day["contributionCount"])
            normalized_days.append({"date": day["date"], "count": count, "level": level_for_count(count)})
        normalized_weeks.append({"days": normalized_days})
    return {
        "source": "graphql",
        "total": int(calendar["totalContributions"]),
        "weeks": normalized_weeks,
    }


def fetch_public(username, weeks):
    today = dt.date.today()
    start = monday_for(today - dt.timedelta(weeks=weeks - 1))
    url = PUBLIC_ENDPOINT.format(username=username, start=start.isoformat(), end=today.isoformat())
    text = request_text(url, {"User-Agent": "quickshell-github-contribution-widget"})
    days = empty_days(start, today)

    for match in re.finditer(r'data-date="(\d{4}-\d{2}-\d{2})"[^>]*?(?:data-count|data-contribution-count)="(\d+)"', text):
        if match.group(1) in days:
            days[match.group(1)] = int(match.group(2))

    if all(count == 0 for count in days.values()):
        aria_pattern = re.compile(r'(\d+) contributions? on ([^"]+?)"[^>]*data-date="(\d{4}-\d{2}-\d{2})"')
        for match in aria_pattern.finditer(html.unescape(text)):
            if match.group(3) in days:
                days[match.group(3)] = int(match.group(1))

    return {
        "source": "public",
        "total": sum(days.values()),
        "weeks": weeks_from_days(days, start, today, weeks),
    }


def write_cache(path, payload):
    path = os.path.expanduser(trim_file_url(path))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix="github-contributions.", suffix=".json", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as cache_file:
            json.dump(payload, cache_file, separators=(",", ":"))
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def main():
    parser = argparse.ArgumentParser(description="Fetch GitHub contribution data for the Quickshell sidebar widget.")
    parser.add_argument("--username", required=True)
    parser.add_argument("--token-file", default="")
    parser.add_argument("--cache", required=True)
    parser.add_argument("--weeks", type=int, default=26)
    args = parser.parse_args()

    username = args.username.strip()
    weeks = max(8, min(args.weeks, 53))
    if not username:
        raise SystemExit("Missing GitHub username")

    token = read_token(args.token_file)
    try:
        data = fetch_graphql(username, token, weeks) if token else fetch_public(username, weeks)
    except Exception as first_error:
        if token:
            try:
                data = fetch_public(username, weeks)
            except Exception as second_error:
                raise SystemExit(f"GraphQL failed: {first_error}; public fallback failed: {second_error}")
        else:
            raise SystemExit(str(first_error))

    payload = {
        "username": username,
        "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "weeksRequested": weeks,
        **data,
    }
    write_cache(args.cache, payload)
    print(json.dumps({"ok": True, "cache": trim_file_url(args.cache), "source": payload["source"], "total": payload["total"]}))


if __name__ == "__main__":
    main()
