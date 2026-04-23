# CLAUDE.md — Fillando Meta Repository

Це мета-репозиторій для керування розробкою **Fillando** — інтернет-магазину витратних матеріалів для 3D-друку.

---

## Scope

Fillando складається з двох child-репозиторіїв:

| Repo | Directory | Stack | GitHub |
|------|-----------|-------|--------|
| **Backend** | `fillando-be/` | NestJS, MongoDB (Mongoose), JWT, Argon2, S3, Resend, Nova Post API | `vvbogdanovih/fillando-be` |
| **Frontend** | `fillando-fe/` | Next.js 16 (App Router), React 19, TypeScript, Tailwind CSS 4, Zustand, React Query, React Hook Form + Zod | `vvbogdanovih/fillando-fe` |

Child repos клонуються в кореневу директорію і **gitignored** в мета-репо. Кожен має власний remote і CLAUDE.md з деталями.

---

## Layout

```
Fillando/                     ← мета-репо (цей git)
├── CLAUDE.md                 ← ви тут
├── README.md                 ← quick start
├── .gitignore                ← ігнорить fillando-be/, fillando-fe/, .env
├── docs/
│   ├── requirements/         ← FRD та інші вимоги
│   │   └── FRD.md
│   ├── architecture/         ← архітектурні рішення
│   └── runbooks/             ← гайди з налаштування
│       └── env-template.env  ← master шаблон змінних
├── scripts/
│   ├── clone-all.sh          ← клонування child repos
│   ├── sync-env.sh           ← розподіл .env по child repos
│   └── validate-env.sh       ← перевірка env credentials
├── fillando-be/              ← [gitignored] backend repo
└── fillando-fe/              ← [gitignored] frontend repo
```

---

## Documentation Hierarchy

Документація організована за пріоритетом:

1. **`docs/requirements/FRD.md`** — єдине джерело правди щодо реалізованого функціоналу
2. **`docs/architecture/`** — ADR та архітектурні рішення
3. **`docs/runbooks/`** — інструкції з налаштування, env template
4. **`fillando-be/CLAUDE.md`** — backend-специфічні конвенції та команди
5. **`fillando-fe/CLAUDE.md`** — frontend-специфічні конвенції та команди

---

## Environment Management

### Master .env

Один `.env` файл в корені мета-репо містить ВСІ змінні для обох проектів. Секції розділені маркерами:

```
# === BEGIN COMMON ===
...
# === END COMMON ===
# === BEGIN BACKEND ===
...
# === END BACKEND ===
# === BEGIN FRONTEND ===
...
# === END FRONTEND ===
```

### Sync

```bash
bash scripts/sync-env.sh
```

Скрипт розбирає `.env` по секціях і записує:
- `fillando-be/.env` ← COMMON + BACKEND
- `fillando-fe/.env` ← COMMON + FRONTEND

### Validate

```bash
bash scripts/validate-env.sh
```

Перевіряє наявність обов'язкових змінних та базові smoke-тести підключень.

---

## Commands

```bash
# Clone child repos (idempotent)
bash scripts/clone-all.sh

# Sync env from root .env to child repos
bash scripts/sync-env.sh

# Validate env variables
bash scripts/validate-env.sh

# Backend
cd fillando-be
yarn start:dev              # dev server (hot reload)
yarn build                  # build
yarn lint                   # ESLint
yarn test                   # unit tests
docker compose up -d        # MongoDB

# Frontend
cd fillando-fe
yarn dev                    # dev server (port 9000)
yarn build                  # production build
```

---

## Development Workflow

### Branch Strategy

- **`main`** — стабільна гілка, production-ready
- Feature branches створюються від `main` в кожному child repo окремо
- PR в `main` через GitHub

### Commit Conventions

Кожен child repo має свої конвенції (див. їхні CLAUDE.md). Мета-репо використовує:

```
docs: update FRD with new feature
scripts: add validate-env script
chore: update env template
```

### Working with Child Repos

Claude Code агент повинен:

1. **Читати CLAUDE.md** відповідного child repo перед будь-якою роботою в ньому
2. **Перевіряти docs/requirements/FRD.md** при додаванні нового функціоналу
3. **Оновлювати FRD.md** після завершення реалізації нової фічі
4. **Не змішувати** зміни між repos — один PR = один repo

---

## Key Architecture Facts

### Backend (fillando-be)

- **API prefix:** Немає глобального prefix (`/auth/login`, не `/api/auth/login`). `/api` додається тільки Nginx на production
- **Auth:** JWT (httpOnly cookies) + Google OAuth, Argon2 + pepper
- **Roles:** `USER`, `ADMIN`
- **DB:** MongoDB через Mongoose, repository pattern
- **File storage:** AWS S3 через presigned URLs
- **Email:** Resend API
- **Delivery:** Nova Post API integration
- **Swagger:** `/swagger`

### Frontend (fillando-fe)

- **Framework:** Next.js 16 App Router, React 19
- **State:** Zustand (auth store, cart store) + React Query
- **Forms:** React Hook Form + Zod
- **HTTP:** Axios singleton з auto token refresh
- **Cart:** Dual mode — guest (localStorage) + server (API)
- **Styling:** Tailwind CSS 4, dark mode only
- **UI:** Custom components (shadcn/ui conventions), Radix UI primitives
- **i18n:** Українська мова, UAH валюта

---

## Planning Entry Points

| Що | Де |
|----|----|
| Що вже реалізовано | `docs/requirements/FRD.md` |
| Як налаштувати env | `docs/runbooks/env-template.env` |
| Backend конвенції | `fillando-be/CLAUDE.md` |
| Frontend конвенції | `fillando-fe/CLAUDE.md` |
| API endpoints | `fillando-be/openapi.json` |
