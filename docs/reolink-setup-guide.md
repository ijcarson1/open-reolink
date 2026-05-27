# Reolink camera setup for open-reolink

Before open-reolink can monitor a Reolink camera, the camera itself needs two small configuration changes. These take ~5 minutes per camera and are done **once, in the camera's web dashboard** — not in the Reolink mobile app, which hides some of these settings.

## What you need

- The camera's IP address on your LAN. Find it in your router's DHCP lease list, or in the Reolink mobile app under the camera's network info screen.
- The camera's `admin` password. This is the password you set when the camera was first installed — *not* your Reolink cloud account password.

## Steps

### 1. Set a DHCP reservation for the camera

In your router's DHCP settings, reserve the camera's current IP so it doesn't change on reboot. open-reolink identifies cameras by IP and doesn't follow DHCP renumbering automatically (planned for a later release).

### 2. Open the camera's web dashboard

In a browser: `https://<camera-ip>/` — for example, `https://192.168.1.10/`. Reolink uses a self-signed certificate by default, so your browser will warn you. Accept the warning (you're connecting to a device on your own LAN). Log in as `admin` with the camera's admin password.

### 3. Enable ONVIF and RTSP

Go to **Settings → Network → Advanced → Port Settings** (or similar; menu layout varies slightly by firmware version):

- ✅ **RTSP** — enabled. Default port `554`.
- ✅ **ONVIF** — enabled. Default port `8000`. *ONVIF requires RTSP to also be enabled.*
- ✅ **HTTPS** — enabled. Default port `443`.
- HTTP — your call. open-reolink works with either, but HTTPS-only is more secure.

Click **Save**. The camera will log you out; log back in.

### 4. Create a second user account for ONVIF events

> **Why?** Reolink firmware on most current models blocks the built-in `admin` account from authenticating over ONVIF — even though `admin` is an Administrator. ONVIF accepts any *non-`admin`*-named account at User level. open-reolink subscribes to motion and doorbell-ring events over ONVIF, so it needs that second account. (We don't auto-create it: managing the users on your camera is something you should do deliberately.)

Go to **Settings → System → User Management**:

- Click **Add User**
- Username: anything except `admin` — we suggest `onvif` as a convention
- Password: a new password (it doesn't have to match the admin password; this is a separate, less-privileged account)
- Permission level: **User**
- Click **Save**

### 5. (Recommended) Enable NTP

Go to **Settings → Network → Advanced → NTP Settings → Set Up**. Pick `pool.ntp.org` or your router's NTP if it has one. open-reolink relies on the camera and your Mac having synchronised clocks within ~5 minutes for ONVIF authentication to work.

### 6. Back in open-reolink

When the onboarding wizard prompts you, enter:

- The camera's **admin password** (for snapshots and other admin-only operations)
- The **event-subscriber username and password** you just created in step 4

That's it — open-reolink stores both passwords in the macOS Keychain and never sends them anywhere off-device.

## Why two passwords?

- The `admin` account is needed for some Reolink HTTP CGI operations (snapshot, planned spotlight/siren toggles, planned quick-reply playback).
- The non-`admin` event account is needed for ONVIF Pull-Point subscriptions (live motion + doorbell-ring notifications).

Reolink's firmware treats these as two different auth paths, so one account can't currently cover both. If Reolink changes this in a future firmware release, open-reolink will collapse to a single-password setup automatically.

## Troubleshooting

- **"Authentication failed" on the second user**: in the camera web UI, make sure you saved the new user with permission level **User** and entered the password correctly. Reolink locks accounts for ~5 minutes after several failed attempts; if you see this, wait and retry.
- **"ONVIF service unreachable"**: confirm the ONVIF service is enabled in **Network → Advanced → Port Settings**. Confirm the port (8000 by default) matches what open-reolink discovered.
- **Camera disappears every few days**: check your router for DHCP reservation. open-reolink stores the IP, not a hostname.
