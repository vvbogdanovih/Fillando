# Implementation Plans

An Implementation Plan describes **how and when** we deliver a specific piece of
work — the breakdown into small, PR-sized tasks, sequencing, which repos change,
and risks. It usually follows an approved [Technical Design](../designs/).

Start from [`../templates/implementation-plan.md`](../templates/implementation-plan.md),
copy it here as `NNNN-short-slug.md`, and set the front-matter status.

Remember: **one PR = one repo** — a plan touching both `fillando-be` and
`fillando-fe` still lands as separate PRs per component.

## Index

Shipped plans are deleted once their feature is `Done` — git history has them,
so this table only lists plans that are still active.

| Plan | Title | Status |
|------|-------|--------|
| [Plan-0002](plan-0002-catalog-seo-roadmap.md) | Catalog SEO & UX roadmap (6 phases) | In Progress — Фази 0 і 1 у `dev`, 2–5 не почато |
| [Plan-0003](plan-0003-security-hardening.md) | Вразливості та воронка замовлення | In Progress — код у `dev`, не задеплоєно |
| [Plan-0004](plan-0004-catalog-phase-1.md) | Каталог: таксономія, кольори, лендінги (Фази 0+1) | In Progress — код у `dev`, 5 міграцій не на проді |
| [Plan-0005](plan-0005-catalog-target-state.md) | **Цільовий стан каталогу — трекер приймання** | In Progress — блоки C і D закриті в коді (`dev`), блок E спроєктований (Plan-0006); у проді 0 з 14 екранів |
| [Plan-0006](plan-0006-google-merchant.md) | Google Merchant: фід, structured data, GA4, нові поля (Фаза 5) | Approved — код не розпочато (2026-09-06) |

**Plan-0005 — це визначення готовності.** Він відповідає на питання «чи ми
закінчили», і жоден інший план не має права називати роботу завершеною, доки
його матриця приймання не зелена в проді. Реліз гілки — не приймання.
