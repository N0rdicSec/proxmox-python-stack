#!/bin/bash
set -e

echo ""
echo "███╗   ███╗██╗   ██╗    ███████╗ █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗██████╗ ██╗████████╗███████╗   "
echo "████╗ ████║╚██╗ ██╔╝    ██╔════╝██╔══██╗██║   ██║██╔═══██╗██║   ██║██╔══██╗██║╚══██╔══╝██╔════╝   "
echo "██╔████╔██║ ╚████╔╝     █████╗  ███████║██║   ██║██║   ██║██║   ██║██████╔╝██║   ██║   █████╗     "
echo "██║╚██╔╝██║  ╚██╔╝      ██╔══╝  ██╔══██║╚██╗ ██╔╝██║   ██║██║   ██║██╔══██╗██║   ██║   ██╔══╝     "
echo "██║ ╚═╝ ██║   ██║       ██║     ██║  ██║ ╚████╔╝ ╚██████╔╝╚██████╔╝██║  ██║██║   ██║   ███████╗   "
echo "╚═╝     ╚═╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝  ╚═══╝   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝   ╚══════╝   "
echo "                                                                                                   "
echo "██████╗ ██╗   ██╗████████╗██╗  ██╗ ██████╗ ███╗   ██╗    ███████╗████████╗ █████╗  ██████╗██╗  ██╗"
echo "██╔══██╗╚██╗ ██╔╝╚══██╔══╝██║  ██║██╔═══██╗████╗  ██║    ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝"
echo "██████╔╝ ╚████╔╝    ██║   ███████║██║   ██║██╔██╗ ██║    ███████╗   ██║   ███████║██║     █████╔╝ "
echo "██╔═══╝   ╚██╔╝     ██║   ██╔══██║██║   ██║██║╚██╗██║    ╚════██║   ██║   ██╔══██║██║     ██╔═██╗ "
echo "██║        ██║      ██║   ██║  ██║╚██████╔╝██║ ╚████║    ███████║   ██║   ██║  ██║╚██████╗██║  ██╗"
echo "╚═╝        ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
echo "=================================================================================================="
echo "⬇️🚀🚀 Made by 0din 🚀🚀⬇️"
echo "[Docker | Python 3.12 | Code-Server(VsCode Web) | FastAPI |"
echo "Postgres 17 | pgAdmin 9 | Redis 7 | Nginx Proxy Manager | Gitea 1.25]"
echo "=================================================================================================="
echo ""
echo "🚀 Setting up DevLab stack on Ubuntu 24.04 LXC..."

# ─────────────────────────────────────────────────────────────
# Image versions — update these to bump the stack
# ─────────────────────────────────────────────────────────────
POSTGRES_VERSION="17"
PGADMIN_VERSION="9.13.0"
GITEA_VERSION="1.25.3"
ACT_RUNNER_VERSION="0.3.0"
REDIS_VERSION="7.4-alpine"
NPM_VERSION="latest"   # jc21/nginx-proxy-manager has no stable semver tag

# ─────────────────────────────────────────────────────────────
# Root / user-mode guard
# ─────────────────────────────────────────────────────────────
USER_MODE=false
if [ "$1" = "--user-mode" ]; then
    USER_MODE=true
    echo "🔧 Running in user mode — skipping system setup"
elif [ "$EUID" -ne 0 ]; then
    echo "❌ This script requires root privileges for system setup."
    echo "Please run with sudo:"
    echo "  sudo $0"
    echo ""
    echo "Or to skip system setup and only deploy the stack:"
    echo "  $0 --user-mode"
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# Determine which real user invoked sudo (for docker group)
# ─────────────────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-}"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    # Running as root directly — fall back to 'ubuntu' if it exists, else root
    if id "ubuntu" &>/dev/null; then
        REAL_USER="ubuntu"
    else
        REAL_USER="root"
    fi
fi

