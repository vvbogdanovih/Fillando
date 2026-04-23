# Deployment Runbook

## Інфраструктура

Домашній сервер (Proxmox VE) зі статичним IP. Дві окремі VM для backend та frontend. Все в Docker (включно з Nginx).

```
  Internet
     │
     │  Static IP
     ▼
  ┌──────────────────────────────────────────────────────┐
  │  Router                                              │
  │                                                      │
  │  Port forwarding:                                    │
  │    :80  → Proxmox router VM :80    (HTTP)            │
  │    :443 → Proxmox router VM :443   (HTTPS)           │
  │    :2222 → Backend VM :22          (SSH для CI/CD)   │
  │    :2223 → Frontend VM :22         (SSH для CI/CD)   │
  └──────────────┬───────────────────────┬───────────────┘
                 │ LAN                   │ LAN
     ┌───────────▼──────────┐  ┌─────────▼──────────────┐
     │  Proxmox Host        │  │                        │
     │                      │  │                        │
     │  ┌────────────────┐  │  │  ┌──────────────────┐  │
     │  │ VM: Backend    │  │  │  │ VM: Frontend     │  │
     │  │ Ubuntu 22/24   │  │  │  │ Ubuntu 22/24     │  │
     │  │                │  │  │  │                  │  │
     │  │ ┌── Docker ──┐ │  │  │  │ ┌── Docker ──┐  │  │
     │  │ │ Nginx :80  │ │  │  │  │ │ Nginx :80  │  │  │
     │  │ │   ↓        │ │  │  │  │ │   ↓        │  │  │
     │  │ │ NestJS     │ │  │  │  │ │ Next.js    │  │  │
     │  │ │ :4000      │ │  │  │  │ │ :3000      │  │  │
     │  │ └────────────┘ │  │  │  │ └────────────┘  │  │
     │  └────────────────┘  │  │  └──────────────────┘  │
     │                      │  │                        │
     │  ┌────────────────┐  │  └────────────────────────┘
     │  │ VM: MongoDB    │  │
     │  │ (вже працює)   │  │
     │  └────────────────┘  │
     └──────────────────────┘

  DNS:
    fillando.com      → Static IP
    api.fillando.com  → Static IP
```

| Компонент | VM | Docker контейнер | Порт |
|-----------|-----|-----------------|------|
| Nginx (BE) | Backend VM | `fillando-nginx-be` | 80 |
| NestJS | Backend VM | `fillando-be` | 4000 (internal) |
| Nginx (FE) | Frontend VM | `fillando-nginx-fe` | 80 |
| Next.js | Frontend VM | `fillando-fe` | 3000 (internal) |
| MongoDB | MongoDB VM | Вже розгорнутий | 27017 |

---

## Крок 0 — Мережа та DNS

### 0.1 DNS записи

| Тип | Ім'я | Значення |
|-----|------|----------|
| A | `fillando.com` | `<статичний IP>` |
| A | `api.fillando.com` | `<статичний IP>` |
| CNAME | `www.fillando.com` | `fillando.com` |

### 0.2 Port forwarding на роутері

Два домени на одному IP — потрібен router-рівень для розподілу по доменах.

**Рекомендовано: Nginx router на Proxmox host** (або lightweight LXC/VM):

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

```bash
sudo tee /etc/nginx/sites-available/fillando-router << 'EOF'
# Backend: api.fillando.com → Backend VM
server {
    listen 80;
    server_name api.fillando.com;

    location / {
        proxy_pass http://<BACKEND_VM_LAN_IP>:80;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE support
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 86400s;
    }
}

# Frontend: fillando.com → Frontend VM
server {
    listen 80;
    server_name fillando.com www.fillando.com;

    location / {
        proxy_pass http://<FRONTEND_VM_LAN_IP>:80;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/fillando-router /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 0.3 SSL (Let's Encrypt на router рівні)

```bash
sudo certbot --nginx -d fillando.com -d www.fillando.com -d api.fillando.com \
    --non-interactive --agree-tos -m your@email.com
