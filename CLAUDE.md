# CLAUDE.md — GlassCast: stream Ray-Ban Meta glasses to Discord (no Mac)

Project brief for Claude Code. Originally researched 2026-11-01; the **VERIFY** items were
checked the same day against Meta's repo at the 1.0.1 SDK (results in §13). Re-check anything
version-specific against the Meta docs MCP (`search_dat_docs`) before relying on it.

---

## 1. Goal

A personal iPhone app ("GlassCast") that shows the live camera feed from the owner's Ray-Ban
Meta glasses full-screen, so it can be shared into a Discord voice channel with Discord's iOS
screen share. Built **without a Mac**: compiled on GitHub Actions macOS runners, installed
from a Windows PC with SideStore/iloader using a free Apple ID.

Personal use only (Meta Developer Mode). Not for App Store distribution.

## 2. Owner's environment and constraints

| Item | Value |
|---|---|
| Glasses | Ray-Ban Meta Wayfarer **Gen 2**, model RW4012 601/71, size 53-22-155 |
| Phone | iPhone 17 Pro (iOS 26.x) |
| Computer | Windows PC, no Mac |
| Apple account | **Free Apple ID** (no paid Developer Program) |
| Glasses companion app | Meta AI app (iOS), glasses already paired |
| Location | Ohio, USA |
| GitHub | `xb021012/glasscast` (public, for free macOS runner minutes) |

Free Apple ID consequences:
- Sideloaded apps expire after **7 days**; SideStore refreshes on-device.
- Max **3** sideloaded apps at once, SideStore included (SideStore + CameraAccess spike + GlassCast = 3).
- Free teams can create only **10 App IDs per 7 days**.
- Some entitlements are unavailable on free teams; SideStore drops what it can't grant (see Risks).

## 3. Architecture

### Phase 1 (MVP) — phone-only
```
Glasses camera ──Bluetooth/Wi-Fi (DAT SDK)──▶ GlassCast on iPhone (full-screen preview)
                                                     │
                                  Discord iOS app ──screen share──▶ Discord voice channel
```
- GlassCast stays in the foreground, displaying frames full-screen.
- Owner starts Discord screen share (iOS broadcast) from a voice channel, then switches back.
  GlassCast deliberately does **not** end the session when backgrounded (the sample does), so the
  stream survives that trip; it retries immediately on return if it dropped.
- Voice: the glasses' mics can be Discord's Bluetooth mic (standard headset path, not DAT).
  That audio competes with the DAT video for Bluetooth bandwidth — test both ways.

### Phase 2 (optional) — PC/OBS route
GlassCast forwards frames over local Wi-Fi to the PC (WebSocket MJPEG or WebRTC) → OBS Browser
Source → OBS Virtual Camera → Discord camera / Go Live. Only after Phase 1 works.

