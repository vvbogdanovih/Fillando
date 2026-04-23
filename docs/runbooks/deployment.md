# Deployment Runbook

## Інфраструктура

Домашній сервер (Proxmox VE) зі статичним IP. Дві окремі VM для backend та frontend.

```
  Internet
     │
     │  Static IP (ваш провайдер)
     ▼
  ┌──────────────────────────────────────────────────────┐
  │  Router                                              │
  │                                                      │
  │  Port forwarding:                                    │
  │    :80  → HAProxy / VM          (HTTP)               │
  │    :443 → HAProxy / VM          (HTTPS)              │
  │    :2222 → Backend VM :22       (SSH для CI/CD)      │
  │    :2223 → Frontend VM :22      (SSH для CI/CD)      │
  └──────────────┬───────────────────────┬───────────────┘
                 │ LAN                   │ LAN
     ┌───────────▼──────────┐  ┌─────────▼──────────────┐
     │  Proxmox Host        │  │                        │
     │                      │  │                        │
     │  ┌────────────────┐  │  │  ┌──────────────────┐  │
     │  │ VM: Backend    │  │  │  │ VM: Frontend     │  │
     │  │ Ubuntu 22/24   │  │  │  │ Ubuntu 22/24     │  │
     │  │                │  │  │  │                  │  │
     │  │ Nginx (:80/443)│  │  │  │ Nginx (:80/443)  │  │
     │  │   ↓            │  │  │  │   ↓              │  │
     │  │ NestJS (:4000) │  │  │  │ Next.js (:3000)  │  │
     │  │ (Docker)       │  │  │  │ (Docker)         │  │
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

| Компонент | VM | Порт (internal) | Docker |
|-----------|-----|-----------------|--------|
| NestJS | Backend VM | 4000 | Так |
| Nginx | Backend VM | 80, 443 | Ні (host) |
| Next.js | Frontend VM | 3000 | Так |
| Nginx | Frontend VM | 80, 443 | Ні (host) |
| MongoDB | MongoDB VM | 27017 | Вже розгорнутий |

---

## Крок 0 — Мережа та DNS

### 0.1 DNS записи

В панелі DNS провайдера (Cloudflare, тощо) створити A-записи, що вказують на ваш статичний IP:

| Тип | Ім'я | Значення | Proxy |
|-----|------|----------|-------|
| A | `fillando.com` | `<ваш статичний IP>` | Вимкнено* |
| A | `api.fillando.com` | `<ваш статичний IP>` | Вимкнено* |
| CNAME | `www.fillando.com` | `fillando.com` | Вимкнено* |

*Proxy вимкнено якщо SSL через Let's Encrypt. Якщо Cloudflare proxy — SSL налаштовується інакше (див. примітку нижче).

### 0.2 Port forwarding на роутері

Оскільки обидва домени йдуть на один IP, потрібен один з двох підходів:

**Варіант A: Reverse proxy на Proxmox host (рекомендовано)**

Один Nginx/HAProxy на Proxmox host розподіляє трафік по доменах:

```bash
# На Proxmox host (або окремій lightweight VM)
sudo apt install -y nginx