# ─────────────────────────────────────────────────────────────
# System setup (root mode only)
# ─────────────────────────────────────────────────────────────
if [ "$USER_MODE" = false ]; then

    echo "📦 Updating system packages..."
    apt-get update && apt-get upgrade -y

    echo "🔧 Installing dependencies..."
    apt-get install -y \
        curl wget git \
        apt-transport-https ca-certificates gnupg lsb-release \
        software-properties-common openssl

    # ── Docker ──────────────────────────────────────────────
    echo "🐳 Installing Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    # ── Docker daemon config for LXC ────────────────────────
    echo "⚙️  Configuring Docker for LXC..."
    mkdir -p /etc/docker
    # Note: no custom DNS — Docker inherits the host's resolv.conf,
    # which is correct for Proxmox LXC environments.
    cat > /etc/docker/daemon.json <<'DAEMON_EOF'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMON_EOF

    # ── cgroup v2 / LXC service override (applied once) ─────
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        echo "🏗️  Detected cgroup v2 — applying Docker service override..."
        mkdir -p /etc/systemd/system/docker.service.d
        cat > /etc/systemd/system/docker.service.d/override.conf <<'OVERRIDE_EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket firewalld.service containerd.service time-set.target
Wants=network-online.target containerd.service
Requires=docker.socket containerd.service

[Service]
Type=notify
# Clear the default ExecStart before overriding it
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
OVERRIDE_EOF
        systemctl daemon-reload
        echo "✅ cgroup v2 override applied"
    fi

    systemctl enable docker
    systemctl start docker

    # Add the invoking user to the docker group
    if [ "$REAL_USER" != "root" ] && id "$REAL_USER" &>/dev/null; then
        usermod -aG docker "$REAL_USER"
        echo "✅ Added '$REAL_USER' to docker group (re-login required to take effect)"
    fi

    echo "✅ Verifying Docker installation..."
    docker --version
    docker compose version

    echo "📁 Creating project structure..."
    PROJECT_DIR="/opt/docker/python-stack"
    mkdir -p "$PROJECT_DIR"
    if [ "$REAL_USER" != "root" ]; then
        chown -R "$REAL_USER":"$REAL_USER" "$PROJECT_DIR"
    fi

else
    PROJECT_DIR="$HOME/docker/python-stack"
    mkdir -p "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

# ─────────────────────────────────────────────────────────────
# External Docker network
# ─────────────────────────────────────────────────────────────
echo "🌐 Creating external Docker network..."
if ! docker network inspect devlab-network >/dev/null 2>&1; then
    docker network create --subnet=172.20.0.0/16 devlab-network
    echo "✅ Network 'devlab-network' created"
else
    echo "✅ Network 'devlab-network' already exists"
fi

# ─────────────────────────────────────────────────────────────
# Generate secure passwords
# ─────────────────────────────────────────────────────────────
echo "🎲 Generating secure passwords..."
POSTGRES_PASSWORD="postgrespass_$(openssl rand -hex 8)"
GITEA_DB_PASSWORD="giteapass_$(openssl rand -hex 8)"
PGADMIN_DEFAULT_PASSWORD="pgadmin_$(openssl rand -hex 8)"
VSCODE_PASSWORD="vscode_$(openssl rand -hex 8)"
REDIS_PASSWORD="redis_$(openssl rand -hex 8)"
GITEA_SECRET_KEY=$(openssl rand -hex 32)
GITEA_INTERNAL_TOKEN=$(openssl rand -hex 32)
FASTAPI_PASSWORD="fastapi_$(openssl rand -hex 8)"

# ─────────────────────────────────────────────────────────────
# Write .env (consistent naming, 600 permissions)
# ─────────────────────────────────────────────────────────────
echo "🔑 Writing environment configuration..."
cat > .env <<EOF
# ── PostgreSQL (shared instance) ──────────────────────────
POSTGRES_USER=devlab
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=gitea

# ── Gitea ─────────────────────────────────────────────────
GITEA_DB_USER=gitea
GITEA_DB_PASSWORD=${GITEA_DB_PASSWORD}
GITEA_DB_NAME=gitea
GITEA_SECRET_KEY=${GITEA_SECRET_KEY}
GITEA_INTERNAL_TOKEN=${GITEA_INTERNAL_TOKEN}

# ── pgAdmin ───────────────────────────────────────────────
PGADMIN_DEFAULT_EMAIL=admin@pgadmin.local
PGADMIN_DEFAULT_PASSWORD=${PGADMIN_DEFAULT_PASSWORD}

# ── VS Code Server ────────────────────────────────────────
VSCODE_PASSWORD=${VSCODE_PASSWORD}