```

SSL termination на router → далі по LAN трафік йде по HTTP до VM. Nginx в Docker на VM працює тільки на порті 80.

### 0.4 Port forwarding таблиця

| Зовнішній порт | Внутрішній IP | Внутрішній порт | Призначення |
|----------------|--------------|-----------------|-------------|
| 80 | Router VM/Host | 80 | HTTP → Nginx router |
| 443 | Router VM/Host | 443 | HTTPS → Nginx router |
| 2222 | Backend VM | 22 | SSH (CI/CD backend) |
| 2223 | Frontend VM | 22 | SSH (CI/CD frontend) |

---

## Крок 1 — Підготовка обох VM

Виконати на **кожній** VM.

### 1.1 VM в Proxmox

- **OS:** Ubuntu 22.04 / 24.04
- **RAM:** мін. 2GB
- **Disk:** 20GB+
- **Network:** Bridge (доступ до LAN)

### 1.2 Базове налаштування

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ufw
```

### 1.3 Deploy-користувач

```bash
sudo adduser deploy
sudo usermod -aG sudo deploy
su - deploy
```

### 1.4 Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw enable
```

**Note:** Тільки порт 80 — SSL termination на router, до VM трафік йде по HTTP.

### 1.5 Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker deploy
exit
su - deploy
docker --version && docker compose version
```

### 1.6 SSH Deploy Key для GitHub

```bash
# Backend VM:
ssh-keygen -t ed25519 -C "deploy@fillando-be" -f ~/.ssh/github_deploy -N ""

# Frontend VM:
ssh-keygen -t ed25519 -C "deploy@fillando-fe" -f ~/.ssh/github_deploy -N ""
```

Додати `~/.ssh/github_deploy.pub` в GitHub → Repo → Settings → Deploy keys.

```bash
cat >> ~/.ssh/config << 'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_deploy
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
ssh -T git@github.com
```

---

## Крок 2 — Backend VM

### 2.1 Клонування

```bash
sudo mkdir -p /srv/fillando-api
sudo chown deploy:deploy /srv/fillando-api
git clone git@github.com:vvbogdanovih/fillando-be.git /srv/fillando-api
cd /srv/fillando-api
```

### 2.2 Nginx config (файл в репо)

Створити `nginx/default.conf` в репо:

```nginx
server {
    listen 80;
    server_name api.fillando.com;

    location / {
        proxy_pass http://api:4000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE support (Nova Post sync)
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 86400s;
    }
}
```

### 2.3 docker-compose.prod.yml

```yaml
services:
    api:
        build:
            context: .
            dockerfile: Dockerfile.prod
        container_name: fillando-be
        restart: unless-stopped
        env_file: .env.prod
        expose:
            - '4000'
        networks:
            - fillando-net

    nginx:
        image: nginx:alpine
        container_name: fillando-nginx-be
        restart: unless-stopped
        ports:
            - '80:80'
        volumes:
            - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
        depends_on:
            - api
        networks:
            - fillando-net

networks:
    fillando-net:
```

**Ключові моменти:**
- `api` використовує `expose` (не `ports`) — порт 4000 доступний тільки в Docker network
- `nginx` проксює на `http://api:4000` — Docker DNS по імені сервісу
- Назовні відкритий тільки порт 80 (Nginx)

### 2.4 Production environment

```bash
cat > .env.prod << 'EOF'
NODE_ENV=production
PORT=4000
LOG_LEVEL=info
FRONTEND_URL=https://fillando.com

DATABASE_URL=mongodb://<USER>:<PASS>@<MONGO_VM_LAN_IP>:27017/<DB>?authSource=admin

JWT_SECRET=<CHANGE>
JWT_EXPIRATION=15
ACCSESS_TOKEN_NAME=access_token

REFRESH_JWT_SECRET=<CHANGE>
REFRESH_JWT_EXPIRATION=10080
REFRESH_TOKEN_NAME=refresh_token

PASSWORD_PEPPER=<CHANGE_min_16_chars>

GOOGLE_CLIENT_ID=<CHANGE>
GOOGLE_CLIENT_SECRET=<CHANGE>
GOOGLE_CALLBACK_URL=https://api.fillando.com/auth/google/callback

AWS_REGION=eu-north-1
AWS_ACCESS_KEY_ID=<CHANGE>
AWS_SECRET_ACCESS_KEY=<CHANGE>
AWS_S3_BUCKET_NAME=<CHANGE>
AWS_S3_PUBLIC_URL=https://<BUCKET>.s3.eu-north-1.amazonaws.com

NOVA_POS_API_KEY=<CHANGE>

RESEND_API_KEY=<CHANGE>
SERVICE_EMAIL=<CHANGE>
ALLOW_EMAIL_SENDING=true
EOF

chmod 600 .env.prod
```

