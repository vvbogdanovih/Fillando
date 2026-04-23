# Fillando — Meta Repository

Мета-репозиторій для керування розробкою інтернет-магазину витратних матеріалів для 3D-друку.

## Quick Links

| Ресурс | Посилання |
|--------|-----------|
| Гайд розробки | [CLAUDE.md](CLAUDE.md) |
| FRD | [docs/requirements/FRD.md](docs/requirements/FRD.md) |
| Env template | [docs/runbooks/env-template.env](docs/runbooks/env-template.env) |

## Репозиторії

| Repo | Stack | GitHub |
|------|-------|--------|
| **fillando-be** | NestJS, MongoDB, Mongoose, JWT, S3, Resend | `vvbogdanovih/fillando-be` |
| **fillando-fe** | Next.js 16, React 19, Tailwind CSS 4, Zustand, React Query | `vvbogdanovih/fillando-fe` |

## Getting Started

```bash
# 1. Clone meta repo
git clone <meta-repo-url> Fillando && cd Fillando

# 2. Clone child repos
bash scripts/clone-all.sh

# 3. Copy env template and fill in values
cp docs/runbooks/env-template.env .env
# edit .env with real values

# 4. Sync env to child repos
bash scripts/sync-env.sh

# 5. Start MongoDB
cd fillando-be && docker compose up -d && cd ..

# 6. Start backend
cd fillando-be && yarn install && yarn start:dev

# 7. Start frontend (in another terminal)
cd fillando-fe && yarn install && yarn dev
```
