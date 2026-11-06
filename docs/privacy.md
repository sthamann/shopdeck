# Shopdeck privacy policy

Effective date: 6 November 2026. Publisher: Stefan Hamann.

Shopdeck is a native Mac application for managing Shopware shops that you choose to connect. There is no Shopdeck account, advertising SDK or analytics service operated by the publisher. The publisher does not receive your shop credentials, order records, customer records, private notes or dashboard data through a Shopdeck service.

## Your shops and local data

Shopdeck communicates directly with the shop URLs you configure, using the permissions of your Shopware integration. Products, orders and customer information are processed to provide the views and actions you request. API credentials are stored in the macOS Keychain. Workspace settings, change history, notes, follow ups and bookmarks are stored locally on your Mac. Files you export are saved where you choose.

Native widgets read a local snapshot shared with the app. This snapshot contains display statistics and selected record summaries. It does not contain API credentials. Desktop widgets can make these statistics visible to people who can see your screen.

## Optional AI access

In versions with the local MCP integration, you select which shops your AI client may access. Customer data sharing has a separate switch for each shop. Data returned to Codex, Claude or another client may be processed by that client and its provider under their own terms and privacy policy. Shopdeck does not operate those AI services. Private notes and follow ups are not exposed through the MCP tools.

## Network services

Shopdeck accesses connected shops, their storefronts and the services needed for the features you request. Update and security checks may access Shopware services. The direct download edition can contact GitHub for app updates; the Mac App Store edition obtains app updates through Apple. Remote product images are loaded from their configured media addresses. These service operators receive the connection information inherent in an internet request, including your IP address. Their own privacy policies apply.

## Notifications and control

Notifications are optional. macOS asks for notification permission when you enable them. You can disable notifications in System Settings, revoke AI sharing in Shopdeck, remove a connected shop or revoke its integration credentials in Shopware. Removing a shop stops its configured access; previously exported files and historical local records may remain on your Mac. You can remove local application data separately. Removing the app alone does not automatically remove its Keychain items or exported files.

## Support

For privacy questions, open a [GitHub issue](https://github.com/sthamann/shopdeck/issues). Do not include API secrets, customer records or private order data in a public issue. You can use the repository contact options for a private inquiry if available.

Changes to this policy are published in this repository.
