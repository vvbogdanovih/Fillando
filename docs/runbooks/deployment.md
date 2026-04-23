# Deployment Runbook

## Інфраструктура

Домашній сервер (Proxmox VE) зі статичним IP. Три контейнери/VM: LXC router (Nginx + SSL), VM backend, VM frontend. MongoDB на окремій VM (вже працює). Все (крім router) в Docker.

```
  Internet
     │
     │  Static IP
     ▼
  ┌──────────────────────────────────────────────────────────┐
  │  Home Router                                             │
  │                                                          │
  │  Port forwarding:                                        │
  │    :80  ──► LXC nginx-router :80      (HTTP)             │
  │    :443 ──► LXC nginx-router :443     (HTTPS)            │
  │    :2222 ─► Backend VM :22            (SSH для CI/CD)    │
  │    :2223 ─► Frontend VM :22           (SSH для CI/CD)    │
  └──────────────────────┬───────────────────────────────────┘
                         │ LAN
  ┌──────────────────────▼───────────────────────────────────┐
  │  Proxmox VE Host                                         │
  │                                                          │
  │  ┌─────────────────────────────────────────────────┐     │
  │  │ LXC: nginx-router  (ID 200)                     │     │
  │  │ Ubuntu 22.04, 256MB RAM, 2GB disk               │     │
  │  │                                                  │     │
  │  │ Nginx + Certbot (SSL termination)                │     │
  │  │   :443 ─── fillando.com ──────► FE VM :80        │     │
  │  │   :443 ─── api.fillando.com ──► BE VM :80        │     │
  │  └─────────────────────────────────────────────────┘     │
  │                                                          │
  │  ┌─────────────────────┐   ┌─────────────────────┐      │
  │  │ VM: Backend (ID 101)│   │ VM: Frontend (ID 102│      │
  │  │ Ubuntu 22.04        │   │ Ubuntu 22.04        │      │
  │  │ 2GB RAM, 20GB disk  │   │ 2GB RAM, 20GB disk  │      │
  │  │                     │   │                     │      │
  │  │ ┌─── Docker ─────┐ │   │ ┌─── Docker ─────┐  │      │
  │  │ │ nginx:alpine   │ │   │ │ nginx:alpine   │  │      │
  │  │ │  :80           │ │   │ │  :80           │  │      │
  │  │ │  ↓             │ │   │ │  ↓             │  │      │
  │  │ │ NestJS :4000   │ │   │ │ Next.js :3000  │  │      │
  │  │ └────────────────┘ │   │ └────────────────┘  │      │
  │  └─────────────────────┘   └─────────────────────┘      │
  │                                                          │
  │  ┌─────────────────────┐                                 │
  │  │ VM: MongoDB         │                                 │
  │  │ (вже працює)        │                                 │
  │  └─────────────────────┘                                 │
  └──────────────────────────────────────────────────────────┘

  DNS (A-записи → Static IP):
    fillando.com
    api.fillando.com
    www.fillando.com (CNAME → fillando.com)
```

### Приклад LAN-адрес (замінити на реальні)

| Контейнер/VM | LAN IP | Proxmox ID | Призначення |
|-------------|--------|------------|-------------|
| LXC nginx-router | `192.168.1.200` | 200 | SSL termination, routing по доменах |
| VM Backend | `192.168.1.101` | 101 | NestJS + Nginx (Docker) |
| VM Frontend | `192.168.1.102` | 102 | Next.js + Nginx (Docker) |
| VM MongoDB | `192.168.1.103` | 103 | MongoDB (вже працює) |

### Компоненти

| Компонент | Де працює | Docker контейнер | Порт |
|-----------|-----------|-----------------|------|
| Nginx router | LXC 200 | — (host Nginx) | 80, 443 |
| Certbot (SSL) | LXC 200 | — (host) | — |
| Nginx (BE) | VM 101 | `fillando-nginx-be` | 80 |
| NestJS | VM 101 | `fillando-be` | 4000 (internal) |
| Nginx (FE) | VM 102 | `fillando-nginx-fe` | 80 |
| Next.js | VM 102 | `fillando-fe` | 3000 (internal) |
| MongoDB | VM 103 | вже є | 27017 |

