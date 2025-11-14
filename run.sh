#!/bin/bash
set -e

# Load environment variables from .env file
if [ -f .env ]; then
  echo "[INFO] Loading configuration from .env file..."
  # Read .env file line by line, handling comments and empty lines
  set -a
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and lines starting with #
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Remove inline comments (everything after #)
    line=$(echo "$line" | sed 's/#.*$//')
    # Skip if line is empty after removing comments
    [[ -z "$line" ]] && continue
    # Trim whitespace
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Remove quotes from value if present (handles KEY="value" or KEY='value')
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      # Remove surrounding quotes (single or double)
      value=$(echo "$value" | sed "s/^['\"]//;s/['\"]\$//")
      line="${key}=${value}"
    fi
    # Export the variable
    export "$line"
  done < .env
  set +a
else
  echo "[ERROR] .env file not found!"
  if [ -f .env.example ]; then
    echo "[INFO] Please create a .env file based on .env.example"
    echo "[INFO] Example: cp .env.example .env"
  else
    echo "[ERROR] .env.example template file not found!"
    echo "[ERROR] Please ensure .env.example exists in the project directory"
  fi
  echo "[INFO] Then edit .env with your configuration"
  exit 1
fi

# Trim whitespace from all variables
DOMAIN_NAME=$(echo "$DOMAIN_NAME" | xargs)
SUBDOMAIN=$(echo "$SUBDOMAIN" | xargs)
EMAIL=$(echo "$EMAIL" | xargs)
DB_POSTGRESDB_PASSWORD=$(echo "$DB_POSTGRESDB_PASSWORD" | xargs)

# Validate required variables
if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL" ] || [ -z "$SUBDOMAIN" ] || [ -z "$DB_POSTGRESDB_PASSWORD" ]; then
  echo "[ERROR] Missing required variables in .env file!"
  echo "[ERROR] Required: DOMAIN_NAME, EMAIL, SUBDOMAIN, DB_POSTGRESDB_PASSWORD"
  exit 1
fi

# Validate domain format (basic check)
if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
  echo "[ERROR] Invalid DOMAIN_NAME format: $DOMAIN_NAME"
  echo "[ERROR] Expected format: example.com"
  exit 1
fi

# Validate email format (basic check)
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "[ERROR] Invalid EMAIL format: $EMAIL"
  echo "[ERROR] Expected format: user@example.com"
  exit 1
fi

# Check if running on Ubuntu/Debian
if ! command -v apt &> /dev/null; then
  echo "[WARN] This script is designed for Ubuntu/Debian systems."
  echo "[WARN] Docker installation may not work on other distributions."
  echo "[WARN] Please install Docker manually if needed."
fi

# Update package lists (but don't upgrade everything automatically)
# Users can upgrade manually if desired: sudo apt upgrade
if command -v apt &> /dev/null; then
  echo "[INFO] Updating package lists..."
  sudo apt update -y
fi

# Ensure curl is installed (needed for IP detection and Docker installation)
if ! command -v curl &> /dev/null; then
  echo "[INFO] Installing curl..."
  sudo apt install -y curl
fi

# Check and install Docker if not present
echo "[INFO] Checking for Docker installation..."
if ! command -v docker &> /dev/null; then
  echo "[INFO] Docker not found. Installing Docker..."
  
  # Install prerequisites
  sudo apt install -y ca-certificates curl gnupg lsb-release
  
  # Add Docker's official GPG key
  sudo mkdir -p /etc/apt/keyrings
  # Remove existing key if present to avoid overwrite prompt
  sudo rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  
  # Set up the repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # Install Docker Engine
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  
  # Start and enable Docker service
  sudo systemctl start docker
  sudo systemctl enable docker
  
  # Add current user to docker group (optional, for non-sudo docker commands)
  sudo usermod -aG docker $USER
  
  echo "[INFO] Docker installed successfully!"
else
  echo "[INFO] Docker is already installed."
fi

# Check and install Docker Compose if not present
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null && ! sudo docker compose version &> /dev/null; then
  echo "[INFO] Docker Compose not found. Installing Docker Compose..."
  
  # Docker Compose plugin should be installed with docker-ce, but if not, install standalone
  if ! sudo docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "[INFO] Docker Compose (standalone) installed successfully!"
  else
    echo "[INFO] Docker Compose plugin is available (requires sudo)."
  fi
else
  echo "[INFO] Docker Compose is already installed."
fi

# Verify Docker is running
if ! sudo systemctl is-active --quiet docker; then
  echo "[INFO] Starting Docker service..."
  sudo systemctl start docker
fi

# Determine if we need sudo for docker commands
# (needed if Docker was just installed and user hasn't logged out/in)
if docker info &> /dev/null; then
  DOCKER_CMD="docker"
  COMPOSE_CMD="docker compose"
else
  echo "[INFO] Using sudo for Docker commands (group membership will take effect after logout/login)"
  DOCKER_CMD="sudo docker"
  COMPOSE_CMD="sudo docker compose"
fi

echo "[INFO] Detecting public IP..."
DETECTED_IP=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || curl -s --max-time 10 ifconfig.co 2>/dev/null || echo "")

