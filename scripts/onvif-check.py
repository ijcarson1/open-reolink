#!/usr/bin/env python3
"""ONVIF Pull-Point Subscription check for a Reolink camera.

Verifies that the camera supports the architecture we're planning:
  1. ONVIF device service reachable
  2. Auth works (WS-UsernameToken digest)
  3. Events service is advertised
  4. CreatePullPointSubscription succeeds
  5. PullMessages returns (with or without pending events)

Usage:
  python3 scripts/onvif-check.py <ip> <username> <password> [--port 8000]

Before running:
  Enable ONVIF on the camera (Reolink web UI -> Network -> Advanced -> ONVIF
  -> Enable). Default port 8000 on most Reolink firmware.
"""
import argparse
import base64
import datetime
import hashlib
import os
import sys
import uuid
import xml.etree.ElementTree as ET
from urllib import error, request

NS_SCHEMA = "http://www.onvif.org/ver10/schema"
NS_WSA = "http://www.w3.org/2005/08/addressing"


def wsa_headers(to_url: str, action: str) -> str:
    return f"""<wsa:MessageID xmlns:wsa="http://www.w3.org/2005/08/addressing">urn:uuid:{uuid.uuid4()}</wsa:MessageID>
    <wsa:To xmlns:wsa="http://www.w3.org/2005/08/addressing">{to_url}</wsa:To>
    <wsa:Action xmlns:wsa="http://www.w3.org/2005/08/addressing">{action}</wsa:Action>
    <wsa:ReplyTo xmlns:wsa="http://www.w3.org/2005/08/addressing"><wsa:Address>http://www.w3.org/2005/08/addressing/anonymous</wsa:Address></wsa:ReplyTo>"""


def wsse_header_digest(username: str, password: str) -> str:
    nonce = os.urandom(16)
    created = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    digest = base64.b64encode(
        hashlib.sha1(nonce + created.encode() + password.encode()).digest()
    ).decode()
    nonce_b64 = base64.b64encode(nonce).decode()
    return f"""<s:Header>
    <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
      <wsse:UsernameToken>
        <wsse:Username>{username}</wsse:Username>
        <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">{digest}</wsse:Password>
        <wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">{nonce_b64}</wsse:Nonce>
        <wsu:Created>{created}</wsu:Created>
      </wsse:UsernameToken>
    </wsse:Security>
  </s:Header>"""


def wsse_header_text(username: str, password: str) -> str:
    return f"""<s:Header>
    <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
      <wsse:UsernameToken>
        <wsse:Username>{username}</wsse:Username>
        <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText">{password}</wsse:Password>
      </wsse:UsernameToken>
    </wsse:Security>
  </s:Header>"""


def extract_fault(resp: str) -> str:
    """Pull the SOAP fault reason+subcode out of a response, if any."""
    try:
        root = ET.fromstring(resp)
    except ET.ParseError:
        return ""
    parts = []
    for tag in ("Value", "Text"):
        for el in root.iter():
            if el.tag.endswith("}" + tag) and el.text:
                parts.append(f"{el.tag.split('}')[-1]}: {el.text.strip()}")
    return " | ".join(parts[:6])


def soap_call(url: str, body: str) -> tuple[int | None, str]:
    req = request.Request(
        url,
        data=body.encode(),
        headers={"Content-Type": "application/soap+xml; charset=utf-8"},
    )
    try:
        with request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return None, f"{type(e).__name__}: {e}"


def envelope(auth: str, body_inner: str, wsa: str = "") -> str:
    # If both auth and wsa are present, we need to merge them into a single
    # <s:Header>. auth already has its own <s:Header> wrapper; strip it.
    if wsa:
        if auth:
            inner_auth = auth.replace("<s:Header>", "").replace("</s:Header>", "")
            header = f"<s:Header>{wsa}{inner_auth}</s:Header>"
        else:
            header = f"<s:Header>{wsa}</s:Header>"
    else:
        header = auth
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  {header}
  <s:Body>
    {body_inner}
  </s:Body>
