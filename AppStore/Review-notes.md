# App Review notes draft

Status: engineering preparation. Do not submit the current engineering build.

Shopdeck is a native macOS client for merchant owned Shopware 6 installations. It manages physical commerce records. It does not sell digital goods, require a Shopdeck subscription or create a separate Shopdeck user account.

Review access: the first launch assistant offers a demo workspace with fictional shops, orders, products and customers. A fresh installation must be tested to confirm this path before submission. Live API and administration behavior additionally requires a reachable review shop and a dedicated integration; no such public review shop has been supplied for this submission yet. Localhost URLs and developer workstation Docker containers are not accessible to App Review.

The Store build uses App Sandbox and must obtain updates only from Apple. Sparkle is absent from the Store target. Widgets read local snapshots in YXRJR897BM.app.shopdeck; they do not receive integration credentials. This macOS Team ID group does not require registration on the Developer website.

Before review, resolve the Store behavior of the current stdio MCP installation and Docker installer. The direct download version copies command line helpers and skills into client locations and can install Docker Desktop. These flows are not ready for the Store. Do not describe them as tested Store features, hide them only during review, or submit screenshots advertising unsupported behavior.

File exports, document ZIPs, local media proposals and plugin ZIPs require end to end sandbox testing with user selected URLs and persistent security scoped access where files are retained for later approval. Customer sharing must remain explicit per shop.

The existing Shopware emblem is a third party brand asset. Its provenance is documented in Assets/README.md. Supply authorization for Store use if App Review requests it; repository source attribution alone is not a trademark license.

Proposed categories: Business, Productivity. Proposed price: free, matching the current public app. Release: manual developer release after review. Final privacy, age rating, export compliance and territorial business declarations remain to be completed against the shipping Store candidate.
