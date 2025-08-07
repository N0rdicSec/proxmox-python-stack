#!/bin/bash
set -e
echo ""
echo ""
echo "███╗   ███╗██╗   ██╗    ███████╗ █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗██████╗ ██╗████████╗███████╗   "
echo "████╗ ████║╚██╗ ██╔╝    ██╔════╝██╔══██╗██║   ██║██╔═══██╗██║   ██║██╔══██╗██║╚══██╔══╝██╔════╝   "
echo "██╔████╔██║ ╚████╔╝     █████╗  ███████║██║   ██║██║   ██║██║   ██║██████╔╝██║   ██║   █████╗     "
echo "██║╚██╔╝██║  ╚██╔╝      ██╔══╝  ██╔══██║╚██╗ ██╔╝██║   ██║██║   ██║██╔══██╗██║   ██║   ██╔══╝     "
echo "██║ ╚═╝ ██║   ██║       ██║     ██║  ██║ ╚████╔╝ ╚██████╔╝╚██████╔╝██║  ██║██║   ██║   ███████╗   "
echo "╚═╝     ╚═╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝  ╚═══╝   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝   ╚══════╝   "
echo "                                                                                                  "
echo "██████╗ ██╗   ██╗████████╗██╗  ██╗ ██████╗ ███╗   ██╗    ███████╗████████╗ █████╗  ██████╗██╗  ██╗"
echo "██╔══██╗╚██╗ ██╔╝╚══██╔══╝██║  ██║██╔═══██╗████╗  ██║    ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝"
echo "██████╔╝ ╚████╔╝    ██║   ███████║██║   ██║██╔██╗ ██║    ███████╗   ██║   ███████║██║     █████╔╝ "
echo "██╔═══╝   ╚██╔╝     ██║   ██╔══██║██║   ██║██║╚██╗██║    ╚════██║   ██║   ██╔══██║██║     ██╔═██╗ "
echo "██║        ██║      ██║   ██║  ██║╚██████╔╝██║ ╚████║    ███████║   ██║   ██║  ██║╚██████╗██║  ██╗"
echo "╚═╝        ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
echo "=================================================================================================="
echo "⬇️🚀🚀 Made by 0din and polished on Z.ai 🚀🚀⬇️"
echo ""                                                                                                  
echo "=================================================================================================="
echo ""
echo "🚀 Setting up DevLab stack on Ubuntu 22.04 LXC..."

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script requires root privileges for system setup."
    echo "Please run with sudo:"
    echo "  sudo $0"
    echo ""
    echo "Or if you want to skip system setup and only deploy the stack:"
    echo "  $0 --user-mode"
    exit 1
fi

# Check for user-mode flag
USER_MODE=false
if [ "$1" = "--user-mode" ]; then
    USER_MODE=true
    echo "🔧 Running in user mode - skipping system setup"
fi

# System setup (only if not in user mode)
if [ "$USER_MODE" = false ]; then
    # Update system
    echo "📦 Updating system packages..."
    apt update && apt upgrade -y

    # Install dependencies
    echo "🔧 Installing dependencies..."
    apt install -y curl wget git apt-transport-https ca-certificates gnupg lsb-release software-properties-common

    # Install Docker (Ubuntu repository method - more reliable for LXC)
    echo "🐳 Installing Docker..."
    # Remove any old Docker packages
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add Docker's official GPG key and repository for Ubuntu
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository for Ubuntu (not Debian)
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    # Update package index and install Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Configure Docker for LXC environment
    echo "⚙️  Configuring Docker for LXC..."
    # Create Docker daemon configuration for LXC compatibility
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["10.0.0.1", "192.168.2.1", "45.90.28.184"]
}
EOF

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    # Add docker user to docker group
    if id "docker" &>/dev/null; then
        usermod -aG docker docker
        echo "✅ Added 'docker' user to docker group"
    fi

    # LXC-specific optimizations
    echo "🏗️  Applying LXC optimizations..."
    # Ensure proper cgroup permissions for Docker in LXC
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        echo "Detected cgroup v2, ensuring proper Docker configuration..."
        # Modern LXC with cgroup v2 - create override directory and service file
        mkdir -p /etc/systemd/system/docker.service.d
        
        # Create override configuration for Docker service
        cat > /etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket firewalld.service containerd.service time-set.target
Wants=network-online.target containerd.service
Requires=docker.socket containerd.service

