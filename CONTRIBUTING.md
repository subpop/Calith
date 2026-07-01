# Contributing to Calith

Thank you for your interest in contributing to Calith.

## Prerequisites

- macOS 26.0 (Tahoe) or later
- Xcode 26+
- Swift 6

## Getting Started

1. Clone the repository.
2. Copy `Secrets.xcconfig.example` to `Secrets.xcconfig` and fill in any API
   keys you need. At minimum, the file must exist (it can be empty).
3. Open `Calith.xcodeproj` in Xcode.
4. Build with Cmd+B (scheme: **Calith**).

## Code Style

- **Swift 6** with strict concurrency. The project uses `MainActor` as the
  default actor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- Use `@Observable` for state management. `ObservableObject` is acceptable only
  when bridging Objective-C/KVO APIs (e.g. Sparkle).
- Prefer Swift-native APIs over Foundation legacy equivalents (see `AGENTS.md`
  for the full list of conventions).
- Match the style of surrounding code. Do not reformat unrelated lines.

## Commit Messages

Use imperative mood, sentence-case. Keep commits focused and atomic.

```
Add thread support to timeline view
Fix crash when provider returns empty response
```

## Branching

- Work on a feature branch off `main`.
- Open a pull request against `main`.
- CI must pass before merging (the workflow builds the project with code
  signing disabled).

## Release Process

Calith is distributed directly via DMG with automatic updates powered by
[Sparkle](https://sparkle-project.org/). Updates are served through a Sparkle
appcast hosted on GitHub Pages (`docs/appcast.xml`), and release assets are
uploaded to GitHub Releases.

### One-time setup

Before your first release, complete these steps:

1. **Generate a Sparkle EdDSA keypair.** Run Sparkle's `generate_keys` tool
   (installed as part of the Sparkle Swift package). Store the private key
   securely -- it lives in your Keychain. Put the public key in
   `Calith/Info.plist` under `SUPublicEDKey`.

2. **Store a notarization profile.** Create a profile named
   `notarytool-signing-profile` using `xcrun notarytool`:
   ```
   xcrun notarytool store-credentials notarytool-signing-profile \
     --apple-id <your-apple-id> \
     --team-id <your-team-id> \
     --password <app-specific-password>
   ```

3. **Set the `DEVELOPER_ID` environment variable** to your Developer ID
   Application certificate SHA-1 fingerprint. You can find it with:
   ```
   security find-identity -v -p codesigning
   ```

4. **Install required tools:**
   - [GitHub CLI (`gh`)](https://cli.github.com/)
   - [`create-dmg`](https://github.com/create-dmg/create-dmg) (expected at
     `/opt/local/bin/create-dmg`)
   - [`pandoc`](https://pandoc.org/) (for converting changelog entries to HTML)

5. **Configure the GitHub remote.** Update `GITHUB_REPO` and `WEBSITE` in
   `scripts/publish-update.sh` to match your repository, or set them as
   environment variables.

### Versioning

- `MARKETING_VERSION` (CFBundleShortVersionString) is the user-facing version
  (e.g. `1.2.0`).
- `CURRENT_PROJECT_VERSION` (CFBundleVersion) is the monotonically increasing
  build number (e.g. `5`).

Bump both in the Xcode project before building a release.

### Changelog

The publish script extracts release notes from `CHANGELOG.md`. Each version
entry must follow this format:

```markdown
## 1.2.0 (5) - 2026-08-11

- Added foo.
- Fixed bar.
```

The heading format is: `## <version> (<build>) <rest>`.

### Building a release

The `scripts/` directory contains three scripts that form the release pipeline:

1. **`scripts/prepare-dmg.sh`** -- Builds a codesigned, notarized, and stapled
   DMG from a local build. It looks for `.app` bundles under `builds/` and
   prompts you to select one.

2. **`scripts/publish-update.sh <dmg-path>`** -- Takes a DMG, generates a
   Sparkle appcast entry (signing it with your EdDSA private key), extracts the
   matching changelog entry, merges it into the existing appcast, creates (or
   updates) a GitHub Release with the DMG attached, and pushes the updated
   `docs/appcast.xml` to deploy via GitHub Pages.

3. **`scripts/release.sh`** -- Runs `prepare-dmg.sh` then `publish-update.sh`
   end-to-end.

Typical workflow:

```bash
# 1. Build a Release archive in Xcode (Product > Archive), then export the
#    .app bundle into builds/<some-name>/.

# 2. Run the full release pipeline:
DEVELOPER_ID=<your-cert-fingerprint> ./scripts/release.sh

# Or run the steps individually:
DEVELOPER_ID=<your-cert-fingerprint> ./scripts/prepare-dmg.sh
./scripts/publish-update.sh /path/to/Calith-1.2.0.dmg
```

The script will prompt for confirmation before creating the GitHub Release and
pushing the appcast.

## License

By contributing, you agree that your contributions will be licensed under the
[Apache License 2.0](LICENSE).
