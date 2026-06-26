# Pairing file — generate once, import on-device

The pairing record is the only trust material the relay needs (§2). Generate it
once on a computer, then import it into the app (Pairing tab), which stores it in
the App Group container for the NE to use.

## Generate (on a computer)

Use **`idevice_pair`** (the `idevice` fork), **not iLoader**, on iOS 26.x —
iLoader lagged 26.4+ (§6).

- **Windows:** install Apple's **iTunes drivers** (the classic installer, *not*
  the Microsoft Store build) so usbmux sees the device.
- Plug in the iPhone, trust the computer, then:

```sh
idevice_pair pair        # writes a pairing record (a plist)
```

Copy the resulting `*.plist` somewhere you can get it onto the phone (AirDrop,
Files, iCloud Drive).

## Import (on the phone)

1. Open ActionRelay → **Pairing** tab → **Import pairing file…**
2. Pick the `.plist`. The app validates it has `HostID` / `DeviceCertificate`
   and copies it into the shared container.

## Longevity

Pairing records can expire/invalidate over time and across major iOS updates
(§13). The heartbeat keeps the live tunnel session alive but does not refresh an
expired record — when the Status tab shows **Pairing: missing/invalid**,
regenerate and re-import. Never commit a pairing file; it is in `.gitignore`.
