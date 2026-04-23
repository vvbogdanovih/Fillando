# Functional Requirements Document (FRD)

## Fillando — Інтернет-магазин витратних матеріалів для 3D-друку

**Дата:** 22.04.2026
**Версія:** 1.0
**Стек:** NestJS (MongoDB) + Next.js 16 (React 19, TypeScript, Tailwind CSS 4)

---

## Зміст

1. [Загальний огляд](#1-загальний-огляд)
2. [Аутентифікація та авторизація](#2-аутентифікація-та-авторизація)
3. [Управління профілем користувача](#3-управління-профілем-користувача)
4. [Каталог товарів](#4-каталог-товарів)
5. [Сторінка товару](#5-сторінка-товару)
6. [Кошик](#6-кошик)
7. [Оформлення замовлення (Checkout)](#7-оформлення-замовлення-checkout)
8. [Замовлення — клієнт](#8-замовлення--клієнт)
9. [Адмін-панель — Замовлення](#9-адмін-панель--замовлення)
10. [Адмін-панель — Товари](#10-адмін-панель--товари)
11. [Адмін-панель — Категорії та підкатегорії](#11-адмін-панель--категорії-та-підкатегорії)
12. [Адмін-панель — Виробники (Vendors)](#12-адмін-панель--виробники-vendors)
13. [Адмін-панель — Знижкові купони](#13-адмін-панель--знижкові-купони)
14. [Адмін-панель — Реквізити оплати](#14-адмін-панель--реквізити-оплати)
15. [Інтеграція з Новою Поштою](#15-інтеграція-з-новою-поштою)
16. [Завантаження файлів (S3)](#16-завантаження-файлів-s3)
17. [Email-сповіщення](#17-email-сповіщення)
18. [Моделі даних](#18-моделі-даних)
19. [Перелік маршрутів](#19-перелік-маршрутів)
20. [Нереалізований функціонал (заглушки)](#20-нереалізований-функціонал-заглушки)

---

## 1. Загальний огляд

Fillando — повноцінний e-commerce додаток для продажу витратних матеріалів для 3D-друку (PLA, PETG, ABS, TPU, Nylon). Платформа складається з:

- **Backend API** — NestJS + MongoDB (Mongoose), JWT-аутентифікація, RBAC
- **Frontend** — Next.js 16 App Router, SSR/SSG, Zustand, React Query, React Hook Form + Zod

### Ролі

| Роль | Опис |
|------|------|
| `USER` | Звичайний покупець. Може переглядати каталог, керувати кошиком, оформляти замовлення, переглядати власні замовлення, редагувати профіль |
| `ADMIN` | Повний доступ до адмін-панелі: CRUD товарів, категорій, виробників, купонів, замовлень, реквізитів; синхронізація Нової Пошти |

### Методи аутентифікації

| Метод | Опис |
|-------|------|
| `EMAIL` | Реєстрація та логін через email/пароль |
| `GOOGLE` | OAuth 2.0 через Google (автоматичне створення акаунту при першому вході) |
| `GITHUB` | Визначено в enum, але **не реалізовано** |

---

## 2. Аутентифікація та авторизація

### 2.1 Реєстрація

| | |
|---|---|
| **Маршрут FE** | `/auth/register` |
| **Endpoint** | `POST /auth/register` |
| **Доступ** | Публічний |

**Поля форми:**

| Поле | Тип | Валідація |
|------|-----|-----------|
| `name` | string | Обов'язкове, мін. 2 символи |
| `email` | string | Обов'язкове, валідний email |
| `password` | string | Обов'язкове, мін. 6 символів (FE) / 8 символів (BE) |
| `confirmPassword` | string | Обов'язкове, має збігатися з `password` |

**Бізнес-логіка:**
- Перевірка унікальності email (409 Conflict якщо зайнятий)
- Хешування пароля через Argon2 + `PASSWORD_PEPPER`
- Створення користувача з роллю `USER`, методом `EMAIL`
- Видача JWT access + refresh токенів (httpOnly cookies)
- Збереження хешованого refresh token в БД з IP/UA трекінгом
- Після успіху: збереження user в Zustand store, мердж гостьового кошика

**Відповідь:** `{ message, user: { id, email, name, role, picture } }`

### 2.2 Логін

| | |
|---|---|
| **Маршрут FE** | `/auth/login` |
| **Endpoint** | `POST /auth/login` |
| **Доступ** | Публічний |

**Поля форми:**

| Поле | Тип | Валідація |
|------|-----|-----------|
| `email` | string | Обов'язкове, валідний email |
| `password` | string | Обов'язкове, мін. 6 символів (FE) / 8 символів (BE) |

**Бізнес-логіка:**
- Перевірка існування користувача та правильності пароля
- Видача JWT access + refresh токенів
- Збереження хешованого refresh token з контекстом клієнта
- Після успіху: збереження user в Zustand, мердж гостьового кошика на сервер

### 2.3 Google OAuth

| | |
|---|---|
| **Ініціація** | `GET /auth/google` → редірект на Google |
| **Callback** | `GET /auth/google/callback` → редірект на `/auth/success` |

**Бізнес-логіка:**
- Якщо користувач існує: перевірка що `authMethod === GOOGLE`
- Якщо новий: створення з `authMethod = GOOGLE`
- Видача токенів, редірект на фронтенд
- Сторінка `/auth/success` викликає `checkAuth()` для гідрації стейту

### 2.4 Refresh токену

| | |
|---|---|
| **Endpoint** | `POST /auth/refresh` |
| **Доступ** | Публічний (читає з cookies) |

**Бізнес-логіка:**
- Витягування refresh token з cookie
- Пошук хешованого токена в БД, перевірка терміну дії
- Видалення старого, видача нової пари access + refresh
- На фронтенді: автоматичний виклик при 401, з дедуплікацією промісів

### 2.5 Вихід

| | |
|---|---|
| **Endpoint** | `POST /auth/logout` |

**Бізнес-логіка:**
- Видалення refresh token з БД
- Очищення cookies
- На FE: очищення Zustand store, скидання серверного кошика

### 2.6 Перевірка сесії

| | |
|---|---|
| **Endpoint** | `GET /auth/me` |
| **Доступ** | JwtAuthGuard |

- Викликається при завантаженні додатку (`provider.tsx`)
- Повертає поточного користувача або 401
- `FullScreenLoader` показується до завершення перевірки

### 2.7 Конфігурація токенів

| Параметр | Access Token | Refresh Token |
|----------|-------------|---------------|
| Термін дії | `JWT_EXPIRATION` хв | `REFRESH_JWT_EXPIRATION` хв |
| Cookie flags | httpOnly, sameSite: lax | httpOnly, sameSite: strict |
| Зберігання в БД | Ні | Так (SHA256 хеш + IP/UA) |

---

## 3. Управління профілем користувача

### 3.1 Перегляд профілю

| | |
|---|---|
| **Маршрут FE** | `/account/profile` |
| **Endpoint** | `GET /users/me` |
| **Доступ** | JwtAuthGuard |

**Відповідь:** `{ id, email, name, phone, picture, role, authMethod }`

### 3.2 Оновлення профілю

| | |
|---|---|
| **Endpoint** | `PATCH /users/me` |
| **Доступ** | JwtAuthGuard |

**Поля (всі опціональні):**

| Поле | Валідація |
|------|-----------|
| `name` | Мін. 1 символ |
| `phone` | Формат `+380XXXXXXXXX` (regex: `^\+380\d{9}$`), унікальний |
| `picture` | Валідний URL або null (для скидання) |

**Бізнес-логіка:**
- Мінімум одне поле має бути заповнене (400 якщо порожній запит)
- Перевірка унікальності телефону (409 при конфлікті)
- Обрізка пробілів у string полях

---

## 4. Каталог товарів

### 4.1 Сторінка каталогу

| | |
|---|---|
| **Маршрут FE** | `/{categorySlug}/{subcategorySlug}` |
| **Endpoint** | `GET /products/catalog` |
| **Доступ** | Публічний |

**Query-параметри:**

| Параметр | Тип | За замовч. | Опис |
|----------|-----|-----------|------|
| `subcategory_id` | string | — | **Обов'язковий**, ObjectId підкатегорії |
| `page` | number | 1 | Номер сторінки (від 1) |
| `limit` | number | 20 | Кількість на сторінку (макс. 100) |
| `price_min` | number | — | Мінімальна ціна |
| `price_max` | number | — | Максимальна ціна |
| `sort` | string | `newest` | Сортування |
| `[attribute_key]` | string | — | Динамічні фільтри за атрибутами (через кому) |

**Приклад:** `?subcategory_id=xxx&vyrobnyk=Sony,LG&price_min=100&price_max=500`

**Бізнес-логіка:**
- Агрегація MongoDB: match (subcategory, status=active, ціна, атрибути) → facet (items + total)
- Атрибутні фільтри: OR всередині одного атрибута, AND між різними
- Фронтенд: бічна панель з фільтрами (слайдер ціни, мультиселекти), пагінація через URL

**Відповідь:**
```json
{
  "items": [{ "_id", "product_id", "name", "slug", "sku", "price", "stock", "thumbnail", "v_value", "status" }],
  "total": 150,
  "page": 1,
  "limit": 20
}
```

### 4.2 Хлібні крихти та SEO

- Breadcrumb schema (JSON-LD) на сторінках каталогу та товару
- Категорія визначається через `GET /categories/slug/{slug}`

---

## 5. Сторінка товару

| | |
|---|---|
| **Маршрут FE** | `/products/{slug}` |
| **Endpoint** | `GET /products/by-slug/{slug}` |
| **Доступ** | Публічний |

**Відповідь:**
```json
{
  "variant": { "_id", "product_id", "name", "slug", "sku", "price", "stock", "images", "v_value", "status" },
  "product": { "_id", "name", "category_id", "subcategory_id", "vendor_id", "description", "variant_type", "attributes" }
}
```

**UI-елементи:**
- Галерея зображень з мініатюрами та навігацією
- Назва товару з варіантом (якщо є)
- Бейдж наявності (в наявності / немає / мало залишилось)
- Ціна в ₴ (UAH)
- SKU
- Селектор варіанту (dropdown, якщо є інші варіанти)
- Вибір кількості (+/- кнопки з валідацією по стоку)
- Кнопка "Додати в кошик" (неактивна якщо немає в наявності)
- Опис товару (rich HTML)
- Таблиця атрибутів
- Product schema (JSON-LD) для SEO

**Поведінка:**
- Якщо товар вже в кошику — кнопка показує "В кошику" з галочкою
- Валідація кількості по доступному стоку (підказка при перевищенні)

---

## 6. Кошик

### 6.1 Архітектура

Кошик працює в двох режимах:
- **Гостьовий:** Zustand store, `guestItems` зберігаються в localStorage (`fillando-cart`)
- **Авторизований:** Серверний кошик через API, `items` в Zustand синхронізовані з сервером

Мердж при логіні: `POST /cart/merge` — якщо серверний кошик порожній, гостьові товари переносяться.

### 6.2 UI

- **Бічна панель (CartSidebar)** — відкривається по кліку на іконку кошика в хедері
- Бейдж кількості товарів (максимум "99+")
- Список товарів з зображеннями, назвами, цінами
- Контроли кількості (+/-) для кожного товару
- Кнопка видалення (кошик)
- Загальна сума
- Кнопка "Оформити замовлення"

### 6.3 Endpoints

| Метод | Endpoint | Опис | Доступ |
|-------|----------|------|--------|
| `GET` | `/cart` | Отримати кошик (з перевіркою валідності товарів) | JWT |
| `POST` | `/cart/items` | Додати товар | JWT |
| `PATCH` | `/cart/items/:variantId` | Оновити кількість | JWT |
| `DELETE` | `/cart/items/:variantId` | Видалити товар | JWT |
| `DELETE` | `/cart` | Очистити кошик | JWT |
| `POST` | `/cart/merge` | Мердж гостьового кошика | JWT |

### 6.4 Валідація

- При отриманні кошика: перевірка існування варіантів та наявності на складі
- Видалені/відсутні товари потрапляють у `removed_items`
- Кількість не може перевищувати доступний стік (409 Conflict)
- Мердж: якщо серверний кошик вже має товари — гостьові ігноруються

---

## 7. Оформлення замовлення (Checkout)

| | |
|---|---|
| **Маршрут FE** | `/checkout` |
| **Endpoint** | `POST /orders` |
| **Доступ** | OptionalJwtAuthGuard (гостьове замовлення підтримується) |

### 7.1 Форма checkout

#### Контактна інформація

| Поле | Валідація |
|------|-----------|
| `customer.name` | Обов'язкове |
| `customer.phone` | Обов'язкове, формат `+380XXXXXXXXX` |
| `customer.email` | Обов'язкове, валідний email |

Для авторизованих користувачів поля заповнюються автоматично з профілю.

#### Метод доставки

| Метод | Додаткові поля |
|-------|---------------|
| `NOVA_POST` | Місто (автокомпліт), тип відділення (Поштомат/Відділення/Вантажне), відділення (пошук/вибір) |
| `COURIER` | Місто, вулиця, будинок, квартира (опц.) |
| `PICKUP` | Без додаткових полів |

#### Метод оплати

| Метод | Доступність |
|-------|-------------|
| `IBAN` | Завжди доступний (за замовч.) |
| `CASH` | Тільки при `PICKUP` |
| `LIQPAY` | Вимкнено (coming soon) |
| `MONOPAY` | Вимкнено (coming soon) |

#### Знижковий купон

| Поле | Валідація |
|------|-----------|
| `coupon_code` | 10 символів, A-Z0-9 |

- Валідація в реальному часі через `POST /discount-coupons/validate`
- Результат: `{ valid: true, coupon: {...} }` або `{ valid: false, reason: "NOT_FOUND" | "INACTIVE" | "EXPIRED" }`
- При валідному купоні: показ % знижки та розраховану суму

#### Коментар

- Опціональне текстове поле

### 7.2 Логіка створення замовлення (Backend)

1. Валідація товарів (існування, ціни)
2. Валідація адреси доставки відповідно до методу
3. Валідація купона (якщо вказано):
   - Пошук за кодом → перевірка `is_active` та `valid_until`
   - Розрахунок: `discount_amount = subtotal * discount_percent / 100`
4. Розрахунок: `total_price = subtotal - discount_amount`
5. Генерація `order_number`: `"FO-"` + 7-значний лічильник (напр., `FO-0000001`)
6. Створення snapshot товарів (ціна, назва, SKU на момент замовлення)
7. Відправка email підтвердження (для IBAN оплати)

### 7.3 Сторінка успіху

| | |
|---|---|
| **Маршрут FE** | `/checkout/success` |

- Номер замовлення
- Інформація про оплату ("Реквізити будуть надіслані на email")
- Підсумок замовлення (підсумок, знижка, загальна сума)
- Кнопка "Продовжити покупки"
- Кошик очищається після створення замовлення

---

## 8. Замовлення — клієнт

### 8.1 Список замовлень

| | |
|---|---|
| **Маршрут FE** | `/profile/orders` |
| **Endpoint** | `GET /orders/me` |
| **Доступ** | JwtAuthGuard |

- Пагінований список з колонками: номер, статус, оплата, сума, дата

### 8.2 Деталі замовлення

| | |
|---|---|
| **Маршрут FE** | `/profile/orders/{id}` |
| **Endpoint** | `GET /orders/me/{id}` |
| **Доступ** | JwtAuthGuard (тільки власні замовлення) |

- Повна інформація: товари, доставка, оплата, ТТН, коментар
- Тільки перегляд (клієнт не може редагувати)

---

## 9. Адмін-панель — Замовлення

| | |
|---|---|
| **Маршрут FE** | `/admin/orders` |
| **Доступ** | Role.ADMIN |

### 9.1 Список замовлень

| Endpoint | Опис |
|----------|------|
| `GET /orders` | Всі замовлення з фільтрацією та пагінацією |

**Фільтри:** `order_status`, `payment_status`, `page`, `limit` (10/20/50/100)

### 9.2 Деталі та редагування

| Endpoint | Опис |
|----------|------|
| `GET /orders/{id}` | Повні деталі замовлення |
| `PATCH /orders/{id}` | Повне оновлення замовлення |
| `PATCH /orders/{id}/status` | Швидка зміна статусу замовлення |
| `PATCH /orders/{id}/payment-status` | Швидка зміна статусу оплати (+ transaction_id) |
| `PATCH /orders/{id}/ttn` | Встановлення ТТН Нової Пошти |

**Статуси замовлення:** `NEW` → `CONFIRMED` → `PROCESSING` → `SHIPPED` → `DELIVERED` / `CANCELLED` / `RETURNED`

**Статуси оплати:** `PENDING` → `PAID` / `FAILED` / `REFUNDED`

---

## 10. Адмін-панель — Товари

| | |
|---|---|
| **Маршрут FE** | `/admin/products` |
| **Доступ** | Role.ADMIN (для створення/редагування), Публічний (для перегляду) |

### 10.1 Список товарів

| Endpoint | Опис |
|----------|------|
| `GET /products` | Всі товари |

### 10.2 Створення товару

| | |
|---|---|
| **Маршрут FE** | `/admin/products/create` |
| **Endpoint** | `POST /products` |

**Поля товару:**

| Поле | Тип | Опис |
|------|-----|------|
| `name` | string | Назва товару |
| `vendor_id` | ObjectId | Виробник (dropdown) |
| `category_id` | ObjectId | Категорія (dropdown) |
| `subcategory_id` | ObjectId | Підкатегорія (dropdown) |
| `description` | `{ json, html }` | Опис (rich text editor, Quill delta + HTML) |
| `attributes` | array | Атрибути `[{ l: "Виробник", v: "Sony" }]` (key генерується з label) |
| `variant_type` | `{ key, label }` | Тип варіанту (напр. `{ key: "color", label: "Колір" }`) |

**Поля варіанту:**

| Поле | Тип | Опис |
|------|-----|------|
| `v_value` | string | Значення варіанту (напр. "Чорна") |
| `price` | number | Ціна |
| `stock` | number | Кількість на складі (за замовч. 0) |
| `images` | string[] | URL зображень (завантаження через S3) |
| `vendor_product_sku` | string | SKU виробника (опц.) |
| `status` | enum | `draft` / `active` / `archived` (за замовч. `active`) |

**Автоматичні поля:**
- `sku`: генерується як `"FL-"` + 6-значний лічильник (напр. `FL-000001`)
- `slug`: генерується з назви товару + v_value (напр. `futbolka-bazova-chorna`)
- `name` варіанту: `"{назва товару} — {v_value}"`

**Валідація перед створенням:** `POST /products/validate` — перевірка унікальності slugs та SKUs

### 10.3 Редагування товару

| | |
|---|---|
| **Маршрут FE** | `/admin/products/{id}/edit` |

**Endpoints:**

| Метод | Endpoint | Опис |
|-------|----------|------|
| `GET` | `/products/{id}` | Отримати товар |
| `PATCH` | `/products/{id}` | Оновити метадані товару |
| `GET` | `/products/{id}/variants` | Всі варіанти |
| `POST` | `/products/{id}/variants` | Додати варіант |
| `PATCH` | `/products/{id}/variants/{variantId}` | Оновити варіант |
| `DELETE` | `/products/{id}/variants/{variantId}` | Видалити варіант |
| `PATCH` | `/products/{id}/variants/{variantId}/images` | Замінити зображення варіанту |
| `DELETE` | `/products/{id}` | Видалити товар (з усіма варіантами) |

### 10.4 Допоміжні endpoints

| Endpoint | Опис |
|----------|------|
| `GET /products/variants/slugs` | Всі слаги варіантів (для sitemap) |
| `GET /products/variants/count` | Загальна кількість варіантів |

---

## 11. Адмін-панель — Категорії та підкатегорії

| | |
|---|---|
| **Маршрут FE** | `/admin/categories` |
| **Доступ запису** | Role.ADMIN |
| **Доступ читання** | Публічний |

### 11.1 Категорії

**Endpoints:**

| Метод | Endpoint | Опис |
|-------|----------|------|
| `GET` | `/categories` | Всі категорії |
| `GET` | `/categories/with-subcategories` | Категорії з підкатегоріями та атрибутами |
| `GET` | `/categories/slug/{slug}` | Категорія за slug |
| `GET` | `/categories/{id}` | Категорія за ID |
| `POST` | `/categories` | Створити (ADMIN) |
| `PATCH` | `/categories/{id}` | Оновити (ADMIN) |
| `PUT` | `/categories/{id}` | Замінити повністю (ADMIN) |
| `DELETE` | `/categories/{id}` | Видалити з усіма підкатегоріями (ADMIN) |

**Поля категорії:**

| Поле | Тип | Опис |
|------|-----|------|
| `name` | string | Назва (унікальна) |
| `slug` | string | URL slug (унікальний) |
| `image` | string | URL зображення (опц.) |
| `order` | number | Порядок відображення (мін. 0) |

### 11.2 Підкатегорії

**Endpoints:**

| Метод | Endpoint | Опис |
|-------|----------|------|
| `GET` | `/categories/{id}/subcategories` | Всі підкатегорії |
| `GET` | `/categories/{id}/subcategories/{subId}` | Одна підкатегорія |
| `POST` | `/categories/{id}/subcategories` | Додати (ADMIN) |
| `PATCH` | `/categories/{id}/subcategories/{subId}` | Оновити (ADMIN) |
| `PUT` | `/categories/{id}/subcategories/{subId}` | Замінити (ADMIN) |
| `DELETE` | `/categories/{id}/subcategories/{subId}` | Видалити (ADMIN) |

**Поля підкатегорії:**

| Поле | Тип | Опис |
|------|-----|------|
| `name` | string | Назва |
| `slug` | string | URL slug |
| `required_attributes` | array | Атрибути фільтрації |

**Структура `required_attribute`:**

| Поле | Тип | Опис |
|------|-----|------|
| `key` | string | Генерується з label (slug) |
| `label` | string | Назва (напр. "Виробник") |
| `filter_type` | enum | `multi-select` або `range` |
| `unit` | string | Одиниця виміру (опц., напр. "мм") |

---

## 12. Адмін-панель — Виробники (Vendors)

| | |
|---|---|
| **Маршрут FE** | `/admin/vendors` |

### Endpoints

| Метод | Endpoint | Опис | Доступ |
|-------|----------|------|--------|
| `GET` | `/vendors` | Всі виробники | Публічний |
| `GET` | `/vendors/{id}` | Виробник за ID | Публічний |
| `GET` | `/vendors/check-availability?slug={slug}` | Перевірка доступності slug | Публічний |
| `POST` | `/vendors` | Створити | JWT |
| `PATCH` | `/vendors/{id}` | Оновити | JWT |
| `DELETE` | `/vendors/{id}` | Видалити | JWT |

**Поля:**

| Поле | Тип | Валідація |
|------|-----|-----------|
| `name` | string | Обов'язкове, унікальне, мін. 1 символ |
| `slug` | string | Обов'язкове, унікальне, regex `/^[a-z0-9-]+$/` |

**UI:** Перевірка доступності slug в реальному часі.

---

## 13. Адмін-панель — Знижкові купони

| | |
|---|---|
| **Маршрут FE** | `/admin/coupons` |

### Endpoints

| Метод | Endpoint | Опис | Доступ |
|-------|----------|------|--------|
| `GET` | `/discount-coupons` | Список (пагінація, фільтри) | ADMIN |
| `GET` | `/discount-coupons/{id}` | Отримати за ID | ADMIN |
| `POST` | `/discount-coupons` | Створити | ADMIN |
| `PATCH` | `/discount-coupons/{id}` | Оновити | ADMIN |
| `DELETE` | `/discount-coupons/{id}` | Видалити | ADMIN |
| `POST` | `/discount-coupons/validate` | Валідація коду | Публічний |

**Фільтри списку:** `is_active` (boolean), `q` (пошук за кодом), `page`, `limit`

**Поля створення:**

| Поле | Тип | Валідація |
|------|-----|-----------|
| `discount_percent` | number | 0–100, обов'язкове |
| `valid_until` | date | Обов'язкове |
| `is_active` | boolean | За замовч. true |

**Автоматичні поля:**
- `number`: `"DIS-"` + 7-значний лічильник (напр. `DIS-0000001`)
- `code`: 10 випадкових символів A-Z0-9 (унікальний)

---

## 14. Адмін-панель — Реквізити оплати

| | |
|---|---|
| **Маршрут FE** | `/admin/payment-details/iban` |

### Endpoints

| Метод | Endpoint | Опис | Доступ |
|-------|----------|------|--------|
| `GET` | `/payment-details` | Всі реквізити | JWT |
| `GET` | `/payment-details/active` | Активні реквізити | Публічний |
| `GET` | `/payment-details/{id}` | За ID | JWT |
| `POST` | `/payment-details` | Створити | JWT |
| `PATCH` | `/payment-details/{id}` | Оновити | JWT |
| `DELETE` | `/payment-details/{id}` | Видалити | JWT |
| `PATCH` | `/payment-details/{id}/activate` | Активувати (деактивує інші) | JWT |

**Поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `last_name` | string | Прізвище |
| `first_name` | string | Ім'я |
| `middle_name` | string | По батькові (опц.) |
| `iban` | string | IBAN (унікальний) |
| `edrpou` | string | ЄДРПОУ |
| `bank_name` | string | Назва банку |
| `is_available` | boolean | Активний (за замовч. false) |

**Логіка активації:** При активації одного — всі інші деактивуються.

---

## 15. Інтеграція з Новою Поштою

### 15.1 Синхронізація даних

| | |
|---|---|
| **Маршрут FE** | `/admin` (секція дашборду) |
| **Endpoint** | `GET /nova-post/sync` (SSE) |
| **Доступ** | ADMIN |

- Server-Sent Events stream з прогресом синхронізації
- Завантаження міст та відділень з API Нової Пошти
- Збереження в локальні колекції MongoDB

### 15.2 Пошук міст

| Endpoint | `GET /nova-post/cities?q={query}` |
|----------|------|
| **Доступ** | Публічний |
| **Мін. довжина query** | 2 символи |

### 15.3 Пошук відділень

| Endpoint | `GET /nova-post/warehouses` |
|----------|------|
| **Доступ** | Публічний |

**Query-параметри:**

| Параметр | Опис |
|----------|------|
| `cityRef` | Обов'язковий, ref міста |
| `type` | `PARCEL_LOCKER` / `POST` / `CARGO` (опц.) |
| `q` | Пошук за номером або описом (опц.) |

### 15.4 Типи відділень

| Тип | UUID |
|-----|------|
| `PARCEL_LOCKER` | `f9316480-5f2d-425d-bc2c-ac7cd29decf0` |
| `POST` | `841339c7-591a-42e2-8233-7a0a00f0ed6f` |
| `CARGO` | `9a68df70-0267-42a8-bb5c-37f427e36ee4` |

---

## 16. Завантаження файлів (S3)

**Base Path:** `/upload`
**Доступ:** JwtAuthGuard

### 16.1 Процес завантаження

1. **Presign:** `POST /upload/presign` — отримання presigned PUT URLs
2. **Upload:** Клієнт завантажує файл безпосередньо в S3 за presigned URL
3. **Confirm:** `POST /upload/confirm` — підтвердження завантаження (HeadObject перевірка)
4. **Delete:** `DELETE /upload` — видалення файлів з S3

### 16.2 Типи сутностей

| Тип | S3 шлях |
|-----|---------|
| `product` | `products/{entityId}/{uuid}.{ext}` |
| `user` | `users/{entityId}/avatar/{uuid}.{ext}` |
| `vendor` | `vendors/{entityId}/{uuid}.{ext}` |
| `category` | `categories/{entityId}/{uuid}.{ext}` |

### 16.3 Підтримувані формати

| MIME type | Розширення |
|-----------|-----------|
| `image/jpeg` | `.jpg` |
| `image/png` | `.png` |
| `image/webp` | `.webp` |

**Термін дії presigned URL:** 15 хвилин.

---

## 17. Email-сповіщення

**Провайдер:** Resend API
**Відправник:** `Fillando <noreply@fillando.com>`
**Контроль:** `ALLOW_EMAIL_SENDING` env var

### 17.1 Підтвердження замовлення (IBAN)

**Тригер:** Створення замовлення з `payment_method = IBAN`

**Отримувачі:**
1. **Клієнт** — тема: `"Замовлення {orderNumber} успішно створено"`
2. **Сервіс** (`SERVICE_EMAIL`) — тема: `"Нове замовлення {orderNumber}"`

**Дані листа:** номер замовлення, контакти клієнта, товари, суми, знижка, спосіб доставки, адреса, статуси.

---

## 18. Моделі даних

### 18.1 Users

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `email` | string | unique, required |
| `password` | string | optional (null для OAuth) |
| `name` | string | required |
| `phone` | string | unique, sparse, optional |
| `picture` | string | optional |
| `role` | enum | `USER` / `ADMIN`, default: `USER` |
| `authMethod` | enum | `EMAIL` / `GOOGLE` / `GITHUB`, default: `EMAIL` |

### 18.2 Refresh Tokens

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `userId` | ObjectId → User | required |
| `tokenHash` | string | SHA256 хеш |
| `ipAddress` | string | optional |
| `userAgent` | string | optional (parsed) |
| `expiresAt` | datetime | required |

### 18.3 Categories

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `name` | string | unique, required |
| `slug` | string | unique, required |
| `image` | string | default: null |
| `order` | number | default: 0 |
| `subcategories` | embedded array | Subcategory objects |

### 18.4 Vendors

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `name` | string | unique, required |
| `slug` | string | unique, required |

### 18.5 Products

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `name` | string | required |
| `category_id` | ObjectId → Category | required |
| `subcategory_id` | ObjectId | required |
| `vendor_id` | ObjectId → Vendor | required |
| `description` | `{ json, html }` | optional |
| `variant_type` | `{ key, label }` | optional |
| `attributes` | array `[{ k, l, v }]` | — |

### 18.6 Product Variants

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `product_id` | ObjectId → Product | required |
| `subcategory_id` | ObjectId | required |
| `name` | string | required |
| `slug` | string | unique, required |
| `sku` | string | unique, required |
| `price` | number | required |
| `stock` | number | default: 0 |
| `images` | string[] | — |
| `v_value` | string | default: null |
| `vendor_product_sku` | string | optional |
| `status` | enum | `draft` / `active` / `archived` |

**Індекси:** `product_id`, `subcategory_id + status`, `slug` (unique), `sku` (unique)

### 18.7 Carts

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `user_id` | ObjectId → User | unique, required |
| `items` | array | `[{ variant_id, quantity, added_at }]` |

### 18.8 Orders

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `order_number` | string | unique, regex `FO-\d{7}` |
| `user_id` | ObjectId → User | nullable (гостьове замовлення) |
| `customer` | embedded | `{ name, phone, email }` |
| `items` | array | `[{ variant_id, product_id, name, sku, vendor_sku, price, quantity, image }]` |
| `total_price` | number | required |
| `subtotal_price` | number | required |
| `applied_discount` | embedded | `{ coupon_id, code, discount_percent, discount_amount }` nullable |
| `payment_method` | enum | `CASH` / `IBAN` / `LIQPAY` / `MONOPAY` |
| `payment_status` | enum | `PENDING` / `PAID` / `FAILED` / `REFUNDED` |
| `payment_transaction_id` | string | nullable |
| `delivery_method` | enum | `NOVA_POST` / `COURIER` / `PICKUP` |
| `delivery_address` | embedded | `{ city_name, warehouse_description, warehouse_number, street, building, apartment }` nullable |
| `nova_post_ttn` | string | nullable |
| `order_status` | enum | `NEW` / `CONFIRMED` / `PROCESSING` / `SHIPPED` / `DELIVERED` / `CANCELLED` / `RETURNED` |
| `comment` | string | nullable |

**Індекси:** `order_number` (unique), `user_id`, `order_status`, `payment_status`

### 18.9 Discount Coupons

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `number` | string | unique, regex `DIS-\d{7}` |
| `code` | string | unique, 10 символів A-Z0-9 |
| `discount_percent` | number | 0–100 |
| `valid_until` | datetime | required |
| `is_active` | boolean | default: true |

### 18.10 Payment Details

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `last_name` | string | required |
| `first_name` | string | required |
| `middle_name` | string | optional |
| `iban` | string | unique, required |
| `edrpou` | string | required |
| `bank_name` | string | required |
| `is_available` | boolean | default: false |

### 18.11 Nova Post Cities

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `ref` | string | unique |
| `name` | string | required |
| `settlementType` | string | required |
| `area` | string | required |

### 18.12 Nova Post Warehouses

| Поле | Тип | Обмеження |
|------|-----|-----------|
| `ref` | string | unique |
| `description` | string | required |
| `shortAddress` | string | required |
| `number` | number | required |
| `cityRef` | string | required |
| `cityName` | string | required |
| `maxWeightAllowed` | number | required |
| `typeOfWarehouse` | string | required (UUID) |
| `postalCode` | string | required |

---

## 19. Перелік маршрутів

### 19.1 Публічні сторінки (FE)

| Маршрут | Опис |
|---------|------|
| `/` | Головна сторінка |
| `/auth/login` | Логін |
| `/auth/register` | Реєстрація |
| `/auth/success` | OAuth callback |
| `/{categorySlug}/{subcategorySlug}` | Каталог товарів |
| `/products/{slug}` | Сторінка товару |
| `/checkout` | Оформлення замовлення |
| `/checkout/success` | Успішне замовлення |

### 19.2 Захищені сторінки (authenticated)

| Маршрут | Опис |
|---------|------|
| `/account/profile` | Профіль користувача |
| `/profile/orders` | Мої замовлення |
| `/profile/orders/{id}` | Деталі замовлення |

### 19.3 Адмін-панель (Role.ADMIN)

| Маршрут | Опис |
|---------|------|
| `/admin` | Дашборд (синхронізація НП) |
| `/admin/products` | Список товарів |
| `/admin/products/create` | Створення товару |
| `/admin/products/{id}/edit` | Редагування товару |
| `/admin/vendors` | Виробники |
| `/admin/categories` | Категорії |
| `/admin/coupons` | Знижкові купони |
| `/admin/orders` | Замовлення |
| `/admin/orders/{id}` | Деталі замовлення |
| `/admin/payment-details` | Реквізити оплати |
| `/admin/payment-details/iban` | IBAN реквізити |
| `/admin/users` | Користувачі (заглушка) |
| `/admin/style-guide` | Showcase компонентів |

---

## 20. Нереалізований функціонал (заглушки)

| Функціонал | Статус |
|------------|--------|
| Оплата LiqPay | UI вимкнено ("coming soon") |
| Оплата MonoPay | UI вимкнено ("coming soon") |
| GitHub OAuth | Enum визначено, реалізація відсутня |
| Управління користувачами (адмін) | Сторінка-заглушка |
| Налаштування акаунту | Сторінка-заглушка |
| Реквізити LiqPay/MonoPay/Cash | Сторінки-заглушки |

---

## Додаток: Технічні деталі

### Безпека
- Паролі: Argon2 + pepper (мін. 16 символів)
- JWT: httpOnly cookies, sameSite, окремі секрети для access/refresh
- Refresh token rotation (видалення старого при кожному оновленні)
- IP/UA трекінг для refresh токенів
- CORS: whitelist за FRONTEND_URL
- RBAC: `@Roles()` декоратор + `RolesGuard`
- Валідація: class-validator (BE), Zod (FE + response validation)
- Whitelist: невідомі поля відкидаються (ValidationPipe)

### Стейт-менеджмент (FE)
- **Zustand** `useAuthStore` — user, isAuthChecked; persist → localStorage
- **Zustand** `useCartStore` — items (сервер), guestItems (localStorage), isOpen
- **React Query** — серверний стейт для каталогу, замовлень, адмін-даних

### HTTP Service (FE)
- Axios singleton з credentials: true
- Автоматичний refresh при 401 (з дедуплікацією)
- Опціональна Zod-валідація response
- Toast-сповіщення при помилках

### Локалізація
- **Мова:** Українська (uk)
- **Валюта:** UAH (₴)
- **Телефон:** +380XXXXXXXXX
- **SEO:** locale `uk_UA`