### 2.5 Перший запуск

```bash
cd /srv/fillando-api
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml logs -f
```

---

## Крок 3 — Frontend VM

### 3.1 Клонування

```bash
sudo mkdir -p /srv/fillando-frontend
sudo chown deploy:deploy /srv/fillando-frontend
git clone git@github.com:vvbogdanovih/fillando-fe.git /srv/fillando-frontend
cd /srv/fillando-frontend
```

### 3.2 Nginx config (файл в репо)

Створити `nginx/default.conf` в репо:

```nginx
server {
    listen 80;
    server_name fillando.com www.fillando.com;

    location / {
        proxy_pass http://frontend:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
    }
}
```

### 3.3 docker-compose.prod.yml

```yaml
services:
    frontend:
        build:
            context: .
            dockerfile: Dockerfile.prod
            args:
                NEXT_PUBLIC_API_BASE_URL: https://api.fillando.com
        container_name: fillando-fe
        restart: unless-stopped
        env_file: .env.prod
        expose:
            - '3000'
        networks:
            - fillando-net

    nginx:
        image: nginx:alpine
        container_name: fillando-nginx-fe
        restart: unless-stopped
        ports:
            - '80:80'
        volumes:
            - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
        depends_on:
            - frontend
        networks:
            - fillando-net

networks:
    fillando-net:
```

### 3.4 Production environment

```bash
cat > .env.prod << 'EOF'
NODE_ENV=production
NEXT_PUBLIC_API_BASE_URL=https://api.fillando.com
NEXT_PUBLIC_SITE_URL=https://fillando.com
EOF

chmod 600 .env.prod
```

### 3.5 Перший запуск

```bash
cd /srv/fillando-frontend
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml logs -f
```

---

## Крок 4 — GitHub Actions CI/CD

### 4.1 SSH ключі для CI

На локальній машині:

```bash
ssh-keygen -t ed25519 -C "github-actions-be" -f ~/.ssh/fillando_be_deploy -N ""
ssh-keygen -t ed25519 -C "github-actions-fe" -f ~/.ssh/fillando_fe_deploy -N ""
```

Додати публічні ключі на VM:

```bash
# Backend VM (deploy user):
echo "<fillando_be_deploy.pub>" >> ~/.ssh/authorized_keys

# Frontend VM (deploy user):
echo "<fillando_fe_deploy.pub>" >> ~/.ssh/authorized_keys
```

### 4.2 GitHub Secrets

Обидва репо використовують однаковий `SSH_HOST` (статичний IP), але різний `SSH_PORT`.

**fillando-be** → Settings → Secrets → Actions:

| Secret | Value |
|--------|-------|
| `SSH_HOST` | Статичний IP |
| `SSH_USER` | `deploy` |
| `SSH_KEY` | Приватний ключ `fillando_be_deploy` |
| `SSH_PORT` | `2222` |

**fillando-fe** → Settings → Secrets → Actions:

| Secret | Value |
|--------|-------|
| `SSH_HOST` | Статичний IP |
| `SSH_USER` | `deploy` |
| `SSH_KEY` | Приватний ключ `fillando_fe_deploy` |
| `SSH_PORT` | `2223` |

### 4.3 Backend workflow

**`fillando-be/.github/workflows/deploy.yml`**:

```yaml
name: Deploy Backend

on:
    push:
        branches: [main]

jobs:
    deploy:
        runs-on: ubuntu-latest
        steps:
            - name: Deploy via SSH
              uses: appleboy/ssh-action@v1
              with:
                  host: ${{ secrets.SSH_HOST }}
                  username: ${{ secrets.SSH_USER }}
                  key: ${{ secrets.SSH_KEY }}
                  port: ${{ secrets.SSH_PORT }}
                  script: |
                      cd /srv/fillando-api
                      git pull origin main
                      docker compose -f docker-compose.prod.yml build --no-cache api
                      docker compose -f docker-compose.prod.yml up -d --no-deps api
                      docker image prune -f
```

### 4.4 Frontend workflow