---

## Крок 0 — DNS

### 0.1 Створити A-записи

В панелі DNS провайдера (Cloudflare, Namecheap, тощо):

| Тип | Ім'я | Значення | TTL |
|-----|------|----------|-----|
| A | `fillando.com` | `<ваш статичний IP>` | Auto |
| A | `api.fillando.com` | `<ваш статичний IP>` | Auto |
| CNAME | `www` | `fillando.com` | Auto |

Якщо використовуєте Cloudflare — **вимкнути Proxy** (сіра хмарка), щоб Let's Encrypt міг верифікувати домен.

### 0.2 Перевірка

Зачекати 5-10 хвилин, потім перевірити:

```bash
dig fillando.com +short
dig api.fillando.com +short
```

Обидва повинні повернути ваш статичний IP.

---

## Крок 1 — LXC nginx-router (Proxmox)

Це lightweight контейнер, який приймає весь HTTP/HTTPS трафік і роутить по доменах на відповідні VM.

### 1.1 Створення LXC в Proxmox Web UI

1. Відкрити Proxmox Web UI (`https://<proxmox-ip>:8006`)
2. **Create CT** (верхня панель)
3. Заповнити:

| Параметр | Значення |
|----------|----------|
| **General** | |
| Node | ваш node |
| CT ID | `200` (або інший вільний) |
| Hostname | `nginx-router` |
| Password | задати пароль root |
| **Template** | |
| Storage | local |
| Template | `ubuntu-22.04-standard` (завантажити якщо немає*) |
| **Disks** | |
| Storage | local-lvm |
| Disk size | `2` GB |
| **CPU** | |
| Cores | `1` |
| **Memory** | |
| Memory | `256` MB |
| Swap | `256` MB |
| **Network** | |
| Bridge | `vmbr0` |
| IPv4 | Static: `192.168.1.200/24` |
| Gateway | `192.168.1.1` (IP роутера) |
| **DNS** | |
| DNS domain | залишити порожнім |
| DNS servers | `8.8.8.8` |

*Якщо шаблону немає: Proxmox → local storage → CT Templates → Templates → завантажити `ubuntu-22.04-standard`.

4. Натиснути **Finish** → **Start**

### 1.2 Підключення до LXC

З Proxmox Web UI → виділити CT 200 → Console, або:

```bash
# З Proxmox host shell:
pct enter 200
```

### 1.3 Оновлення та встановлення

```bash
apt update && apt upgrade -y
apt install -y nginx certbot python3-certbot-nginx curl
systemctl enable nginx
systemctl start nginx
```

### 1.4 Перевірка мережі

Переконатися що LXC бачить інші VM по LAN:

```bash
# Перевірити доступність Backend VM
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.101:80
# Поки поверне помилку (VM ще не налаштована) — це нормально

# Перевірити доступність Frontend VM
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.102:80

# Перевірити DNS
ping -c 2 google.com
```

### 1.5 Nginx конфігурація

Видалити default site:

```bash
rm -f /etc/nginx/sites-enabled/default
```

Створити конфіг для api.fillando.com:

```bash
cat > /etc/nginx/sites-available/api.fillando.com << 'EOF'
server {
    listen 80;
    server_name api.fillando.com;

    location / {
        proxy_pass http://192.168.1.101:80;
        proxy_http_version 1.1;

        # Прокинути оригінальні заголовки
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE support (Nova Post sync endpoint)
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 86400s;

        # Великі тіла запитів (upload)
        client_max_body_size 50m;
    }
}
EOF
```

Створити конфіг для fillando.com:

```bash
cat > /etc/nginx/sites-available/fillando.com << 'EOF'
server {
    listen 80;
    server_name fillando.com www.fillando.com;

    location / {
        proxy_pass http://192.168.1.102:80;
        proxy_http_version 1.1;

        # Прокинути оригінальні заголовки
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket upgrade (Next.js HMR не потрібен в prod,
        # але корисно для можливих WebSocket фіч)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
    }
}
EOF
```

Активувати сайти:

```bash
ln -sf /etc/nginx/sites-available/api.fillando.com /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/fillando.com /etc/nginx/sites-enabled/
```

Перевірити та перезавантажити:

```bash
nginx -t
systemctl reload nginx
```

### 1.6 Port forwarding на домашньому роутері

Зайти в панель управління роутера (зазвичай `192.168.1.1`) і створити правила:

| Зовнішній порт | Протокол | Внутрішній IP | Внутрішній порт | Опис |
|----------------|----------|--------------|-----------------|------|
| 80 | TCP | 192.168.1.200 | 80 | HTTP → LXC router |
| 443 | TCP | 192.168.1.200 | 443 | HTTPS → LXC router |
| 2222 | TCP | 192.168.1.101 | 22 | SSH → Backend VM |
| 2223 | TCP | 192.168.1.102 | 22 | SSH → Frontend VM |

Після збереження перевірити з **зовнішньої мережі** (мобільний інтернет, або сервіс типу `portchecker.co`):

```bash
# З телефону або зовнішнього сервера:
curl -v http://fillando.com
curl -v http://api.fillando.com
```

Мають відповісти Nginx (502 Bad Gateway поки VM не запущені — це нормально).

### 1.7 SSL сертифікати (Let's Encrypt)

**Важливо:** Цей крок виконувати тільки після того, як port forwarding працює і DNS вказує на ваш IP.

```bash
certbot --nginx \
    -d fillando.com \
    -d www.fillando.com \
    -d api.fillando.com \
    --non-interactive \
    --agree-tos \
    -m your@email.com
```

Certbot автоматично:
- Отримає сертифікати від Let's Encrypt
- Модифікує Nginx конфіги (додасть `listen 443 ssl`, шляхи до сертифікатів, redirect 80 → 443)
- Налаштує auto-renewal через systemd timer

Перевірити auto-renewal:

```bash
certbot renew --dry-run
```

Перевірити що Nginx конфіги оновлені:

```bash
cat /etc/nginx/sites-available/api.fillando.com
cat /etc/nginx/sites-available/fillando.com
```

Повинні з'явитися блоки `listen 443 ssl` з шляхами до `/etc/letsencrypt/live/...`.

### 1.8 Фінальна перевірка LXC router

```bash
# Статус Nginx
systemctl status nginx

# Сертифікати
certbot certificates

# Перевірити SSL ззовні (з телефону/іншого ПК):
# https://fillando.com      → має відповісти (502 поки VM не готові)
# https://api.fillando.com  → має відповісти (502 поки VM не готові)
```

---

## Крок 2 — Підготовка Backend та Frontend VM

Виконати кроки 2.1–2.6 на **кожній** VM (Backend та Frontend).

### 2.1 Створення VM в Proxmox Web UI

1. **Create VM** в Proxmox Web UI
2. Параметри:

| Параметр | Backend VM | Frontend VM |
|----------|-----------|-------------|
| **VM ID** | 101 | 102 |
| **Name** | `fillando-be` | `fillando-fe` |
| **ISO** | ubuntu-22.04-server | ubuntu-22.04-server |
| **Disk** | 20 GB | 20 GB |
| **CPU** | 2 cores | 2 cores |
| **RAM** | 2048 MB | 2048 MB |
| **Network** | Bridge `vmbr0` | Bridge `vmbr0` |

3. Після інсталяції Ubuntu, налаштувати статичний IP:

**Backend VM** — `192.168.1.101`:

