# Plan-0007 — Фасети каталогу та UX фільтрів (Фаза 2)

- **Status:** In Progress — увесь код у `dev`: PR-1 (be, `62b1a59`) і PR-2 (fe, один коміт) 2026-09-06, **не запушено**; лишаються 15–16 після релізу й приймання. Покупець цього ще не бачить. `☐` = не почато; `☑` = код у `dev`; `☐ прод` = чекає на реліз або приймання
- **Owner:** vvbogdanovih
- **Date:** 2026-09-06
- **Target:** екран 1 макета («Категорія /filament») — **видно покупцю** в проді (Plan-0005 §3): лічильники біля значень, акордеон, «показати ще», чипи з «Очистити все», sticky-кнопка в drawer
- **Design (TD):** [TD-0008](../designs/TD-0008-catalog-facets-and-filter-ux.md) (Approved 2026-09-06, рецензія [TD-0008-review.md](../designs/TD-0008-review.md)) · контракт ізоляції — [TD-0005](../designs/TD-0005-catalog-category-isolation.md) · індексація — [TD-0002 §5.4](../designs/TD-0002-catalog-taxonomy-and-landings.md)
- **Components:** both (fillando-be, fillando-fe)
- **Tracker:** [Plan-0005 §4, блок F](plan-0005-catalog-target-state.md) і додаток, §«Категорія /filament», рядки 3–5 — готовність визначає трекер, не цей файл

## 1. Objective

Дати сайдбару категорії фасетні лічильники, пораховані по поточному звуженню з
виключенням власного виміру, числовий порядок значень і UX із роадмапу Фази 2
(акордеон, пошук у групі, «показати ще», «Очистити все», sticky «Показати N
товарів» на мобілці) — без змін у URL, індексації й контракті ізоляції.

Definition of done — за Plan-0005 §3, у проді на реальних даних:

- `GET /products/catalog` віддає `facets` для кожного виміру категорії;
  вибір значення у вимірі не обнуляє решту значень цього виміру, але звужує
  інші; `color_options.count` звужується так само; значення впорядковані
  числово, де вони числові;
- на `/filament`: групи-акордеон, «(N)» біля кожного значення, нульові
  приглушені, «Показати ще» після 8, пошук у групі при >10, «Очистити все»
  над сіткою, на мобілці — sticky-кнопка з тим самим числом, що в рядку
  «Знайдено»;
- вимір з одним значенням («Діаметр») у сайдбарі відсутній;
- на `/filament/pla-silk` закріплені виміри не в сайдбарі й не знімаються
  «Очистити все».

## 2. Scope

Обсяг, рішення, альтернативи й ризики — у TD-0008. Тут лише розбиття на PR-и
й порядок. Дефолти TD §8, за якими йде код: нове поле `facets` + похідне
`filter_options` на один реліз; range-фільтрів немає; виміри з <2 значень
ховаються; акордеон розкритий за замовчуванням.

**Що цей план свідомо не робить:** range за атрибутами чи `weight_g`, нові
виміри, зміни словника кольорів, зміни URL/канонікалів, персоналізацію
порядку (TD-0008 §2). Реліз — блок A Plan-0005.

**Передумови.** Plan-0004 у `dev` (є `required_attributes` таксономії,
`color_family`, лендінги) — виконано. `CategoryRepository` експортується з
`CategoryModule` — є.

## 3. Work breakdown

Правило «один PR = один репо». Кроки TD-0008 §9 у дужках.

### PR-1 (be) — фасети, сортування, форма відповіді