# ── Redis ─────────────────────────────────────────────────
REDIS_PASSWORD=${REDIS_PASSWORD}

# ── FastAPI ───────────────────────────────────────────────
FASTAPI_USER=admin
FASTAPI_PASSWORD=${FASTAPI_PASSWORD}

# ── Gitea Actions Runner ──────────────────────────────────
# Fill this in after completing the Gitea setup wizard, then
# run: docker compose up -d gitea-runner
GITEA_RUNNER_TOKEN=
EOF
chmod 600 .env
echo "✅ .env written (permissions: 600)"

# ─────────────────────────────────────────────────────────────
# Persistent storage directories
# ─────────────────────────────────────────────────────────────
echo "📂 Creating persistent storage directories..."
mkdir -p \
    code \
    gitea \
    postgres \
    pgadmin \
    gitea-runner \
    redis \
    npm/data \
    npm/letsencrypt \
    fastapi \
    vscode

# pgAdmin's data directory must be writable by uid 5050 inside the container
chmod 777 pgadmin
echo "✅ Directories created (pgadmin dir chmod 777)"

# ─────────────────────────────────────────────────────────────
# VS Code Server — Dockerfile
# ─────────────────────────────────────────────────────────────
echo "📝 Writing VS Code Dockerfile..."
cat > vscode/Dockerfile <<'VSCODE_EOF'
FROM codercom/code-server:latest

USER root

# Install Python 3.12, pip, and dev tools
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install VS Code extensions useful for Python development
RUN code-server --install-extension ms-python.python \
    && code-server --install-extension ms-toolsai.jupyter \
    && code-server --install-extension ms-python.black-formatter \
    && code-server --install-extension ms-python.isort \
    && code-server --install-extension eamodio.gitlens \
    && code-server --install-extension ms-azuretools.vscode-docker \
    && code-server --install-extension humao.rest-client \
    && code-server --install-extension usernamehw.errorlens \
    && code-server --install-extension hbenl.vscode-test-explorer \
    && code-server --install-extension gitlab.gitlab-workflow \
    && code-server --install-extension github.vscode-pull-request-github \
    && code-server --install-extension github.vscode-github-actions

ENV PATH=$PATH:/home/coder/.local/bin

USER coder
VSCODE_EOF

# ─────────────────────────────────────────────────────────────
# FastAPI — Dockerfile
# ─────────────────────────────────────────────────────────────
echo "📝 Writing FastAPI Dockerfile..."
cat > fastapi/Dockerfile <<'FASTAPI_DOCKERFILE_EOF'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
FASTAPI_DOCKERFILE_EOF

# ─────────────────────────────────────────────────────────────
# FastAPI — requirements.txt
# ─────────────────────────────────────────────────────────────
echo "📝 Writing FastAPI requirements.txt..."
cat > fastapi/requirements.txt <<'REQS_EOF'
fastapi==0.115.12
uvicorn[standard]==0.34.0
pydantic==2.11.1
sqlalchemy==2.0.40
psycopg2-binary==2.9.10
python-multipart==0.0.20
python-jose[cryptography]==3.4.0
passlib[bcrypt]==1.7.4
python-dotenv==1.1.0
REQS_EOF

# ─────────────────────────────────────────────────────────────
# FastAPI — main.py
# Credentials come entirely from environment variables — no
# defaults are embedded in the source file for security.
# ─────────────────────────────────────────────────────────────
echo "📝 Writing FastAPI main.py..."
cat > fastapi/main.py <<'FASTAPI_APP_EOF'
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel
import secrets
import os

app = FastAPI(title="DevLab API", version="1.0.0")
security = HTTPBasic()


def get_current_username(credentials: HTTPBasicCredentials = Depends(security)) -> str:
    """Validate HTTP Basic credentials against environment-supplied values."""
    api_user = os.environ.get("FASTAPI_USER", "")
    api_pass = os.environ.get("FASTAPI_PASSWORD", "")

    if not api_user or not api_pass:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="API credentials not configured",
        )

    username_ok = secrets.compare_digest(credentials.username, api_user)
    password_ok = secrets.compare_digest(credentials.password, api_pass)

    if not (username_ok and password_ok):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username


@app.get("/")
def read_root():
    return {"message": "Welcome to the DevLab Python Stack API"}


@app.get("/health")
def health_check():
    return {"status": "healthy"}


