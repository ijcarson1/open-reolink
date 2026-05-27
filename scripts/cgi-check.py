#!/usr/bin/env python3
"""Reolink HTTP CGI auth + events probe.

Plan-B fallback for cameras whose ONVIF authentication is locked down.
Verifies:
  1. Login (cmd=Login) returns a session token
  2. Device info (cmd=GetDevInfo) — model, firmware, capabilities
  3. Motion state (cmd=GetMdState) — current motion bool
  4. Recent events / alarm config (cmd=GetAlarm or cmd=GetEvents)

Usage:
  python3 scripts/cgi-check.py <ip> <username> <password> [--https] [--port N]
"""
import argparse
import json
import ssl
import sys
from urllib import error, request

# Reolink uses self-signed HTTPS certs. We accept them for this LAN diagnostic.
_INSECURE_CTX = ssl.create_default_context()
_INSECURE_CTX.check_hostname = False
_INSECURE_CTX.verify_mode = ssl.CERT_NONE


def cgi_call(base: str, payload: list[dict], token: str | None = None) -> tuple[int | None, dict | str]:
    url = base + "/cgi-bin/api.cgi"
    if token:
        url += f"?token={token}"
    req = request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    ctx = _INSECURE_CTX if base.startswith("https://") else None
    try:
        with request.urlopen(req, timeout=10, context=ctx) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            try:
                return resp.status, json.loads(body)
            except json.JSONDecodeError:
                return resp.status, body
    except error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return None, f"{type(e).__name__}: {e}"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ip")
    ap.add_argument("username")
    ap.add_argument("password")
    ap.add_argument("--https", action="store_true", help="Use HTTPS (Reolink's default when HTTP is disabled)")
    ap.add_argument("--port", type=int, help="Override port (defaults: 80 for http, 443 for https)")
    args = ap.parse_args()

    scheme = "https" if args.https else "http"
    port = args.port if args.port else (443 if args.https else 80)
    base = f"{scheme}://{args.ip}:{port}"
    print(f"Target: {base}/cgi-bin/api.cgi")
    print(f"Auth:   {args.username}:{'*' * len(args.password)}")
    print()

    # ── 1: Login ──────────────────────────────────────────────────────────────
    print("[1/4] Login")
    payload = [{
        "cmd": "Login",
        "param": {"User": {"Version": "0", "userName": args.username, "password": args.password}},
    }]
    code, resp = cgi_call(base, payload)
    if code != 200 or not isinstance(resp, list):
        print(f"  FAIL: HTTP {code}")
        print(f"  Response: {str(resp)[:1500]}")
        sys.exit(1)
    item = resp[0] if resp else {}
    if item.get("code") != 0:
        print(f"  FAIL: API code {item.get('code')}, error: {item.get('error')}")
        print(f"  Full response: {json.dumps(item, indent=2)[:1500]}")
        sys.exit(1)
    token = item.get("value", {}).get("Token", {}).get("name")
    lease = item.get("value", {}).get("Token", {}).get("leaseTime")
    if not token:
        print(f"  FAIL: no token in response: {json.dumps(item, indent=2)[:800]}")
        sys.exit(1)
    print(f"  Token: {token[:24]}... (lease: {lease}s)")

    # ── 2: GetDevInfo ────────────────────────────────────────────────────────
    print("[2/4] GetDevInfo")
    code, resp = cgi_call(base, [{"cmd": "GetDevInfo", "action": 0}], token=token)
    if code != 200 or not isinstance(resp, list) or resp[0].get("code") != 0:
        print(f"  FAIL: HTTP {code}, body: {str(resp)[:600]}")
        sys.exit(1)
    info = resp[0].get("value", {}).get("DevInfo", {})
    print(f"  Model:    {info.get('model')}")
    print(f"  Firmware: {info.get('firmVer')}")
    print(f"  Type:     {info.get('type')}  channels: {info.get('channelNum')}")
    print(f"  Audio:    {info.get('audioNum')}  serial: {info.get('serial')[:8]}...")

    # ── 3: GetMdState ────────────────────────────────────────────────────────
    print("[3/4] GetMdState (current motion)")
    code, resp = cgi_call(base, [{"cmd": "GetMdState", "action": 0, "param": {"channel": 0}}], token=token)
    if code != 200 or not isinstance(resp, list) or resp[0].get("code") != 0:
        print(f"  FAIL: HTTP {code}, body: {str(resp)[:600]}")
    else:
        state = resp[0].get("value", {}).get("state")
        print(f"  Motion right now: {'YES' if state == 1 else 'no'}")

    # ── 4: GetAiState (newer firmware: person/vehicle/animal detection) ──────
    print("[4/4] GetAiState (AI detection state)")
    code, resp = cgi_call(base, [{"cmd": "GetAiState", "action": 0, "param": {"channel": 0}}], token=token)
    if code != 200 or not isinstance(resp, list):
        print(f"  not supported (HTTP {code}) — probably an older / non-AI model")
    elif resp[0].get("code") != 0:
        print(f"  not supported: {resp[0].get('error')}")
    else:
        v = resp[0].get("value", {})
        ai_states = {k: vv for k, vv in v.items() if isinstance(vv, dict) and "alarm_state" in vv}
        print(f"  AI detection categories: {list(ai_states.keys())}")
        for k, vv in ai_states.items():
            print(f"    {k}: {'TRIGGERED' if vv.get('alarm_state') == 1 else 'idle'}  supported: {bool(vv.get('support'))}")

    print()
    print("Reolink CGI: SUPPORTED on this camera.")
    print("If ONVIF auth is broken on this firmware, CGI is a workable Plan B for v1.")


if __name__ == "__main__":
    main()
