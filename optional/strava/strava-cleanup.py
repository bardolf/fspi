#!/usr/bin/env python3
"""
Strava activity inspector / cleaner.

Inspects the N most recent activities (CLI arg, default 4) and clears the
`description` field on each one whose description contains the marker
"HUAWEI WATCH" — i.e. the auto-generated text that Huawei Health injects
on every imported activity ("Ride 2026-05-04 16:17:26 HUAWEI WATCH FIT 4 Pro"
and similar).

The match is a plain case-sensitive substring on a string the user would
never type by hand, so legitimate human descriptions are left alone. The
operation is idempotent: an activity whose description is already empty is
silently skipped.

USAGE
    ./strava-cleanup.py            # default: last 4 activities
    ./strava-cleanup.py 200        # one-shot bulk clean

NOTE on rate limits: Strava's free tier allows 100 reads / 15 min. Each
activity costs one detail GET (the list endpoint omits `description`), so
runs of ~80+ activities can hit the limit. If you get HTTP 429, wait 15
minutes and re-run — already-cleared activities will be skipped.

======================================================================
ONE-TIME OAUTH SETUP
======================================================================

1) Register a personal API application:
      https://www.strava.com/settings/api

   - Application Name: anything (e.g. "personal-cleanup")
   - Category: anything
   - Website / Authorization Callback Domain: localhost
   You'll get a Client ID and Client Secret.

2) Authorize the app against your account. Open this URL in a browser
   (replace <CLIENT_ID>):

      https://www.strava.com/oauth/authorize?client_id=<CLIENT_ID>&response_type=code&redirect_uri=http://localhost&approval_prompt=force&scope=activity:read_all,activity:write

   After clicking Authorize, Strava redirects to:

      http://localhost/?state=&code=<AUTH_CODE>&scope=read,activity:read_all,activity:write

   Browser will show a connection error — that's fine. Copy <AUTH_CODE>
   from the URL bar. Verify "scope=" contains BOTH activity:read_all AND
   activity:write — if not, repeat with approval_prompt=force.

3) Exchange the one-shot auth code for a long-lived refresh token. Run
   as a single line — multi-line with backslashes is fragile when pasted:

      curl -X POST https://www.strava.com/oauth/token -d client_id=<CLIENT_ID> -d client_secret=<CLIENT_SECRET> -d code=<AUTH_CODE> -d grant_type=authorization_code

   The JSON response contains "refresh_token". That's the credential we
   need. The "access_token" in the same response expires in 6 h; ignore
   it, this script refreshes its own on every run.

   Note: the <AUTH_CODE> is one-shot and short-lived. If the call fails
   (e.g. typo, copy-paste mishap), the code may already be consumed —
   just redo step 2 to get a fresh one.

4) Save credentials to ~/.config/strava/credentials.json (mode 0600):

      mkdir -p ~/.config/strava
      cat > ~/.config/strava/credentials.json <<'EOF'
      {
        "client_id":     "12345",
        "client_secret": "abc...",
        "refresh_token": "xyz..."
      }
      EOF
      chmod 600 ~/.config/strava/credentials.json

   ~/.config/strava/credentials.json is the XDG-conformant spot for this
   kind of long-lived token; keep mode 0600 since the refresh token is
   effectively a permanent password to your activities.

After that, just run this script — no more browser steps.
"""

import argparse
import json
import os
import stat
import sys
from pathlib import Path
from urllib import error, parse, request

CRED_PATH = Path.home() / ".config" / "strava" / "credentials.json"
API = "https://www.strava.com/api/v3"
OAUTH_TOKEN_URL = "https://www.strava.com/oauth/token"
HUAWEI_MARKER = "HUAWEI WATCH"
PER_PAGE_MAX = 200  # Strava's hard cap


def load_credentials() -> dict:
    if not CRED_PATH.exists():
        sys.exit(
            f"missing credentials file: {CRED_PATH}\n"
            "see the header of this script for one-time OAuth setup"
        )
    mode = CRED_PATH.stat().st_mode
    if mode & (stat.S_IRWXG | stat.S_IRWXO):
        print(
            f"warning: {CRED_PATH} is group/world-readable; run "
            f"`chmod 600 {CRED_PATH}`",
            file=sys.stderr,
        )
    with CRED_PATH.open() as f:
        creds = json.load(f)
    for key in ("client_id", "client_secret", "refresh_token"):
        if not creds.get(key):
            sys.exit(f"{CRED_PATH} is missing required field: {key}")
    return creds


