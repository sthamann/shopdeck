# Signed releases and updates

Version **0.13.0 (13000)** ships an optimized Apple silicon app signed with Developer ID Application. The app is notarized by Apple and contains a stapled ticket. The Developer ID signed disk image passed integrity and signature checks. Its mounted app passed deep code signature verification, staple validation and Gatekeeper assessment as `Notarized Developer ID`. The Sparkle feed and its enclosure both verify against the app's embedded Ed25519 public key.

The release check used Shopware's document generator in an isolated local shop to create an invoice and a delivery note. Both Shopdeck downloads matched the corresponding original Shopware PDF byte for byte, and both opened in PDFKit. The test removed the generated documents and checked that they were gone.

Official downloads are published in this repository’s GitHub Releases. Shopdeck checks:

```
https://github.com/sthamann/shopdeck/releases/latest/download/appcast.xml
```

The feed points to a versioned release asset. Sparkle verifies the Ed25519 signature embedded in the feed before installing it. The application carries only the public update key.

## Build a release

1. Run the relevant tests and review the release notes.
2. Build with a Developer ID Application identity. Both helpers, the widget extension, Sparkle’s nested components and the main application need valid signatures and hardened runtime.
3. Submit the application to Apple through Xcode Organizer using Direct Distribution. Wait for approval, export the notarized app and staple its ticket.
4. Create the disk image with the app and an Applications shortcut. Sign the disk image with Developer ID. Check the embedded application’s Gatekeeper assessment and validate its staple.
5. Sign the final download with the private Sparkle key:

```sh
python3 script/prepare_appcast.py Shopdeck-0.13.0-arm64.dmg \
  --download-url https://github.com/sthamann/shopdeck/releases/download/v0.13.0/Shopdeck-0.13.0-arm64.dmg \
  --key /secure/local/path/sparkle-ed25519.key \
  --output appcast.xml \
  --notes "Release notes for this version"
```

6. Publish the versioned DMG, a `Shopdeck.dmg` alias, `appcast.xml` and checksums in the same GitHub Release. The latest stable release supplies the update feed.
7. Download the published assets again, verify the checksum and feed signature, and check the update path in the app.

App build numbers use `major * 1000000 + minor * 1000 + patch`, so future minor versions remain monotonic. Keep version and build numbers in the application, widget extension and feed consistent.

Never commit a private update key, certificate private key, P12, App Store Connect API key or Shopware integration secret. The repository’s ignore rules exclude these files and build work directories. Store publisher signing material outside the source tree.

A Developer ID signature and successful notarization are separate checks. Each release states its actual status.
