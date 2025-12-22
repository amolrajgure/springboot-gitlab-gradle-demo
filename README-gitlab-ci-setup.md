# 🧭 GitLab CI/CD Setup Guide (Docker + WSL2 + Gradle + Spring Boot)

This document captures the exact steps to set up a fully working GitLab CI pipeline on WSL2 using:

GitLab CE (Docker)
GitLab Runner (Docker executor)
Gradle multi-module Spring Boot project
Docker Compose–based image builds
Attachable Docker network (critical)
This setup supports:
Git clone
Gradle build
Artifact upload
Docker image build & push

### ✔ Architecture

GitLab + Runner running in Docker
Runner using host Docker daemon
Single shared Docker network (gitlab-net)
App services + CI job containers on same network

### ✔ Pipeline design
Build stage: Gradle JARs
Docker stage: image builds via docker compose
Test stage: full integration test with real containers
No registry dependency
No port conflicts
Clean teardown every run

### ✔ Testing
Container-native service discovery (product-composite, review, etc.)
Deterministic wait logic
Proper test tooling via ci-test-tools
Same behavior locally and in CI

1️⃣ Prerequisites

WSL2 enabled
Docker Desktop installed (with WSL integration)
Docker resources:
Memory: 6–8 GB minimum
CPU: 4 cores recommended
Git installed inside WSL2

2️⃣ Create an attachable Docker network (CRITICAL STEP)

GitLab Runner job containers must dynamically attach to the same network as GitLab.
docker network create --attachable gitlab-net

Verify:
docker network inspect gitlab-net | grep Attachable
Expected:
"Attachable": true
⚠️ Without --attachable, artifact upload will fail.

3️⃣ GitLab + Runner Docker Compose
docker-compose.gitlab.yml (FINAL)
version: "3.8"

services:
gitlab:
image: gitlab/gitlab-ce:latest
container_name: gitlab
hostname: gitlab

    ports:
      - "8080:80"
      - "5050:5050"

    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://gitlab'
        registry_external_url 'http://gitlab:5050'

    volumes:
      - gitlab_config:/etc/gitlab
      - gitlab_logs:/var/log/gitlab
      - gitlab_data:/var/opt/gitlab

    networks:
      - gitlab-net

gitlab-runner:
image: gitlab/gitlab-runner:latest
container_name: gitlab-runner
depends_on:
- gitlab

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - gitlab_runner:/etc/gitlab-runner

    networks:
      - gitlab-net

networks:
gitlab-net:
external: true

volumes:
gitlab_config:
gitlab_logs:
gitlab_data:
gitlab_runner:


Start services:
docker compose -f docker-compose.gitlab.yml up -d

Wait until GitLab is healthy:
docker ps
You should see:
gitlab   Up (...) (healthy)

4️⃣ Register GitLab Runner (Docker executor)
Clean slate (if needed)
docker exec -it gitlab-runner rm -f /etc/gitlab-runner/config.toml

Register runner
docker exec -it gitlab-runner gitlab-runner register \
--url http://gitlab \
--token <PROJECT_REGISTRATION_TOKEN> \
--executor docker \
--description "wsl2-production-runner"


⚠️ Do NOT pass docker flags here (image, privileged, etc.).

5️⃣ Final Runner Configuration
/etc/gitlab-runner/config.toml (FINAL)
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

# Clone via host (GitLab UI exposed on localhost:8080)
clone_url = "http://host.docker.internal:8080"

[runners.docker]
image = "docker:26"
privileged = true
tls_verify = false

    # 🔑 CRITICAL: job containers join GitLab network
    network_mode = "gitlab-net"

    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock",
      "/cache"
    ]

    shm_size = 0


Restart runner:
docker restart gitlab-runner

Verify:
docker exec -it gitlab-runner gitlab-runner list
Token must not be empty.

9️⃣ GitLab CI Pipeline Behavior
Pipeline stages:
Gradle build (./gradlew build)
Artifacts uploaded (**/build/libs/*.jar)
Docker Compose build (docker compose build)
Images pushed to GitLab registry
Artifact upload works because:
Job containers share gitlab-net
gitlab:80 resolves to GitLab container nginx

🔑 Key Lessons (Save These)
Docker executor job containers are NOT docker-compose containers
Artifact upload requires network-level access to GitLab nginx
Docker networks must be attachable
Never overwrite config.toml after registration without preserving the token
clone_url ≠ artifact upload URL
external_url must be stable inside GitLab container

✅ Final Verification Checklist
Before running pipelines:
docker network inspect gitlab-net → Attachable: true
docker ps → GitLab (healthy)
gitlab-runner list → valid token
New pipeline triggered (old ones won’t recover)

🎉 Result
You now have:
Fully working local GitLab CI
Multi-module Gradle build
Docker image build via Compose
Reliable artifact upload
Production-grade runner networking

# Commands used

## Create a Personal Access Token (PAT)
Open GitLab UI
👉 http://localhost:8080
Login as root
Click Avatar → Preferences
Go to Access Tokens
Fill:
Token name: git-push
Expiration: optional
Scopes:
✅ api
✅ read_repository
✅ write_repository
Click Create personal access token
COPY IT NOW (you won’t see it again)
e.g. glpat-cPADHVAdCo7OHCid4xYX9286MQp1OjEH.01.0w1aywmta


docker compose -f docker-compose.gitlab.yml down
docker compose -f docker-compose.gitlab.yml up -d

### Update config.toml for the runner
docker cp gitlab-runner:/etc/gitlab-runner/config.toml ./config.toml
docker cp ./config.toml gitlab-runner:/etc/gitlab-runner/config.toml
docker restart gitlab-runner

docker exec -it gitlab-runner gitlab-runner unregister --all-runners


docker exec -it gitlab-runner gitlab-runner register \
--url http://gitlab \
--token glrt-GLxCNbRBBD2t9ozRVLRR4W86MQp0OjEKdToxCw.01.120jp1qo7 \
--executor docker \
--docker-image docker:24.0.5 \
--docker-privileged \
--description "wsl2-runner"

docker exec -it gitlab-runner gitlab-runner list
docker exec -it gitlab-runner ls -l /etc/gitlab-runner/
docker exec -it gitlab-runner rm -f /etc/gitlab-runner/config.toml
docker exec -it gitlab-runner gitlab-runner register   --url http://gitlab   --token glrt-GLxCNbRBBD2t9ozRVLRR4W86MQp0OjEKdToxCw.01.120jp1qo7   --executor docker   --description "wsl2-runner"

docker stop gitlab-runner
docker exec -it gitlab-runner gitlab-runner unregister --all-runners
docker exec -it gitlab-runner cat /etc/gitlab-runner/config.toml
docker exec -it gitlab gitlab-ctl status

docker run --rm --add-host gitlab:host-gateway alpine getent hosts gitlab
docker logs -f gitlab


git commit --allow-empty -m "fix gitlab external_url for artifacts"
git push -u origin main
git pull --rebase origin main

docker network create --attachable gitlab-net
docker network rm gitlab-net
docker network inspect gitlab-net
docker network ls | grep gitlab-net

### Locally build ci-test-tools to be use in test script
docker build -t ci-test-tools -f Dockerfile.ci-test .