**`fillando-fe/.github/workflows/deploy.yml`**:

```yaml
name: Deploy Frontend

on:
    push:
        branches: [main]

jobs:
    deploy:
        runs-on: ubuntu-latest
        steps:
            - name: Deploy via SSH
              uses: appleboy/ssh-action@v1
              with:
                  host: ${{ secrets.SSH_HOST }}
                  username: ${{ secrets.SSH_USER }}
                  key: ${{ secrets.SSH_KEY }}
                  port: ${{ secrets.SSH_PORT }}
                  script: |
                      cd /srv/fillando-frontend
                      git pull origin main
                      docker compose -f docker-compose.prod.yml build --no-cache frontend
                      docker compose -f docker-compose.prod.yml up -d --no-deps frontend
                      docker image prune -f
```

**Note:** Ребілдиться тільки app контейнер (`--no-deps api` / `--no-deps frontend`), Nginx не перезбирається — він використовує готовий `nginx:alpine` образ і конфіг з volume.

---

## Крок 5 — CORS та Cookies

### Cookie domain

Фронт (`fillando.com`) і бек (`api.fillando.com`) — різні піддомени. В NestJS додати `domain` при встановленні cookies:

```typescript
response.cookie(name, value, {
    httpOnly: true,
    secure: true,
    sameSite: 'lax',
    domain: '.fillando.com',  // спільний root domain
    maxAge: ...,
})
```

### CORS

В `.env.prod`: `FRONTEND_URL=https://fillando.com`. NestJS CORS вже використовує це як origin з `credentials: true`.

### trust proxy

`app.set('trust proxy', 1)` — вже є в `main.ts`. Коректно для роботи за Nginx.

---

## Крок 6 — Верифікація

### Checklist

- [ ] DNS A-записи → статичний IP
- [ ] Port forwarding (80, 443, 2222, 2223)
- [ ] Router Nginx розподіляє трафік по доменах
- [ ] SSL сертифікати (Let's Encrypt на router)
- [ ] `https://api.fillando.com/swagger` відкривається
- [ ] `https://api.fillando.com/categories` повертає JSON
- [ ] `https://fillando.com` завантажується
- [ ] Логін/реєстрація працюють
- [ ] Google OAuth callback працює
- [ ] Cookies передаються між доменами
- [ ] Push в `main` → GitHub Actions → автодеплой

### Логи

```bash
# Backend VM
docker logs fillando-be --tail 100 -f
docker logs fillando-nginx-be --tail 100 -f

# Frontend VM
docker logs fillando-fe --tail 100 -f
docker logs fillando-nginx-fe --tail 100 -f
```

### Рестарт

```bash
# Backend VM
cd /srv/fillando-api && docker compose -f docker-compose.prod.yml restart

# Frontend VM
cd /srv/fillando-frontend && docker compose -f docker-compose.prod.yml restart
```

---

## Troubleshooting

### Docker build OOM (< 2GB RAM)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Let's Encrypt не видає сертифікат

- DNS вказує на ваш IP: `dig fillando.com`
- Порти 80/443 доступні ззовні: `curl -v http://fillando.com`
- Firewall на router VM: `sudo ufw status`

### GitHub Actions SSH timeout

- Port forwarding працює: `ssh -p 2222 deploy@<IP>` з локальної машини
- Public key на VM: `cat ~/.ssh/authorized_keys`

### Cookies не передаються

- `domain: '.fillando.com'` в cookie options
- `secure: true` (HTTPS обов'язковий)
- CORS header: `Access-Control-Allow-Credentials: true`

### Disk space

```bash
docker system prune -a --volumes
```

---

## Файлова структура (що додати в репо)

### fillando-be

```
fillando-be/
├── nginx/
│   └── default.conf          ← Nginx config
├── docker-compose.prod.yml   ← вже є (оновити)
├── Dockerfile.prod           ← вже є
└── .github/
    └── workflows/
        └── deploy.yml        ← вже є (оновити branch на main)
```

### fillando-fe

```
fillando-fe/
├── nginx/
│   └── default.conf          ← Nginx config
├── docker-compose.prod.yml   ← вже є (оновити)
├── Dockerfile.prod           ← вже є
└── .github/
    └── workflows/
        └── deploy.yml        ← вже є (оновити branch на main)
```