```bash
sudo tee /etc/netplan/00-installer-config.yaml << 'EOF'
network:
    version: 2
    ethernets:
        ens18:
            addresses:
                - 192.168.1.101/24
            routes:
                - to: default
                  via: 192.168.1.1
            nameservers:
                addresses:
                    - 8.8.8.8
                    - 1.1.1.1
EOF
sudo netplan apply
```

**Frontend VM** — `192.168.1.102`:

```bash
sudo tee /etc/netplan/00-installer-config.yaml << 'EOF'
network:
    version: 2
    ethernets:
        ens18:
            addresses:
                - 192.168.1.102/24
            routes:
                - to: default
                  via: 192.168.1.1
            nameservers:
                addresses:
                    - 8.8.8.8
                    - 1.1.1.1
EOF
sudo netplan apply
```

**Note:** Ім'я інтерфейсу (`ens18`) може відрізнятися — перевірити через `ip a`.

### 2.2 Оновлення системи

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ufw
```

### 2.3 Створення deploy-користувача

```bash
sudo adduser deploy
# Ввести пароль, решту полів пропустити (Enter)
sudo usermod -aG sudo deploy
```

Перейти на нового користувача:

```bash
su - deploy
```

Всі наступні команди виконуються від `deploy`.

### 2.4 Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw enable
```

Перевірити:

```bash
sudo ufw status
# Status: active
# To         Action  From
# --         ------  ----
# OpenSSH    ALLOW   Anywhere
# 80         ALLOW   Anywhere
```

**Note:** Тільки порт 80 — SSL termination відбувається на LXC router, до VM трафік йде по HTTP.

### 2.5 Docker

```bash
# Встановити Docker
curl -fsSL https://get.docker.com | sudo sh

# Додати deploy до групи docker
sudo usermod -aG docker deploy

# Перелогінитися щоб група застосувалась
exit
su - deploy

# Перевірити
docker --version
# Docker version 27.x.x
docker compose version
# Docker Compose version v2.x.x
```

### 2.6 SSH Deploy Key для GitHub

На **кожній** VM (як deploy user) згенерувати ключ:

```bash
# На Backend VM:
ssh-keygen -t ed25519 -C "deploy@fillando-be" -f ~/.ssh/github_deploy -N ""

# На Frontend VM:
ssh-keygen -t ed25519 -C "deploy@fillando-fe" -f ~/.ssh/github_deploy -N ""
```

Вивести публічний ключ:

```bash
cat ~/.ssh/github_deploy.pub
```

Скопіювати і додати в GitHub:
1. Зайти на https://github.com/vvbogdanovih/fillando-be (або fillando-fe)
2. Settings → Deploy keys → **Add deploy key**
3. Title: `Backend VM deploy key` (або `Frontend VM deploy key`)
4. Key: вставити вміст `.pub`
5. **Allow write access:** не потрібно (тільки read для `git pull`)

Налаштувати SSH config:

```bash
mkdir -p ~/.ssh
cat >> ~/.ssh/config << 'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_deploy
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
```

Перевірити з'єднання:

```bash
ssh -T git@github.com
# Hi vvbogdanovih/fillando-be! You've been granted access.
```

---

## Крок 3 — Backend VM

Всі команди виконуються на Backend VM (`192.168.1.101`) під користувачем `deploy`.

### 3.1 Клонування репо

```bash
sudo mkdir -p /srv/fillando-api
sudo chown deploy:deploy /srv/fillando-api
git clone git@github.com:vvbogdanovih/fillando-be.git /srv/fillando-api
cd /srv/fillando-api
```

Перевірити:

```bash
ls -la
# Має показати файли репо: src/, package.json, Dockerfile.prod, тощо
```

### 3.2 Створити Nginx конфіг

```bash
mkdir -p nginx
```

