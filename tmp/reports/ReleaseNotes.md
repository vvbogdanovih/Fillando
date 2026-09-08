## 08/09
- Added search over the admin colour and landing tables; the «Показано N з M» counter is truthful now.
- Closed the last artboard gaps: colour dialog subtitle and stop-order rule, Google Feed as a top-level menu item, honest wording for a cancelled order.
- Re-audited all 152 appendix rows against dev: 119 closed in code, 31 of them with data on dev, 5 left and none of them code.

## 07/09
- Named the last unnamed Dual-Silk colour (HC187, Yellow-Green) with the owner.
- Checked every colour name against the Kingroon and Sunlu invoices; 17 supplier names added, 25 dev variants re-pointed.
- Gave colour families bilingual labels and taught the search the suppliers' spellings.
- Renamed the plain series from Standard to Basic at the owner's word; re-derived it on dev.
- Added a searchable colour multi-select above the swatch chips, at the owner's request.
- Ran the full catalogue migration chain on dev at the owner's word; verify passed clean.
- Checked the storefront on the migrated data: short names, swatches, both Candy colours, the refill page.
- Found the sitemap keeps old slugs after a rename until revalidated; wrote it into the release steps.
- Applied the known-defect fixes on dev; the rename dry run is collision-free.
- Told the two Candy variants apart by the owner's call; the rename now covers every product.
- Wrote the short-name rename migration with a reviewed dictionary; search falls back on the category.
- Kept the category word in product page titles for short names.

## 06/09
- Let buyers change the payment method and pay a stuck LiqPay order; one live card session per order.
- Designed and reviewed the catalogue facet counts; built them on the backend.
- Built the facet sidebar: counts, accordion, search, clear all, sticky drawer button.
- Made saved landing copy appear on the storefront at once.
- Approved both designs; caught the wrong-brand feed bug.
- Wrote Plan-0006 and built its Google Shopping feed.
- Weighed every variant and pulled Nova Poshta rates.
- Enriched product markup and wired GA4 events.
- Built the admin feed screen and new catalogue fields.
- Finished the product page: brand, delivery, discontinued.
- Fixed checkout stock errors, hidden rows, colour dialog.

## 05/09
- Built the colour dictionary as a table.
- Showed how many variants each colour uses.
- Built the landings table with content status.
- Blocked publishing a landing matching nothing.
- Matched the storefront to the catalogue design.
- Wired the refill to its spooled twin.
- Fixed nine defects found by review.

## 20/08
- Confirmed the vendor pricing formula against Prom.
- Corrected 174 overstated prices on dev.

## 19/08
- Traced inflated prices on out-of-stock items.
- Fixed pricing to reuse the last vendor discount.
- Added a guard against lapsed promo campaigns.
- Built a backfill for the frozen prices.
- Showed the price date on unavailable products.