def _http(req: request.Request) -> object:
    try:
        with request.urlopen(req) as r:
            return json.loads(r.read())
    except error.HTTPError as e:
        body = e.read().decode(errors="replace")
        sys.exit(f"{req.get_method()} {req.full_url} failed: {e.code} {body}")


def http_post_form(url: str, data: dict) -> dict:
    body = parse.urlencode(data).encode()
    return _http(request.Request(url, data=body, method="POST"))


def http_get(url: str, token: str) -> object:
    return _http(request.Request(
        url, headers={"Authorization": f"Bearer {token}"}
    ))


def http_put_json(url: str, token: str, payload: dict) -> dict:
    body = json.dumps(payload).encode()
    return _http(request.Request(
        url,
        data=body,
        method="PUT",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type":  "application/json",
        },
    ))


def refresh_access_token(creds: dict) -> str:
    resp = http_post_form(OAUTH_TOKEN_URL, {
        "client_id":     creds["client_id"],
        "client_secret": creds["client_secret"],
        "grant_type":    "refresh_token",
        "refresh_token": creds["refresh_token"],
    })
    new_refresh = resp.get("refresh_token")
    if new_refresh and new_refresh != creds["refresh_token"]:
        creds["refresh_token"] = new_refresh
        tmp = CRED_PATH.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(creds, indent=2))
        os.chmod(tmp, 0o600)
        os.replace(tmp, CRED_PATH)
    return resp["access_token"]


def fetch_recent_activities(token: str, count: int) -> list:
    """Page through /athlete/activities until we have `count` summaries."""
    activities: list = []
    page = 1
    while len(activities) < count:
        remaining = count - len(activities)
        per_page = min(remaining, PER_PAGE_MAX)
        url = f"{API}/athlete/activities?per_page={per_page}&page={page}"
        batch = http_get(url, token)
        if not batch:
            break
        activities.extend(batch)
        if len(batch) < per_page:
            break  # Strava returned a short page → no more activities
        page += 1
    return activities[:count]


def is_huawei_noise(desc: str) -> bool:
    return HUAWEI_MARKER in desc


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Clear the auto-generated Huawei Health description from your "
            "most recent Strava activities."
        ),
    )
    p.add_argument(
        "count",
        nargs="?",
        type=int,
        default=4,
        help="number of most recent activities to inspect (default: 4)",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if args.count < 1:
        sys.exit("count must be >= 1")

    creds = load_credentials()
    token = refresh_access_token(creds)

    print(f"fetching last {args.count} activit{'y' if args.count == 1 else 'ies'}…")
    summaries = fetch_recent_activities(token, args.count)
    if not summaries:
        print("no activities found")
        return
    print(f"got {len(summaries)} activities; inspecting each (1 detail GET per activity)…")
    print()

    cleared = 0
    skipped_empty = 0
    skipped_user = 0
    mismatches = 0

    for i, s in enumerate(summaries, 1):
        # list endpoint omits "description" → need the detail call
        a = http_get(f"{API}/activities/{s['id']}", token)
        aid = a["id"]
        name = a.get("name") or ""
        desc = a.get("description") or ""
        prefix = f"[{i}/{len(summaries)}] id={aid} name={name!r}"

        if not desc:
            print(f"{prefix} skip: description already empty")
            skipped_empty += 1
            continue

        if not is_huawei_noise(desc):
            print(f"{prefix} skip: looks like a user description ({desc!r})")
            skipped_user += 1
            continue

        print(f"{prefix} CLEAR (was: {desc!r})")
        updated = http_put_json(
            f"{API}/activities/{aid}",
            token,
            {"description": ""},
        )
        new_desc = updated.get("description") or ""
        if new_desc:
            print(f"   ! Strava still reports description={new_desc!r}")
            mismatches += 1
        else:
            print("   ✓ cleared")
            cleared += 1

    print()
    print("-" * 64)
    print(
        f"summary: inspected={len(summaries)} "
        f"cleared={cleared} "
        f"skipped_empty={skipped_empty} "
        f"skipped_user={skipped_user} "
        f"mismatches={mismatches}"
    )


if __name__ == "__main__":
    main()