### Not possible / do not attempt
- Discord bots can't send video through the official API. No self-bots (ToS).
- No custom wake word ("Hey Meta" is Meta's; DAT voice invocations only launch apps, experimental).
- No code on the glasses. No streams above 720p.

## 4. Meta Wearables Device Access Toolkit (DAT) — facts that matter

- Repo: **`https://github.com/meta/meta-wearables-dat-ios`** (canonical; `facebook/...` redirects,
  and the samples and Meta's docs still use the `facebook/` URL in SPM). Binary xcframeworks +
  public samples. SDK release tags (`1.0.1`) contain only the package; **samples live on `main`**.
- Version **1.0.1** (2026-10-09, no developer-facing changes over 1.0.0 of 2026-09-24).
  0.x → 1.0 changed a lot (`addCamera` replaced `addStream`; device state on `Device`;
  `StreamError` thermal cases renamed). Don't trust older blog posts / third-party samples.
- Requirements: Xcode 26.4+, Swift 6.3+, iOS 17.2+ deployment target.
- Sample: `samples/CameraAccess/CameraAccess.xcodeproj`, scheme `CameraAccess`.
- Exact public API: read the `.swiftinterface` files in the xcframeworks at the pinned tag
  (`MWDATCore`, `MWDATCamera`). GlassCast was written against those.

### Camera stream limits
- `StreamingResolution`: `.high` 720×1280, `.medium` 504×896, `.low` 360×640.
- `frameRate: UInt` — 2, 7, 15, 24, 30.
- `StreamConfiguration()` = `.raw`, `.medium`, 30 fps → GlassCast always passes values explicitly.
- `VideoCodec`: `.raw` (render with `frame.makeUIImage()`) or `.hvc1` (decode yourself; GlassCast
  reuses the sample's `VideoFrameDecoder`).
- Bluetooth Classic bandwidth bound; the SDK lowers resolution first, then fps (never below 15).
- A running stream's config can't change: `camera.stop()` then `session.addCamera(config:)` again
  on the same started session.
- `Device` exposes `batteryLevel`, `chargingState`, `thermalLevel` (`unknown, none, light,
  moderate, severe, critical, emergency, shutdown`), `hingeState`, `donState`,
  `addDeviceStateListener`.

### Experimental features
Audio-in-stream, standalone photo capture, inputs, motion, speech, voice invocations are
experimental. GlassCast uses only the non-experimental camera stream.

### Info.plist essentials (verified, see App/GlassCast/Info.plist)
- `CFBundleURLTypes` scheme `glasscast`; `MWDAT.AppLinkURLScheme` = `glasscast://`.
- Developer Mode: `MetaAppID` empty, `0`, or unexpanded `$(META_APP_ID)` → attestation skipped;
  `ClientToken` likewise; `TeamID` may be empty. (Production needs all three.)
- `MWDAT.Analytics.OptOut = true`, `MWDAT.CrashReporting.OptOut = true` (both default on).
- `UIBackgroundModes`: `processing`, `bluetooth-central`, `bluetooth-peripheral`, `external-accessory`.
- `UISupportedExternalAccessoryProtocols`: `com.meta.ar.wearable` (Bluetooth Classic, used by
  camera streaming). **Note:** the CameraAccess sample omits this and `external-accessory`, though
  Meta's getting-started guide requires them. GlassCast includes them.
- `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices`
  (`_bonjour._tcp`). No camera/mic usage strings (no mock device, no recording).
- Callback: forward URLs with a `metaWearablesAction` query item to `Wearables.shared.handleUrl(_:)`.

### Glasses-side setup
1. Meta AI app → your glasses → **Developer Mode** ON. Resets after firmware updates.
2. Internet needed for registration.
3. Glasses battery > 10% for the toolkit's on-glasses component to install.

## 5. Tooling for Claude Code

```bash
claude plugin marketplace add facebook/meta-wearables-dat-ios
claude plugin install mwdat-ios@mwdat-ios-marketplace
claude mcp add --transport http wearables https://mcp.developer.meta.com/wearables
```
- Use `search_dat_docs` for DAT API questions; no auth needed.
- This machine can't run Xcode. All builds run in GitHub Actions from the command line.

## 6. Repo layout
```
/App/project.yml                # XcodeGen spec; CI generates App/GlassCast.xcodeproj
/App/GlassCast/...              # Swift sources, Info.plist, entitlements, assets
/ci/*.sh, ci/sideload.entitlements
/.github/workflows/build-ipa.yml
/docs/INSTALL-WINDOWS.md        # owner-facing install & refresh steps
/LICENSE-META-SAMPLE            # Meta's terms for code derived from CameraAccess
/CLAUDE.md
```
The `.xcodeproj` is generated (XcodeGen) rather than committed: without a Mac nobody can maintain a
hand-edited `project.pbxproj`. Never commit Apple credentials, pairing files, or Meta tokens.

## 7. Build pipeline — GitHub Actions

`build-ipa.yml` runs on `macos-26`:
- **camera-access-spike**: checks out Meta's repo at a pinned `main` commit and builds the
  unmodified CameraAccess sample → `CameraAccess.ipa` (M0).
- **glasscast**: `xcodegen generate`, build → `GlassCast.ipa` (`CFBundleVersion` = run number).
- `ci/select-xcode.sh` picks the newest non-beta Xcode and fails below 26.4.
- `ci/package-ipa.sh` ad-hoc signs (`codesign -s -`) with `ci/sideload.entitlements` so the
  Wi-Fi entitlements are visible to SideStore, then zips `Payload/` into an IPA. Plain
  `CODE_SIGNING_ALLOWED=NO` builds carry no entitlements at all.
- **release** (main only): replaces the rolling `build-latest` release with both IPAs, so the
  phone can download them directly:
  `https://github.com/xb021012/glasscast/releases/download/build-latest/GlassCast.ipa`

## 8. Install pipeline — Windows + SideStore
See `docs/INSTALL-WINDOWS.md`. Per SideStore's prerequisites page (checked 2026-11-01): 64-bit
Windows (not Windows-on-Arm), iTunes (Apple's direct download preferred over Microsoft Store),
iloader (MSI), LocalDevVPN on the phone, phone on **Wi-Fi** (not cellular), passcode set.

## 9. Milestones and acceptance criteria

**M0 — Risk spike** (CI side done; needs the owner's phone)
- [x] Build Meta's unmodified CameraAccess sample in CI.
- [ ] Owner sideloads it and confirms: app launches after re-signing; registration round-trip with
      Meta AI returns to the app; camera permission granted; live stream shows.

**M1 — GlassCast MVP** (code done, untested on device)
- [x] Rebrand → GlassCast (bundle ID `io.github.xb021012.glasscast`, scheme `glasscast`)
- [x] Full-screen aspect-fit preview on black; tap toggles clean mode (also hides status bar/home indicator)
- [x] Resolution + fps (15/24/30) + codec picker; applying re-attaches the camera
- [x] Defaults High @ 24 fps, Raw
- [x] Screen kept awake while live
- [x] Overlay: state, actual frame size, measured/requested fps, codec, battery, thermal warning
- [x] Error handling: backoff retry (2/4/8/15/30 s), 60 s cooldown after thermal/peak-power stops,
      immediate retry when glasses reappear or app returns to foreground; gives up on permission
      denied, low battery, glasses-app update required, SDK too old
- [x] No MockDevice code at all

**M2 — Discord workflow polish**
- [x] In-app "How to go live on Discord" screen
- [ ] Test glasses mic vs phone mic as Discord mic; document
- [ ] Measure latency, minutes to thermal throttle, battery drain / 10 min

**M3 (optional) — PC/OBS route** — not started.

## 10. Known risks and mitigations

| Risk | Mitigation |
|---|---|
| SideStore re-signing changes the bundle ID/team | Developer Mode skips attestation and the TeamID check (verified in Meta's guide), and the callback uses the URL scheme, not the bundle ID — so this should be fine. M0 confirms. |
| Free Apple ID can't grant `HotspotConfiguration` / `wifi-info` (the sample's Wi-Fi entitlements) | Unverified. If SideStore drops them, only the Wi-Fi link is affected; camera streaming uses Bluetooth Classic. M0 shows whether streaming works without them. Fallbacks: borrow a Mac for Xcode free provisioning, or Android (DAT Android SDK). |
| DAT API drift | Use only the current sample + swiftinterface + `search_dat_docs` |
| Stream drops / blocky | Lower resolution/fps; HEVC; keep phone close; no other Bluetooth audio |
| Heat/battery | Thermal chip + cooldown retry; 24 fps default |
| Developer Mode off after glasses update | Shown in onboarding, registration error text, and help screen |
| Discord UX changes | Help screen kept generic |

## 11. Rules and terms
- Meta Wearables Developer Terms: no surveillance; no reverse engineering/modifying the SDK; data
  used only for the requested experience. Don't tamper with the capture LED.
- Respect bystanders and recording laws (Ohio is one-party consent for audio). Not legal advice.
- Analytics and crash reporting opted out in Info.plist.

## 12. References
- DAT iOS repo: https://github.com/meta/meta-wearables-dat-ios
- DAT docs: https://wearables.developer.meta.com/docs/develop/
- iOS integration: https://wearables.developer.meta.com/docs/build-integration-ios/
- Known issues: https://wearables.developer.meta.com/docs/develop/dat/knownissues/
- Developer terms: https://wearables.developer.meta.com/terms/
- Docs MCP: https://mcp.developer.meta.com/wearables
- SideStore docs: https://docs.sidestore.io/docs/intro · prerequisites: https://docs.sidestore.io/docs/installation/prerequisites · pairing file: https://docs.sidestore.io/docs/advanced/pairing-file

## 13. Verification log (2026-11-01)
| Brief said (VERIFY) | Found |
|---|---|
| Canonical repo URL | `meta/meta-wearables-dat-ios`; `facebook/` redirects |
| Sample path | `samples/CameraAccess/CameraAccess.xcodeproj` on `main` — **not** in the `1.0.1` tag |
| `ClientToken` placeholder `AR|0|1` | Not needed: empty/`0`/unexpanded placeholder all mean Developer Mode (BirdSpotter sample uses `0`) |
| Info.plist keys | As §4; sample omits the external-accessory pieces the guide requires |
| Analytics opt-out keys | `MWDAT > Analytics > OptOut`, `MWDAT > CrashReporting > OptOut` |
| Sample entitlements | `keychain-access-groups`, `networking.HotspotConfiguration`, `networking.wifi-info` |
| Sample stream config | `.hvc1`, `.low`, 24 fps; stops session on background |
