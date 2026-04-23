# Architecture Overview

## System Diagram

```
                         ┌──────────────┐
                         │   Browser    │
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │    Nginx     │
                         │  (production)│
                         └──┬───────┬───┘
                            │       │
                    /api/*  │       │  /*
                            │       │
                   ┌────────▼──┐ ┌──▼─────────┐
                   │ NestJS    │ │  Next.js    │
                   │ :4000     │ │  :9000      │
                   └────┬──────┘ └─────────────┘
                        │
          ┌─────────────┼─────────────┐
          │             │             │
   ┌──────▼──┐   ┌──────▼──┐   ┌─────▼─────┐
   │ MongoDB │   │  AWS S3  │   │ External  │
   │ :27017  │   │ (images) │   │   APIs    │
   └─────────┘   └──────────┘   └─────┬─────┘
                                      │
                              ┌───────┼───────┐
                              │       │       │
                         Nova Post  Resend  Google
                          API       Email   OAuth
```

## Tech Stack

### Backend (fillando-be)

| Layer | Technology |
|-------|-----------|
| Framework | NestJS (Express) |
| Language | TypeScript |
| Database | MongoDB 7 via Mongoose |
| Auth | JWT (httpOnly cookies) + Passport (Google OAuth) |
| Password hashing | Argon2 + pepper |
| Validation | class-validator + class-transformer |
| Logging | nestjs-pino |
| File storage | AWS S3 (presigned URLs) |
| Email | Resend API |
| Delivery | Nova Post API |
| API docs | Swagger (OpenAPI) at `/swagger` |

### Frontend (fillando-fe)

| Layer | Technology |
|-------|-----------|
| Framework | Next.js 16 (App Router, SSR/SSG) |
| Language | TypeScript |
| UI | React 19 |
| Styling | Tailwind CSS 4, Radix UI primitives |
| State (client) | Zustand (auth, cart) |
| State (server) | React Query (TanStack Query) |
| Forms | React Hook Form + Zod |
| HTTP | Axios singleton |
| Icons | Lucide React |
| Notifications | React Hot Toast |

## Request Flow

```
Browser → Next.js (SSR/CSR)
  │
  ├─ Server Components → direct fetch to NestJS
  │
  └─ Client Components → Axios httpService
       │
       ├─ 200 OK → Zod validates response → return data
       │
       └─ 401 Unauthorized
            │
            ├─ POST /auth/refresh (native fetch, deduplicated)
            │    ├─ success → retry original request
            │    └─ fail → logout, redirect to /auth/login
            │
            └─ other errors → toast notification
```

## Auth Architecture

```
                    ┌─────────────────────────────┐
                    │       JWT Auth Flow          │
                    └─────────────────────────────┘

  Login/Register/OAuth
         │
         ▼
  ┌──────────────┐    httpOnly cookie     ┌──────────┐
  │   NestJS     │ ──────────────────────►│ Browser  │
  │              │   access_token         │          │
  │  issues:     │   refresh_token        │ sends    │
  │  - access    │                        │ cookies  │
  │  - refresh   │◄──────────────────────│ on every │
  └──────┬───────┘   automatic            │ request  │
         │                                └──────────┘
         ▼
  ┌──────────────┐
  │  MongoDB     │
  │              │
  │ refresh_     │   SHA256 hash + IP + UA + expiresAt
  │ tokens       │
  └──────────────┘

  Token Rotation:
  refresh → delete old → issue new pair → save new hash
```

## File Upload Architecture

```
  Client                    NestJS                     AWS S3
    │                         │                          │
    │  POST /upload/presign   │                          │
    │ ───────────────────────►│                          │
    │                         │  generate presigned URL  │
    │  { uploadUrl, publicUrl}│                          │
    │ ◄───────────────────────│                          │
    │                         │                          │
    │  PUT uploadUrl + file   │                          │
    │ ─────────────────────────────────────────────────► │
    │                         │                          │
    │  POST /upload/confirm   │                          │
    │ ───────────────────────►│  HeadObject (verify)     │
    │                         │ ────────────────────────►│
    │  { confirmed: [...] }   │                          │
    │ ◄───────────────────────│                          │
```

## Data Flow: Checkout

```
  Cart (Zustand)
       │
       ▼
  Checkout Form (React Hook Form + Zod)
       │
       ├─ Nova Post cities/warehouses (autocomplete)
       ├─ Discount coupon validation (real-time)
       │
       ▼
  POST /orders
       │
       ├─ Validate items (exist, stock > 0)
       ├─ Validate delivery address (per method)
       ├─ Validate coupon (if provided)
       ├─ Calculate: subtotal → discount → total
       ├─ Generate order_number (FO-XXXXXXX)
       ├─ Snapshot items (price at purchase time)
       ├─ Send confirmation email (if IBAN)
       │
       ▼
  Redirect → /checkout/success
  Clear cart
```

## Deployment (Production)

```
  VPS (single server)
  ├── Nginx (reverse proxy, TLS)
  │   ├── /api/* → NestJS :4000
  │   └── /*     → Next.js :9000 (or static export)
  ├── NestJS process (PM2 or systemd)
  ├── Next.js process (PM2 or systemd)
  └── MongoDB (local or Atlas)
```

**Note:** `/api` prefix exists ONLY at Nginx level. NestJS routes are `/auth/login`, `/products/catalog`, etc. — without any global prefix.
