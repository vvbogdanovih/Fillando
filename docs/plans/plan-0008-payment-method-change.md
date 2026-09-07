# Plan-0008 — Зміна способу оплати клієнтом і доплата LiqPay-замовлення

- **Status:** In Progress — увесь код у `dev`: PR-1 (be, `a4d78ed`) і PR-2 (fe, `d7813d6`), 2026-09-06, **не запушено**; лишаються ручні LiqPay-сценарії (A5) і приймання. Покупець цього ще не бачить. `☐` = не почато; `☑` = код у `dev`; `☐ прод` = чекає на реліз або приймання
- **Owner:** vvbogdanovih
- **Date:** 2026-09-06
- **Target:** екран 7 макета («Оплата не пройшла») — **видно покупцю** в проді (Plan-0005 §3): чесний текст, кнопка «Обрати інший спосіб оплати» справді міняє спосіб, застрягле PENDING можна оплатити
- **Design (TD):** [TD-0009](../designs/TD-0009-customer-payment-method-change.md) (Approved 2026-09-06, рецензія [TD-0009-review.md](../designs/TD-0009-review.md)) · попередники — [TD-0001](../designs/TD-0001-liqpay-integration.md), [TD-0003](../designs/TD-0003-order-cancellation-payment-status.md), [TD-0004](../designs/TD-0004-cash-on-delivery.md)
- **Components:** both (fillando-be, fillando-fe)
- **Tracker:** [Plan-0005 §3 екран 7, §6 рішення 10](plan-0005-catalog-target-state.md); додаток, рядки 119, 121, 122, 222 — готовність визначає трекер, не цей файл

## 1. Objective

Дати покупцю з неоплаченим LiqPay-замовленням дві справжні дії з екрана статусу й кабінету:
змінити спосіб оплати на накладний платіж / IBAN / готівку і доплатити застрягле PENDING без
ризику двох живих сесій LiqPay; прибрати з тексту обіцянку резерву, якого немає.

Definition of done — за Plan-0005 §3, у проді на реальних даних:

- `PATCH /orders/lookup/:n/payment-method?token=` і `PATCH /orders/me/:id/payment-method`
  переводять FAILED/PENDING-замовлення на COD/IBAN/CASH з листом; заблоковані стани → 409
  `PAYMENT_METHOD_LOCKED`; пізній callback LiqPay після зміни не ламає дані;
- `POST /liqpay/checkout` для PENDING у межах 15 хв → 409 `LIQPAY_SESSION_ACTIVE`;
- на `/checkout/success` після відмови банку — чесний текст і діалог зміни методу; після 60 с
  очікування PENDING — «Оплатити» і «Обрати інший спосіб оплати»; у `/profile/orders/[id]` —
  ті самі дії за статусом.

## 2. Scope

Обсяг, рішення, альтернативи й ризики — у TD-0009. Тут лише розбиття на PR-и й порядок.

**Що цей план свідомо не робить:** резерв стоку; LIQPAY як ціль зміни; історію змін замовлення;
реквізити в IBAN-листі (TD-0009 §2, §8). Реліз — блок A Plan-0005.

## 3. Work breakdown

Правило «один PR = один репо».

### PR-1 (be) — маршрути, правило статусу, cooldown, листи

| # | Task | Component | Depends on | Status |
|---|------|-----------|------------|--------|
| 1 | `order.schema.ts`: `liqpay_checkout_started_at: Date \| null` (default null) | fillando-be | — | ☑ |
| 2 | `endpoints.constant.ts`: `LOOKUP_PAYMENT_METHOD`, `MY_PAYMENT_METHOD`; `api-operation.constant.ts`: два записи + опис `LIQPAY.CHECKOUT` про 409 | fillando-be | — | ☑ |
| 3 | `dto/change-payment-method.dto.ts` (`@IsIn` на COD/IBAN/CASH); `order-payment-status-response.dto.ts` + `order_status`, `delivery_method`, `can_change_payment_method` | fillando-be | — | ☑ |
| 4 | `helpers/payment-status.helpers.ts`: `PAYMENT_METHOD_CHANGEABLE_*`, `canCustomerChangePaymentMethod`, `resolvePaymentStatusOnPaymentMethodChange(current)`; `helpers/liqpay-session.helpers.ts`: `LIQPAY_SESSION_COOLDOWN_MS`, `liqpayRetryAfterSeconds`; спеки | fillando-be | — | ☑ |
| 5 | `order.service.ts`: `CASH: [PICKUP]` в `ALLOWED_DELIVERY_BY_PAYMENT`; `toPublicPaymentStatus`; `changePaymentMethodPublic`, `changeMyPaymentMethod`, приватний `changePaymentMethod` з умовним `findOneAndUpdate` (пін статусів і поточного методу, перечит на промах); `claimLiqpayCheckout` (умовний клейм сесії); `applyGatewayPaymentResult` — усі записи з піном на LIQPAY, гілка після зміни методу з `inFulfilment` (TD §5.4.2); `findOwnOrder` з перевіркою ObjectId; адмінський `update` скидає штамп сесії при зміні методу | fillando-be | 3, 4 | ☑ |
| 6 | `order.controller.ts`: два `@Patch` (публічний з `ThrottlerGuard` 5/хв, `me` з `JwtAuthGuard`) | fillando-be | 5 | ☑ |
| 7 | `liqpay.service.ts`: атомний клейм до побудови payload → на промах перечит і 409 `LIQPAY_SESSION_ACTIVE` з `retry_after_seconds` або 400; повідомлення 400 українською; `liqpay.service.spec.ts` | fillando-be | 1 | ☑ |
| 8 | `email.service.ts`: `sendPaymentMethodChanged`, `sendLiqpayPaidAfterMethodChange`; три шаблони — `variant: 'created' \| 'payment_method_changed'` + `previousPaymentMethod`, вступний `<p>`; сервісний шаблон — `heading` | fillando-be | — | ☑ |
| 9 | `order.service.spec.ts`: no-op той самий метод; FAILED LIQPAY→COD → PENDING + лист; CASH на NOVA_POST → 400; PROCESSING → 409; хибний токен → 404 без репо; `update` → `null` → 409; `me` з чужим id → 404; callback paid/failed на COD-замовленні. Int-спека: умовний фільтр не матчить PAID | fillando-be | 5–8 | ☑ |
| 10 | `yarn spec:export`; `src/docs/LIQPAY_FLOW.md` (cooldown, таблиця, поля lookup, прибрати «No rate limiting yet»), `ORDER_ADMIN_API.md` (публічні ендпоінти, CASH→PICKUP), `API_AND_SWAGGER.md` §4a, `DATA_MODELS.md` | fillando-be | 5–8 | ☑ |

