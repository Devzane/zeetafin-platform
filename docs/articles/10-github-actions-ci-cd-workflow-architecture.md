---
title: "Declarative CI/CD Pipelines: Architecting GitHub Actions for Container Builds and ECR"
subtitle: "Part 10 of the Production DevOps Series: Multi-Job Workflows, Buildx Layer Caching, Concurrency Locks, and Immutable Tagging"
tags: ["github-actions", "cicd", "docker", "devops", "cloud", "aws"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 10
canonical_url: ""
cover_image: ""
---

# Declarative CI/CD Pipelines: Architecting GitHub Actions for Container Builds and ECR

Continuous Integration (CI) and Continuous Deployment (CD) are often treated as a linear script of commands. But without concurrency controls, layer caching, and immutable artifact tagging, deployment workflows suffer from race conditions, failed rebuilds, and unrepeatable deployments.

In Part 10 of our DevOps series, we architect the primary continuous delivery engine for **ZeetaFin ERP**: a declarative **GitHub Actions** workflow (`.github/workflows/deploy.yml`). We examine how to configure path filtering, prevent parallel deployment collisions, leverage GitHub Actions layer caching, and publish immutable image tags to Amazon ECR.

---

## 1. High-Level Pipeline Architecture

The workflow splits into two dependent jobs executed across isolated GitHub-hosted runners:

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      Trigger: push to main / manual                    │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Job 1: build-and-push (GitHub Runner: ubuntu-latest)                   │
 │   • Evaluates target tag: Git Commit SHA (e.g. 7d1a2b3)                │
 │   • Sets up Docker Buildx with GitHub Actions cache (type=gha)         │
 │   • Inlines NEXT_PUBLIC_API_URL build argument                         │
 │   • Builds & Pushes zeetafin-backend & zeetafin-frontend to Amazon ECR │
 │   • Exports outputs: ecr_registry and image_tag                        │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼ needs: build-and-push
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Job 2: deploy-to-ec2 (GitHub Runner: ubuntu-latest)                    │
 │   • Configures ephemeral deploy key with chmod 600                     │
 │   • Synchronizes docker-compose.prod.yml and deploy.sh over SCP        │
 │   • Triggers remote execution over SSH                                 │
 │   • Performs external HTTP smoke check against http://EC2_HOST:3000   │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Preventing Deployment Collisions with Concurrency Groups

If two developers merge pull requests within seconds of each other, two GitHub Action runs launch simultaneously. If both runners SSH into the single production host at the same time, containers get restarted mid-pull, and database connections break.

We eliminate this race condition using GitHub Actions **concurrency**:

```yaml
concurrency:
  group: production-deployment
  cancel-in-progress: false
```

* `group: production-deployment`: Any workflow runs targeting production share this mutex lock.
* `cancel-in-progress: false`: Ensures the second deployment cleanly queues and waits for the first deployment to finish and pass its health check, rather than terminating midway.

---

## 3. Path Filtering and Manual Overrides

To avoid running expensive container builds when only documentation changes, use path filtering:

```yaml
on:
  push:
    branches:
      - main
    paths:
      - 'phase2/**'
      - 'phase3/**'
      - '.github/workflows/**'
      - 'Dockerfile'
      - 'docker-compose*.yml'
      - '!**/README.md'
      - '!README.md'
      - '!**/readme.md'
      - '!readme.md'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment target environment'
        required: true
        default: 'production'
      tag_override:
        description: 'Optional container image tag override (defaults to commit SHA)'
        required: false
        default: ''
```

* `paths`: The workflow triggers only if code inside application directories or manifests changed.
* `workflow_dispatch`: Enables manual triggering directly from the GitHub UI, including the option to redeploy an arbitrary past tag.

---

## 4. Job 1: Building and Pushing to Amazon ECR

Here is the declarative build specification:

```yaml
jobs:
  build-and-push:
    name: Build & Push Images to Amazon ECR
    runs-on: ubuntu-latest
    outputs:
      ecr_registry: ${{ steps.login-ecr.outputs.registry }}
      image_tag: ${{ steps.set-tag.outputs.tag }}

    steps:
      - name: Checkout Application Code
        uses: actions/checkout@v4

      - name: Set Image Tag
        id: set-tag
        run: |
          if [ -n "${{ github.event.inputs.tag_override }}" ]; then
            TAG="${{ github.event.inputs.tag_override }}"
          else
            TAG="${{ github.sha }}"
          fi
          echo "tag=${TAG}" >> "$GITHUB_OUTPUT"
          echo "Building and releasing with Image Tag: ${TAG}"

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Authenticate with AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION || 'us-east-1' }}

      - name: Log in to Amazon Elastic Container Registry (ECR)
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      # Backend Container Build
      - name: Build & Push Backend Container Image
        uses: docker/build-push-action@v5
        with:
          context: ./phase2/backend
          file: ./phase2/backend/Dockerfile
          push: true
          tags: |
            ${{ steps.login-ecr.outputs.registry }}/zeetafin-backend:${{ steps.set-tag.outputs.tag }}
            ${{ steps.login-ecr.outputs.registry }}/zeetafin-backend:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # Frontend Container Build
      - name: Build & Push Frontend Container Image
        uses: docker/build-push-action@v5
        with:
          context: ./phase2/frontend
          file: ./phase2/frontend/Dockerfile
          build-args: |
            NEXT_PUBLIC_API_URL=http://${{ secrets.EC2_HOST }}:3001/api
          push: true
          tags: |
            ${{ steps.login-ecr.outputs.registry }}/zeetafin-frontend:${{ steps.set-tag.outputs.tag }}
            ${{ steps.login-ecr.outputs.registry }}/zeetafin-frontend:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## 5. Architectural Deep Dive: Layer Caching and Immutable Tagging

### Why We Use `cache-from: type=gha`
Without caching, GitHub Actions downloads base images and runs `npm ci` from scratch on every run. By configuring:

```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

Docker Buildx caches intermediate layers inside GitHub's native cache storage. When code changes in `src/`, Docker skips the `deps` stage entirely, reducing build times from 3 minutes to under 25 seconds.

### The Double-Tag Strategy
Every image pushed receives two tags:
1. `${{ github.sha }}`: An immutable, permanent tag mapped directly to the git commit.
2. `latest`: A rolling tag that points to the most recent release on the default branch.

In production environments, **never deploy by pulling `latest` alone**. If a regression occurs, knowing the exact git commit SHA guarantees rapid rollbacks to a verified previous build.

---

## 6. Common Pitfalls & Troubleshooting

| Symptom | Root Cause | Solution |
| :--- | :--- | :--- |
| **`login-ecr: repository does not exist`** | The ECR repository was not created beforehand. | Run `aws ecr create-repository --repository-name zeetafin-backend` in the target region. |
| **Cache size limits exceeded** | GitHub Actions restricts cache storage to 10 GB per repository. | Old caches expire automatically after 7 days; `cache-to: type=gha,mode=max` updates existing layers cleanly. |
| **Frontend build fails during SSG** | Frontend expects backend API reachable during static page generation. | Ensure Next.js components use dynamic client fetching or mock API responses for static builds. |

---

## Next Steps

With container artifacts built and pushed to Amazon ECR, we construct the remote deployment engine that connects to EC2 and manages zero-collision container replacements.

👉 **Next in Series:** [Part 11: Production Deployment Automation: Remote EC2 Orchestration and Zero-Downtime Rollouts](./03-ec2-remote-deployment-engine-automation.md)