```bash
cat > nginx/default.conf << 'EOF'
server {
    listen 80;
    server_name api.fillando.com;

    # Великі тіла запитів (для upload presign)
    client_max_body_size 50m;

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
EOF
```

### 3.3 Створити docker-compose.prod.yml

```bash
cat > docker-compose.prod.yml << 'EOF'
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
EOF
```

**Пояснення:**
- `api` — NestJS, порт 4000 доступний тільки в Docker мережі (`expose`, не `ports`)
- `nginx` — проксює зовнішній порт 80 на `http://api:4000` (Docker DNS по імені сервісу)
- Конфіг Nginx підключається через volume (зміна без перебілду)

### 3.4 Створити .env.prod

```bash
cat > .env.prod << 'EOF'
NODE_ENV=production
PORT=4000
LOG_LEVEL=info
FRONTEND_URL=https://fillando.com

# MongoDB (LAN IP MongoDB VM)
DATABASE_URL=mongodb://<USER>:<PASS>@192.168.1.103:27017/<DB>?authSource=admin

# JWT
JWT_SECRET=<згенерувати: openssl rand -hex 32>
JWT_EXPIRATION=15
ACCSESS_TOKEN_NAME=access_token

REFRESH_JWT_SECRET=<згенерувати: openssl rand -hex 32>
REFRESH_JWT_EXPIRATION=10080
REFRESH_TOKEN_NAME=refresh_token

# Password
PASSWORD_PEPPER=<згенерувати: openssl rand -hex 16>

# Google OAuth
GOOGLE_CLIENT_ID=<з Google Cloud Console>
GOOGLE_CLIENT_SECRET=<з Google Cloud Console>
GOOGLE_CALLBACK_URL=https://api.fillando.com/auth/google/callback

# AWS S3
AWS_REGION=eu-north-1
AWS_ACCESS_KEY_ID=<з AWS IAM>
AWS_SECRET_ACCESS_KEY=<з AWS IAM>
AWS_S3_BUCKET_NAME=<назва бакету>
AWS_S3_PUBLIC_URL=https://<бакет>.s3.eu-north-1.amazonaws.com

# Nova Post
NOVA_POS_API_KEY=<з кабінету Нової Пошти>

# Email (Resend)
RESEND_API_KEY=<з Resend dashboard>
SERVICE_EMAIL=<email для сервісних сповіщень>
ALLOW_EMAIL_SENDING=true
EOF

# Захистити файл
chmod 600 .env.prod
```

Згенерувати секрети (виконати і вставити в .env.prod):

```bash
echo "JWT_SECRET: $(openssl rand -hex 32)"
echo "REFRESH_JWT_SECRET: $(openssl rand -hex 32)"
echo "PASSWORD_PEPPER: $(openssl rand -hex 16)"
```

### 3.5 Перший запуск

```bash
cd /srv/fillando-api

# Збілдити і запустити
docker compose -f docker-compose.prod.yml up -d --build

# Перевірити статус
docker compose -f docker-compose.prod.yml ps
# NAME                 STATUS
# fillando-be          Up
# fillando-nginx-be    Up

# Перевірити логи
docker logs fillando-be --tail 50
# Має показати NestJS bootstrap, підключення до MongoDB

# Перевірити що API відповідає
curl http://localhost:80/categories
# Має повернути JSON (або [] якщо БД порожня)
```

### 3.6 Перевірка з LXC router

З LXC nginx-router (`pct enter 200`):

```bash
curl http://192.168.1.101:80/categories
# Має повернути JSON
```

Якщо SSL вже налаштований, перевірити ззовні:

```bash
curl https://api.fillando.com/categories
```

---

## Крок 4 — Frontend VM

Всі команди виконуються на Frontend VM (`192.168.1.102`) під користувачем `deploy`.

### 4.1 Клонування репо

```bash
sudo mkdir -p /srv/fillando-frontend
sudo chown deploy:deploy /srv/fillando-frontend
git clone git@github.com:vvbogdanovih/fillando-fe.git /srv/fillando-frontend
cd /srv/fillando-frontend
```

