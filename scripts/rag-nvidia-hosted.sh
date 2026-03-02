#!/usr/bin/env bash
# ==============================================================================
# NVIDIA RAG Blueprint — RTX 4070 Management Script
# ==============================================================================
# Usage: ./scripts/rag-nvidia-hosted.sh <command>
#
#   setup    Check prerequisites and authenticate with NGC
#   start    Deploy all services
#   status   Show container health, GPU usage, and API status
#   logs     Tail service logs  (optional: logs <service-name>)
#   stop     Stop all services (keeps data volumes)
#   clean    Stop all services and remove all data volumes
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/deploy/compose/docker-compose-nvidia-hosted.yaml"
ENV_FILE="$PROJECT_ROOT/deploy/compose/nvidia-hosted-cuvs.env"

# Service ports
RAG_PORT=8081
INGESTOR_PORT=8082
FRONTEND_PORT=8090

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}$*${RESET}"; }

# ------------------------------------------------------------------------------
cmd_setup() {
    section "=== Prerequisite Check ==="
    local failed=0

    # NVIDIA driver
    if nvidia-smi &>/dev/null; then
        local gpu
        gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        ok "NVIDIA driver: $gpu"
    else
        error "nvidia-smi failed — install NVIDIA drivers first"
        failed=1
    fi

    # Docker
    if docker info &>/dev/null; then
        local docker_ver
        docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
        ok "Docker: $docker_ver"
    else
        error "Docker not running — start Docker or install Docker Engine"
        failed=1
    fi

    # Docker Compose v2
    if docker compose version &>/dev/null; then
        local compose_ver
        compose_ver=$(docker compose version --short 2>/dev/null)
        # Check minimum version 2.29.1
        local major minor patch
        IFS='.' read -r major minor patch <<< "$compose_ver"
        if [[ "$major" -gt 2 ]] || [[ "$major" -eq 2 && "$minor" -gt 29 ]] || \
           [[ "$major" -eq 2 && "$minor" -eq 29 && "${patch%%[^0-9]*}" -ge 1 ]]; then
            ok "Docker Compose: v$compose_ver"
        else
            warn "Docker Compose v$compose_ver found — v2.29.1 or later required"
        fi
    else
        error "Docker Compose v2 not found"
        failed=1
    fi

    # NVIDIA Container Toolkit
    if docker run --rm --gpus all --entrypoint nvidia-smi nvidia/cuda:12.4.0-base-ubuntu22.04 &>/dev/null; then
        ok "NVIDIA Container Toolkit: GPU accessible in Docker"
    else
        warn "GPU not accessible in Docker — installing NVIDIA Container Toolkit..."
        if command -v apt-get &>/dev/null; then
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
                sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
            sudo apt-get update -q
            sudo apt-get install -y -q nvidia-container-toolkit
            sudo nvidia-ctk runtime configure --runtime=docker
            sudo systemctl restart docker
            ok "NVIDIA Container Toolkit installed"
        else
            error "Auto-install requires apt-get — install manually: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
            failed=1
        fi
    fi

    # NGC API key
    if [[ -z "${NGC_API_KEY:-}" ]]; then
        error "NGC_API_KEY is not set"
        echo "  Get a key at: https://org.ngc.nvidia.com/setup/api-keys"
        echo "  Then run:     export NGC_API_KEY=\"nvapi-...\""
        failed=1
    else
        ok "NGC_API_KEY is set (${NGC_API_KEY:0:12}...)"
    fi

    if [[ $failed -ne 0 ]]; then
        echo ""
        error "Prerequisites not met — fix the errors above and re-run setup"
        exit 1
    fi

    # NGC Docker login
    section "=== NGC Authentication ==="
    if echo "${NGC_API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin; then
        ok "Authenticated with nvcr.io"
    else
        error "NGC login failed — check your API key"
        exit 1
    fi

    echo ""
    ok "All checks passed. Run:  $0 start"
}

# ------------------------------------------------------------------------------
cmd_start() {
    section "=== Starting NVIDIA RAG Blueprint ==="

    if [[ -z "${NGC_API_KEY:-}" ]]; then
        error "NGC_API_KEY is not set — export it first, then re-run"
        exit 1
    fi

    info "Sourcing environment: $ENV_FILE"
    # shellcheck source=/dev/null
    source "$ENV_FILE"

    info "Starting services (this may take 5–10 min on first run)..."
    docker compose -f "$COMPOSE_FILE" up -d

    section "=== Waiting for Services ==="
    _wait_healthy

    section "=== Service URLs ==="
    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')
    echo -e "  ${BOLD}Local:${RESET}"
    echo    "    Web UI       http://localhost:$FRONTEND_PORT"
    echo    "    RAG API      http://localhost:$RAG_PORT"
    echo    "    Ingestor API http://localhost:$INGESTOR_PORT"
    echo -e "  ${BOLD}Network:${RESET}"
    echo    "    Web UI       http://$host_ip:$FRONTEND_PORT"
    echo    "    RAG API      http://$host_ip:$RAG_PORT"
    echo    "    Ingestor API http://$host_ip:$INGESTOR_PORT"
    echo ""
    ok "Ready. Open http://localhost:$FRONTEND_PORT in your browser."
}

