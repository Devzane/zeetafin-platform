---
title: "Hardening Node.js Workloads: Multi-Stage Docker Builds for NestJS REST APIs"
subtitle: "Part 6 of the Production DevOps Series: Shrinking Node.js Images by 70%, Dropping Root Privileges, and Configuring Native Container Health Checks"
tags: ["docker", "nestjs", "nodejs", "security", "typescript", "devops"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 6
canonical_url: ""
cover_image: ""
---

# Hardening Node.js Workloads: Multi-Stage Docker Builds for NestJS REST APIs

NestJS is a powerful TypeScript-based framework for enterprise backend APIs, but running TypeScript in production introduces specific challenges for containerization:
1. TypeScript cannot run directly on Node.js without ahead-of-time compilation (`tsc`) or memory-heavy runtime transpilers (`ts-node`).
2. Compilers, typings (`@types/*`), and CLI tools (`@nestjs/cli`) are required only at build time. Leaving them inside the production container bloats image sizes and increases vulnerability surfaces.
3. Node applications running as `root` violate basic container security principles.

In Part 6 of our DevOps series, we build a production-grade multi-stage `Dockerfile` for `zeetafin-backend` that compiles TypeScript cleanly, discards build tools, drops root privileges to user `node`, and configures automated HTTP health monitoring.

---

## 1. Multi-Stage Pipeline Blueprint

Our build pipeline splits into three distinct phases within a single `Dockerfile`:

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Stage 1: deps (Dependency Resolution)                                  │
 │   • Image: node:20-alpine                                              │
 │   • Action: COPY package*.json -> RUN npm ci                           │
 │   • Output: Complete node_modules (production + development tools)     │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Stage 2: builder (TypeScript Compilation)                              │
 │   • Image: node:20-alpine                                              │
 │   • Action: Mount node_modules from deps -> RUN npm run build          │
 │   • Output: Optimized JavaScript bundles in /app/dist                  │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Stage 3: runner (Production Runtime Environment)                       │
 │   • Image: node:20-alpine (Clean base)                                 │
 │   • Action: RUN npm ci --omit=dev (Only production runtime packages)   │
 │   • Action: COPY --from=builder /app/dist ./dist                       │
 │   • Security: USER node (UID 1000)                                     │
 │   • Probe: HEALTHCHECK via wget against /api/docs                      │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Complete Dockerfile Implementation

Here is the complete, documented `phase2/backend/Dockerfile`:

```dockerfile
# Multi-stage Dockerfile for NestJS Backend (ZeetaFin ERP API)

# ==============================================================================
# Stage 1: Dependency Resolution
# ==============================================================================
FROM node:20-alpine AS deps
WORKDIR /app

# Copy package descriptors first to maximize Docker layer cache hits
COPY package.json package-lock.json ./

# npm ci ensures reproducible, lockfile-locked installation
RUN npm ci

# ==============================================================================
# Stage 2: TypeScript Compilation
# ==============================================================================
FROM node:20-alpine AS builder
WORKDIR /app

# Pull cached node_modules from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Compile TypeScript into native CommonJS / ES bundles inside /app/dist
RUN npm run build

# ==============================================================================
# Stage 3: Production Runtime
# ==============================================================================
FROM node:20-alpine AS runner
WORKDIR /app

# Define production environment variables
ENV NODE_ENV=production
ENV PORT=3001

# Install ONLY production dependencies (excluding nest-cli, typescript, etc.)
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy compiled JavaScript output from the builder stage
COPY --from=builder /app/dist ./dist

# Non-root user provided by default in official Node Alpine images (UID 1000)
USER node

EXPOSE 3001

# Built-in health check querying the OpenAPI Swagger documentation endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3001/api/docs || exit 1

# Launch compiled application
CMD ["node", "dist/main.js"]
```

---

## 3. Deep-Dive: Key Security & Optimization Patterns

### 1. `npm ci --omit=dev` vs. `npm install`

In production, running `npm install` is an anti-pattern:
* `npm install` may rewrite `package-lock.json` if semver allows upgrades, causing non-deterministic builds across staging and production.
* `npm ci` strictly honors `package-lock.json` and deletes any existing `node_modules` before installing.
* Adding `--omit=dev` prevents heavyweight devDependencies (e.g. `@nestjs/cli`, `@types/*`, `jest`, `ts-loader`) from ever being installed into the final runtime stage.

### 2. Dropping Privileges to `USER node`

The official `node:20-alpine` image includes a pre-configured unprivileged user named `node` (UID 1000, GID 1000). By default, containers run as `root` (UID 0). By explicitly adding:

```dockerfile
USER node
```

Any attacker attempting to exploit application vulnerabilities cannot write to protected root directories (`/bin`, `/sbin`, `/etc`), cannot install system packages, and cannot easily escalate privileges on the host kernel.

### 3. Native Container Healthcheck Probing

Without a `HEALTHCHECK` instruction, Docker marks a container healthy as soon as the process PID exists, even if the application is locked up in a deadlock or failing database connections.

Our `HEALTHCHECK` executes:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3001/api/docs || exit 1
```

* `wget --spider`: Alpine Linux does not package `curl` by default, but provides lightweight `wget` via `BusyBox`. The `--spider` flag checks web page presence without downloading content.
* `start-period=10s`: Grace period allowing the NestJS app to connect to PostgreSQL and run TypeORM migrations before health failures count against it.

---

## 4. Local Build & Image Verification

Build the image locally from your terminal:

```bash
# Navigate to the backend directory
cd phase2/backend

# Build image with local tag
docker build -t zeetafin-backend:local .
```

### Inspecting Image Size and Layers

Compare the size of the multi-stage build against a standard build:

```bash
docker images zeetafin-backend:local
```

```text
REPOSITORY          TAG       IMAGE ID       CREATED          SIZE
zeetafin-backend    local     7d1a2b3c4e5f   20 seconds ago   369MB
```

A standard single-stage build of this project is ~1.2 GB. The multi-stage build slashes the image down to **369 MB**—a **70% reduction**.

### Verifying Non-Root Execution

Run an ephemeral container and inspect the running user:

```bash
docker run --rm zeetafin-backend:local whoami
# Output: node

docker run --rm zeetafin-backend:local id
# Output: uid=1000(node) gid=1000(node) groups=1000(node)
```

---

## 5. Common Pitfalls & Troubleshooting

| Symptom | Root Cause | Fix |
| :--- | :--- | :--- |
| **`Cannot find module '.../dist/main.js'`** | TypeScript build failed or `tsconfig.json` output path does not match the `COPY` path. | Verify `tsconfig.json` specifies `"outDir": "./dist"` and `COPY --from=builder /app/dist ./dist` exists. |
| **`wget: can't connect to remote host (127.0.0.1:3001)` in Healthcheck** | App listening on `127.0.0.1` inside container instead of `0.0.0.0`, or port mismatch. | In NestJS `main.ts`, ensure `app.listen(port, '0.0.0.0')` is configured. |
| **`EACCES: permission denied`** | Attempting to write files at runtime to an unowned directory under `USER node`. | If your app writes files locally, run `RUN chown -R node:node /app/data` before switching to `USER node`. |

---

## Next Steps

Now that our backend API is hardened and packaged, we apply modern containerization patterns to the Next.js frontend.

👉 **Next in Series:** [Part 7: Next.js in Production: Optimizing Frontend Containers with Standalone Builds and Alpine Linux](./03-nextjs-frontend-standalone-containerization.md)
