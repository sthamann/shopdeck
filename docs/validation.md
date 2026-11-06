# Validation notes

The local validation environment uses Shopware **6.7.16.0** in an isolated Dockware container. Tests create their own resources. They do not approve an existing merchant proposal.

- Server sorting, pagination, search, shop selection and record limits are exercised through the same client used by the application. A federated regression uses 600 records across two shops, including matches beyond the first 50 rows.
- A journal regression applies 120 changes, reopens the persisted journal, checks that retrying a completed operation cannot overwrite a later external value, then undoes the batch in reverse order. A newer field value causes a conflict.
- The MCP workflow test starts with customer sharing disabled. It reads products and sales channels, checks compact output, prepares a local image and verifies binary media upload against the stored file size.
- The same workflow creates a CMS page containing text, an image and four existing products. It reads back section and slot configuration, verifies the landing page assignment and follows same origin SEO redirects to check the reachable storefront.
- A disposable plugin ZIP is validated, uploaded, installed and activated using Shopware extension actions. The test independently reads installed version and active state, then removes its test resources.
- Native Shopware tool discovery and a real native tool invocation are checked separately. The fixture advertises more catalogue entries than its current session exposes.
- Manual interface checks cover first launch, language selection, the automatic local port suggestion, real product thumbnails, whole row sorting, keyboard detail opening, embedded administration login and return navigation, multiple proposal approval and the resulting journal entries.

The SwiftUI detector scans source with regex only. Its output does not establish visual contrast or accessibility compliance. The changed surfaces are also inspected as rendered native windows.

Opt in to the isolated workflow test:

```sh
SHOPDECK_WORKFLOW_LIVE=1 swift test --filter MCPWorkflowTests/testLiveMCPMediaCampaignAndPluginApproval
```

This test is deliberately pinned to `127.0.0.1:18888` and uses the standard local Docker test credentials. Use a disposable fixture there. Normal `swift test` skips live tests unless explicitly enabled.