# ------------------------------------------------------------------------------
cmd_status() {
    section "=== Containers ==="
    docker compose -f "$COMPOSE_FILE" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
        docker ps --filter "name=rag-\|name=milvus\|name=ingestor" \
                  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    section "=== API Health ==="
    _check_health "RAG server"      "http://localhost:$RAG_PORT/v1/health?check_dependencies=true"
    _check_health "Ingestor server" "http://localhost:$INGESTOR_PORT/v1/health?check_dependencies=true"

    section "=== GPU Usage ==="
    if nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu \
                   --format=csv,noheader,nounits | \
        awk -F',' '{printf "  GPU: %s | Util: %s%% | VRAM: %s/%s MiB | Temp: %s°C\n", $1,$2,$3,$4,$5}'
    else
        warn "nvidia-smi not available"
    fi
}

# ------------------------------------------------------------------------------
cmd_logs() {
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        info "Tailing logs for: $service  (Ctrl+C to stop)"
        docker compose -f "$COMPOSE_FILE" logs -f "$service"
    else
        info "Tailing logs for all services  (Ctrl+C to stop)"
        docker compose -f "$COMPOSE_FILE" logs -f
    fi
}

# ------------------------------------------------------------------------------
cmd_stop() {
    section "=== Stopping Services ==="
    docker compose -f "$COMPOSE_FILE" down
    ok "Services stopped (data volumes preserved)"
}

# ------------------------------------------------------------------------------
cmd_clean() {
    section "=== Removing Services and Data ==="
    warn "This will delete all vector database data and ingested documents."
    read -r -p "  Continue? [y/N] " confirm
    if [[ "${confirm,,}" == "y" ]]; then
        docker compose -f "$COMPOSE_FILE" down -v
        ok "Services stopped and volumes removed"
    else
        info "Cancelled"
    fi
}

# ------------------------------------------------------------------------------
_wait_healthy() {
    local max_attempts=30
    local interval=10

    for endpoint in \
        "RAG server|http://localhost:$RAG_PORT/v1/health" \
        "Ingestor server|http://localhost:$INGESTOR_PORT/v1/health"; do
        local name="${endpoint%%|*}"
        local url="${endpoint##*|}"
        local attempt=0
        printf "  Waiting for %s " "$name"
        while [[ $attempt -lt $max_attempts ]]; do
            if curl -sf "$url" -o /dev/null; then
                echo -e " ${GREEN}ready${RESET}"
                break
            fi
            printf "."
            sleep "$interval"
            (( attempt++ ))
        done
        if [[ $attempt -eq $max_attempts ]]; then
            echo ""
            warn "$name did not become healthy in time — check logs: $0 logs"
        fi
    done
}

_check_health() {
    local name="$1"
    local url="$2"
    local response
    if response=$(curl -sf "$url" 2>/dev/null); then
        local msg
        msg=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message','?'))" 2>/dev/null || echo "up")
        ok "$name: $msg"
        # Print NIM status if present
        echo "$response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for nim in d.get('nim', []):
    status = nim.get('status', '?')
    color = '\033[0;32m' if status == 'healthy' else '\033[0;31m'
    reset = '\033[0m'
    print(f\"  {color}  {nim.get('service','?'):12} {status}{reset}\")
" 2>/dev/null || true
    else
        warn "$name: not reachable at $url"
    fi
}

# ------------------------------------------------------------------------------
usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  setup          Check prerequisites and authenticate with NGC"
    echo "  start          Deploy all services"
    echo "  status         Show container health, GPU usage, and API status"
    echo "  logs [svc]     Tail logs (optionally for a specific service)"
    echo "  stop           Stop all services (keeps data volumes)"
    echo "  clean          Stop all services and remove all data volumes"
    echo ""
    echo "Examples:"
    echo "  export NGC_API_KEY=\"nvapi-...\""
    echo "  $0 setup"
    echo "  $0 start"
    echo "  $0 status"
    echo "  $0 logs rag-server"
    echo "  $0 stop"
}

# ------------------------------------------------------------------------------
case "${1:-}" in
    setup)  cmd_setup ;;
    start)  cmd_start ;;
    status) cmd_status ;;
    logs)   cmd_logs "${2:-}" ;;
    stop)   cmd_stop ;;
    clean)  cmd_clean ;;
    *)      usage; exit 1 ;;
esac