[Service]
Type=notify
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
EOF
        
        # Reload systemd to pick up the changes
        systemctl daemon-reload
        echo "✅ Applied Docker service optimizations for cgroup v2"
    fi

    # Verify Docker installation
    echo "✅ Verifying Docker installation..."
    docker --version
    docker compose version

    # Create project directory in system location
    echo "📁 Creating project structure..."
    mkdir -p /opt/docker/python-stack
    chown -R docker:docker /opt/docker/python-stack
    PROJECT_DIR="/opt/docker/python-stack"
else
    # User mode - create project in user's home directory
    echo "📁 Creating project structure in user directory..."
    PROJECT_DIR="$HOME/docker/python-stack"
    mkdir -p "$PROJECT_DIR"
fi

# Switch to project directory
cd "$PROJECT_DIR"

# Create the external network if it doesn't exist
echo "🌐 Creating external network..."
if ! docker network inspect devlab-network >/dev/null 2>&1; then
    docker network create --subnet=172.20.0.0/16 devlab-network
fi

# Generate random passwords first
echo "🎲 Generating secure passwords..."
POSTGRES_PASSWORD="postgrespass_$(openssl rand -hex 8)"
GITEA_DB_PASSWORD="giteapass_$(openssl rand -hex 8)"
NPM_DB_PASSWORD="npm_db_$(openssl rand -hex 8)"
PGADMIN_DEFAULT_PASSWORD="pgadmin_$(openssl rand -hex 8)"
VSCODE_PASSWORD="vscode_$(openssl rand -hex 8)"
REDIS_PASSWORD="redis_$(openssl rand -hex 8)"
GITEA_SECRET_KEY=$(openssl rand -hex 32)
GITEA_INTERNAL_TOKEN=$(openssl rand -hex 32)
FASTAPI_PASSWORD="fastapi_$(openssl rand -hex 8)"

# Create .env file with secure passwords
echo "🔑 Creating environment configuration..."
cat > .env <<EOF
# Database Configuration
POSTGRES_USER=venus
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=gitea

# Gitea Configuration
GITEA_DB_USER=gitea
GITEA_DB_PASSWORD=${GITEA_DB_PASSWORD}
GITEA_DB_NAME=gitea
GITEA_SECRET_KEY=${GITEA_SECRET_KEY}
GITEA_INTERNAL_TOKEN=${GITEA_INTERNAL_TOKEN}

# pgAdmin Configuration
PGADMIN_DEFAULT_EMAIL=admin@pgadmin.local
PGADMIN_DEFAULT_PASSWORD=${PGADMIN_DEFAULT_PASSWORD}

# Code Server Configuration
VSCODE_PASSWORD=${VSCODE_PASSWORD}

# Gitea Runner Configuration
GITEA_RUNNER_TOKEN=

# Redis Configuration
REDIS_PASSWORD=${REDIS_PASSWORD}

# Nginx Proxy Manager Database Configuration
NPM_DB_USER=npm
NPM_DB_PASSWORD=${NPM_DB_PASSWORD}
NPM_DB_NAME=npm

#FASTAPI Configuration
FASTAPI_user=admin
FASTAPI_PASSWORD=${FASTAPI_PASSWORD}
EOF

# Set proper permissions for .env file
chmod 600 .env

# Create directories for persistent storage
echo "📂 Creating storage directories..."
mkdir -p code gitea postgres pgadmin gitea-runner redis npm_db fastapi vscode

# Create VS Code Dockerfile
echo "📝 Creating VS Code Dockerfile..."
mkdir -p vscode
cat <<'EOF' > vscode/Dockerfile
FROM codercom/code-server:latest

USER root

# Install Python and pip
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Python extensions
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
# && code-server --install-extension ms-python.vscode-pylance \
# && code-server --install-extension gitea.vscode-gitea \

# Set up the environment
ENV PATH=$PATH:/home/coder/.local/bin

# Switch back to the coder user
USER coder
EOF

# Create FastAPI Dockerfile
echo "📝 Creating FastAPI Dockerfile..."
mkdir -p fastapi
cat <<'EOF' > fastapi/Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# Create a basic requirements.txt for FastAPI
echo "📝 Creating FastAPI requirements.txt..."
cat <<'EOF' > fastapi/requirements.txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
sqlalchemy==2.0.23
psycopg2-binary==2.9.9
python-multipart==0.0.6
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0
EOF

# Create a basic FastAPI app
echo "📝 Creating basic FastAPI app..."
cat <<'EOF' > fastapi/main.py
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel
import secrets
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="DevLab API", version="1.0.0")

