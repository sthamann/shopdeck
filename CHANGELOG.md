# Changelog

## 0.12.0

- Add picking lists for selected orders across shops, with freshly paginated line items, physical product quantities, keyboard checks, order allocations and printable PDF and CSV exports.
- Exclude cancelled orders, digital products and non product positions. Refuse incomplete results and keep shops, variants and historical SKUs separate.
- Add dynamic calendar periods to all record lists. Preserve relative periods in saved views and freeze their resolved boundaries during a federated load.
- Add private record bookmarks in the top toolbar and command palette, with fresh details on opening and persistence across restarts.
- Use the configured replenishment threshold from the command palette. Show the rejected field name for unexpected API write fields without echoing submitted values.
- Keep the list toolbar compact at normal window widths and adapt order actions to split views.

## 0.11.0

- Preview existing order PDFs in a native PDFKit view. Download individual originals or ZIP packages from selected orders across shops, with cancellation and explicit size limits.
- Add optional macOS notifications to private follow ups, including a direct return to the record, rescheduling and completion cleanup.
- Restore tabs, split views, search, shop selection, filters, sort, page, sales channels and currencies. Save named workspaces, duplicate tabs and reopen a closed tab with ⌘⇧T.
- Resolve restored channel filters before the channel catalogue arrives, preventing an unfiltered request during startup. Load restored tab data when returning to a tab.
- Translate the new workflows into all six supported languages and expand the English screenshot tour.

## 0.10.0

- Add live merchant attention counts for ageing orders, replenishment and missing product content, with matching server filters.
- Add private notes and dated follow ups for products, orders and customers.
- Add multiple shop selection and export of the complete filtered result set within the configured limit.
- Improve adaptive split layouts and deliver a notarized app through the signed GitHub update channel.

## 0.9.1

- Add an empty workspace setup assistant with automatic computer language selection and English fallback.
- Suggest unique local shop names and available ports, check Docker containers and recheck ports after image download.
- Add persistent Show all shops navigation and a direct return to the administrations overview.
- Show cached, downsampled product thumbnails in native tables. Improve row density and long text clipping. Open the full Shopware product editor for complete editing.
- Add selected bulk approval with current values, progress, stop handling, stable operation IDs and reverse order batch undo.
- Extend history to general API requests, media, plugin, campaign and native MCP operations.
- Replace blanket customer sharing requirements with entity specific read classification and compact, selectable MCP response fields.
- Add staged local binary media uploads, validated plugin installation and activation, coherent CMS campaigns and native Shopware tool invocation. Keep remote writes behind app approval and report verified results separately from action responses.
- Distinguish native Shopware capability catalogue entries from tools actually advertised by a session.
- Prepare optimized Developer ID releases, GitHub download assets and the signed Sparkle update feed.

## 0.8.1

- Move record search, filters and sorting before server pagination, with cross shop merging and configurable result limits.
- Preserve sales channel, currency and sort choices in saved views.
- Add month and year revenue, per widget shop selection and Security Plugin checks.
- Expand native macOS widgets to all 23 dashboard metrics.
- Improve local Docker provisioning, administration login hints, client installation detection and AI usage examples.

## 0.6.0

- Add a visual widget gallery with live miniature previews, search, categories and persistent ordering.

## 0.5.0

- Add workspace tabs, side by side views, saved views within lists, menu bar statistics, Dock order counts and a WidgetKit extension.
- Use a separate Keychain helper and a native AppKit table.

## 0.4.0

- Add custom filters and columns, embedded administration sessions, detailed records, reviewed bulk product changes and guarded undo.
- Add light and dark appearance and expanded settings.

## 0.1.0

- Introduce a native Mac workspace for multiple Shopware shops, Admin API access, products, orders, customers, order notification rules, release notices, six languages, local Docker shops and AI setup.
