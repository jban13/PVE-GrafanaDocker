#!/usr/bin/env bash
set -Eeuo pipefail

# Repository structure:
#   SetupMonitoring.sh
#   pve/pve.yml
#   prometheus/prometheus.yml
#
# Configuration files are copied or downloaded to:
#   ~/pve/pve.yml
#   ~/prometheus/prometheus.yml
#   ~/loki/loki-config.yaml
#
# Loki is optional.
# Alloy is not installed by this script because Alloy runs on another LXC.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="${TARGET_ROOT:-$HOME}"
HOST_IP=""

PVE_SOURCE="${SCRIPT_DIR}/pve/pve.yml"
PVE_DIR="${TARGET_ROOT}/pve"
PVE_CONFIG="${PVE_DIR}/pve.yml"

PROMETHEUS_SOURCE="${SCRIPT_DIR}/prometheus/prometheus.yml"
PROMETHEUS_DIR="${TARGET_ROOT}/prometheus"
PROMETHEUS_CONFIG="${PROMETHEUS_DIR}/prometheus.yml"

LOKI_DIR="${TARGET_ROOT}/loki"
LOKI_CONFIG="${LOKI_DIR}/loki-config.yaml"
LOKI_VOLUME="loki-data"
LOKI_PORT="3100"
LOKI_VERSION=""
LOKI_GIT_TAG=""

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

fail() {
    printf '\nFEHLER: %s\n' "$*" >&2
    exit 1
}

detect_host_ip() {
    HOST_IP="$(
        ip -4 route get 1.1.1.1 2>/dev/null |
            awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i+1); exit}}'
    )"

    if [[ -z "$HOST_IP" ]]; then
        HOST_IP="$(hostname -I | awk '{print $1}')"
    fi

    [[ -n "$HOST_IP" ]] ||
        fail "Die IPv4-Adresse dieses LXC konnte nicht ermittelt werden."

    log "Ermittelte LXC-Adresse: ${HOST_IP}"
}

select_editor() {
    if [[ -n "${EDITOR:-}" ]]; then
        read -r -a EDITOR_CMD <<< "$EDITOR"
    elif command -v nano >/dev/null 2>&1; then
        EDITOR_CMD=(nano)
    elif command -v vi >/dev/null 2>&1; then
        EDITOR_CMD=(vi)
    else
        fail "Kein Editor gefunden. Bitte nano installieren oder EDITOR setzen."
    fi
}

copy_and_edit() {
    local source_file="$1"
    local target_file="$2"
    local target_dir

    target_dir="$(dirname -- "$target_file")"

    [[ -f "$source_file" ]] ||
        fail "Quelldatei fehlt: $source_file"

    mkdir -p -- "$target_dir"

    # Falls Quelle und Ziel identisch sind, ist kein Kopieren erforderlich.
    if [[ "$(readlink -f -- "$source_file")" != "$(readlink -m -- "$target_file")" ]]; then
        if [[ -f "$target_file" ]]; then
            cp -- \
                "$target_file" \
                "${target_file}.bak.$(date '+%Y%m%d-%H%M%S')"
        fi

        cp -- "$source_file" "$target_file"
        log "Konfiguration kopiert nach $target_file"
    else
        log "Konfiguration liegt bereits am Ziel: $target_file"
    fi

    if grep -q "DOCKER_HOST_IP" "$target_file"; then
        sed -i "s|DOCKER_HOST_IP|${HOST_IP}|g" "$target_file"
    fi

    log "Oeffne $target_file zur Bearbeitung"
    "${EDITOR_CMD[@]}" "$target_file"
}

container_exists() {
    docker container inspect "$1" >/dev/null 2>&1
}

ask_yes_no() {
    local prompt="$1"
    local default_answer="${2:-n}"
    local answer

    while true; do
        if [[ "$default_answer" == "j" ]]; then
            read -r -p "${prompt} [J/n]: " answer
            answer="${answer:-j}"
        else
            read -r -p "${prompt} [j/N]: " answer
            answer="${answer:-n}"
        fi

        case "${answer,,}" in
            j|ja|y|yes)
                return 0
                ;;
            n|nein|no)
                return 1
                ;;
            *)
                printf 'Bitte mit j oder n antworten.\n'
                ;;
        esac
    done
}

