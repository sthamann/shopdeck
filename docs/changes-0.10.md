# Shopdeck 0.10.0

A daily workspace that takes you from the numbers to the next action.

- Live merchant attention list with six operational checks, adjustable stock and order age thresholds, and direct navigation to matching records.
- Private notes and dated follow ups on products, orders and customers, with a central list, search, completion, reopening and postponement.
- Multiple shop selection in product, order and customer lists, retained in saved views.
- CSV export of the current page or the filtered result set, respecting configured row limits, visible columns, sorting, shop selection, sales channel and currency.
- Additional empty and missing field filters for catalogue quality checks.
- Adaptive titles, filters and compact actions for narrow split panes.
- More compact dashboard layout and English, German, Dutch, Spanish, French and Italian labels for the new features.

Validation: existing core suite and new merchant feature tests, read only checks of all six queries against an isolated Shopware 6.7 shop, and a UI export of 72 demo products across three shops while only the first 50 were visible. Follow up creation, completion, reopening and persisted multi shop views were checked in the native app.

Follow up dates are in app due dates. They do not schedule macOS notifications. Product content checks cover active parent products. The export respects the configured maximum and reports truncation explicitly.
