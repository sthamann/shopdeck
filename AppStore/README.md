# Shopdeck for Shopware on the Mac App Store

[App Store Connect draft](https://appstoreconnect.apple.com/apps/6831736452/distribution/macos/version/inflight), version 0.12.0, Apple ID 6831736452. App Store Connect rejected the unqualified name Shopdeck as already in use. The draft uses Shopdeck for Shopware. The installed application continues to use Shopdeck.

The English listing, review preparation note and manual release setting are saved in App Store Connect. `metadata/` contains the six localized listings. The privacy and support pages are published in the repository. No build was uploaded to TestFlight or submitted to App Review.

The release requires [full feature parity](Full-feature-parity.md). The development archive is a reproducible starting point. The main app and widget extension are sandboxed, Sparkle is excluded, and the app includes a privacy manifest. `--mcp-stdio` runs the existing MCP server from the signed app executable. The direct download target retains the standalone server and Sparkle.

## Build locally

Use Xcode and XcodeGen. The script copies the sources to a temporary directory before invoking Xcode and keeps the generated artifacts outside the synced Documents directory.

```sh
./script/build_app_store.sh --build
SHOPDECK_STORE_MANAGE_PROFILES=1 ./script/build_app_store.sh --archive
```

The first command checks an unsigned engineering build. The second produces a development signed Xcode archive. The default output directory is `/private/tmp/Shopdeck-AppStore-build`; use `SHOPDECK_STORE_BUILD_DIR` to override it. Xcode logs are `build.log` and `archive.log` in that directory.

For the Store target, initial checks proved that the app builds, the archive and nested signatures verify, and the app entry responds to MCP initialize, tool enumeration and ping with all 20 tools. The standalone helper passed the same protocol probe. An isolated UI copy launched with three synthetic shops. Its WidgetKit extension and group access were omitted to avoid touching the user's existing widget data. This is not a live Store credential, widget or external client acceptance test.

`./script/build_app_store.sh --export` refuses to export until the open items in `release-readiness.json` are verified. Xcode uses the App Store Connect distribution method on export. The development archive does not replace a distribution signed package, an Apple processing check or App Review.

## Store materials

- [Privacy policy](https://github.com/sthamann/shopdeck/blob/main/docs/privacy.md)
- [Support](https://github.com/sthamann/shopdeck/blob/main/docs/support.md)
- [Review notes draft](Review-notes.md)
- [Apple Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)

Capture final Mac screenshots from the shipping candidate at an accepted 16:10 size, such as 2560 × 1600. The current GitHub screenshots and promotional film are development and marketing assets. Do not use them to advertise unverified Store features. Finish the privacy label, age rating, distribution signing, review contact and supported feature tests before requesting review. Keep manual release enabled.