</s:Envelope>"""


def fail(step: str, code: int | None, resp: str) -> None:
    print(f"  FAIL ({step}): HTTP {code}")
    fault = extract_fault(resp)
    if fault:
        print(f"  SOAP fault: {fault}")
    print(f"  Response (first 2500 chars):")
    print("    " + resp[:2500].replace("\n", "\n    "))
    sys.exit(1)


def try_get_device_info(device_url: str, username: str, password: str) -> tuple[str, str]:
    """Try Digest first, then PasswordText, then no-auth. Return (mode, response) on success."""
    for mode, auth in (
        ("PasswordDigest", wsse_header_digest(username, password)),
        ("PasswordText", wsse_header_text(username, password)),
        ("no-auth", ""),
    ):
        body = envelope(auth, '<tds:GetDeviceInformation xmlns:tds="http://www.onvif.org/ver10/device/wsdl"/>')
        code, resp = soap_call(device_url, body)
        if code == 200:
            return mode, resp
        fault = extract_fault(resp)
        print(f"    {mode}: HTTP {code}{' — ' + fault if fault else ''}")
    return "", ""


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ip")
    ap.add_argument("username")
    ap.add_argument("password")
    ap.add_argument("--port", type=int, default=8000)
    args = ap.parse_args()

    device_url = f"http://{args.ip}:{args.port}/onvif/device_service"
    print(f"Target: {device_url}")
    print(f"Auth:   {args.username}:{'*' * len(args.password)}")
    print()

    # ── Step 0: clock skew check (ONVIF GetSystemDateAndTime is anonymous) ────
    print("[0/4] GetSystemDateAndTime (no auth)")
    body = envelope("", '<tds:GetSystemDateAndTime xmlns:tds="http://www.onvif.org/ver10/device/wsdl"/>')
    code, resp = soap_call(device_url, body)
    if code == 200:
        try:
            root = ET.fromstring(resp)
            utc = root.find(f".//{{{NS_SCHEMA}}}UTCDateTime")
            if utc is not None:
                t = utc.find(f"{{{NS_SCHEMA}}}Time")
                d = utc.find(f"{{{NS_SCHEMA}}}Date")
                hh = t.find(f"{{{NS_SCHEMA}}}Hour").text if t is not None else "?"
                mm = t.find(f"{{{NS_SCHEMA}}}Minute").text if t is not None else "?"
                ss = t.find(f"{{{NS_SCHEMA}}}Second").text if t is not None else "?"
                Y = d.find(f"{{{NS_SCHEMA}}}Year").text if d is not None else "?"
                M = d.find(f"{{{NS_SCHEMA}}}Month").text if d is not None else "?"
                D = d.find(f"{{{NS_SCHEMA}}}Day").text if d is not None else "?"
                cam_iso = f"{Y}-{int(M):02d}-{int(D):02d}T{int(hh):02d}:{int(mm):02d}:{int(ss):02d}Z"
                mac_iso = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
                cam_dt = datetime.datetime.strptime(cam_iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.UTC)
                mac_dt = datetime.datetime.now(datetime.UTC)
                skew = (mac_dt - cam_dt).total_seconds()
                print(f"  Camera UTC: {cam_iso}")
                print(f"  Mac UTC:    {mac_iso}")
                print(f"  Skew:       {skew:+.0f}s  {'⚠️ WSSE digest will fail if |skew| > 300s' if abs(skew) > 60 else 'OK'}")
        except Exception as e:
            print(f"  (parse error: {e})")
    else:
        print(f"  WARN: anonymous GetSystemDateAndTime returned HTTP {code} — clock skew unchecked.")

    # ── Step 1: GetDeviceInformation (try Digest, Text, no-auth) ──────────────
    print("[1/4] GetDeviceInformation (probing auth modes)")
    mode, resp = try_get_device_info(device_url, args.username, args.password)
    if not mode:
        print("  FAIL: all auth modes rejected.")
        print()
        print("Likely causes:")
        print("  1. Wrong username/password (Reolink admin login).")
        print("  2. Reolink has a separate ONVIF user — try creating one in the camera's")
        print("     web UI: User Management → Add User → Permission: ONVIF.")
        print("  3. Clock skew if step 0 showed > 5 minutes drift.")
        sys.exit(1)
    print(f"  Auth mode that worked: {mode}")
    root = ET.fromstring(resp)
    manufacturer = root.find(f".//{{{ 'http://www.onvif.org/ver10/device/wsdl' }}}Manufacturer")
    model = root.find(f".//{{{ 'http://www.onvif.org/ver10/device/wsdl' }}}Model")
    firmware = root.find(f".//{{{ 'http://www.onvif.org/ver10/device/wsdl' }}}FirmwareVersion")
    print(f"  Manufacturer: {manufacturer.text if manufacturer is not None else '?'}")
    print(f"  Model:        {model.text if model is not None else '?'}")
    print(f"  Firmware:     {firmware.text if firmware is not None else '?'}")

    def auth_header() -> str:
        if mode == "PasswordDigest":
            return wsse_header_digest(args.username, args.password)
        if mode == "PasswordText":
            return wsse_header_text(args.username, args.password)
        return ""

    # ── Step 2: GetCapabilities (Events) ──────────────────────────────────────
    print("[2/4] GetCapabilities (Events)")
    body = envelope(
        auth_header(),
        """<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl">
        <tds:Category>Events</tds:Category>
      </tds:GetCapabilities>""",
    )
    code, resp = soap_call(device_url, body)
    if code != 200:
        fail("GetCapabilities", code, resp)
    root = ET.fromstring(resp)
    events_node = root.find(f".//{{{NS_SCHEMA}}}Events")
    if events_node is None:
        fail("GetCapabilities", code, resp + "\n(no <Events> in response)")
    events_url_node = events_node.find(f"{{{NS_SCHEMA}}}XAddr")
    pp_node = events_node.find(f"{{{NS_SCHEMA}}}WSPullPointSupport")
    events_url = events_url_node.text if events_url_node is not None else None
    pp_support = pp_node.text if pp_node is not None else None
    print(f"  Events service:   {events_url}")
    print(f"  PullPointSupport: {pp_support}")
    if not events_url:
        print("  FAIL: no events service URL")
        sys.exit(1)
    if pp_support and pp_support.lower() != "true":
        print("  WARN: PullPointSupport is not 'true' — proceeding anyway.")

    # ── Step 3: CreatePullPointSubscription ───────────────────────────────────
    print("[3/4] CreatePullPointSubscription (60s lease)")
    body = envelope(
        auth_header(),
        """<tev:CreatePullPointSubscription xmlns:tev="http://www.onvif.org/ver10/events/wsdl">
        <tev:InitialTerminationTime>PT60S</tev:InitialTerminationTime>
      </tev:CreatePullPointSubscription>""",
    )
    code, resp = soap_call(events_url, body)
    if code != 200:
        fail("CreatePullPointSubscription", code, resp)
    root = ET.fromstring(resp)
    sub_addr = root.find(f".//{{{NS_WSA}}}Address")
    if sub_addr is None or not sub_addr.text:
        fail("CreatePullPointSubscription", code, resp + "\n(no subscription address)")
    sub_url = sub_addr.text
    print(f"  Subscription URL: {sub_url}")

    # ── Step 4: PullMessages ──────────────────────────────────────────────────
    # Subscription endpoint requires WS-Addressing to disambiguate operations.
    print("[4/4] PullMessages (5s timeout, up to 10 messages)")
    body = envelope(
        auth_header(),
        """<tev:PullMessages xmlns:tev="http://www.onvif.org/ver10/events/wsdl">
        <tev:Timeout>PT5S</tev:Timeout>
        <tev:MessageLimit>10</tev:MessageLimit>
      </tev:PullMessages>""",
        wsa=wsa_headers(sub_url, "http://www.onvif.org/ver10/events/wsdl/PullPointSubscription/PullMessagesRequest"),
    )
    code, resp = soap_call(sub_url, body)
    if code != 200:
        fail("PullMessages", code, resp)
    root = ET.fromstring(resp)
    msgs = root.findall(f".//{{{ 'http://docs.oasis-open.org/wsn/b-2' }}}NotificationMessage")
    print(f"  Got {len(msgs)} notification(s) within the 5s window.")
    if msgs:
        for m in msgs:
            topic_el = m.find(f"{{{ 'http://docs.oasis-open.org/wsn/b-2' }}}Topic")
            print(f"    - topic: {topic_el.text if topic_el is not None else '?'}")

    print()
    print("ONVIF Pull-Point: SUPPORTED on this camera.")
    print("To see event topics: trigger motion (or press the doorbell) and re-run.")


if __name__ == "__main__":
    main()
