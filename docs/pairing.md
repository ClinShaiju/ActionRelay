# Pairing file — generate once, import on-device

The on-device tunnel (`tunnel_create_rppairing`) is authenticated by a
**RemotePairing file**: an Ed25519 keypair + a UUID identifier that the phone
has been told to trust. This is **not** the classic lockdown pairing record
(`DeviceCertificate`/`HostID`) that `idevice_pair` / pymobiledevice3 produce —
feeding the tunnel a lockdown record fails with `missing field public_key`.

You generate the RemotePairing file **once on a PC over USB** (the classic
lockdown trust the phone already has is the *input*; the tool upgrades it to the
Ed25519 RemotePairing identity), then import that file on-device.

## Generate (on a PC, iPhone on USB)

1. Install Apple's **iTunes / Apple Devices** so the Apple Mobile Device Service
   (usbmux) sees the phone. Plug in the iPhone and **Trust** the computer.
2. Download **`idevice-tools-windows-v0.1.64.zip`** from
   <https://github.com/jkcoxson/idevice/releases/tag/v0.1.64> and unzip it.
3. Run (the tool auto-discovers the USB device and uses usbmux's stored trust):

   ```sh
   idevice-tools.exe rppairing pair ActionRelay rp_pairing.plist
   ```

   - `ActionRelay` is just the host label shown on the device; any string works.
   - On iOS the pairing PIN defaults to `000000` (no prompt to type).
   - If it can't find the device, list UDIDs with `idevice_id.exe -l` and pass
     `--udid <UDID>` **before** the subcommand:
     `idevice-tools.exe --udid <UDID> rppairing pair ActionRelay rp_pairing.plist`.

   It writes `rp_pairing.plist` (keys: `public_key`, `private_key`,
   `identifier`). macOS/Linux: use the matching `idevice-tools` build the same way.

Get `rp_pairing.plist` onto the phone (AirDrop, email it to yourself, Files).

## Import (on the phone)

1. ActionRelay → **Pairing** tab → **Import pairing file…** and pick it, **or**
   paste its contents into the "Or paste pairing data" box (it's small XML/text).
2. The app accepts it only if it carries `public_key` / `private_key` /
   `identifier`; a lockdown record is rejected with a pointer back to this file.
   On Start, the listener normalizes it to a binary plist before idevice reads
   it (defends against BOM/re-encoding from the transfer).

## Longevity

RemotePairing records can expire/invalidate over time and across major iOS
updates (§13). The heartbeat keeps the live tunnel session alive but does not
refresh an expired record — when the Status tab shows the tunnel failing on
pairing, regenerate with the command above and re-import. Never commit a pairing
file; `dist/` is in `.gitignore`.
