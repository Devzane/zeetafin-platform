---
title: "Next.js in Production: Optimizing Frontend Containers with Standalone Builds and Alpine Linux"
subtitle: "Part 7 of the Production DevOps Series: Slashing Next.js Container Footprints by 80%, Bundling Static Assets, and Hardening Web Runtimes"
tags: ["nextjs", "docker", "react", "devops", "webdev", "cloud"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 7
canonical_url: ""
cover_image: ""
---

# Next.js in Production: Optimizing Frontend Containers with Standalone Builds and Alpine Linux

Next.js 14 App Router brings server-side rendering (SSR), streaming components, and API routing into modern React development. However, deploying a production Next.js application inside Docker can easily produce bloated images over 1.2 GB if standard `next start` patterns are used.

In Part 7 of our DevOps series, we containerize `zeetafin-frontend` using Next.js **Standalone Output Mode**, multi-stage Docker caching, Alpine Linux security baselines, and non-root process isolation. This reduces the final container size to just **224 MB** while preserving full SSR capabilities.

---

## 1. The Challenge of Containerizing Modern Next.js

A standard Next.js build produces two distinct artifact categories:
1. **Server-side JavaScript:** Node.js handlers that execute server components, render HTML, and handle routing.
2. **Client-side Bundles & Static Assets:** Minified JavaScript, CSS, SVGs, and fonts downloaded by user browsers.

In a traditional deployment, running `next start` requires the entire `node_modules` directory (~600 MB–1 GB) to remain on the disk.

```text
 ┌─────────────────────────────────────────────────────────────┐
 │ TRADITIONAL BUILD: next start (Image Size: ~1.2 GB)        │
 │  • Complete node_modules retained in production image       │
 │  • Next CLI and compilation tooling still present           │
 │  • Vulnerable to transitive dependency CVEs                 │
 └─────────────────────────────────────────────────────────────┘
                                vs.
 ┌─────────────────────────────────────────────────────────────┐
 │ STANDALONE BUILD: node server.js (Image Size: 224 MB)       │
 │  • Next.js traces dependency tree automatically             │
 │  • Extracts only required node_modules into .next/standalone│
 │  • Runs via lightweight native node server.js               │
 └─────────────────────────────────────────────────────────────┘
```

---

## 2. Enabling Next.js Standalone Output

In `phase2/frontend/next.config.js`, enable the `standalone` build option:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  images: { domains: [] },
};

module.exports = nextConfig;
```

When you execute `npm run build`, Next.js analyzes every `import` in your application. It produces a compact `.next/standalone/` folder containing only the precise files and dependencies needed to run the server, completely eliminating unused `node_modules`.

> **Important Architectural Detail:** Next.js purposefully excludes `.next/static` and `public/` from the standalone output directory. This design allows you to host static assets on a CDN (like Amazon CloudFront or S3). When self-hosting in Docker, you must manually copy `.next/static` into your runtime image alongside `.next/standalone`.

---

## 3. Handling Client-Side Environment Variables (`NEXT_PUBLIC_*`)

In Next.js, variables prefixed with `NEXT_PUBLIC_` are inlined into the client-side JavaScript bundles **at build time**, not at runtime.

If your frontend needs to call your backend API at `http://localhost:3001/api` or a production domain, that value must be provided to the Docker build process via a build argument (`ARG`), rather than solely as a runtime environment variable (`ENV`):

```dockerfile
ARG NEXT_PUBLIC_API_URL=http://localhost:3001/api
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
```

---

## 4. Multi-Stage Dockerfile Implementation

Here is the complete `phase2/frontend/Dockerfile`:

```dockerfile
# Multi-stage Dockerfile for Next.js Frontend (ZeetaFin ERP)

# ==============================================================================
# Stage 1: Dependency Resolution
# ==============================================================================
FROM node:20-alpine AS deps
# libc6-compat is required on Alpine for process.dlopen compatibility
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Copy dependency manifests
COPY package.json package-lock.json ./
RUN npm ci

# ==============================================================================
# Stage 2: Standalone Application Build
# ==============================================================================
FROM node:20-alpine AS builder
WORKDIR /app

# Mount resolved dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Disable Next.js anonymous telemetry to improve build speed
ENV NEXT_TELEMETRY_DISABLED=1

# Accept API endpoint as build-time argument for inlining
ARG NEXT_PUBLIC_API_URL=http://localhost:3001/api
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

# Build standalone server and static assets
RUN npm run build

# ==============================================================================
# Stage 3: Minimal Production Runtime
# ==============================================================================
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Create a dedicated unprivileged system user and group (UID/GID 1001)
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy standalone bundle and static assets with correct user ownership
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Switch to unprivileged execution
USER nextjs

EXPOSE 3000

# Automated healthcheck testing web server responsiveness
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/ || exit 1

# Launch the optimized standalone server
CMD ["node", "server.js"]
```

---

## 5. Security & Build Optimizations

### 1. `libc6-compat` on Alpine Linux
Alpine Linux uses `musl libc` instead of `glibc`. Some native Node.js addons require standard glibc system calls; installing `libc6-compat` guarantees compatibility without loading a full Debian/Ubuntu userland.

### 2. Dedicated System User (`nextjs:nodejs`)
Rather than relying on generic users, we create an explicit system group and user with UID `1001`:

```dockerfile
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs
```

This prevents file collisions and guarantees that even if a zero-day vulnerability occurs in a dependency, the attacker has no write access to `/app/.next` or system binaries.

### 3. Binding to `0.0.0.0`
By default, Node applications may bind to `localhost` (`127.0.0.1`). In a container, `localhost` is strictly local to the container's private network namespace, preventing external traffic or Docker bridge proxies from reaching it. Setting:

```dockerfile
ENV HOSTNAME="0.0.0.0"
```

ensures Next.js accepts requests arriving across Docker bridge networks.

---

## 6. Building and Testing the Image

Build and tag the frontend container image locally:

```bash
cd phase2/frontend
docker build -t zeetafin-frontend:local .
```

### Validating Size and Security Context

Verify the resulting image size:

```bash
docker images zeetafin-frontend:local
```

```text
REPOSITORY          TAG       IMAGE ID       CREATED          SIZE
zeetafin-frontend   local     a1b2c3d4e5f6   15 seconds ago   224MB
```

The resulting image is **224 MB**, representing an **80% size reduction** from a standard `next start` image.

Confirm that the container runs under the `nextjs` system user:

```bash
docker run --rm zeetafin-frontend:local whoami
# Output: nextjs

docker run --rm zeetafin-frontend:local id
# Output: uid=1001(nextjs) gid=1001(nodejs) groups=1001(nodejs)
```

---

## 7. Common Pitfalls & Troubleshooting

| Symptom | Root Cause | Solution |
| :--- | :--- | :--- |
| **Styles/CSS 404 Not Found in Browser** | `.next/static` was not copied into the runtime stage. | Ensure `COPY --from=builder /app/.next/static ./.next/static` is present in stage 3. |
| **`Error: Cannot find module '/app/server.js'`** | `output: 'standalone'` missing in `next.config.js`. | Add `output: 'standalone'` to your Next.js config before building. |
| **API calls point to `localhost` instead of remote domain** | `NEXT_PUBLIC_API_URL` was not passed at build time. | Pass `--build-arg NEXT_PUBLIC_API_URL="https://api.yourdomain.com"` during `docker build`. |

---

## Next Steps

Now that both backend and frontend images are built and hardened, we orchestrate the full multi-tier stack locally using Docker Compose and push our images to Amazon Elastic Container Registry (ECR).

👉 **Next in Series:** [Part 8: Local Stack Orchestration with Docker Compose and Amazon ECR Container Registry Distribution](./04-docker-compose-orchestration-and-ecr-push.md)
