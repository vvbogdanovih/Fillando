# Domain Model

## Entity Relationship Diagram

```
  ┌──────────┐
  │   User   │
  └────┬─────┘
       │ 1
       │
       ├──────────────── 1:1 ──── Cart
       │                          │ items[]
       │                          │   └─► ProductVariant (ref)
       │
       ├──────────────── 1:N ──── Order
       │                          │ items[] (snapshot)
       │                          │ customer (snapshot)
       │                          │ delivery_address (embedded)
       │                          │ applied_discount (embedded)
       │                          └─► DiscountCoupon (ref, optional)
       │
       └──────────────── 1:N ──── RefreshToken
                                    (tokenHash, IP, UA, expiresAt)


  ┌──────────┐    1:N    ┌─────────────────┐
  │ Product  │ ─────────►│ ProductVariant   │
  └────┬─────┘           │ (slug, sku,      │
       │                 │  price, stock,   │
       │                 │  images, status) │
       │                 └─────────────────┘
       │
       ├─► Category (ref)
       │     └─ subcategories[] (embedded)
       │          └─ required_attributes[] (embedded)
       │
       └─► Vendor (ref)


  ┌──────────────────┐
  │ DiscountCoupon   │    (standalone, ref'd by Order.applied_discount)
  └──────────────────┘

  ┌──────────────────┐
  │ PaymentDetails   │    (standalone, admin-managed IBAN records)
  └──────────────────┘

  ┌──────────────────┐    ┌──────────────────────┐
  │ NovaPostCity     │◄───│ NovaPostWarehouse    │
  └──────────────────┘    └──────────────────────┘
      (synced from Nova Post API)
```

## Collections

### Core Business

| Collection | Purpose | Key Fields |
|------------|---------|------------|
| `users` | Акаунти покупців та адмінів | email (unique), name, role, authMethod, phone, picture |
| `products` | Базові товари з атрибутами | name, category_id, subcategory_id, vendor_id, description, variant_type, attributes[] |
| `product_variants` | Конкретні варіанти товару (SKU) | product_id, slug (unique), sku (unique), price, stock, images[], v_value, status |
| `categories` | Категорії з вкладеними підкатегоріями | name, slug, image, order, subcategories[] → required_attributes[] |
| `vendors` | Виробники / бренди | name (unique), slug (unique) |
| `carts` | Кошики користувачів | user_id (unique), items[] → { variant_id, quantity, added_at } |
| `orders` | Замовлення | order_number (unique), user_id (nullable), customer, items[], total_price, status, delivery, payment |
| `discount_coupons` | Знижкові купони | number (unique), code (unique), discount_percent, valid_until, is_active |

### Support

| Collection | Purpose | Key Fields |
|------------|---------|------------|
| `refresh_tokens` | Refresh-токени для JWT rotation | userId, tokenHash, ipAddress, userAgent, expiresAt |
| `payment_details` | Реквізити для оплати (IBAN) | last_name, first_name, iban (unique), edrpou, bank_name, is_available |
| `nova_post_cities` | Міста НП (синхронізовані) | ref (unique), name, settlementType, area |
| `nova_post_warehouses` | Відділення НП (синхронізовані) | ref (unique), number, cityRef, description, typeOfWarehouse |

## Key Design Decisions

### Embedded vs Referenced

| Pattern | Used For | Reason |
|---------|----------|--------|
| **Embedded** | Subcategories in Category | Завжди завантажуються разом, невелика кількість |
| **Embedded** | required_attributes in Subcategory | Частина визначення підкатегорії |
| **Embedded** | items in Cart | Один кошик = один документ, атомарні оновлення |
| **Embedded** | items in Order | Snapshot на момент замовлення, не змінюються |
| **Embedded** | customer in Order | Snapshot контактів, незалежний від User |
| **Embedded** | delivery_address in Order | Одноразове використання |
| **Embedded** | applied_discount in Order | Snapshot купона на момент замовлення |
| **Referenced** | ProductVariant → Product | Варіантів може бути багато, запитуються окремо (каталог) |
| **Referenced** | Product → Category, Vendor | Спільні сутності, змінюються окремо |
| **Referenced** | Cart.items → ProductVariant | Потрібна актуальна ціна/стік при кожному запиті |
| **Referenced** | Order → User | Nullable (гостьові замовлення), User може бути видалений |

### Auto-generated Identifiers

| Entity | Pattern | Example |
|--------|---------|---------|
| Product Variant SKU | `FL-` + 6-значний лічильник | `FL-000042` |
| Order Number | `FO-` + 7-значний лічильник | `FO-0000001` |
| Coupon Number | `DIS-` + 7-значний лічильник | `DIS-0000015` |
| Coupon Code | 10 рандомних символів A-Z0-9 | `AB12CD34EF` |
| Variant Slug | slugify(product.name + v_value) | `futbolka-bazova-chorna` |
| Variant Name | `{product.name} — {v_value}` | `Футболка базова — Чорна` |