| # | Task | Component | Depends on | Status |
|---|------|-----------|------------|--------|
| 1 | `src/common/utils/facet.utils.ts`: `compareFacetValues` (числа за величиною перед словами, колатор `uk-UA`), `mergeFacetValues(all, counted)` → `{value, count}[]` з нулями для відсутніх. Спека `facet.utils.spec.ts` (TD §5.4.2, §7) | fillando-be | — | ☑ |
| 2 | `ProductService.getCatalog`: інжект `CategoryRepository` (імпорт `CategoryModule` у `ProductModule`), `findById(category_id)` → `facetKeys = required_attributes.map(a => a.key)`; невідома категорія → `[]`, без винятку. Оновити конструктори в 4 спеках (`product.service.spec.ts`, `product.catalog-query.spec.ts`, `product.variant-color.spec.ts`, `product.variant-naming.spec.ts`) | fillando-be | — | ☑ |
| 3 | `findCatalogItems`: параметр `facetKeys`; `narrowingMatch(exclude)` з `attrFilters`/`colorFamilies`/ціни; один `$facet` (гілки `values`, `count_<i>` позиційно, `color_all`, `color_count`; `$lookup` з проєкцією лише `attributes`; групування по `{v, variant}` проти подвійного обліку) після `$match` + `$lookup products` + `$project` легких полів; замінює `filterOptionsPipeline` і `colorOptionsPipeline`; злиття й сортування в JS; `facets` у відповіді, `filter_options` — похідне з `@deprecated`; `color_options.count` — по звуженню (TD §5.3, §5.4.1) | fillando-be | 1, 2 | ☑ |
| 4 | Інт-тест `product-variant-catalog-facets.int-spec.ts`: дев'ять кейсів TD §7 (власний вимір не враховується; інший вимір звужує; нуль присутній; ціна й колір звужують атрибути; атрибут звужує колір; порядок `0.5, 1, 3` і порядок ключів; мультизначний `finish` по разу на значення; чернетка не рахується; вимір без даних → `[]`). Переписати `…-isolation.int-spec.ts` на `facets` | fillando-be | 3 | ☑ |
| 5 | `product.catalog-query.spec.ts`: ключі фасетів із категорії; невідома категорія → порожні ключі | fillando-be | 2 | ☑ |
| 6 | Swagger: `API_OPERATION.PRODUCTS.CATALOG.description` про `facets`; `yarn spec:export`; `src/docs/CATALOG_FACETS.md` (семантика лічильника, чому `filter_options` ще живе, як прибрати) | fillando-be | 3 | ☑ |
| 7 | Виміряти час на dev (301 варіант) і записати числа в TD-0008 §7 — 285 мс end-to-end при RTT 54 мс до бази | fillando-be | 3 | ☑ |

### PR-2 (fe) — сайдбар, чипи, drawer

