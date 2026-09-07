# Glossary

Shared vocabulary for **Fillando** — an online shop for 3D-printing consumables
(filaments, resins, accessories). One agreed definition per term so BA,
developers, and QA mean the same thing. UI language is Ukrainian; this glossary
notes both the Ukrainian business term and the technical entity/route where
relevant. Keep it grouped; add terms as they appear in the
[FRD](requirements/FRD.md).

## Core

| Term | Definition |
|------|------------|
| **Fillando** | The 3D-printing consumables e-commerce platform; the product this repository family builds. |
| **FRD** | Functional Requirements Document — the source of truth for implemented behaviour ([`requirements/FRD.md`](requirements/FRD.md)). |
| **TD** | Technical Design — the design of a feature before it is built ([`designs/`](designs/)). |
| **ADR** | Architecture Decision Record — one significant decision and its rationale ([`adr/`](adr/)). |

## Roles & auth

| Term | Definition |
|------|------------|
| **USER** | Default authenticated customer role — can browse, manage a cart, checkout, and view own orders. |
| **ADMIN** | Back-office role (`Role.ADMIN`) — manages products, categories, vendors, coupons, payment details, and orders. |
| **Guest** | Unauthenticated visitor; can browse and build a cart stored in `localStorage` (see **Cart**). |
| **Google OAuth** | Sign-in via Google, in addition to email/password (Argon2 + pepper). Sessions use JWT in httpOnly cookies. |
| **Refresh token** | Long-lived token (stored server-side + httpOnly cookie) used to silently renew the access token; the FE Axios client refreshes automatically. |

## Catalog

| Term | Definition |
|------|------------|
| **Product (Товар)** | A catalog item (e.g. a filament); has categories, a vendor, media, and one or more variants. |
| **Product Variant** | A purchasable variation of a product (e.g. colour / weight) carrying its own price and stock. |
| **Category (Категорія)** | Flat, single-level grouping of products; drives catalog navigation and breadcrumbs. Carries the `required_attributes` that define which filters the catalog renders. |
| **Vendor (Виробник)** | The manufacturer/brand of a product, managed in the admin panel. |
| **Breadcrumbs / SEO** | Breadcrumbs (Головна → категорія → [лендінг] → товар) plus SEO metadata rendered on catalog, landing and product pages. |

## Cart & orders

| Term | Definition |
|------|------------|
| **Cart (Кошик)** | Dual-mode basket: **guest** carts live in `localStorage`; **authenticated** carts live on the server via API and merge on login. |
| **Checkout (Оформлення замовлення)** | The order-creation flow: delivery (Nova Post) + contact details → order created on the backend. |
| **Order (Замовлення)** | A placed order with line items, delivery info, status, and payment state; visible to the customer and manageable by admins. |
| **Discount Coupon (Знижковий купон)** | Admin-created code applying a discount at checkout. |
| **Wholesale Inquiry (Оптова заявка)** | A bulk-purchase request submitted via a public form and triaged in the admin panel. |

## Payment & delivery

| Term | Definition |
|------|------------|
| **IBAN payment** | Payment by bank transfer: the customer receives an order-confirmation email containing the IBAN / payment details; confirmed manually by an admin. |
| **LiqPay** | PrivatBank's online card-acquiring gateway. Checkout redirects to LiqPay's hosted page; a server-to-server callback confirms payment and flips the order to `PAID`. See [ADR-0009](adr/0009-online-payment-liqpay.md). |
| **Накладний платіж (Cash on delivery, `COD`)** | Payment collected by Nova Post when the customer picks the parcel up. Offered only for `NOVA_POST` and `COURIER` deliveries (both are Nova Post shipments), never for self-pickup. Shipping requires a partial prepayment of at least 200 ₴, agreed by phone and not recorded in the system; checkout gates the choice behind a confirmation dialog. The order stays `PENDING` until an admin marks it `PAID` after Nova Post remits the money. |
| **Payment Provider (Провайдер оплати)** | Admin-managed online acquiring credentials (`LIQPAY`/`MONOPAY`). The merchant `private_key` is stored encrypted (AES-256-GCM); one credential set per provider can be active at a time. |
| **Payment Details (Реквізити оплати)** | Admin-managed bank requisites (IBAN etc.) included in confirmation emails. |
| **LiqPay session cooldown** | One live LiqPay checkout per order: while the payment is `PENDING`, a second `POST /liqpay/checkout` within 15 minutes of the previous one answers `409 LIQPAY_SESSION_ACTIVE` with `retry_after_seconds`; the public lookup exposes the same clock as `liqpay_retry_after_seconds`. A `FAILED` payment may be retried at once. See [TD-0009](designs/TD-0009-customer-payment-method-change.md). |
| **Payment-method change (Зміна способу оплати)** | The buyer moves an unpaid order (payment `PENDING`/`FAILED`, order `NEW`/`CONFIRMED`) from LiqPay to `COD`/`IBAN`/`CASH` — from the checkout status page by token or from the account by ownership. `FAILED` becomes `PENDING`; a late LiqPay `success` still wins and puts the method back to `LIQPAY`. See [state-machines](architecture/state-machines.md#крос-машинне-правило-зміна-способу-оплати-клієнтом). |
| **Voided payment (Скасована оплата)** | `payment_status = VOIDED` — payment is no longer expected because the order was cancelled and no money ever arrived. Set automatically when `order_status` becomes `CANCELLED` while payment is `PENDING`/`FAILED`. Distinct from `REFUNDED`, which means money was received and given back. See [state-machines](architecture/state-machines.md#крос-машинне-правило-скасування-замовлення). |
| **Nova Post (Нова Пошта)** | Ukrainian delivery carrier integrated for city/warehouse lookup during checkout; cities and warehouses are synced and searchable. |
| **Warehouse (Відділення)** | A Nova Post branch/parcel-locker the customer selects as the delivery point. |

## Infrastructure

| Term | Definition |
|------|------------|
| **S3** | AWS S3 object storage for product/media uploads via presigned URLs. |
| **Resend** | Transactional email provider (order confirmations with payment details). |
| **API prefix** | Backend routes have no global prefix; `/api` is added by Nginx on production only (see [environments](environments.md)). |

<!-- Add domain terms below as they are introduced. -->