@app.get("/secure-data", dependencies=[Depends(get_current_username)])
def read_secure_data():
    return {"message": "You have accessed secured data successfully"}
FASTAPI_APP_EOF

# ─────────────────────────────────────────────────────────────
# Postgres init script — creates all databases in one instance
# ─────────────────────────────────────────────────────────────
echo "📝 Writing Postgres init script..."
mkdir -p postgres-init

# POSTGRES_USER and POSTGRES_DB are expanded at runtime from the
# container's own environment variables, so this file uses the
# shell-style $VAR syntax that the postgres entrypoint expects.
cat > postgres-init/01-init.sh <<'PGINIT_EOF'
#!/bin/bash
set -e

# Create the Gitea database and dedicated user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    CREATE USER gitea WITH PASSWORD '${GITEA_DB_PASSWORD}';
    CREATE DATABASE gitea OWNER gitea;
    GRANT ALL PRIVILEGES ON DATABASE gitea TO gitea;
SQL
PGINIT_EOF
chmod +x postgres-init/01-init.sh

# The init script needs the Gitea password at runtime — write a
# companion env file that docker compose will pick up automatically.
# (The .env file already contains GITEA_DB_PASSWORD so nothing extra
#  is needed; the compose file passes it through to the init script.)

# ─────────────────────────────────────────────────────────────
# Docker Compose
# ─────────────────────────────────────────────────────────────
echo "📝 Writing docker-compose.yml..."

# Write the compose file using a regular (double-quoted) heredoc so
# that the VERSION variables from this script expand correctly.
# Dollar signs that must reach the compose runtime are escaped (\$).
cat > docker-compose.yml <<COMPOSE_EOF
# DevLab Python Stack — docker-compose.yml
# Generated by setup-devlab.sh
# Image versions: Gitea ${GITEA_VERSION} | pgAdmin ${PGADMIN_VERSION} | Postgres ${POSTGRES_VERSION} | Redis ${REDIS_VERSION}

