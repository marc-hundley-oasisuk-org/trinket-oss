#!/usr/bin/env bash
set -Eeuo pipefail

echo "======================================="
echo "Trinket OSS Minimal Hyper-V Docker Setup"
echo "======================================="

INSTALL_DIR="${INSTALL_DIR:-/opt/trinket-oss}"
#TRINKET_REPO="${TRINKET_REPO:-https://github.com/trinketapp/trinket-oss.git}"
PRIMARY_REPO="https://github.com/marc-hundley-oasisuk-org/trinket-oss.git"
FALLBACK_REPO="https://github.com/trinketapp/trinket-oss.git"

COMPOSE_FILE="${INSTALL_DIR}/docker-compose.minimal.yml"

# Platform hardening defaults.
# These can be supplied as environment variables for non-interactive builds.
RUN_APT_UPGRADE="${RUN_APT_UPGRADE:-}"
ENABLE_UNATTENDED_UPGRADES="${ENABLE_UNATTENDED_UPGRADES:-}"
ENABLE_UFW="${ENABLE_UFW:-}"

# For your own fork, run:
# sudo TRINKET_REPO="https://github.com/marc-hundley-oasisuk-org/trinket-oss.git" ./setup-trinket-oss.sh

log() {
  echo ""
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

is_true() {
  case "${1:-}" in
    true|TRUE|yes|YES|y|Y|1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

need_root() {
  if [ "${EUID}" -ne 0 ]; then
    die "Please run this script with sudo."
  fi
}

detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  else
    die "Docker Compose is not installed."
  fi

  echo "Using Compose command: ${COMPOSE_CMD}"
}

prompt_for_platform_hardening() {
  if [ ! -t 0 ]; then
    RUN_APT_UPGRADE="${RUN_APT_UPGRADE:-false}"
    ENABLE_UNATTENDED_UPGRADES="${ENABLE_UNATTENDED_UPGRADES:-false}"
    ENABLE_UFW="${ENABLE_UFW:-false}"
    return
  fi

  if [ -z "${RUN_APT_UPGRADE:-}" ]; then
    echo ""
    read -rp "Run apt-get upgrade before installing Trinket? [Y/N] (default Y): " APT_UPGRADE_REPLY

    case "${APT_UPGRADE_REPLY:-Y}" in
      [Yy]*)
        RUN_APT_UPGRADE="true"
        ;;
      *)
        RUN_APT_UPGRADE="false"
        ;;
    esac
  fi

  if [ -z "${ENABLE_UNATTENDED_UPGRADES:-}" ]; then
    echo ""
    read -rp "Enable unattended security updates? [Y/N] (default Y): " UNATTENDED_REPLY

    case "${UNATTENDED_REPLY:-Y}" in
      [Yy]*)
        ENABLE_UNATTENDED_UPGRADES="true"
        ;;
      *)
        ENABLE_UNATTENDED_UPGRADES="false"
        ;;
    esac
  fi

  if [ -z "${ENABLE_UFW:-}" ]; then
    echo ""
    read -rp "Enable basic UFW firewall hardening? [Y/N] (default N): " UFW_REPLY

    case "${UFW_REPLY:-N}" in
      [Yy]*)
        ENABLE_UFW="true"
        ;;
      *)
        ENABLE_UFW="false"
        ;;
    esac
  fi
}

apt_update_and_upgrade() {
  log "Updating apt package lists"

  apt-get update

  if is_true "${RUN_APT_UPGRADE}"; then
    log "Running safe apt package upgrade"

    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"
  else
    log "Skipping apt package upgrade"
  fi
}

#install_required_packages() {
#  log "Installing required OS packages"
#
#  REQUIRED_PACKAGES=(
#    ca-certificates
#    curl
#    git
#    gnupg
#    openssl
#    docker.io
#    docker-compose
#  )

