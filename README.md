# springboot-gitlab-gradle-demo

A complete **local CI/CD setup** for a **Spring Boot microservices system** using **Gradle**, **Docker**, and **self-hosted GitLab** running on **WSL2**.

This repository demonstrates how to:
- Run GitLab locally in Docker
- Configure a Docker-based GitLab Runner
- Build Spring Boot microservices with Gradle
- Build and run Docker images without pushing to a registry
- Execute end-to-end integration tests inside CI

---

## 🏗️ Architecture Overview

### Application
- **product-service**
- **review-service**
- **recommendation-service**
- **product-composite-service** (API aggregator)

All services:
- Are Spring Boot apps
- Use Gradle
- Run in separate Docker containers
- Communicate using Docker DNS (no service registry)

### CI/CD
- **GitLab CE** (Docker)
- **GitLab Runner** (Docker executor)
- **Docker socket binding** (no DinD)
- **Shared Docker network** for GitLab, runner, CI jobs, and app containers

---

## 📁 Repository Structure


---

## 🧩 Prerequisites

- Docker Desktop (with WSL2 backend)
- Docker Compose v2
- Git
- At least **8 GB RAM** recommended

---

## 🚀 Setup From Scratch (Step-by-Step)

---

## 1️⃣ Create Docker Network (IMPORTANT)

Create a shared network used by:
- GitLab
- GitLab Runner
- CI job containers
- Application containers

```bash
docker network create gitlab-net

docker compose -f docker-compose.gitlab.yml up -d

docker ps
docker exec -it gitlab gitlab-ctl status

docker ps
docker exec -it gitlab gitlab-ctl status

docker ps
docker exec -it gitlab gitlab-ctl status
username: root
password: <printed password>
```

4️⃣ Create Project in GitLab

Open GitLab UI

Create a new project
Name: springboot-gitlab-gradle-demo

Push your local repository

5️⃣ Register GitLab Runner
Register runner
```
docker exec -it gitlab-runner gitlab-runner register \
  --url http://gitlab \
  --token <PROJECT_RUNNER_TOKEN> \
  --executor docker \
  --docker-image docker:26 \
  --docker-privileged \
  --description "wsl2-production-runner"
```
6️⃣ Configure Runner (config.toml)
Copy this final working configuration:

```
concurrent = 1
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "wsl2-production-runner"
  url = "http://gitlab"
  token = "<RUNNER_TOKEN>"
  executor = "docker"

  # Git clone must work from CI containers
  clone_url = "http://host.docker.internal:8080"

  [runners.docker]
    image = "docker:26"
    privileged = true
    tls_verify = false

    # 🔑 CRITICAL: join GitLab shared network
    network_mode = "gitlab-net"

    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock",
      "/cache"
    ]
```
Copy it into the container:
```
docker cp config.toml gitlab-runner:/etc/gitlab-runner/config.toml
docker restart gitlab-runner
```

Verify:
```
docker exec -it gitlab-runner gitlab-runner list
```
7️⃣ Build CI Test Tools Image (Once)

CI jobs run inside containers, so we need a test image.

Example Dockerfile for ci-test-tools
```
FROM docker:26

RUN apk add --no-cache \
bash \
curl \
jq \
docker-cli-compose
```

Build it locally:
```
docker build -t ci-test-tools .
```

⚠️ Because the runner uses the host Docker socket, CI jobs can reuse this image without pushing to a registry.

8️⃣ CI Pipeline (.gitlab-ci.yml)
#### Pipeline Stages
1. build – Gradle build (JARs)
1. docker – Docker image build
1. test – Run full system + integration tests

#### Key characteristics
* No Docker registry push
* Container-only networking
* Full end-to-end testing

9️⃣ Application Docker Compose (CI-Safe)
```
services:
product:
build: microservices/product-service
environment:
- SPRING_PROFILES_ACTIVE=docker

recommendation:
build: microservices/recommendation-service
environment:
- SPRING_PROFILES_ACTIVE=docker

review:
build: microservices/review-service
environment:
- SPRING_PROFILES_ACTIVE=docker

product-composite:
build: microservices/product-composite-service
expose:
- "8080"
environment:
- SPRING_PROFILES_ACTIVE=docker

networks:
default:
external: true
name: gitlab-net
```
#### 🔬 Integration Testing

Tests are executed by test-em-all.sh.

Key points:
* Runs inside CI container
* Uses Docker DNS (product-composite)
* Validates full request chain:
* product-composite → product / review / recommendation


#### Example:

HOST=product-composite ./test-em-all.sh

#### ✅ How to Trigger CI Pipeline

Push any change:
```
git add .
git commit -m "Trigger pipeline"
git push
```

#### Or manually:
GitLab UI → CI/CD → Pipelines → Run pipeline

#### 🧠 Why This Setup Works
* No localhost usage inside CI
* No registry dependency
* Single shared Docker network
* Deterministic builds and tests
* Production-like CI behavior