### 4.2 Створити Nginx конфіг

```bash
mkdir -p nginx
```

```bash
cat > nginx/default.conf << 'EOF'
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
EOF
```

### 4.3 Створити docker-compose.prod.yml

```bash
cat > docker-compose.prod.yml << 'EOF'
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
EOF
```

**Note:** `NEXT_PUBLIC_API_BASE_URL` передається як build arg — вбудовується при `next build` в клієнтський JS.

### 4.4 Створити .env.prod

```bash
cat > .env.prod << 'EOF'
NODE_ENV=production
NEXT_PUBLIC_API_BASE_URL=https://api.fillando.com
NEXT_PUBLIC_SITE_URL=https://fillando.com
EOF

chmod 600 .env.prod
```

### 4.5 Swap (рекомендовано)

`next build` споживає багато RAM. Якщо VM має 2GB — додати swap:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Перевірити
free -h
# Swap: 2.0G
```

### 4.6 Перший запуск

```bash
cd /srv/fillando-frontend

# Збілдити і запустити (перший build може зайняти 3-5 хвилин)
docker compose -f docker-compose.prod.yml up -d --build

# Перевірити статус
docker compose -f docker-compose.prod.yml ps

# Перевірити логи
docker logs fillando-fe --tail 50
# ▲ Next.js 16.x.x
# - Local: http://localhost:3000

# Перевірити локально
curl -s -o /dev/null -w "%{http_code}" http://localhost:80
# 200
```

### 4.7 Перевірка з LXC router

З LXC nginx-router:

```bash
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.102:80
# 200
```

Ззовні:

```bash
curl https://fillando.com
```

---

## Крок 5 — GitHub Actions CI/CD

### 5.1 Згенерувати SSH ключі для CI

На **локальній машині** (Mac):

```bash
# Для Backend VM
ssh-keygen -t ed25519 -C "github-actions-be" -f ~/.ssh/fillando_be_deploy -N ""

# Для Frontend VM
ssh-keygen -t ed25519 -C "github-actions-fe" -f ~/.ssh/fillando_fe_deploy -N ""
```

### 5.2 Додати публічні ключі на VM

**Backend VM** (як deploy user):

```bash
# Скопіювати вміст ~/.ssh/fillando_be_deploy.pub з Mac і вставити:
echo "ssh-ed25519 AAAA... github-actions-be" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Frontend VM** (як deploy user):

```bash
echo "ssh-ed25519 AAAA... github-actions-fe" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 5.3 Перевірити SSH з локальної машини

```bash
# Backend VM (через port forwarding роутера)
ssh -p 2222 -i ~/.ssh/fillando_be_deploy deploy@<ваш-статичний-IP>