#  if is_true "${ENABLE_UNATTENDED_UPGRADES}"; then
#    REQUIRED_PACKAGES+=(unattended-upgrades)
#  fi

#  if is_true "${ENABLE_UFW}"; then
#    REQUIRED_PACKAGES+=(ufw)
#  fi

#  DEBIAN_FRONTEND=noninteractive apt-get install -y \
#    "${REQUIRED_PACKAGES[@]}"
#}

install_required_packages() {
  log "Installing required OS packages"

  REQUIRED_PACKAGES=(
    ca-certificates
    curl
    git
    gnupg
    openssl
    docker.io
  )

  if is_true "${ENABLE_UNATTENDED_UPGRADES}"; then
    REQUIRED_PACKAGES+=(unattended-upgrades)
  fi

  if is_true "${ENABLE_UFW}"; then
    REQUIRED_PACKAGES+=(ufw)
  fi

  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    "${REQUIRED_PACKAGES[@]}"

  # Prefer Docker Compose v2 plugin where available.
  if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
    log "Installing Docker Compose v2 plugin"
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
  else
    log "Docker Compose plugin not available, installing legacy docker-compose"
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose
  fi
}

configure_unattended_upgrades() {
  if ! is_true "${ENABLE_UNATTENDED_UPGRADES}"; then
    log "Unattended security updates not enabled"
    return
  fi

  log "Enabling unattended security updates"

  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
}

configure_ufw() {
  if ! is_true "${ENABLE_UFW}"; then
    log "UFW firewall hardening not enabled"
    return
  fi

  log "Configuring UFW firewall"

  ufw default deny incoming
  ufw default allow outgoing

  # Allow remote administration before enabling the firewall.
  ufw allow 22/tcp

  # Allow the production Trinket HTTPS endpoint.
  ufw allow 443/tcp

  ufw --force enable
  ufw status verbose
}

install_docker() {
  log "Installing Docker and Docker Compose if required"

  prompt_for_platform_hardening
  apt_update_and_upgrade
  install_required_packages
  configure_unattended_upgrades
  configure_ufw

  systemctl enable docker
  systemctl start docker

  docker --version
  detect_compose
}

cleanup_apt() {
  log "Cleaning up apt packages"

  apt-get autoremove -y
  apt-get autoclean -y
}


clone_or_update_repo() {
  log "Preparing repository at ${INSTALL_DIR}"

  if [ -d "${INSTALL_DIR}/.git" ]; then
    log "Repository already exists, skipping clone"
    cd "${INSTALL_DIR}"
    return
  fi

  mkdir -p "$(dirname "${INSTALL_DIR}")"

  log "Testing access to primary repo..."
  if git ls-remote "${PRIMARY_REPO}" &>/dev/null; then
    log "✅ Primary repo reachable, cloning..."
    git clone "${PRIMARY_REPO}" "${INSTALL_DIR}"
  else
    log "⚠️ Primary repo not reachable, falling back to upstream..."

    if git ls-remote "${FALLBACK_REPO}" &>/dev/null; then
      log "✅ Upstream repo reachable, cloning..."
      git clone "${FALLBACK_REPO}" "${INSTALL_DIR}"
    else
      die "❌ Failed to access both repositories"
    fi
  fi

  cd "${INSTALL_DIR}"

  # Add upstream for tracking (safe if already exists)
  git remote add upstream "${FALLBACK_REPO}" 2>/dev/null || true
}


