# GlassCast

Shows the live camera of Ray-Ban Meta glasses full-screen on an iPhone, so it can be shared into a
Discord voice channel with Discord's iOS screen share. Personal project built on Meta's
[Wearables Device Access Toolkit](https://github.com/meta/meta-wearables-dat-ios) in Developer Mode.

- **Install (Windows, free Apple ID):** [docs/INSTALL-WINDOWS.md](docs/INSTALL-WINDOWS.md)
- **Latest build:** [GlassCast.ipa](https://github.com/xb021012/glasscast/releases/download/build-latest/GlassCast.ipa)
  · Meta's unmodified sample for the first test: [CameraAccess.ipa](https://github.com/xb021012/glasscast/releases/download/build-latest/CameraAccess.ipa)
- **Project notes:** [CLAUDE.md](CLAUDE.md)

Builds run on GitHub Actions (`.github/workflows/build-ipa.yml`); the Xcode project is generated
from `App/project.yml` with XcodeGen.

Parts of the Swift code are derived from Meta's CameraAccess sample and remain under Meta's terms
([LICENSE-META-SAMPLE](LICENSE-META-SAMPLE)). Not affiliated with Meta or Discord.
