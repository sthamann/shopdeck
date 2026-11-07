# Full feature Store release

The release must retain the full Shopdeck feature set. A reduced merchant edition is not the release plan. The existing GitHub edition remains available while the Store candidate is prepared. This document is a release prerequisite, not evidence that the Store flows already work.

| Existing function | Store preparation and remaining proof |
| --- | --- |
| Products, orders, customers, server filtering and sorting | Xcode target compiles shared implementation. Verify real API access inside the signed sandbox. |
| Picking lists, original PDFs, CSV and ZIP exports | Shared implementation retained. Test user selected destinations and access retained across asynchronous exports. |
| Notes, reminders, bookmarks and saved workspaces | Local container storage retained. Test first launch, restoration, reminders and migration from direct distribution. |
| Dashboard, sales channels and separate currencies | Shared implementation retained. Test actual aggregations against a review shop. |
| WidgetKit desktop and Notification Center | Extension builds. Existing macOS Team ID group is retained; verify signed Store app and extension exchange snapshots. |
| Codex and Claude MCP | The app now has a Store-only --mcp-stdio entry using the same MCP transport as the standalone helper. Test the signed executable from external clients, with shared credentials and all 20 tools. The guided installer still needs to select and retain access to client configuration locations and use this command. |
| Skills | Preserve skill contents. Implement explicit user selected document export/import compatible with sandbox and review rules. Do not silently write into other applications' directories. |
| Local media, plugins and CMS campaigns | Retain approval and validation. Implement and test user granted access to source files, including access after restart and the CLI process. |
| Docker test shops and automatic setup | Retained as a release requirement. Current Docker Desktop downloader and external CLI/socket discovery are not Store compatible. Resolve the complete first setup and engine control flow before claiming feature parity. Apple's prohibition on downloading standalone apps cannot be bypassed with an embedded installer or hidden review switch. |
| App updates | Store edition uses Apple updates. GitHub edition retains Sparkle and its existing feed. |
| Six languages and appearance | The Xcode build loads the same translation table from its app resources. Verify all six languages in the rendered Store app. |

The Store app must never activate a different capability set only for App Review. A successful local build or MCP tool catalogue is not a completed external client setup or an approved Store distribution.

Relevant sources: [Mac App Store rules](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility), [App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), [macOS Team ID app groups](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).