resolve_latest_loki_version() {
    local release_json
    local latest_tag

    log "Ermittle die neueste stabile Loki-Version"

    release_json="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --connect-timeout 15 \
            --max-time 30 \
            "https://api.github.com/repos/grafana/loki/releases/latest"
    )" || fail "Die neueste Loki-Version konnte nicht von GitHub abgerufen werden."

    latest_tag="$(
        printf '%s\n' "$release_json" |
            sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' |
            head -n 1
    )"

    [[ "$latest_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "Unerwartetes Release-Tag von GitHub: ${latest_tag:-leer}"

    LOKI_GIT_TAG="$latest_tag"
    LOKI_VERSION="${latest_tag#v}"
}

select_loki_version() {
    local requested_version

    printf '\n'

    read -r -p \
        "Gewuenschte Loki-Version, z.B. 3.7.7, oder Enter fuer die neueste stabile Version: " \
        requested_version

    requested_version="$(
        printf '%s' "$requested_version" |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    )"

    if [[ -z "$requested_version" ]]; then
        resolve_latest_loki_version
    else
        requested_version="${requested_version#v}"

        [[ "$requested_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
            fail "Ungueltige Loki-Version: $requested_version"

        LOKI_VERSION="$requested_version"
        LOKI_GIT_TAG="v${requested_version}"
    fi

    log "Ausgewaehlte Loki-Version: ${LOKI_VERSION}"
}

download_loki_config() {
    local config_url
    local temporary_config
    local backup_file

    mkdir -p -- "$LOKI_DIR"

    config_url="https://raw.githubusercontent.com/grafana/loki/${LOKI_GIT_TAG}/cmd/loki/loki-local-config.yaml"
    temporary_config="${LOKI_CONFIG}.tmp"

    rm -f -- "$temporary_config"

    log "Lade offizielle Loki-Konfiguration fuer ${LOKI_GIT_TAG}"
    log "Quelle: ${config_url}"

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 15 \
        --max-time 60 \
        "$config_url" \
        --output "$temporary_config" ||
        fail "Loki-Konfiguration fuer ${LOKI_GIT_TAG} konnte nicht heruntergeladen werden."

    [[ -s "$temporary_config" ]] ||
        fail "Die heruntergeladene Loki-Konfiguration ist leer."

    grep -q '^auth_enabled:' "$temporary_config" ||
        fail "Die heruntergeladene Datei scheint keine Loki-Konfiguration zu sein."

    grep -Eq \
        '^[[:space:]]*http_listen_port:[[:space:]]*3100[[:space:]]*$' \
        "$temporary_config" ||
        fail "Die Loki-Konfiguration enthaelt nicht den erwarteten Port 3100."

    if [[ -f "$LOKI_CONFIG" ]]; then
        backup_file="${LOKI_CONFIG}.bak.$(date '+%Y%m%d-%H%M%S')"

        cp -- "$LOKI_CONFIG" "$backup_file"

        log "Vorhandene Loki-Konfiguration gesichert unter:"
        printf '%s\n' "$backup_file"
    fi

    mv -- "$temporary_config" "$LOKI_CONFIG"
    chmod 0644 "$LOKI_CONFIG"

    log "Loki-Konfiguration gespeichert unter $LOKI_CONFIG"
}

edit_loki_config() {
    if ask_yes_no \
        "Soll die Loki-Konfiguration vor der Installation geoeffnet werden?" \
        "n"; then

        log "Oeffne $LOKI_CONFIG zur Bearbeitung"
        "${EDITOR_CMD[@]}" "$LOKI_CONFIG"
    else
        log "Loki-Konfiguration wird unveraendert verwendet."
    fi
}

validate_loki_config() {
    log "Lade Loki-Image grafana/loki:${LOKI_VERSION}"

    docker pull "grafana/loki:${LOKI_VERSION}"

    log "Pruefe die Loki-Konfiguration"

    docker run \
        --rm \
        -v "${LOKI_CONFIG}:/etc/loki/loki-config.yaml:ro" \
        "grafana/loki:${LOKI_VERSION}" \
        -config.file=/etc/loki/loki-config.yaml \
        -verify-config=true ||
        fail "Die Loki-Konfiguration ist ungueltig."

    log "Die Loki-Konfiguration ist gueltig."
}

wait_for_loki() {
    local attempt
    local readiness_response

    log "Warte auf Loki-Readiness"

    # Loki kann direkt nach dem Start einige Sekunden lang melden:
    # Ingester not ready: waiting for 15s after being ready
    for attempt in {1..12}; do
        readiness_response="$(
            curl \
                --silent \
                --max-time 5 \
                "http://localhost:${LOKI_PORT}/ready" 2>/dev/null ||
                true
        )"

        if [[ "$readiness_response" == "ready" ]]; then
            log "Loki ist bereit."
            return 0
        fi

        printf \
            'Loki ist noch nicht bereit, Versuch %s/12...\n' \
            "$attempt"

        sleep 5
    done

    printf '\nLetzte Loki-Logmeldungen:\n'
    docker logs loki --tail 50 || true

    fail "Loki wurde nicht innerhalb der erwarteten Zeit bereit."
}

create_loki_container() {
    log "Persistentes Docker-Volume ${LOKI_VOLUME} anlegen"

    docker volume create "$LOKI_VOLUME" >/dev/null

    log "Berechtigungen des Loki-Volumes fuer UID 10001 vorbereiten"
    
    docker run \
    --rm \
    -v "${LOKI_VOLUME}:/tmp/loki" \
    alpine:3.22 \
    chown -R 10001:10001 /tmp/loki

    log "Loki ${LOKI_VERSION} installieren"

    docker run \
        --name loki \
        --restart unless-stopped \
        -p "${LOKI_PORT}:3100" \
        -d \
        -v "${LOKI_CONFIG}:/etc/loki/loki-config.yaml:ro" \
        -v "${LOKI_VOLUME}:/tmp/loki" \
        "grafana/loki:${LOKI_VERSION}" \
        -config.file=/etc/loki/loki-config.yaml

    wait_for_loki
}

install_loki() {
    select_loki_version
    download_loki_config
    edit_loki_config
    validate_loki_config

    if container_exists loki; then
        log "Ein Loki-Container existiert bereits."

        printf 'Vorhandenes Image: '

        docker container inspect \
            --format '{{.Config.Image}}' \
            loki 2>/dev/null ||
            true

        if ask_yes_no \
            "Soll der vorhandene Loki-Container mit Version ${LOKI_VERSION} neu erstellt werden?" \
            "n"; then

            log "Entferne den vorhandenen Loki-Container"

            docker rm -f loki

            create_loki_container
        else
            log "Vorhandener Loki-Container wird beibehalten."
            log "Die neue Konfiguration wurde nicht auf den vorhandenen Container angewendet."
        fi
    else
        create_loki_container
    fi
}

select_editor
detect_host_ip

log "Paketlisten aktualisieren und Docker installieren"

apt-get update
apt-get install -y docker.io curl

systemctl enable --now docker

# pve.yml vor dem Docker-Pull kopieren und bearbeiten.
copy_and_edit "$PVE_SOURCE" "$PVE_CONFIG"

log "Prometheus-PVE-Exporter installieren"

docker pull prompve/prometheus-pve-exporter

if container_exists prometheus-pve-exporter; then
    log "Container prometheus-pve-exporter existiert bereits und wird beibehalten."
else
    docker run --init \
        --name prometheus-pve-exporter \
        --restart unless-stopped \
        -d \
        -p 0.0.0.0:9221:9221 \
        -v "${PVE_CONFIG}:/etc/prometheus/pve.yml:ro" \
        prompve/prometheus-pve-exporter
fi

docker ps

curl \
    --fail \
    --show-error \
    http://localhost:9221/ ||
    true

# prometheus.yml direkt vor der Prometheus-Installation kopieren und bearbeiten.
copy_and_edit "$PROMETHEUS_SOURCE" "$PROMETHEUS_CONFIG"

log "Prometheus installieren"

docker volume create prometheus-data >/dev/null
docker pull prom/prometheus

if container_exists prometheus; then
    log "Container prometheus existiert bereits und wird beibehalten."
else
    docker run \
        --name prometheus \
        --restart unless-stopped \
        -p 9090:9090 \
        -d \
        -v "${PROMETHEUS_CONFIG}:/etc/prometheus/prometheus.yml:ro" \
        -v prometheus-data:/prometheus \
        prom/prometheus
        --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.retention.time=30d --storage.tsdb.path=/prometheus --storage.tsdb.retention.size=10GB 
fi

log "Grafana installieren"

docker volume create grafana-storage >/dev/null
docker pull grafana/grafana-enterprise

if container_exists grafana; then
    log "Container grafana existiert bereits und wird beibehalten."
else
    docker run \
        --name grafana \
        --restart unless-stopped \
        -d \
        -p 3000:3000 \
        --volume grafana-storage:/var/lib/grafana \
        grafana/grafana-enterprise
fi

if ask_yes_no "Soll Loki installiert werden?" "n"; then
    install_loki
else
    log "Loki-Installation wurde uebersprungen."
fi

log "Installation abgeschlossen"

docker ps \
    --filter name=prometheus-pve-exporter \
    --filter name=prometheus \
    --filter name=grafana \
    --filter name=loki

printf '\n'
printf 'PVE-Exporter: http://%s:9221\n' "$HOST_IP"
printf 'Prometheus:   http://%s:9090\n' "$HOST_IP"
printf 'Grafana:      http://%s:3000\n' "$HOST_IP"

if container_exists loki; then
    printf 'Loki:         http://%s:%s\n' \
        "$HOST_IP" \
        "$LOKI_PORT"

    printf 'Loki Ready:   http://%s:%s/ready\n' \
        "$HOST_IP" \
        "$LOKI_PORT"

    printf '\n'
    printf 'Alloy-Zieladresse fuer einen anderen LXC:\n'

    printf 'http://%s:%s/loki/api/v1/push\n' \
        "$HOST_IP" \
        "$LOKI_PORT"
fi
