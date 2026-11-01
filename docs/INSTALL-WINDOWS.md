# Installing GlassCast from a Windows PC

You don't need a Mac. GitHub builds the app; SideStore puts it on your iPhone using your normal
(free) Apple ID. You do the PC part once. After that, everything happens on the phone.

**What you need**
- A 64-bit Windows PC (Windows on Arm won't work) and a USB cable for the iPhone
- The iPhone on **Wi-Fi** (not cellular) with a passcode set
- Your Apple ID
- The Meta AI app with your glasses paired

---

## Part 1 — One-time setup

### On the iPhone
1. Install **LocalDevVPN** from the App Store. Open it once and tap **Allow** when iOS asks to add a
   VPN configuration.

### On the PC
2. Install **iTunes**. Apple's own download is recommended over the Microsoft Store version (it
   brings the USB driver the next tools need).
3. Install **iloader** for Windows. Use the **MSI** installer.

### Put SideStore on the phone
4. Plug the iPhone into the PC and unlock it. Tap **Trust** if the phone asks.
5. Open iloader, sign in with your Apple ID, and choose to install **SideStore**. iloader also sets
   up the pairing file and certificate SideStore needs.
6. On the iPhone: **Settings → Privacy & Security → Developer Mode → On**. The phone restarts;
   confirm Developer Mode when it comes back.
7. **Settings → General → VPN & Device Management**: tap your Apple ID under Developer App and
   tap **Trust**.
8. Turn **LocalDevVPN** on, open **SideStore**, and refresh SideStore itself once.

The PC isn't needed after this.

---

## Part 2 — First test: Meta's sample app (do this before GlassCast)

This checks that Meta's toolkit works on a sideloaded app with a free Apple ID. If this fails,
GlassCast will fail the same way, so it's worth five minutes.

1. In the Meta AI app: open your glasses' settings and turn **Developer Mode** on. (If you can't
   see it: Settings → App Info → tap the app version 5 times.)
2. On the iPhone, open Safari and go to:
   `https://github.com/xb021012/glasscast/releases/download/build-latest/CameraAccess.ipa`
   Save it to Files.
3. Turn LocalDevVPN on. In SideStore, go to **My Apps → +** and pick `CameraAccess.ipa`.
4. Open **Camera Access** and check each of these (write down which ones work):
   - [ ] The app opens
   - [ ] **Connect my glasses** jumps to Meta AI, and after you approve, you land back in the app
   - [ ] **Start Session**, then **Preview**: Meta AI asks for camera access, you allow it
   - [ ] The live view from the glasses appears on the phone

If any box fails, stop there and note the exact error message.

---

## Part 3 — Install GlassCast

1. In Safari:
   `https://github.com/xb021012/glasscast/releases/download/build-latest/GlassCast.ipa`
   Save it to Files.
2. LocalDevVPN on → SideStore → **My Apps → +** → pick `GlassCast.ipa`.
3. Open GlassCast → **Connect my glasses** → approve in Meta AI → you're sent back to GlassCast.
4. Tap **Go live**. The first time, GlassCast asks before sending you to Meta AI to allow camera
   access.

To go live on Discord, tap the **?** button in GlassCast.

You can delete Camera Access afterwards to free up a slot (free Apple IDs allow 3 sideloaded apps,
and SideStore counts as one).

---

## Every week: refresh

Sideloaded apps stop opening after **7 days**. Before that:

1. Make sure you're on Wi-Fi and turn **LocalDevVPN** on.
2. Open **SideStore → My Apps → Refresh All**.

SideStore shows how many days each app has left.

## Updating GlassCast

Each new build replaces the files at the same links. Download `GlassCast.ipa` again in Safari and
install it the same way; SideStore updates the app in place.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| SideStore says something about the **pairing file** | On the PC: iloader → **Delete Stored Pairing** → plug in and pair again → **Manage Pairing File → Place**. |
| SideStore can't install or refresh | Check you're on Wi-Fi (not cellular) and LocalDevVPN is on. |
| An app won't open / "no longer available" | It's past 7 days. Refresh it in SideStore. |
| GlassCast can't connect after a glasses update | Glasses updates turn **Developer Mode** off. Turn it back on in Meta AI. |
| "Update app on glasses" button appears | Tap it; Meta AI updates the toolkit component on the glasses (needs >10% battery). |
| Video is blocky or stutters | Settings (slider icon) → try **Medium** or **15 fps**. Turn off other Bluetooth audio. |
| "Glasses hot" | Let them rest. GlassCast waits a minute and retries on its own. |
| SideStore says you've hit an App ID limit | Free Apple IDs can register 10 app IDs per 7 days. Wait a few days. |