#### 🧹 Cleanup
docker compose -f docker-compose.gitlab.yml down -v
docker network rm gitlab-net

#### 🏁 Final Result
* ✅ Local GitLab
* ✅ Docker-based CI runner
* ✅ Spring Boot microservices
* ✅ Gradle builds
* ✅ Docker image builds
* ✅ Full integration tests

Docker-in-Docker (DinD) vs Your Current Setup
🧠 High-level summary (one-liner)

DinD runs a Docker daemon inside the CI container.
Your setup reuses the host’s Docker daemon via the socket.

That single difference causes big changes in networking, stability, and complexity.

1️⃣ Your Current Setup (Docker Socket Binding)
How it works
```
GitLab Runner (container)
│
├── CI Job Container (docker:26)
│   │
│   └── docker CLI
│         │
│         ▼
│   /var/run/docker.sock  ──►  Host Docker daemon
│                                   │
│                                   ├── App containers
│                                   ├── GitLab
│                                   └── gitlab-net network
```

#### Key characteristics
```
Feature	        Value
Docker daemon	Host Docker
Networking	Shared (gitlab-net)
Performance	Fast
Stability	High
Security	Lower (host-level access)
Complexity	Low
Debugging	Easy
```
Why your setup works so well

✔ Containers created in CI exist on the same Docker engine
✔ DNS resolution works (product, review, etc.)
✔ docker compose up behaves exactly like local Docker
✔ No registry push needed
✔ No TLS / certs / DinD health issues

This is why integration tests finally worked.

2️⃣ Docker-in-Docker (DinD)
```
How DinD works
GitLab Runner (container)
│
├── CI Job Container
│   │
│   └── docker CLI
│         │
│         ▼
│   Docker daemon (DinD)
│         │
│         ├── App containers
│         └── DinD-only network
```

The Docker daemon is inside the CI job container

What changes with DinD
```
Area	        DinD Behavior
Docker daemon	Inside job container
Networking	Isolated
Docker network	NOT shared with host
Service discovery	Breaks unless carefully wired
Registry	Often required
Performance	Slower
Memory	Higher
Stability	Fragile (esp. on WSL2)
Debugging	Painful
```
3️⃣ Why DinD broke things earlier for you

You saw errors like:

dial tcp: lookup gitlab: no such host

Docker service not starting

Artifacts upload failing

Registry push failures

Containers reachable locally but not in CI

Root cause

DinD creates a second Docker universe
Your CI containers were running here:
DinD Docker daemon
But GitLab, runner, and your network were here:
Host Docker daemon

So:
gitlab-net didn’t exist inside DinD
product-composite DNS didn’t resolve
Ports were already allocated
Registry hostname mismatch

4️⃣ Visual Comparison
Docker Socket Binding (YOU ARE HERE ✅)
```
┌──────────────────────────────┐
│ Host Docker Engine           │
│                              │
│  ┌──────────┐   ┌──────────┐ │
│  │ GitLab   │   │ Runner   │ │
│  └──────────┘   └──────────┘ │
│        │             │       │
│        └──── gitlab-net ──────┘
│                    │
│           CI job containers
│           App containers
└──────────────────────────────┘
```
Docker-in-Docker (DinD ❌ for your case)
```
┌──────────────────────────────┐
│ Host Docker Engine           │
│                              │
│  ┌──────────┐   ┌──────────┐ │
│  │ GitLab   │   │ Runner   │ │
│  └──────────┘   └──────────┘ │
└──────────────────────────────┘
│
CI job container
│
┌──────────────────┐
│ DinD Docker      │
│ (isolated world) │
└──────────────────┘
```
5️⃣ When SHOULD you use DinD?

DinD is useful when:

✔ You don’t trust the host
✔ You need full isolation
✔ You are on shared CI runners
✔ You only do docker build + push
✔ You don’t need inter-container networking

Typical use cases:

SaaS CI runners

Simple image build pipelines

Kubernetes-native CI

6️⃣ When NOT to use DinD (your case)

❌ Local GitLab
❌ WSL2
❌ Multi-container integration tests
❌ Docker Compose
❌ Service-to-service networking

Your pipeline needs:

Stable DNS

Shared network

Low friction debugging

👉 Socket binding is the correct choice

7️⃣ Security Note (important)

⚠️ Docker socket binding gives CI jobs root access to the host.

This is OK when:

GitLab is local

You trust the code

Single developer setup

❌ Not OK for:

Multi-tenant runners

Public projects

8️⃣ Final Verdict
For springboot-gitlab-gradle-demo
Approach	Verdict
Docker-in-Docker	❌ Wrong tool
Docker socket binding	✅ Best solution
🔑 One-sentence takeaway

DinD creates a second Docker world; your setup smartly avoids it by using the host Docker world directly — which is exactly why everything finally worked.