| # | Task | Component | Depends on | Status |
|---|------|-----------|------------|--------|
| 8 | `catalog.api.ts`: `FacetValue`, `CatalogResponse.facets` (optional), `filter_options` як `@deprecated` optional; хелпер `catalogFacets(response)` — `facets ?? fromFilterOptions(filter_options)` (список без лічильників, коли бекенд старіший — рецензія М2); `CatalogPage` передає результат у сайдбар | fillando-fe | 6 | ☑ |
| 8a | `CatalogPage`: `initialData` лише коли `params` збігаються з початковими SSR-параметрами, інакше `placeholderData: keepPreviousData`; `isFetching` наверх для drawer і сайдбара (рецензія М1). Тест: клік по фільтру не сідає новий ключ SSR-каталогом | fillando-fe | 8 | ☑ |
| 9 | `AttributeFilter.tsx`: приймає `FacetValue[]`; «(N)» біля підпису (`title` — «N товарів із цим значенням»); нуль — приглушене лише число, чекбокс клікабельний; «Показати ще N» / «Згорнути» після 8; поле «Пошук у групі» при >10 (за підписом і сирим значенням); обране видиме завжди; `filter_type: 'range'` — той самий список; без лічильників, якщо їх нема (фолбек). Тест `AttributeFilter.test.tsx` | fillando-fe | 8 | ☑ |
| 10 | `FilterSidebar.tsx`: Radix `Accordion type="multiple"` **керований** (стан — набір згорнутих груп, тож нові групи відкриті; рецензія S6.4), у тригері — підпис і кількість обраних; вимір з <2 значень і колір з <2 родин не рендеряться; ціна — перша група. Тест `FilterSidebar.test.tsx` (вимір з одним значенням, згорнута група, фолбек без `facets`) | fillando-fe | 9 | ☑ |
| 11 | `ActiveFilterChips.tsx`: кнопка «Очистити все» — знімає **кожен** параметр, крім `page`/`limit`/`sort` і закріплених (той самий набір, що `narrowingKeys`; рецензія S2); чип із сирим підписом для ключа поза вимірами; не з'являється без знімних чипів. Тест `ActiveFilterChips.test.tsx` | fillando-fe | 8 | ☑ |
| 12 | `FilterDrawer.tsx`: винести drawer із `CatalogPage` (шапка, прокрутка, sticky-футер «Показати N товарів» через `productsCount(pagination.total)`; під час `isFetching` — «Показати товари» з `aria-busy`; «Очистити» за наявності обраного); кнопка закриває drawer. Тест `FilterDrawer.test.tsx` | fillando-fe | 8a, 10, 11 | ☑ |
| 13 | `admin/landings/_components/PinnedFilters.tsx`: виміри й значення з `facets` (через той самий хелпер); картка для ключа, який уже є в `value`, рендериться навіть коли його нема у `facets` (рецензія М4; на dev таких лендінгів немає); оновити мок у `LandingForm.test.tsx` | fillando-fe | 8 | ☑ |
| 14 | `CLAUDE.md` фронта: у розділі «Storefront colour & landings» — абзац про фасети (лічильник без власного виміру, нуль не ховати, вимір з <2 значень не рендерити, стан акордеона не в URL); `yarn test`, `npx tsc --noEmit`, `yarn build` з піднятим бекендом | fillando-fe | 9–13 | ☑ |

### Після релізу й приймання

| # | Task | Component | Depends on | Status |
|---|------|-----------|------------|--------|
| 15 | PR-3 (be): видалити `filter_options` з відповіді й Swagger; `yarn spec:export` | fillando-be | реліз | ☐ прод |
| 16 | FRD §4 — фасети, порядок значень, приховані виміри; Plan-0002 Фаза 2 → Done; Plan-0005 §3 екран 1 і §4 блок F; TD-0008 → Implemented | meta | приймання | ☐ прод |

## 4. Sequencing & milestones

1. PR-1 (задачі 1–7) → `yarn spec:export` → коміт у `dev` fillando-be.
2. PR-2 (задачі 8–14) → коміт у `dev` fillando-fe. Задачі 9, 11 можна робити
   паралельно; 12 залежить від обох.
3. Реліз — блок A Plan-0005, разом із решою `dev`.
4. Після приймання — 15, 16.

Оцінка Plan-0002 §Фаза 2 (2 PR, ~1 тиждень) лишається.

## 6. Testing & rollout

- be: `yarn test` (юніти 1, 5), `yarn test:db:up` → `yarn test:integration` →
  `yarn test:db:down` (4); `npx eslint <мої файли>` (не `yarn lint` — він з
  `--fix` чіпає чужі файли); ручний `curl` за TD-0008 §9.
- fe: `yarn test`, `npx tsc --noEmit`, `yarn build` з піднятим бекендом на
  9001; ручна перевірка `/filament` і `/filament/pla-silk` на 1280 і <768.
- Порядок деплою: **бекенд перед фронтом** (Plan-0005 A2 → A3). Старий фронт
  на новому бекенді працює через похідне `filter_options`; новий фронт на
  старому — через фолбек задачі 8 (сайдбар без лічильників). Відкат — revert
  PR-1: фронт через фолбек працює далі.
- Міграцій даних немає.

## 7. Open questions

Усі — в TD-0008 §8 з дефолтами; жодне не блокує PR-1 і PR-2. Якщо власник
поверне range-фільтри (§8 п.2) — це +1 задача be (`weight_min/max` на
`variantMatch`, `weight_range` у відповіді) і +1 fe (узагальнений
`PriceRangeFilter`), окремим PR після цих двох.