# Frontend VM
ssh -p 2223 -i ~/.ssh/fillando_fe_deploy deploy@<ваш-статичний-IP>
```

Обидва мають підключитися без запиту пароля.

### 5.4 Додати GitHub Secrets

**fillando-be** repo → Settings → Secrets and variables → Actions → **New repository secret**:

| Secret | Значення | Приклад |
|--------|----------|---------|
| `SSH_HOST` | Ваш статичний IP | `91.123.45.67` |
| `SSH_USER` | `deploy` | `deploy` |
| `SSH_KEY` | Вміст `~/.ssh/fillando_be_deploy` (ПРИВАТНИЙ ключ!) | Починається з `-----BEGIN OPENSSH PRIVATE KEY-----` |
| `SSH_PORT` | `2222` | `2222` |

Скопіювати приватний ключ:

```bash
cat ~/.ssh/fillando_be_deploy | pbcopy
# Вставити в поле Value секрету SSH_KEY
```

**fillando-fe** repo → Settings → Secrets and variables → Actions:

| Secret | Значення |
|--------|----------|
| `SSH_HOST` | Той самий статичний IP |
| `SSH_USER` | `deploy` |
| `SSH_KEY` | Вміст `~/.ssh/fillando_fe_deploy` (приватний ключ) |
| `SSH_PORT` | `2223` |

### 5.5 Backend workflow

Створити файл `fillando-be/.github/workflows/deploy.yml`:

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

### 5.6 Frontend workflow

Створити файл `fillando-fe/.github/workflows/deploy.yml`:

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

**Що відбувається при push в main:**
1. GitHub Actions підключається по SSH до VM (через port forwarding)
2. `git pull` — завантажує нові зміни
3. `docker compose build --no-cache api` — перебілджує тільки app контейнер
4. `docker compose up -d --no-deps api` — перезапускає app без Nginx
5. `docker image prune -f` — очищує старі Docker образи

Nginx контейнер **не перезапускається** при деплої — він використовує готовий `nginx:alpine` і конфіг з volume.

### 5.7 Тестування CI/CD

1. Зробити будь-яку зміну в `fillando-be` (напр. додати коментар)
2. Push в `main`
3. Перейти в GitHub → Actions → побачити запущений workflow
4. Зачекати завершення (1-3 хвилини)
5. Перевірити: `curl https://api.fillando.com/categories`

---

## Крок 6 — CORS та Cookies (cross-subdomain)

Фронт (`fillando.com`) і бек (`api.fillando.com`) — різні піддомени одного root domain.

### 6.1 Cookie domain

В NestJS, де встановлюються cookies, додати `domain`:

```typescript
response.cookie(name, value, {
    httpOnly: true,
    secure: true,                    // HTTPS обов'язковий в production
    sameSite: 'lax',
    domain: '.fillando.com',         // спільний root domain → cookie на обох піддоменах
    maxAge: ...,
})
```

Без `domain: '.fillando.com'` cookie буде привʼязаний тільки до `api.fillando.com` і фронт його не побачить.

### 6.2 Умовний secure flag

Щоб не ламати локальну розробку (HTTP):

```typescript
secure: ENV.NODE_ENV === 'production'
```

### 6.3 CORS

В `.env.prod` вже є: `FRONTEND_URL=https://fillando.com`. NestJS CORS використовує це як origin з `credentials: true` — все коректно.

### 6.4 trust proxy

`app.set('trust proxy', 1)` вже є в `main.ts`. Необхідно для коректного `X-Forwarded-Proto` за двома рівнями Nginx.

---

## Крок 7 — Верифікація

### Повний checklist

**Мережа:**
- [ ] DNS A-записи вказують на статичний IP (`dig fillando.com`)
- [ ] Port forwarding працює (80, 443 → LXC router; 2222 → BE; 2223 → FE)
- [ ] LXC router бачить обидві VM по LAN

**SSL:**
- [ ] `https://fillando.com` — валідний сертифікат (перевірити в браузері — замочок)
- [ ] `https://api.fillando.com` — валідний сертифікат
- [ ] `certbot renew --dry-run` проходить на LXC router

**Backend:**
- [ ] `https://api.fillando.com/swagger` — Swagger UI відкривається
- [ ] `https://api.fillando.com/categories` — повертає JSON
- [ ] `docker logs fillando-be` — без помилок
- [ ] MongoDB підключення працює (перевірити в логах)

**Frontend:**
- [ ] `https://fillando.com` — сторінка завантажується
- [ ] `https://fillando.com/auth/login` — форма логіну працює
- [ ] Каталог товарів завантажується
- [ ] Зображення з S3 відображаються

**Auth:**
- [ ] Реєстрація нового користувача
- [ ] Логін/логаут
- [ ] Google OAuth (callback → `https://api.fillando.com/auth/google/callback`)
- [ ] Cookies передаються між `fillando.com` ↔ `api.fillando.com`