if [ -z "$DETECTED_IP" ]; then
  echo "[WARN] Could not detect external IP automatically."
  echo "[WARN] You may need to set EXTERNAL_IP manually in .env file."
  if [ -z "$EXTERNAL_IP" ]; then
    echo "[ERROR] EXTERNAL_IP is not set and could not be detected."
    echo "[ERROR] Please set EXTERNAL_IP in your .env file."
    exit 1
  else
    echo "[INFO] Using EXTERNAL_IP from .env: $EXTERNAL_IP"
    DETECTED_IP="$EXTERNAL_IP"
  fi
else
  echo "[INFO] Detected external IP: $DETECTED_IP"
fi

# Update EXTERNAL_IP in .env if not set or different
if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" != "$DETECTED_IP" ]; then
  echo "[INFO] Updating EXTERNAL_IP in .env file..."
  # Update EXTERNAL_IP in .env file
  if grep -q "^EXTERNAL_IP=" .env; then
    sed -i "s|^EXTERNAL_IP=.*|EXTERNAL_IP=${DETECTED_IP}|" .env
  else
    echo "EXTERNAL_IP=${DETECTED_IP}" >> .env
  fi
  export EXTERNAL_IP=$DETECTED_IP
else
  echo "[INFO] Using EXTERNAL_IP from .env: $EXTERNAL_IP"
fi

# Ensure Let's Encrypt directory exists
mkdir -p ./letsencrypt/www

# Construct full domain name (trimmed)
FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN_NAME}"
FULL_DOMAIN=$(echo "$FULL_DOMAIN" | xargs)

echo "[STEP 1] Checking if a certificate already exists..."
if [ ! -f "./letsencrypt/live/${FULL_DOMAIN}/fullchain.pem" ]; then
  echo "[STEP 2] Stopping any running nginx container to free port 80..."
  $COMPOSE_CMD stop nginx 2>/dev/null || true
  $COMPOSE_CMD rm -f nginx 2>/dev/null || true
  
  # Check if port 80 is available
  if command -v netstat &> /dev/null; then
    if netstat -tuln | grep -q ":80 "; then
      echo "[WARN] Port 80 appears to be in use. Certbot needs port 80 for HTTP-01 challenge."
      echo "[WARN] Please ensure port 80 is available or stop the service using it."
    fi
  fi
  
  echo "[STEP 3] Obtaining initial Let's Encrypt certificate..."
  # Debug: Show actual variable values (with length to detect hidden characters)
  echo "[DEBUG] Domain value: '$FULL_DOMAIN' (length: ${#FULL_DOMAIN})"
  echo "[DEBUG] Email value: '$EMAIL' (length: ${#EMAIL})"
  
  # Trim any whitespace from variables and re-export
  FULL_DOMAIN=$(echo "$FULL_DOMAIN" | xargs)
  EMAIL=$(echo "$EMAIL" | xargs)
  export FULL_DOMAIN EMAIL
  
  echo "[INFO] Domain: $FULL_DOMAIN"
  echo "[INFO] Email: $EMAIL"
  echo "[INFO] Running certbot with verbose output..."
  
  # Use docker run directly for initial certificate (service definition is for renewal loop)
  if ! $DOCKER_CMD run --rm \
    --name certbot_initial \
    -p 80:80 \
    -v "$(pwd)/letsencrypt:/etc/letsencrypt" \
    certbot/certbot certonly --standalone \
    --agree-tos --non-interactive \
    --preferred-challenges http \
    -d "$FULL_DOMAIN" -m "$EMAIL" -v; then
    echo "[ERROR] Failed to obtain certificate!"
    echo "[ERROR] Please check:"
    echo "  1. Domain $FULL_DOMAIN resolves to this server's IP"
    echo "  2. Port 80 is accessible from the internet"
    echo "  3. Firewall allows incoming connections on port 80"
    exit 1
  fi
  
  echo "[INFO] Certificate obtained successfully!"
else
  echo "[INFO] Existing certificate found — skipping initial issuance."
fi

echo "[STEP 4] Starting all services (postgres, n8n, nginx)..."
$COMPOSE_CMD up -d

echo
echo "✅ n8n is now running with SSL certificates."
echo
echo "n8n URL: https://${FULL_DOMAIN}"
echo
echo "Database:"
echo "  Host: postgres"
echo "  Port: 5432"
echo "  Database: ${DB_POSTGRESDB_DATABASE:-n8n}"
echo "  User: ${DB_POSTGRESDB_USER:-n8n}"
echo
echo "Logs:"
echo "  n8n logs        → $COMPOSE_CMD logs -f n8n"
echo "  postgres logs  → $COMPOSE_CMD logs -f postgres"
echo "  nginx logs     → $COMPOSE_CMD logs -f nginx"
echo "  (or use: $DOCKER_CMD logs -f <container_name>)"
echo
echo "[INFO] SSL certificates are valid for 90 days. Renew manually when needed."