prompt_for_configuration() {
  if [ ! -t 0 ]; then
    return
  fi

  if [ -z "${TRINKET_HTTPS_ENABLED:-}" ]; then
    echo ""
    read -rp "Enable HTTPS? [Y/N] (default Y): " HTTPS_REPLY

    case "${HTTPS_REPLY:-Y}" in
      [Yy]*)
        TRINKET_HTTPS_ENABLED="true"
        ;;
      *)
        TRINKET_HTTPS_ENABLED="false"
        ;;
    esac
  fi

  if [ "${TRINKET_HTTPS_ENABLED}" = "true" ]; then
    if [ -z "${TRINKET_HOSTNAME:-}" ]; then
      read -rp "Hostname or IP address: " TRINKET_HOSTNAME
    fi

    if [ -z "${TRINKET_PORT:-}" ]; then
      read -rp "HTTPS port (default 443): " TRINKET_PORT
      TRINKET_PORT="${TRINKET_PORT:-443}"
    fi

    if [ -z "${TRINKET_HTTPS_CERT_SOURCE:-}" ] && [ -z "${TRINKET_HTTPS_KEY_SOURCE:-}" ]; then
      read -rp "Use an existing certificate/key? [Y/N] (default N): " CERT_REPLY

      case "${CERT_REPLY:-N}" in
        [Yy]*)
          read -rp "Certificate path: " TRINKET_HTTPS_CERT_SOURCE
          read -rp "Key path: " TRINKET_HTTPS_KEY_SOURCE
          ;;
      esac
    fi
  fi

  if [ -z "${MICROSOFT_SSO_ENABLED:-}" ]; then
    echo ""
    read -rp "Enable Microsoft Entra sign-in? [Y/N] (default N): " MS_REPLY

    case "${MS_REPLY:-N}" in
      [Yy]*)
        MICROSOFT_SSO_ENABLED="true"
        ;;
      *)
        MICROSOFT_SSO_ENABLED="false"
        ;;
    esac
  fi

  if [ "${MICROSOFT_SSO_ENABLED}" = "true" ]; then
      if [ -z "${MICROSOFT_TENANT_ID:-}" ]; then
        read -rp "Directory (Tenant) ID: " MICROSOFT_TENANT_ID
      fi

      if [ -z "${MICROSOFT_TENANT_ID}" ]; then
        echo "❌ Directory (Tenant) ID cannot be blank"
        exit 1
      fi

      if [ -z "${MICROSOFT_CLIENT_ID:-}" ]; then
        read -rp "Application (Client) ID: " MICROSOFT_CLIENT_ID
      fi

      if [ -z "${MICROSOFT_CLIENT_ID}" ]; then
        echo "❌ Application (Client) ID cannot be blank"
        exit 1
      fi

      if [ -z "${MICROSOFT_CLIENT_SECRET:-}" ]; then
        read -rsp "Client Secret: " MICROSOFT_CLIENT_SECRET
        echo ""

        if [ -z "${MICROSOFT_CLIENT_SECRET}" ]; then
          echo "❌ Client secret cannot be blank"
          exit 1
        fi

        echo "✓ Client secret received (${#MICROSOFT_CLIENT_SECRET} characters)"
      fi

      if [ -z "${MICROSOFT_CALLBACK_URL:-}" ]; then
        read -rp "Callback URL: " MICROSOFT_CALLBACK_URL
      fi

      if [ -z "${MICROSOFT_CALLBACK_URL}" ]; then
        echo "❌ Callback URL cannot be blank"
        exit 1
      fi

      if [ -z "${MICROSOFT_ALLOWED_DOMAINS:-}" ]; then
        read -rp "Allowed domains (comma separated, blank = unrestricted): " MICROSOFT_ALLOWED_DOMAINS
      fi

      if [ -z "${MICROSOFT_AUTO_CREATE_USERS:-}" ]; then
        read -rp "Automatically create users? [Y/N] (default Y): " AUTO_REPLY

        case "${AUTO_REPLY:-Y}" in
          [Yy]*)
            MICROSOFT_AUTO_CREATE_USERS="true"
            ;;
          *)
            MICROSOFT_AUTO_CREATE_USERS="false"
            ;;
        esac
      fi
    fi
}