**CI/CD:**
- [ ] Push в `main` (BE) → GitHub Actions → автодеплой backend
- [ ] Push в `main` (FE) → GitHub Actions → автодеплой frontend
- [ ] SSH з GitHub Actions доходить до VM

### Корисні команди

```bash
# === Backend VM ===
# Логи app
docker logs fillando-be --tail 100 -f
# Логи nginx
docker logs fillando-nginx-be --tail 100 -f
# Статус
docker compose -f docker-compose.prod.yml ps
# Рестарт
docker compose -f docker-compose.prod.yml restart
# Повний перезбір
docker compose -f docker-compose.prod.yml up -d --build

# === Frontend VM ===
docker logs fillando-fe --tail 100 -f
docker logs fillando-nginx-fe --tail 100 -f
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml restart

# === LXC Router ===
# Логи Nginx
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
# Перезавантажити Nginx
nginx -t && systemctl reload nginx
# Сертифікати
certbot certificates
```

---

## Troubleshooting

### Docker build OOM (Next.js)

Якщо `docker build` падає при `next build`:

```bash
# Додати swap (на Frontend VM)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Let's Encrypt не видає сертифікат

1. DNS вказує на правильний IP: `dig fillando.com +short`
2. Порти 80/443 доступні ззовні (перевірити з мобільного)
3. Cloudflare proxy вимкнений (сіра хмарка)
4. Firewall на LXC router: `ufw status` → порти 80, 443 відкриті

### 502 Bad Gateway на LXC router

Router не може достукатися до VM:

```bash
# З LXC router перевірити доступність
curl http://192.168.1.101:80   # Backend VM
curl http://192.168.1.102:80   # Frontend VM
```

Якщо не відповідає:
- VM запущена? (`qm status 101` з Proxmox host)
- Docker контейнери працюють? (зайти на VM → `docker ps`)
- Firewall на VM дозволяє порт 80? (`sudo ufw status`)

### GitHub Actions SSH timeout

```bash
# Перевірити port forwarding з локальної машини:
ssh -p 2222 -i ~/.ssh/fillando_be_deploy deploy@<статичний-IP>

# Якщо timeout — порт не прокинутий на роутері
# Якщо connection refused — sshd не працює на VM або firewall блокує
```

### Cookies не передаються між доменами

1. `domain: '.fillando.com'` в cookie options
2. `secure: true` (без HTTPS cookie з `secure` не встановиться)
3. Перевірити в DevTools → Application → Cookies: чи є cookie з domain `.fillando.com`
4. CORS header: `Access-Control-Allow-Credentials: true`

### Disk space на VM

Docker образи накопичуються. Очищення:

```bash
# Видалити невикористовувані образи
docker image prune -f

# Повне очищення (видаляє все невикористовуване, включно з volumes!)
docker system prune -a --volumes
```

### LXC router — Nginx не стартує після рестарту Proxmox

```bash
# З Proxmox host:
pct start 200

# Перевірити що Nginx стартував:
pct exec 200 -- systemctl status nginx
```

Додати auto-start в Proxmox: CT 200 → Options → Start at boot → **Yes**.

---

## Файлова структура (що додати в кожен репо)

### fillando-be

```
fillando-be/
├── nginx/
│   └── default.conf              ← NEW: Nginx config
├── docker-compose.prod.yml       ← UPDATE: додати nginx service
├── Dockerfile.prod               ← вже є
├── .env.prod                     ← створити на сервері (не в git!)
└── .github/
    └── workflows/
        └── deploy.yml            ← UPDATE: branch main
```

### fillando-fe

```
fillando-fe/
├── nginx/
│   └── default.conf              ← NEW: Nginx config
├── docker-compose.prod.yml       ← UPDATE: додати nginx service
├── Dockerfile.prod               ← вже є
├── .env.prod                     ← створити на сервері (не в git!)
└── .github/
    └── workflows/
        └── deploy.yml            ← UPDATE: branch main
```