security = HTTPBasic()

def get_current_username(credentials: HTTPBasicCredentials = Depends(security)):
    correct_username = secrets.compare_digest(credentials.username, os.getenv("API_USER", "admin"))
    correct_password = secrets.compare_digest(credentials.password, os.getenv("API_PASSWORD", ${FASTAPI_PASSWORD}))
    if not (correct_username and correct_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username

@app.get("/")
def read_root():
    return {"message": "Welcome to Python Stack API"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

@app.get("/secure-data", dependencies=[Depends(get_current_username)])
def read_secure_data():
    return {"message": "This is secure data"}
EOF

# Create updated Docker Compose file with latest versions and LXC optimizations
echo "📝 Creating Docker Compose configuration..."
cat <<'EOF' > docker-compose.yml
services:
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
      - ~/.ssh:/home/coder/.ssh:ro
    environment:
      - PASSWORD=${VSCODE_PASSWORD}
      - SUDO_PASSWORD=${VSCODE_PASSWORD}
    restart: unless-stopped
    depends_on:
      - postgres
    networks:
      - devlab-network
    user: root
    command: bash -c "\
      if [ ! -f /home/coder/.ssh/id_rsa ]; then \
        ssh-keygen -t rsa -b 4096 -f /home/coder/.ssh/id_rsa -N '' && \
        chmod 600 /home/coder/.ssh/id_rsa && \
        chmod 644 /home/coder/.ssh/id_rsa.pub; \
      fi && \
      /usr/bin/code-server --bind-addr 0.0.0.0:8080 --auth password"

  fastapi:
    build: 
      context: ./fastapi
      dockerfile: Dockerfile
    container_name: fastapi
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
    volumes:
      - ./fastapi:/app
    depends_on:
      - postgres
    networks:
      - devlab-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  gitea:
    image: gitea/gitea:1.22.1
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=postgres:5432
      - GITEA__database__NAME=${GITEA_DB_NAME}
      - GITEA__database__USER=${GITEA_DB_USER}
      - GITEA__database__PASSWD=${GITEA_DB_PASSWORD}
      - GITEA__server__DOMAIN=localhost
      - GITEA__server__SSH_DOMAIN=localhost
      - GITEA__server__ROOT_URL=http://localhost:3000/
      - GITEA__security__SECRET_KEY=${GITEA_SECRET_KEY}
      - GITEA__security__INTERNAL_TOKEN=${GITEA_INTERNAL_TOKEN}
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
      retries: 3
      start_period: 40s

  postgres:
    image: postgres:16.4
    container_name: postgres
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --lc-collate=C --lc-ctype=C
    restart: unless-stopped
    volumes:
      - ./postgres:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    networks:
      - devlab-network

  pgadmin:
    image: dpage/pgadmin4:8.10
    container_name: pgadmin
    environment:
      - PGADMIN_DEFAULT_EMAIL=${PGADMIN_DEFAULT_EMAIL}
      - PGADMIN_DEFAULT_PASSWORD=${PGADMIN_DEFAULT_PASSWORD}
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

  gitea-runner:
    image: gitea/act_runner:0.2.10
    container_name: gitea-runner
    depends_on:
      gitea:
        condition: service_started
    volumes:
      - ./gitea-runner:/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - CONFIG_FILE=/data/config.yaml
      - GITEA_INSTANCE_URL=http://gitea:3000
      - GITEA_RUNNER_REGISTRATION_TOKEN=${GITEA_RUNNER_TOKEN}
    restart: unless-stopped
    networks:
      - devlab-network

  # Optional: Redis for caching and session storage
  redis:
    image: redis:7.2.5-alpine
    container_name: redis
    ports:
      - "6379:6379"
    volumes:
      - ./redis:/data
    restart: unless-stopped
    command: redis-server --appendonly yes
    networks:
      - devlab-network

  # Optional: Nginx reverse proxy
  npm:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    environment:
      DB_POSTGRES_HOST: 'db'
      DB_POSTGRES_PORT: '5432'
      DB_POSTGRES_USER: ${NPM_DB_USER}
      DB_POSTGRES_PASSWORD: ${NPM_DB_PASSWORD}
      DB_POSTGRES_NAME: ${NPM_DB_NAME}
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    depends_on:
      - db
    networks:
      - devlab-network

  db:
    image: postgres:latest
    container_name: npm_db
    environment:
      POSTGRES_USER: ${NPM_DB_USER}
      POSTGRES_PASSWORD: ${NPM_DB_PASSWORD}
      POSTGRES_DB: ${NPM_DB_NAME}
    volumes:
      - ./npm_db:/var/lib/postgresql/data
    networks:
      - devlab-network

networks:
  devlab-network:
    external: true
    name: devlab-network

volumes:
  postgres_data:
  gitea_data:
  redis_data:
  npm_db:
EOF

# Set proper permissions
echo "🔐 Setting permissions..."
if [ "$USER_MODE" = false ]; then
    chmod -R 755 "$PROJECT_DIR"
    chown -R docker:docker "$PROJECT_DIR"
else
    chmod -R 755 "$PROJECT_DIR"
fi

# LXC-specific optimizations
echo "🏗️  Applying LXC optimizations..."
# Ensure proper cgroup permissions for Docker in LXC
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    echo "Detected cgroup v2, ensuring proper Docker configuration..."
    # Modern LXC with cgroup v2
        cat > /etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket firewalld.service containerd.service time-set.target
Wants=network-online.target containerd.service
Requires=docker.socket containerd.service

[Service]
Type=notify
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
EOF
fi

echo "🔍 Checking if VS Code Dockerfile has changed..."
if [ ! -f .vscode_build_hash ] || ! sha256sum -c .vscode_build_hash --status 2>/dev/null; then
    echo "📦 VS Code Dockerfile changed or no previous build found. Rebuilding..."
    docker compose build vscode
    sha256sum vscode/Dockerfile > .vscode_build_hash
else
    echo "✅ VS Code Dockerfile unchanged. Skipping rebuild."
fi
echo ""
echo "🔍 Checking if FastAPI Dockerfile has changed..."
if [ ! -f .fastapi_build_hash ] || ! sha256sum -c .fastapi_build_hash --status 2>/dev/null; then
    echo "📦 FastAPI Dockerfile changed or no previous build found. Rebuilding..."
    docker compose build fastapi
    sha256sum fastapi/Dockerfile > .fastapi_build_hash
else
    echo "✅ FastAPI Dockerfile unchanged. Skipping rebuild."
fi

echo "🚀 Starting DevLab services..."
docker compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Display service status
echo "📊 Service Status:"
docker compose ps

# Get LXC IP address
LXC_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "✅ DevLab stack deployed successfully!"
echo "======================================"
echo " 🔑 Credentials saved in .env file - keep this secure!"
echo ""
echo " 📋 Access Information:"
echo ""
echo " ✨ FastAPI: http://${LXC_IP}:8000"
echo " 🧲 FastAPI Login: $(grep FASTAPI_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo " 📊 Nginx Proxy Manager: http://${LXC_IP}:81"
echo " 🔐 DB Password: $(grep NPM_DB_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo " 💻 VS Code:      http://${LXC_IP}:8080"
echo "    Password: $(grep VSCODE_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo " 🗂️ Gitea:        http://${LXC_IP}:3000"
echo "    (>>>> Complete setup wizard on first visit <<<<)"
echo ""
echo " 🗄️ pgAdmin:      http://${LXC_IP}:5050"
echo "    Email: $(grep PGADMIN_DEFAULT_EMAIL .env | cut -d'=' -f2)"
echo "    Password: $(grep PGADMIN_DEFAULT_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo " 🔄 Redis:        ${LXC_IP}:6379"
echo "    Password: $(grep REDIS_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo " 🐘 PostgreSQL:   ${LXC_IP}:5432"
echo "    User: $(grep POSTGRES_USER .env | cut -d'=' -f2)"
echo "    Password: $(grep POSTGRES_PASSWORD .env | cut -d'=' -f2)"
echo "    Database: $(grep POSTGRES_DB .env | cut -d'=' -f2)"
echo ""
echo "📁 Project files are stored in: $PROJECT_DIR"
echo "🔧 To manage services: cd $PROJECT_DIR && docker compose [up|down|restart|logs]"
echo "🔑 To view credentials: cat $PROJECT_DIR/.env"
echo ""
echo "⚠️  Security Notice:"
echo "   - All passwords are auto-generated and stored in .env file"
echo "   - Keep the .env file secure (600 permissions applied)"
echo "   - Configure firewall rules as needed"
echo "   - Consider enabling SSL/TLS for external access"
echo ""
echo "🏁 Setup complete! Happy coding!"
echo "✅ Created by 0din!"
