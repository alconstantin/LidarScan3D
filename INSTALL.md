# How to install LiDAR Scan 3D on your iPhone

The app isn't on the App Store, so you install it yourself from a computer using
your own free Apple ID. It takes about 10–15 minutes the first time.

## What you need

- **An iPhone with a LiDAR sensor**: iPhone 12 Pro / Pro Max or any newer Pro model
  (13 Pro, 14 Pro, 15 Pro, 16 Pro, 17 Pro). Non-Pro models have no LiDAR and the
  app won't work on them.
- **iOS 17 or newer** (Settings → General → About → iOS Version).
- **A Windows PC or a Mac** and **a USB cable** for your iPhone.
- **An Apple ID** (your usual one is fine, or create a separate one if you prefer).

---

## Step 1 — Download the app

1. Open: **https://github.com/alconstantin/LidarScan3D/releases/latest**
2. Under **Assets**, download **`LidarScan3D.ipa`**.
   Don't open it — just remember where it was saved (usually *Downloads*).

## Step 2 — Install the required software on your computer

**On Windows:**

1. Install **iTunes** and **iCloud** from Apple's website, **not** from the Microsoft Store:
   - iTunes: https://www.apple.com/itunes/download/win64
   - iCloud: https://support.apple.com/en-us/103232

   If you already have the Microsoft Store versions, uninstall them and install the
   website versions instead.
2. Install **Sideloadly** from https://sideloadly.io (Windows download).
3. Restart your computer.

**On Mac:**

1. Install **Sideloadly** from https://sideloadly.io (macOS download).

## Step 3 — Connect your iPhone

1. Plug your iPhone into the computer with the cable.
2. Unlock the phone. If you see **"Trust This Computer?"**, tap **Trust** and enter
   your passcode.

## Step 4 — Install the app with Sideloadly

1. Open **Sideloadly**.
2. Check that your iPhone shows up under **iDevice**.
3. Drag **`LidarScan3D.ipa`** into the Sideloadly window (onto the IPA icon on the left).
4. Under **Apple account**, enter your Apple ID email.
5. Click **Start**.
6. Enter your Apple ID password, then the **verification code** that appears on
   your phone. (Your credentials go only to Apple, to sign the app under your name.)
7. Wait until the log at the bottom says **"Done."**

## Step 5 — Enable the app on your iPhone

**a) Turn on Developer Mode** (one time only):

1. **Settings → Privacy & Security → Developer Mode** (near the bottom).
2. Turn it on and accept the restart.
3. After the restart, confirm with **Turn On** and your passcode.

> The Developer Mode option only appears after you've installed the app in Step 4.

**b) Trust the developer** (that's you):

1. **Settings → General → VPN & Device Management**.
2. Under **Developer App**, tap your email address.
3. Tap **Trust "…"** and confirm.

## Step 6 — Done!

Open **LiDAR Scan 3D** from your home screen and allow camera access.

Your scans and exported files are in the **Files** app → **On My iPhone →
LiDAR Scan 3D**.

---

## ⚠️ Important: the app must be renewed every 7 days

With a free Apple ID, Apple only lets sideloaded apps run for **7 days**. After
that the app won't open (your scans are **not** lost).

To renew: connect the phone again, open Sideloadly and repeat **Step 4** (drag the
same `.ipa`, click Start). You don't need to repeat Step 5.

## Updates

When a new version is released, download the new `LidarScan3D.ipa` from Step 1 and
repeat **Step 4**. Your existing scans are kept.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Sideloadly doesn't see the phone | Unlock the phone, try another cable/port, make sure you tapped "Trust This Computer". On Windows, make sure iTunes is the Apple website version, not the Store one. |
| Error about **"bundle identifier"** / "App ID not available" | In Sideloadly, open **Advanced options** and enable **Change bundle ID** (the suggested value is fine), then click Start again. Use the same setting when renewing. |
| Error **"maximum number of apps"** | A free Apple ID can have at most 3 sideloaded apps installed. Remove one you no longer use. |
| On launch: **"Untrusted Developer"** | Do Step 5b. |
| On launch: **Developer Mode required** | Do Step 5a. |
| The app stopped opening after a week | That's expected — see "renewed every 7 days" above. |
| The app opens but won't scan | Make sure your phone is a **Pro** model (has LiDAR) and that camera access is allowed (Settings → LiDAR Scan 3D → Camera). |