sudo tee /etc/nginx/sites-available/fillando-router << 'EOF'
# Frontend: fillando.com → Frontend VM
server {
    listen 80;
    server_name fillando.com www.fillando.com;

    location / {
        proxy_pass http://<FRONTEND_VM_LAN_IP>:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Backend: api.fillando.com → Backend VM
server {
    listen 80;
    server_name api.fillando.com;

    location / {
        proxy_pass http://<BACKEND_VM_LAN_IP>:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/fillando-router /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Port forwarding на роутері:

| Зовнішній порт | Внутрішній IP | Внутрішній порт | Призначення |
|----------------|--------------|-----------------|-------------|
| 80 | Proxmox host / router VM | 80 | HTTP (Nginx router) |
| 443 | Proxmox host / router VM | 443 | HTTPS (Nginx router) |
| 2222 | Backend VM LAN IP | 22 | SSH для CI/CD (backend) |
| 2223 | Frontend VM LAN IP | 22 | SSH для CI/CD (frontend) |

**Варіант B: Пряме перенаправлення портів (простіше, але обмежено)**

Якщо лише один домен на VM, можна перенаправляти 80/443 напряму. Але з двома доменами на одному IP — **потрібен Варіант A** або Cloudflare proxy.

### 0.3 SSL стратегія

**Якщо Nginx router на Proxmox host:**

SSL termination робити на цьому рівні (Certbot на host), а далі проксювати по HTTP в LAN:

```bash
# На Proxmox host / router VM
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d fillando.com -d www.fillando.com -d api.fillando.com \
    --non-interactive --agree-tos -m your@email.com
```

В цьому випадку Nginx на Backend VM та Frontend VM працюють **тільки по HTTP** (port 80), без SSL.

**Якщо Cloudflare proxy увімкнено:**

Cloudflare забезпечує SSL на edge. Proxmox router проксює по HTTP. Додатковий SSL не потрібен.

---

## Крок 1 — Підготовка обох VM

Виконати на **кожній** VM (Backend та Frontend).

### 1.1 Створення VM в Proxmox

- **OS:** Ubuntu 22.04 або 24.04
- **RAM:** Мінімум 2GB (для `docker build` / `next build`)
- **Disk:** 20GB+
- **Network:** Bridge mode (доступ до LAN)

### 1.2 Оновлення системи

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ufw
```

### 1.3 Створення deploy-користувача

```bash
sudo adduser deploy
sudo usermod -aG sudo deploy
su - deploy
```

### 1.4 Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable
```

### 1.5 Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker deploy

# Re-login
exit
su - deploy

# Verify
docker --version
docker compose version
```

### 1.6 Nginx

```bash
sudo apt install -y nginx
sudo systemctl enable nginx
```

### 1.7 SSH ключ для GitHub (Deploy Key)

На **кожній** VM:

```bash
# Backend VM:
ssh-keygen -t ed25519 -C "deploy@fillando-be" -f ~/.ssh/github_deploy -N ""

# Frontend VM:
ssh-keygen -t ed25519 -C "deploy@fillando-fe" -f ~/.ssh/github_deploy -N ""
```

Додати публічний ключ в GitHub:
- Repo → Settings → Deploy keys → Add deploy key
- Вставити вміст `~/.ssh/github_deploy.pub`

SSH config:

```bash
cat >> ~/.ssh/config << 'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_deploy
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
```

Перевірити: `ssh -T git@github.com`

---

## Крок 2 — Backend VM

### 2.1 Клонування репо

```bash
sudo mkdir -p /srv/fillando-api
sudo chown deploy:deploy /srv/fillando-api
git clone git@github.com:vvbogdanovih/fillando-be.git /srv/fillando-api
cd /srv/fillando-api
```

### 2.2 Production environment

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

**Note:** `DATABASE_URL` використовує LAN IP MongoDB VM (напр. `192.168.1.x`), оскільки всі VM в одній локальній мережі.

### 2.3 Production docker-compose

Створити `docker-compose.prod.yml`:

```yaml
services:
    api:
        build:
            context: .
            dockerfile: Dockerfile.prod
        container_name: fillando-be
        restart: unless-stopped
        env_file: .env.prod
        ports:
            - '127.0.0.1:4000:4000'
```

### 2.4 Nginx config

```bash
sudo tee /etc/nginx/sites-available/api.fillando.com << 'EOF'
server {
    listen 80;
    server_name api.fillando.com;

    location / {
        proxy_pass http://127.0.0.1:4000;
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
EOF

sudo ln -sf /etc/nginx/sites-available/api.fillando.com /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 2.5 Перший запуск

```bash
cd /srv/fillando-api
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
```

Перевірити: `curl http://localhost:4000/categories`

---

## Крок 3 — Frontend VM

### 3.1 Клонування репо

```bash
sudo mkdir -p /srv/fillando-frontend
sudo chown deploy:deploy /srv/fillando-frontend
git clone git@github.com:vvbogdanovih/fillando-fe.git /srv/fillando-frontend
cd /srv/fillando-frontend
```

### 3.2 Production environment

```bash
cat > .env.prod << 'EOF'
NODE_ENV=production
NEXT_PUBLIC_API_BASE_URL=https://api.fillando.com
NEXT_PUBLIC_SITE_URL=https://fillando.com
EOF

chmod 600 .env.prod
```

### 3.3 Production docker-compose

`docker-compose.prod.yml`:

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
        ports:
            - '127.0.0.1:3000:3000'
```

### 3.4 Nginx config

```bash
sudo tee /etc/nginx/sites-available/fillando.com << 'EOF'
server {
    listen 80;
    server_name fillando.com www.fillando.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
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

sudo ln -sf /etc/nginx/sites-available/fillando.com /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 3.5 Перший запуск

```bash
cd /srv/fillando-frontend
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
```

Перевірити: `curl http://localhost:3000`

---

## Крок 4 — GitHub Actions CI/CD

### 4.1 SSH ключ для CI

На **локальній машині** згенерувати ключі:

```bash
ssh-keygen -t ed25519 -C "github-actions-be" -f ~/.ssh/fillando_be_deploy -N ""
ssh-keygen -t ed25519 -C "github-actions-fe" -f ~/.ssh/fillando_fe_deploy -N ""
```

Додати **публічні** ключі на відповідні VM:

```bash
# На Backend VM (як deploy user):
echo "<вміст fillando_be_deploy.pub>" >> ~/.ssh/authorized_keys

# На Frontend VM (як deploy user):
echo "<вміст fillando_fe_deploy.pub>" >> ~/.ssh/authorized_keys
```

### 4.2 GitHub Secrets

**fillando-be** repo → Settings → Secrets → Actions:

| Secret | Value |
|--------|-------|
| `SSH_HOST` | Ваш статичний IP |
| `SSH_USER` | `deploy` |
| `SSH_KEY` | Вміст `~/.ssh/fillando_be_deploy` (приватний ключ) |
| `SSH_PORT` | `2222` (порт-форвардинг на роутері → Backend VM :22) |

**fillando-fe** repo → Settings → Secrets → Actions:

| Secret | Value |
|--------|-------|
| `SSH_HOST` | Ваш статичний IP |
| `SSH_USER` | `deploy` |
| `SSH_KEY` | Вміст `~/.ssh/fillando_fe_deploy` (приватний ключ) |
| `SSH_PORT` | `2223` (порт-форвардинг на роутері → Frontend VM :22) |

**Note:** `SSH_HOST` однаковий для обох (ваш статичний IP), але `SSH_PORT` різний — роутер перенаправляє різні порти на різні VM.

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

---

## Крок 5 — CORS та Cookies (cross-subdomain)

Фронт (`fillando.com`) і бек (`api.fillando.com`) на різних піддоменах. Для коректної роботи cookies:

### 5.1 Backend: Cookie domain

В коді NestJS, де встановлюються cookies, додати `domain`:

```typescript
response.cookie(name, value, {
    httpOnly: true,
    secure: true,                    // обов'язково для production
    sameSite: 'lax',
    domain: '.fillando.com',         // ← спільний root domain
    maxAge: ...,
})
```

`domain: '.fillando.com'` — cookie буде доступний і на `fillando.com`, і на `api.fillando.com`.

### 5.2 Backend: CORS

В `.env.prod`:

```
FRONTEND_URL=https://fillando.com
```

NestJS CORS config вже використовує `FRONTEND_URL` як origin з `credentials: true`.

### 5.3 Backend: trust proxy

`app.set('trust proxy', 1)` — вже є в `main.ts`. Це коректно для роботи за Nginx.

---

## Крок 6 — Верифікація

### Checklist

- [ ] DNS A-записи вказують на статичний IP
- [ ] Port forwarding на роутері (80, 443, 2222, 2223)
- [ ] SSL сертифікати (Let's Encrypt або Cloudflare)
- [ ] `https://api.fillando.com/swagger` відкривається
- [ ] `https://api.fillando.com/categories` повертає JSON
- [ ] `https://fillando.com` завантажується
- [ ] Логін/реєстрація працюють
- [ ] Google OAuth callback працює
- [ ] Cookies передаються між fillando.com та api.fillando.com
- [ ] GitHub Actions: push в main → автоматичний деплой

### Логи

```bash
# Backend VM
docker logs fillando-be --tail 100 -f

# Frontend VM
docker logs fillando-fe --tail 100 -f

# Nginx (на будь-якій VM)
sudo tail -f /var/log/nginx/error.log
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

### Docker build OOM (мало RAM на VM)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Let's Encrypt не видає сертифікат

- Перевірити що порти 80/443 доступні ззовні: `curl -v http://fillando.com`
- DNS має вказувати на ваш IP: `dig fillando.com`
- Firewall не блокує: `sudo ufw status`

### GitHub Actions SSH connection refused

- Перевірити port forwarding: `ssh -p 2222 deploy@<ваш-IP>` з локальної машини
- Перевірити що public key додано в `~/.ssh/authorized_keys` на VM

### Cookies не передаються

- Перевірити `domain: '.fillando.com'` в cookie options
- Перевірити `secure: true` (потрібен HTTPS)
- Перевірити CORS: `Access-Control-Allow-Credentials: true` в response headers

### Disk space

```bash
docker system prune -a --volumes
```

---

## CI/CD Flow Summary

```
  Developer pushes to main
         │
         ▼
  GitHub Actions (ubuntu-latest)
         │
         │  SSH через статичний IP
         │  port 2222 (BE) / 2223 (FE)
         ▼
  Router (port forwarding)
         │
         ▼
  VM (Backend або Frontend)
         │
         ├── git pull origin main
         ├── docker compose build --no-cache
         ├── docker compose up -d --no-deps
         └── docker image prune -f
```