### PR-2 (fe) — діалог, кнопка оплати, дві сторінки

| # | Task | Component | Depends on | Status |
|---|------|-----------|------------|--------|
| 11 | `common/constants/payment.constants.ts` ← `isPaymentMethodAllowed`/`COD_ALLOWED_DELIVERY` з `checkout.constants.ts` (реекспорт); `api-routes.constants.ts` два шляхи; `order-payment.api.ts` + `order-payment.schemas.ts` (нові поля lookup **optional**) | fillando-fe | 10 | ☑ |
| 12 | `common/components/order-payment/PaymentMethodOptions.tsx` (3 радіо, вимкнені за доставкою, підказки, деталі COD приміткою) + тест | fillando-fe | 11 | ☑ |
| 13 | `ChangePaymentMethodDialog.tsx` (Radix Dialog + `useLenisModalLock`, тости 400/409) + тест | fillando-fe | 12 | ☑ |
| 14 | `PayNowButton.tsx` (`startLiqpayCheckout`; 409 `LIQPAY_SESSION_ACTIVE` → текст із хвилинами; інші 400 → refetch) + тест | fillando-fe | 11 | ☑ |
| 15 | `CheckoutSuccessContent.tsx`: чесний текст FAILED; PENDING після 60 с → `PayNowButton` + діалог; у `failed` друга кнопка → діалог; гілка «Спосіб оплати змінено» з конверсією один раз; кнопки сховані при `can_change_payment_method === false`; тести | fillando-fe | 13, 14 | ☑ |
| 16 | `OrderDetails.tsx`: дії в картці «Оплата» за статусом, інвалідація запитів; тест | fillando-fe | 13, 14 | ☑ |
| 17 | `e2e/mock-api.mjs` — PATCH-маршрут і 409-фікстура (без запуску e2e); `docs/checkout-flow.md` («Known gap», дерево §5, «Why stop at 60 s», контракт §1); `CLAUDE.md` абзац; `yarn test`, `npx tsc --noEmit`, `yarn build` | fillando-fe | 15, 16 | ☑ |

### Мета (робоче дерево власника)

| # | Task | Component | Depends on | Status |
|---|------|-----------|------------|--------|
| 18 | `state-machines.md`: `FAILED → PENDING` (зміна способу оплати, клієнт) + крос-машинне правило зміни методу; FRD §7.3 :492, :495, §8.2 :531, §8.3 :540-541; `glossary.md` «LiqPay session cooldown»; TD-0009 → Approved після рецензії | meta | 10, 17 | ☑ |
| 19 | Plan-0005 :74 екран 7 → «код у dev», §6 рішення 10 закрито; додаток :119, :121, :122, :222 → `~~частково~~ **код у dev**`; після приймання — TD-0009 → Implemented, FRD перечитати проти проду | meta | 18 | ☐ прод |

## 4. Sequencing & milestones

1. TD-0009 Draft → рецензія → Approved за дефолтами §8.
2. PR-1 (1–10) → коміт у `dev` fillando-be.
3. PR-2 (11–17) → коміт у `dev` fillando-fe. 12 і 14 можна паралельно; 15 і 16 залежать від обох.
4. Реліз — блок A Plan-0005 (бекенд перед фронтом); ручні LiqPay-сценарії A5 — власник.
5. Після приймання — 19.

## 6. Testing & rollout

- be: `yarn test`; `yarn test:db:up` → `yarn test:integration` → `yarn test:db:down`;
  `npx eslint <мої файли>`; `curl` на власний інстанс (TD-0009 §7).
- fe: `yarn test`, `npx tsc --noEmit`, `yarn build` з піднятим бекендом.
- Порядок деплою: бекенд перед фронтом; фронт із optional-полями працює на старому бекенді
  (нові дії просто не показуються). Відкат — revert PR-1.
- Міграцій даних немає (одне nullable-поле з default).

## 7. Open questions

Усі — в TD-0009 §8 з дефолтами; жодне не блокує PR-1 і PR-2.