create_local_config() {
  log "Creating minimal local.yaml"

  mkdir -p "${INSTALL_DIR}/config"

  SESSION_SECRET="$(openssl rand -base64 48 | tr -d '\n')"

  VM_IP=$(hostname -I | awk '{print $1}')
  prompt_for_configuration
  TRINKET_PROTOCOL="${TRINKET_PROTOCOL:-http}"
  TRINKET_HOSTNAME="${TRINKET_HOSTNAME:-${VM_IP}}"

  if [ "${TRINKET_HTTPS_ENABLED:-false}" = "true" ]; then
    TRINKET_PORT="${TRINKET_PORT:-443}"
  else
    TRINKET_PORT="${TRINKET_PORT:-3000}"
  fi

  TRINKET_HTTPS_ENABLED="${TRINKET_HTTPS_ENABLED:-false}"
  TRINKET_HTTPS_CERT_SOURCE="${TRINKET_HTTPS_CERT_SOURCE:-}"
  TRINKET_HTTPS_KEY_SOURCE="${TRINKET_HTTPS_KEY_SOURCE:-}"
  TRINKET_CERT_DIR="${INSTALL_DIR}/certs"
  TRINKET_CONTAINER_CERT_PATH="/usr/local/node/trinket/certs/trinket.crt"
  TRINKET_CONTAINER_KEY_PATH="/usr/local/node/trinket/certs/trinket.key"

  if [ "${TRINKET_HTTPS_ENABLED}" = "true" ]; then
    TRINKET_PROTOCOL="https"
    mkdir -p "${TRINKET_CERT_DIR}"

    if [ -n "${TRINKET_HTTPS_CERT_SOURCE}" ] && [ -n "${TRINKET_HTTPS_KEY_SOURCE}" ]; then
      log "Copying provided HTTPS certificate and key"
      cp "${TRINKET_HTTPS_CERT_SOURCE}" "${TRINKET_CERT_DIR}/trinket.crt"
      cp "${TRINKET_HTTPS_KEY_SOURCE}" "${TRINKET_CERT_DIR}/trinket.key"
    elif [ ! -f "${TRINKET_CERT_DIR}/trinket.crt" ] || [ ! -f "${TRINKET_CERT_DIR}/trinket.key" ]; then
      log "Generating self-signed HTTPS certificate for ${TRINKET_HOSTNAME}"

      if [[ "${TRINKET_HOSTNAME}" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
        CERT_SAN="IP:${TRINKET_HOSTNAME}"
      else
        CERT_SAN="DNS:${TRINKET_HOSTNAME}"
      fi

      openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${TRINKET_CERT_DIR}/trinket.key" \
        -out "${TRINKET_CERT_DIR}/trinket.crt" \
        -subj "/CN=${TRINKET_HOSTNAME}" \
        -addext "subjectAltName=${CERT_SAN}"
    fi

    chmod 644 "${TRINKET_CERT_DIR}/trinket.key"
    chmod 644 "${TRINKET_CERT_DIR}/trinket.crt"
    chown -R root:root "${TRINKET_CERT_DIR}"

    TRINKET_COOKIE_SECURE="true"
    TRINKET_HTTPS_KEY_PATH="${TRINKET_CONTAINER_KEY_PATH}"
    TRINKET_HTTPS_CERT_PATH="${TRINKET_CONTAINER_CERT_PATH}"
  else
    TRINKET_COOKIE_SECURE="false"
    TRINKET_HTTPS_KEY_PATH=""
    TRINKET_HTTPS_CERT_PATH=""
  fi

  MICROSOFT_SSO_ENABLED="${MICROSOFT_SSO_ENABLED:-false}"
  MICROSOFT_TENANT_ID="${MICROSOFT_TENANT_ID:-}"
  MICROSOFT_CLIENT_ID="${MICROSOFT_CLIENT_ID:-}"
  MICROSOFT_CLIENT_SECRET="${MICROSOFT_CLIENT_SECRET:-}"
  MICROSOFT_CALLBACK_URL="${MICROSOFT_CALLBACK_URL:-${TRINKET_PROTOCOL}://${TRINKET_HOSTNAME}:${TRINKET_PORT}/auth/microsoft/callback}"
  MICROSOFT_AUTO_CREATE_USERS="${MICROSOFT_AUTO_CREATE_USERS:-true}"
  MICROSOFT_ALLOWED_DOMAINS="${MICROSOFT_ALLOWED_DOMAINS:-}"

  if [ -z "${MICROSOFT_ALLOWED_DOMAINS}" ]; then
    MICROSOFT_ALLOWED_DOMAINS_BLOCK="      allowedDomains: []"
  else
    MICROSOFT_ALLOWED_DOMAINS_BLOCK="      allowedDomains:"
    IFS=',' read -ra DOMAIN_LIST <<< "${MICROSOFT_ALLOWED_DOMAINS}"
    for DOMAIN in "${DOMAIN_LIST[@]}"; do
      DOMAIN="$(echo "${DOMAIN}" | xargs)"
      if [ -n "${DOMAIN}" ]; then
        MICROSOFT_ALLOWED_DOMAINS_BLOCK="${MICROSOFT_ALLOWED_DOMAINS_BLOCK}
        - '${DOMAIN}'"
      fi
    done
  fi

  cat > "${INSTALL_DIR}/config/local.yaml" <<EOF
# Generated by setup-trinket-oss.sh
# Minimal Hyper-V Docker test configuration.
# Redis is intentionally not configured.

app:
  hostname: 0.0.0.0
  port: ${TRINKET_PORT}
  url:
    hostname: ${TRINKET_HOSTNAME}
    port: ${TRINKET_PORT}
    protocol: ${TRINKET_PROTOCOL}
  basePath: "/"

  https:
    enabled: ${TRINKET_HTTPS_ENABLED}
    keyPath: '${TRINKET_HTTPS_KEY_PATH}'
    certPath: '${TRINKET_HTTPS_CERT_PATH}'

  plugins:
    session:
      cookieOptions:
        password: "${SESSION_SECRET}"
        isSecure: ${TRINKET_COOKIE_SECURE}
  sitename: 'OCL Computer Science'
  supportemail: 'servicedesk@oasisuk.org'
  #logo: '/img/my-logo.png'
  embed:
    skulpt:
      local: true
      min: true

  auth:
    microsoft:
      enabled: ${MICROSOFT_SSO_ENABLED}
      tenantId: '${MICROSOFT_TENANT_ID}'
      clientID: '${MICROSOFT_CLIENT_ID}'
      clientSecret: '${MICROSOFT_CLIENT_SECRET}'
      callbackURL: '${MICROSOFT_CALLBACK_URL}'
${MICROSOFT_ALLOWED_DOMAINS_BLOCK}
      autoCreateUsers: ${MICROSOFT_AUTO_CREATE_USERS}

db:
  mongo:
      host: 127.0.0.1
      port: 27017
      database: trinket

  #Redis is optional - sessions work without it
  redis:
    enabled: false

features:
  trinkets:
    python: true
    html: true
    python3: false

  assets: false
  courses: true
  accessibilityToggle: false

cdn:
  enabled: false

assets:
  useCDN: false

queue:
  enabled: false

exports:
  enabled: false

aws:
  buckets:
    cdn:
      host: ''

    vendorassets:
      host: ''

    skulpt:
      host: ''

  enabled: false
EOF

  chmod 644 "${INSTALL_DIR}/config/local.yaml"
}

create_minimal_compose() {
  log "Creating minimal Docker Compose file"

  cat > "${COMPOSE_FILE}" <<EOF
version: "3.8"

services:
  mongodb:
    image: mongo:5
    container_name: mongodb
    restart: unless-stopped
    ports:
      - "127.0.0.1:27017:27017"
    volumes:
      - mongodb_data:/data/db

  app:
    build:
      context: .
      dockerfile: Dockerfile
    image: trinket/app:latest
    container_name: trinket
    restart: unless-stopped
    cap_add:
      - NET_BIND_SERVICE
    network_mode: host
    depends_on:
      - mongodb
    environment:
      NODE_ENV: ""
    volumes:
      - ./config/local.yaml:/usr/local/node/trinket/config/local.yaml:ro
      - ./certs:/usr/local/node/trinket/certs:ro

volumes:
  mongodb_data:
EOF
}

clean_previous_stacks() {
  log "Cleaning previous Trinket containers"

  cd "${INSTALL_DIR}"

  # Stop minimal stack.
  ${COMPOSE_CMD} -f "${COMPOSE_FILE}" down || true

  # Stop upstream/default stack if it was accidentally used.
  if [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
    ${COMPOSE_CMD} -f "${INSTALL_DIR}/docker-compose.yml" down || true
  fi

  docker rm -f trinket mongodb redis 2>/dev/null || true
}

build_and_start() {
  log "Building and starting minimal stack"

  cd "${INSTALL_DIR}"

  ${COMPOSE_CMD} -f "${COMPOSE_FILE}" build --no-cache app
  ${COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d
}

validate_runtime() {
  log "Validating runtime"

  echo ""
  echo "Docker containers:"
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

  echo ""
  echo "Checking Trinket logs:"
  docker logs trinket --tail=80 || true

  echo ""
  TEST_URL="${TRINKET_PROTOCOL}://localhost:${TRINKET_PORT}"
  echo "Testing local response from VM at ${TEST_URL}..."

  for i in $(seq 1 30); do
    if curl -k -fsS --max-time 5 "${TEST_URL}" >/tmp/trinket-http-test.html; then
      echo "✅ Trinket responded successfully on ${TEST_URL}"
      return 0
    fi

    if ! docker ps --format '{{.Names}}' | grep -qx trinket; then
      echo "❌ Trinket container is not running."
      docker logs trinket --tail=150 || true
      exit 1
    fi

    sleep 2
  done

  echo "❌ Trinket did not return a successful HTTP response."
  echo ""
  echo "Useful diagnostics:"
  echo "  sudo docker logs trinket --tail=150"
  echo "  sudo docker ps"
  echo "  sudo ss -lntp | grep ':3000\\|:27017'"
  exit 1
}

print_summary() {
  VM_IP="$(hostname -I | awk '{print $1}')"

  echo ""
  echo "======================================="
  echo "✅ Trinket OSS minimal setup complete"
  echo "======================================="
  echo ""
  echo "Try from inside the VM:"
  if [ "${TRINKET_PROTOCOL}" = "https" ]; then
    echo "  curl -k https://localhost:${TRINKET_PORT}"
  else
    echo "  curl http://localhost:${TRINKET_PORT}"
  fi
  echo ""
  echo "Try from the Hyper-V host browser:"
  echo "  ${TRINKET_PROTOCOL}://${TRINKET_HOSTNAME}:${TRINKET_PORT}"
  echo ""
  echo "Useful commands:"
  echo "  cd ${INSTALL_DIR}"
  echo "  sudo ${COMPOSE_CMD} -f ${COMPOSE_FILE} logs -f"
  echo "  sudo ${COMPOSE_CMD} -f ${COMPOSE_FILE} restart"
  echo "  sudo docker logs trinket --tail=100"
  echo ""
  echo "Important:"
  echo "  Always use the minimal compose file:"
  echo "  sudo ${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d"
  echo ""
  echo "Do not use plain:"
  echo "  sudo docker-compose up -d"
  echo ""
  echo "Plain docker-compose uses the upstream docker-compose.yml and will start Redis again."
  echo ""
}

main() {
  need_root
  install_docker
  clone_or_update_repo
  create_local_config
  create_minimal_compose
  clean_previous_stacks
  build_and_start
  validate_runtime
  cleanup_apt
  print_summary
}

main "$@"