services:

  # ── VS Code Server ────────────────────────────────────────
  vscode:
    build:
      context: ./vscode
      dockerfile: Dockerfile
    container_name: vscode
    ports:
      - "8080:8080"
    volumes:
      - ./code:/home/coder/project
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - PASSWORD=\${VSCODE_PASSWORD}
      - SUDO_PASSWORD=\${VSCODE_PASSWORD}
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - devlab-network
    user: root
    command: >
      bash -c "
        if [ ! -f /home/coder/.ssh/id_ed25519 ]; then
          mkdir -p /home/coder/.ssh &&
          ssh-keygen -t ed25519 -f /home/coder/.ssh/id_ed25519 -N '' &&
          chmod 700 /home/coder/.ssh &&
          chmod 600 /home/coder/.ssh/id_ed25519 &&
          chmod 644 /home/coder/.ssh/id_ed25519.pub;
        fi &&
        /usr/bin/code-server --bind-addr 0.0.0.0:8080 --auth password
      "
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ── FastAPI ───────────────────────────────────────────────
  fastapi:
    build:
      context: ./fastapi
      dockerfile: Dockerfile
    container_name: fastapi
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}
      - FASTAPI_USER=\${FASTAPI_USER}
      - FASTAPI_PASSWORD=\${FASTAPI_PASSWORD}
    volumes:
      - ./fastapi:/app
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - devlab-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  # ── PostgreSQL (shared instance) ─────────────────────────
  postgres:
    image: postgres:${POSTGRES_VERSION}
    container_name: postgres
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
      - GITEA_DB_PASSWORD=\${GITEA_DB_PASSWORD}
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --lc-collate=C --lc-ctype=C
    restart: unless-stopped
    volumes:
      - ./postgres:/var/lib/postgresql/data
      - ./postgres-init:/docker-entrypoint-initdb.d:ro
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    networks:
      - devlab-network

  # ── pgAdmin 4 ─────────────────────────────────────────────
  pgadmin:
    image: dpage/pgadmin4:${PGADMIN_VERSION}
    container_name: pgadmin
    environment:
      - PGADMIN_DEFAULT_EMAIL=\${PGADMIN_DEFAULT_EMAIL}
      - PGADMIN_DEFAULT_PASSWORD=\${PGADMIN_DEFAULT_PASSWORD}
      - PGADMIN_CONFIG_SERVER_MODE=False
      - PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False
    ports:
      - "5050:80"
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./pgadmin:/var/lib/pgadmin
    restart: unless-stopped
    networks:
      - devlab-network
    healthcheck:
      test: ["CMD", "wget", "-O", "-", "http://localhost:80/misc/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  # ── Gitea ─────────────────────────────────────────────────
  gitea:
    image: gitea/gitea:${GITEA_VERSION}
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=postgres:5432
      - GITEA__database__NAME=\${GITEA_DB_NAME}
      - GITEA__database__USER=\${GITEA_DB_USER}
      - GITEA__database__PASSWD=\${GITEA_DB_PASSWORD}
      - GITEA__server__DOMAIN=localhost
      - GITEA__server__SSH_DOMAIN=localhost
      - GITEA__server__ROOT_URL=http://localhost:3000/
      - GITEA__security__SECRET_KEY=\${GITEA_SECRET_KEY}
      - GITEA__security__INTERNAL_TOKEN=\${GITEA_INTERNAL_TOKEN}
      - GITEA__actions__ENABLED=true
    restart: unless-stopped
    ports:
      - "3000:3000"
      - "2222:22"
    volumes:
      - ./gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - devlab-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # ── Gitea Actions Runner ──────────────────────────────────
  # The runner requires a registration token from the Gitea UI.
  # Steps:
  #   1. Complete the Gitea setup wizard at http://<IP>:3000
  #   2. Go to Site Administration → Actions → Runners → Create Runner
  #   3. Copy the token into GITEA_RUNNER_TOKEN in .env
  #   4. Run: docker compose up -d gitea-runner
  gitea-runner:
    image: gitea/act_runner:${ACT_RUNNER_VERSION}
    container_name: gitea-runner
    depends_on:
      gitea:
        condition: service_healthy
    volumes:
      - ./gitea-runner:/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - CONFIG_FILE=/data/config.yaml
      - GITEA_INSTANCE_URL=http://gitea:3000
      - GITEA_RUNNER_REGISTRATION_TOKEN=\${GITEA_RUNNER_TOKEN}
    restart: unless-stopped
    networks:
      - devlab-network
    profiles:
      - runner

  # ── Redis ─────────────────────────────────────────────────
  redis:
    image: redis:${REDIS_VERSION}
    container_name: redis
    ports:
      - "6379:6379"
    volumes:
      - ./redis:/data
    restart: unless-stopped
    # Password is enforced via the requirepass argument
    command: redis-server --appendonly yes --requirepass \${REDIS_PASSWORD}
    networks:
      - devlab-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "\${REDIS_PASSWORD}", "ping"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ── Nginx Proxy Manager ───────────────────────────────────
  # Uses its built-in SQLite database — no separate DB container needed.
  # Default login after first start: admin@example.com / changeme
  npm:
    image: jc21/nginx-proxy-manager:${NPM_VERSION}
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - ./npm/data:/data
      - ./npm/letsencrypt:/etc/letsencrypt
    networks:
      - devlab-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:81/api/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

networks:
  devlab-network:
    external: true
    name: devlab-network
COMPOSE_EOF

# ─────────────────────────────────────────────────────────────
# Permissions
# ─────────────────────────────────────────────────────────────
echo "🔐 Setting directory permissions..."
if [ "$USER_MODE" = false ] && [ "$REAL_USER" != "root" ]; then
    chown -R "$REAL_USER":"$REAL_USER" "$PROJECT_DIR"
fi
chmod -R 755 "$PROJECT_DIR"
chmod 600 "$PROJECT_DIR/.env"

# ─────────────────────────────────────────────────────────────
# Build images (only if Dockerfile changed)
# ─────────────────────────────────────────────────────────────
echo ""
echo "🔍 Checking VS Code Dockerfile for changes..."
if [ ! -f .vscode_build_hash ] || ! sha256sum -c .vscode_build_hash --status 2>/dev/null; then
    echo "📦 Rebuilding VS Code image..."
    docker compose build vscode
    sha256sum vscode/Dockerfile > .vscode_build_hash
else
    echo "✅ VS Code image is up to date — skipping rebuild"
fi

echo ""
echo "🔍 Checking FastAPI Dockerfile for changes..."
if [ ! -f .fastapi_build_hash ] || ! sha256sum -c .fastapi_build_hash --status 2>/dev/null; then
    echo "📦 Rebuilding FastAPI image..."
    docker compose build fastapi
    sha256sum fastapi/Dockerfile > .fastapi_build_hash
else
    echo "✅ FastAPI image is up to date — skipping rebuild"
fi

# ─────────────────────────────────────────────────────────────
# Start the stack (runner excluded — needs token first)
# ─────────────────────────────────────────────────────────────
echo ""
echo "🚀 Starting DevLab services..."
echo "   (The Gitea runner is excluded — see instructions below)"
docker compose up -d

# ─────────────────────────────────────────────────────────────
# Wait for services to become healthy (replaces bare sleep 30)
# ─────────────────────────────────────────────────────────────
echo ""
echo "⏳ Waiting for all services to report healthy..."
TIMEOUT=120
ELAPSED=0
INTERVAL=5
while true; do
    UNHEALTHY=$(docker compose ps --format json 2>/dev/null \
        | grep -c '"Health":"starting"' || true)
    if [ "$UNHEALTHY" -eq 0 ]; then
        break
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "⚠️  Timeout waiting for services. Some may still be starting."
        break
    fi
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
echo ""
echo "📊 Service Status:"
docker compose ps

LXC_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           ✅  DevLab Stack Deployed Successfully         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  🌐 Host IP : ${LXC_IP}"
echo ""
echo "  💻 VS Code Server     → http://${LXC_IP}:8080"
echo "     Password           : $(grep VSCODE_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo "  ⚡ FastAPI             → http://${LXC_IP}:8000"
echo "     Username           : $(grep FASTAPI_USER .env | head -1 | cut -d'=' -f2)"
echo "     Password           : $(grep FASTAPI_PASSWORD .env | cut -d'=' -f2)"
echo "     Docs               → http://${LXC_IP}:8000/docs"
echo ""
echo "  🗂️  Gitea              → http://${LXC_IP}:3000"
echo "     (Complete setup wizard on first visit)"
echo "     SSH clone port     : 2222"
echo ""
echo "  🗄️  pgAdmin 4          → http://${LXC_IP}:5050"
echo "     Email              : $(grep PGADMIN_DEFAULT_EMAIL .env | cut -d'=' -f2)"
echo "     Password           : $(grep PGADMIN_DEFAULT_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo "  🔄 Redis               → ${LXC_IP}:6379"
echo "     Password           : $(grep REDIS_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo "  🐘 PostgreSQL          → ${LXC_IP}:5432"
echo "     User               : $(grep POSTGRES_USER .env | cut -d'=' -f2)"
echo "     Password           : $(grep POSTGRES_PASSWORD .env | cut -d'=' -f2)"
echo "     Database           : $(grep POSTGRES_DB .env | cut -d'=' -f2)"
echo ""
echo "  🔁 Nginx Proxy Manager → http://${LXC_IP}:81"
echo "     Default login      : admin@example.com / changeme"
echo "     (Change these immediately after first login)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🤖 Gitea Actions Runner (manual step required):"
echo "     1. Open Gitea at http://${LXC_IP}:3000 and finish setup"
echo "     2. Go to: Site Administration → Actions → Runners"
echo "     3. Click 'Create Runner' and copy the token"
echo "     4. Edit .env and set GITEA_RUNNER_TOKEN=<token>"
echo "     5. Run: docker compose --profile runner up -d gitea-runner"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  📁 Project root        : $PROJECT_DIR"
echo "  🔑 Credentials file    : $PROJECT_DIR/.env  (chmod 600)"
echo ""
echo "  🔧 Useful commands:"
echo "     docker compose ps                  — check service status"
echo "     docker compose logs -f <service>   — tail logs"
echo "     docker compose restart <service>   — restart one service"
echo "     docker compose down                — stop everything"
echo ""
echo "  ⚠️  Security reminders:"
echo "     • Change the Nginx Proxy Manager default password immediately"
echo "     • Keep .env secure and out of version control"
echo "     • Configure firewall rules to restrict port exposure"
echo "     • Use Nginx Proxy Manager to enable SSL for external access"
echo ""
echo "🏁 Setup complete! Happy coding!"
echo "✅ Created by 0din — fixed and enhanced."
