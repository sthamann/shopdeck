# Try Shopdeck with Codex and Claude

Open **Codex & Claude** in Shopdeck. The page checks whether each client is installed and offers an explicit MCP server check. Enable MCP access for the shops you want to use, then configure your client.

Restart the client completely and begin a new chat. In Claude Code, begin a new session. Claude Desktop users also import the exported Shopdeck skill ZIP under Settings → Skills.

## Shopdeck MCP, Shopware Admin MCP and Agentic Commerce

| Connection | Who uses it and what it does |
| --- | --- |
| **Local Shopdeck MCP** | Codex and Claude connect to the Mac. Shopdeck calls the Admin API for each enabled shop. It can read catalogues and orders, stage media and campaign work, and queue writes for review in **Changes**. |
| **Shopware Admin MCP** | Shopware exposes its native administration tools at `/api/_mcp`. Shopdeck can discover and invoke those tools through its own MCP connection when the shop and integration allow it. Native writes forwarded by Shopdeck go through the same approval queue. |
| **Shopware Agentic Commerce** | The optional `SwagAgenticCommerce` extension serves shopping agents at the storefront. It offers product feeds and sales channel discovery, and can expose catalogue, cart and checkout through UCP. You install and configure it in Shopware. A UCP client uses the sales channel's published profile and advertised transport. |

The two administration paths can be used in parallel and are independent of the storefront extension. Shopdeck's approval queue applies to operations it forwards. Direct storefront traffic follows Shopware's sales channel and UCP settings.

In builds from `main`, **Codex & Claude → Check Shopware integrations** lets you test the selected shop's Admin MCP and separately check whether `SwagAgenticCommerce` is installed and active. The extension check uses the Shopware integration's permission to read plugins. Activation and storefront readiness are separate. Open **Administration** to set up or verify the sales channel profile and product feeds. [Shopware Admin MCP documentation](https://developer.shopware.com/docs/products/tools/mcp-server/intro.html) · [Shopware Agentic Commerce documentation](https://docs.shopware.com/en/shopware-6-en/extensions/agentic-commerce)

[See the connection overview in Shopdeck](screenshots/61-shopware-ai-connections.png)

## Check the connection

> Use Shopdeck to list my enabled shops with their names and shop IDs. Do not change any data.

Expect the shops enabled in Shopdeck. A successful local server check confirms that the bundled process responds; the prompt above separately verifies that the client actually uses it.

## Compare shops

> Compare orders from my enabled shops over the last seven days. Group by shop, sales channel and currency. Use the Shopdeck Admin API bridge if needed. Keep currencies separate.

## Work with products

> In shop [shop name], find product [product number]. Show its current name, stock and description. Propose an improved description for review in Shopdeck.

Inspect the proposal under **Changes** in Shopdeck. Review the current value, proposed value and target shop before approval. Product changes also have a journal and a guarded undo operation.

## Explore the Admin API

Use `admin_api_schema` and `admin_api_routes` to discover what the selected shop exposes. Use `admin_api_request` for permitted reads, including entity searches and aggregations. Use `propose_admin_api_request` to prepare a write or action for **Changes**. The same bridge works with custom entities and extension routes when the shop makes them available.

> Use Shopdeck to discover the API entities in shop [shop name], then find the sales channels and storefront domains. Do not modify anything.

> In [shop name], find the existing CMS page [name] and the sales channel it belongs to. Show the available routes for updating the page. Prepare a proposal only after identifying the existing record and exact change.

Routes and permissions depend on the shop, and sensitive access paths are restricted. The **Changes** screen shows the target shop, method, path and payload before you apply a general API proposal.

## Troubleshoot

- Use **Check now** to verify the local server and inspect its actual tool list.
- If the server responds but the client cannot see it, restart the client after setup and inspect its MCP settings.
- If a shop is absent, enable its per shop MCP switch.
- If customer fields are hidden, review that shop’s separate customer data sharing switch.
- If Shopware denies an operation, inspect the integration permissions in that shop.

## Upload artwork

> In [shop name], prepare the local image at [absolute file path] for upload using propose_media_upload. Do not upload it until I approve it in Shopdeck.

Open **Changes** to see the immutable file preview, size and target shop. After approval, ask the AI to inspect `list_operations`. The receipt includes the media ID, filename, preview URL and stored size verification.

## Build a campaign

> In [shop name], find the storefront sales channel and four suitable products. Prepare a campaign with a text introduction, the local image at [absolute file path] and a product slider. Use propose_campaign and keep publish=false. Show me the approval request.

A campaign contains 1–20 sections of type `text`, `image` or `product_slider`. Image sections use a zero based `file_index` into `files`. Product sliders use existing product IDs. Each request names one shop and one sales channel. After approval, `list_operations` returns the saved CMS and landing page IDs and administration URL. Publishing is an explicit option. Storefront reachability and saved content verification are separate results.

This workflow creates a new campaign. Do not also approve an earlier generic CMS request for the same campaign unless you intend to create both.

## Install a plugin

> Prepare the local plugin ZIP at [absolute file path] for [shop name] using propose_plugin_install. Show compatibility and request approval to install and activate it.

Shopdeck validates archive paths, links, expansion limits and Composer metadata. The package must declare its version and Shopware core compatibility. Shopware checks remaining dependencies during installation. The verified result includes installed version and activation status. A plugin can execute code on your server, so review its source and provenance before approving. Installed plugins are not overwritten by this install workflow.

## Native Shopware tools

`discover_shopware_tools` returns both the capability catalogue and availability in the current session. `call_shopware_tool` invokes native tools; safe entity reads run directly, while mutations, configuration access and toolset changes require approval. A catalogue only entry can still be unavailable on a shop. Use the generic Admin API bridge when the shop does not expose that native capability.

## Large changes and history

**Apply all** opens a selection and before/after review. Every product write has its own persisted operation ID and verification. Processing stops on an error; unapplied proposals remain pending. Batch undo runs in reverse order and stops if newer values conflict. General API action responses are labelled separately from independently verified entity writes. Interrupted file and campaign operations retain completed step receipts and require review rather than automatic replay.
