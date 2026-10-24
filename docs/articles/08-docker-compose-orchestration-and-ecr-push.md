---
title: "Local Stack Orchestration with Docker Compose and Amazon ECR Container Registry Distribution"
subtitle: "Part 8 of the Production DevOps Series: Service Health Probes, Database Seeding, and Publishing Hardened Images to AWS ECR"
tags: ["docker", "docker-compose", "aws", "ecr", "postgresql", "devops"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 8
canonical_url: ""
cover_image: ""
---

# Local Stack Orchestration with Docker Compose and Amazon ECR Container Registry Distribution

Building standalone container images is only half the battle. In a microservices or multi-tier environment, services must communicate over isolated software-defined networks, handle database startup race conditions, and be versioned into a private container registry.

In Part 8 of our DevOps series, we orchestrate the complete **ZeetaFin ERP** stack (PostgreSQL 16, NestJS API, Next.js Web UI) locally using **Docker Compose**. We verify data persistence and healthcheck dependency ordering, and then distribute our hardened images to **Amazon Elastic Container Registry (ECR)**.

---

## 1. Local Orchestration Architecture

Before deploying to the cloud, developers and CI runners must be able to run and verify the entire environment locally with a single command:

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                     Docker Compose Local Network                       │
 │                                                                        │
 │  ┌──────────────────────────────────────────────────────────────────┐  │
 │  │ zeetafin-network (Isolated Bridge Driver)                        │  │
 │  │                                                                  │  │
 │  │  ┌──────────────────┐    ┌──────────────────┐    ┌────────────┐  │  │
 │  │  │ zeetafin-frontend│    │ zeetafin-backend │    │ zeetafin-db│  │  │
 │  │  │ Next.js :3000    ├────► NestJS :3001     ├────► Postgres   │  │  │
 │  │  │                  │    │                  │    │ :5432      │  │  │
 │  │  └────────┬─────────┘    └────────┬─────────┘    └─────┬──────┘  │  │
 │  └───────────┼───────────────────────┼────────────────────┼─────────┘  │
 └──────────────┼───────────────────────┼────────────────────┼────────────┘
                │                       │                    │
                ▼                       ▼                    ▼
          Host Port 3000          Host Port 3001       Host Port 5432
         (Web Application)       (OpenAPI Swagger)    (PostgreSQL CLI)
```

---

## 2. Docker Compose Implementation (`docker-compose.yml`)

Here is the declarative multi-tier configuration in `phase2/docker-compose.yml`:

```yaml
services:
  db:
    image: postgres:16-alpine
    container_name: zeetafin-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: zeetafin_secret
      POSTGRES_DB: zeetafin
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d zeetafin"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - zeetafin-network

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    image: zeetafin-backend:local
    container_name: zeetafin-backend
    restart: unless-stopped
    environment:
      PORT: 3001
      DB_HOST: db
      DB_PORT: 5432
      DB_USERNAME: postgres
      DB_PASSWORD: zeetafin_secret
      DB_NAME: zeetafin
      JWT_SECRET: super_secret_jwt_key_zeetafin_devops_assignment_2026
      NODE_ENV: production
      DB_SYNC: "true"
      DB_LOGGING: "false"
    ports:
      - "3001:3001"
    depends_on:
      db:
        condition: service_healthy # Prevents boot before Postgres is ready
    networks:
      - zeetafin-network

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      args:
        NEXT_PUBLIC_API_URL: http://localhost:3001/api
    image: zeetafin-frontend:local
    container_name: zeetafin-frontend
    restart: unless-stopped
    environment:
      PORT: 3000
      NEXT_PUBLIC_API_URL: http://localhost:3001/api
    ports:
      - "3000:3000"
    depends_on:
      - backend
    networks:
      - zeetafin-network

volumes:
  postgres_data:
    driver: local

networks:
  zeetafin-network:
    driver: bridge
```

### Why `condition: service_healthy` is Essential

A common Docker mistake is relying on simple `depends_on: [ "db" ]`. Simple `depends_on` only waits for the database container to create its process—not for the database to actually accept socket connections. If NestJS starts while PostgreSQL is still initializing system tables, the backend crashes immediately.

Using:

```yaml
depends_on:
  db:
    condition: service_healthy
```

guarantees that Docker executes `pg_isready -U postgres -d zeetafin` until exit code `0` is returned before starting the backend container.

---

## 3. Launching and Seeding the Stack

Start the entire environment in detached mode:

```bash
cd phase2
docker compose up -d --build
```

### Verifying Service Health

Check the status of running containers:

```bash
docker compose ps
```

```text
NAME                IMAGE                    COMMAND                  SERVICE    STATUS
zeetafin-db         postgres:16-alpine       "docker-entrypoint.s…"   db         Up (healthy)
zeetafin-backend    zeetafin-backend:local   "docker-entrypoint.s…"   backend    Up (healthy)
zeetafin-frontend   zeetafin-frontend:local  "docker-entrypoint.s…"   frontend   Up (healthy)
```

### Seeding Admin Credentials

Once the database is healthy, seed the database with administrative accounts and financial demo data:

```bash
# Seed directly inside the backend container
docker exec -it zeetafin-backend node -e "require('./dist/seed.js')"
```

The database is now populated with:
* **Admin Email:** `admin@zeeta.com`
* **Admin Password:** `admin123`
* **Role:** `finance_admin` (Full access across accounts, invoices, and analytics)

### End-to-End Local Verification

Test each service from your workstation:
1. **Frontend UI:** Open [http://localhost:3000](http://localhost:3000) in your browser and log in.
2. **Backend Swagger API Docs:** Open [http://localhost:3001/api/docs](http://localhost:3001/api/docs) to test OpenAPI endpoints interactively.
3. **Database Connectivity:**
   ```bash
   docker exec -it zeetafin-db psql -U postgres -d zeetafin -c "\dt"
   ```

---

## 4. Distributing Containers to Amazon ECR

Now that our containers are verified, we publish them to **Amazon Elastic Container Registry (Amazon ECR)** for cloud deployment.

```text
 [ Developer Machine ]
        │
        ├──► docker tag zeetafin-backend:local <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/zeetafin-backend:latest
        ├──► docker tag zeetafin-frontend:local <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/zeetafin-frontend:latest
        │
        ▼  aws ecr get-login-password | docker login --password-stdin
 [ Amazon ECR Repositories (AWS us-east-1) ]
        ├── zeetafin-backend  (Tags: commit-sha, latest)
        └── zeetafin-frontend (Tags: commit-sha, latest)
```

### Step 1: Create ECR Repositories

Create private ECR repositories with automated vulnerability scanning on push:

```bash
export AWS_REGION="us-east-1"

# Create backend repository
aws ecr create-repository \
  --repository-name zeetafin-backend \
  --image-scanning-configuration scanOnPush=true \
  --region ${AWS_REGION}

# Create frontend repository
aws ecr create-repository \
  --repository-name zeetafin-frontend \
  --image-scanning-configuration scanOnPush=true \
  --region ${AWS_REGION}
```

### Step 2: Authenticate Docker to Amazon ECR

Retrieve an authentication token and pipe it directly to Docker CLI login:

```bash
# Retrieve your AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Authenticate local Docker daemon to AWS ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}
```

### Step 3: Tag and Push Images

Apply an immutable tag (such as the current Git commit SHA) and a rolling `latest` tag:

```bash
GIT_SHA=$(git rev-parse --short HEAD || echo "v1.0.0")

# Tag Backend
docker tag zeetafin-backend:local ${ECR_REGISTRY}/zeetafin-backend:${GIT_SHA}
docker tag zeetafin-backend:local ${ECR_REGISTRY}/zeetafin-backend:latest

# Tag Frontend
docker tag zeetafin-frontend:local ${ECR_REGISTRY}/zeetafin-frontend:${GIT_SHA}
docker tag zeetafin-frontend:local ${ECR_REGISTRY}/zeetafin-frontend:latest

# Push to Amazon ECR
docker push ${ECR_REGISTRY}/zeetafin-backend:${GIT_SHA}
docker push ${ECR_REGISTRY}/zeetafin-backend:latest

docker push ${ECR_REGISTRY}/zeetafin-frontend:${GIT_SHA}
docker push ${ECR_REGISTRY}/zeetafin-frontend:latest
```

### Step 4: Verify Published Images in ECR

Query AWS to confirm that the images and tags are live in the registry:

```bash
aws ecr list-images --repository-name zeetafin-backend --region ${AWS_REGION}
aws ecr list-images --repository-name zeetafin-frontend --region ${AWS_REGION}
```

---

## 5. Teardown Local Stack

To stop the local stack and free resources:

```bash
# Stop containers but keep database volume intact:
docker compose down

# Stop containers AND delete persistent volumes (resets database):
docker compose down -v
```

---

## Phase 2 Complete!

Our application containers are hardened, orchestrated, verified, and safely stored in Amazon ECR. In Phase 3, we build an automated CI/CD pipeline that pulls these images and deploys them to our EC2 host on every git push.

👉 **Continue to Phase 3:** [Part 9: Least-Privilege IAM, ECR Repositories, and Hardened GitHub Secrets](../../phase3/articles/01-aws-iam-ecr-github-secrets-security.md)
