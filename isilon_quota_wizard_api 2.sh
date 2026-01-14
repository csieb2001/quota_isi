#!/bin/bash

################################################################################
# PowerScale/Isilon Directory & Quota Creation Wizard (API Version)
# Interaktiver Assistent zur Erstellung von Verzeichnissen mit Quotas
# via OneFS API (Remote Execution)
#
# Copyright (c) 2024 Christopher Siebert
#
# Licensed under the MIT License - see LICENSE file for details
# https://opensource.org/licenses/MIT
#
# Version: 2.0 (API)
# Created: November 2024
################################################################################

# Farben und Formatierung
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Unicode Zeichen
CHECK="✓"
CROSS="✗"
ARROW="→"
STAR="★"

# Globale Variablen
BASE_PATH=""
PREFIX="dir"
COUNT=1000

# API Connection
CLUSTER_ADDRESS=""
API_USER=""
API_PASSWORD=""
COOKIE_FILE="/tmp/isi_cookie_$$"
API_BASE_URL=""

# Owner-Einstellungen
OWNER_USER=""
OWNER_GROUP=""
SET_OWNER="n"

# Quota-Einstellungen
QUOTA_HARD="1M"
QUOTA_SOFT=""
QUOTA_ADVISORY=""
QUOTA_SOFT_GRACE=604800  # 7 Tage in Sekunden
QUOTA_INCLUDE_SNAPSHOTS="false"
QUOTA_THRESHOLDS_ON="applogicalsize"  # applogicalsize, fslogicalsize, physicalsize
QUOTA_CONTAINER="true"  # Directory Quota (true) oder User/Group Quota (false)

# Performance-Einstellungen
PARALLEL_JOBS=10
USE_PARALLEL="n"

################################################################################
# Hilfsfunktionen
################################################################################

print_header() {
    clear
    echo -e "${CYAN}========================================================================${NC}"
    echo -e "${WHITE}${BOLD}        PowerScale/Isilon Quota Wizard v2.0 (API)                   ${NC}"
    echo -e ""
    echo -e "        ${WHITE}Copyright © 2024 Christopher Siebert${NC}"
    echo -e "        ${CYAN}Remote Execution via OneFS API${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    echo
}

print_step() {
    echo -e "${BLUE}${BOLD}$1${NC}"
    echo -e "${BLUE}$(printf '=%.0s' {1..70})${NC}"
    echo
}

print_info() {
    echo -e "${CYAN}ℹ${NC}  $1"
}

print_success() {
    echo -e "${GREEN}${CHECK}${NC}  $1"
}

print_error() {
    echo -e "${RED}${CROSS}${NC}  $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

press_any_key() {
    echo
    read -p "$(echo -e ${WHITE}Drücke eine beliebige Taste zum Fortfahren...${NC})" -n 1 -r
    echo
}

confirm_action() {
    local message="$1"
    echo
    read -p "$(echo -e ${YELLOW}${message} ${WHITE}[j/N]:${NC} )" -n 1 -r
    echo
    [[ $REPLY =~ ^[Jj]$ ]]
}

cleanup() {
    if [ -f "$COOKIE_FILE" ]; then
        rm -f "$COOKIE_FILE"
    fi
}
trap cleanup EXIT

################################################################################
# API Helper Functions
################################################################################

refresh_session() {
    if [ -z "$API_USER" ] || [ -z "$API_PASSWORD" ]; then
        print_error "Kann Session nicht erneuern - Anmeldedaten fehlen" >&2
        return 1
    fi

    print_info "Session erneuern..." >&2
    rm -f "$COOKIE_FILE"

    local auth_payload=$(jq -n --arg user "$API_USER" --arg pass "$API_PASSWORD" \
        '{username: $user, password: $pass, services: ["platform"]}')
    local response=$(curl -s -k -w "\n%{http_code}" -c "$COOKIE_FILE" -H "Content-Type: application/json" \
        -d "$auth_payload" "${API_BASE_URL}/session/1/session")

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        ISI_CSRF_TOKEN=$(awk '/isisessid/ {print $NF}' "$COOKIE_FILE" 2>/dev/null)
        export ISI_CSRF_TOKEN
        print_success "Session erfolgreich erneuert" >&2
        return 0
    else
        print_error "Session-Erneuerung fehlgeschlagen (HTTP $http_code)" >&2
        return 1
    fi
}

api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local extra_header="$4"
    local retry_count="${5:-1}"

    local cmd=(curl -s -k -w "\n%{http_code}" -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X "$method")
    cmd+=(-H "Content-Type: application/json")
    cmd+=(-H "Accept: application/json")

    # Always add CSRF token if available (OneFS requires it for most operations)
    if [ -n "$ISI_CSRF_TOKEN" ]; then
        cmd+=(-H "X-CSRF-Token: $ISI_CSRF_TOKEN")
        cmd+=(-H "Referer: ${API_BASE_URL}")
    fi

    if [ -n "$extra_header" ]; then
        cmd+=(-H "$extra_header")
    fi

    if [ -n "$data" ]; then
        cmd+=(-d "$data")
    fi

    cmd+=("${API_BASE_URL}${endpoint}")

    local response=$("${cmd[@]}")
    local http_code=$(echo "$response" | tail -n1)

    # If we get 401 and haven't retried yet, try to refresh session
    if [ "$http_code" = "401" ] && [ "$retry_count" -gt 0 ]; then
        if refresh_session; then
            # Retry the request with new session
            api_request "$method" "$endpoint" "$data" "$extra_header" 0
            return
        fi
    fi

    echo "$response"
}

check_api_error() {
    local response="$1"
    local context="$2"
    local http_code="$3"

    # Check HTTP status code first
    if [ -n "$http_code" ] && [ "$http_code" -ge 400 ]; then
        print_error "API Error ($context): HTTP $http_code"
        return 1
    fi

    # Check if response contains errors array or error message
    if [ -n "$response" ] && command -v jq >/dev/null 2>&1; then
        if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
            local err_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
            print_error "API Error ($context): $err_msg"
            return 1
        fi
    fi

    return 0
}

################################################################################
# Validierungsfunktionen
################################################################################

check_system() {
    print_header
    print_step "Schritt 1: System-Überprüfung"
    
    local errors=0
    
    # Prüfe ob curl verfügbar ist
    if command -v curl &> /dev/null; then
        print_success "curl gefunden"
    else
        print_error "curl nicht gefunden! Bitte installieren."
        ((errors++))
    fi
    
    # Prüfe ob jq verfügbar ist
    if command -v jq &> /dev/null; then
        print_success "jq gefunden"
    else
        print_error "jq nicht gefunden! Bitte installieren (brew install jq / apt install jq)."
        ((errors++))
    fi
    
    # Prüfe ob GNU Parallel verfügbar ist
    if command -v parallel &> /dev/null; then
        print_success "GNU Parallel verfügbar"
        PARALLEL_AVAILABLE=true
    else
        print_info "GNU Parallel nicht verfügbar (xargs wird als Fallback verwendet)"
        PARALLEL_AVAILABLE=false
    fi
    
    echo
    
    if [ $errors -gt 0 ]; then
        print_error "System-Überprüfung fehlgeschlagen!"
        exit 1
    fi
    
    print_success "System-Überprüfung erfolgreich!"
    press_any_key
}

connect_cluster() {
    print_header
    print_step "Schritt 2: Cluster-Verbindung"
    
    while true; do
        if [ -z "$CLUSTER_ADDRESS" ]; then
            read -p "$(echo -e ${WHITE}${ARROW} Cluster IP/Hostname:${NC} )" CLUSTER_ADDRESS
        fi
        
        if [ -z "$CLUSTER_ADDRESS" ]; then
            print_error "Adresse darf nicht leer sein!"
            continue
        fi
        
        API_BASE_URL="https://${CLUSTER_ADDRESS}:8080"
        
        if [ -z "$API_USER" ]; then
            read -p "$(echo -e ${WHITE}${ARROW} Username:${NC} )" API_USER
        fi
        
        if [ -z "$API_PASSWORD" ]; then
            read -s -p "$(echo -e ${WHITE}${ARROW} Password:${NC} )" API_PASSWORD
            echo
        fi
        
        print_info "Verbinde zu $CLUSTER_ADDRESS..."
        
        # Authenticate and store credentials for session renewal
        rm -f "$COOKIE_FILE"
        local auth_payload=$(jq -n --arg user "$API_USER" --arg pass "$API_PASSWORD" \
            '{username: $user, password: $pass, services: ["platform"]}')
        local response=$(curl -s -k -w "\n%{http_code}" -c "$COOKIE_FILE" -H "Content-Type: application/json" \
            -d "$auth_payload" "${API_BASE_URL}/session/1/session")

        # Store credentials globally for session renewal
        # Don't clear them when connection succeeds
            
        local http_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | sed '$d')

        if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
            if [ -s "$COOKIE_FILE" ]; then
                print_success "Verbindung erfolgreich!"

                # Extract CSRF token more robustly
                ISI_CSRF_TOKEN=$(awk '/isisessid/ {print $NF}' "$COOKIE_FILE" 2>/dev/null)

                if [ -n "$ISI_CSRF_TOKEN" ]; then
                    export ISI_CSRF_TOKEN
                    print_info "CSRF Token erfolgreich extrahiert"
                else
                    print_warning "Konnte CSRF Token nicht extrahieren (könnte zu Auth-Fehlern führen)"
                fi

                # Test API access with a simple call (try different endpoints)
                local test_response=$(api_request "GET" "/platform/1/cluster/identity")
                local test_http_code=$(echo "$test_response" | tail -n1)

                if [ "$test_http_code" != "200" ]; then
                    # Try alternative endpoint
                    test_response=$(api_request "GET" "/session/1/session")
                    test_http_code=$(echo "$test_response" | tail -n1)

                    if [ "$test_http_code" = "200" ]; then
                        print_info "API-Zugriff bestätigt (Session aktiv)"
                    else
                        print_warning "API-Test fehlgeschlagen (HTTP $test_http_code) - aber Login war erfolgreich"
                        print_info "Fortfahren auf eigene Gefahr..."
                    fi
                else
                    print_info "API-Zugriff bestätigt"
                fi

                break
            else
                print_error "Login erfolgreich, aber Cookie konnte nicht gespeichert werden!"
                exit 1
            fi
        else
            if [ -n "$response_body" ] && command -v jq >/dev/null 2>&1; then
                local err_msg=$(echo "$response_body" | jq -r '.errors[0].message // "Authentication failed"' 2>/dev/null)
                print_error "Verbindung fehlgeschlagen: $err_msg"
            else
                print_error "Verbindung fehlgeschlagen! HTTP $http_code"
            fi
            CLUSTER_ADDRESS=""
            # Don't clear API_USER and API_PASSWORD here to allow retry
        fi
        echo
    done
    
    press_any_key
}

validate_path() {
    local path="$1"
    
    if [ -z "$path" ]; then
        print_error "Pfad darf nicht leer sein!"
        return 1
    fi
    
    if [[ ! "$path" =~ ^/ifs ]]; then
        print_error "Pfad muss mit /ifs beginnen!"
        return 1
    fi
    
    # Check via API if path exists
    local response=$(api_request "GET" "/namespace${path}?metadata")
    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
        return 0
    else
        return 1
    fi
}

validate_number() {
    local num="$1"
    local min="$2"
    local max="$3"
    
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        print_error "Ungültige Eingabe! Bitte eine Zahl eingeben."
        return 1
    fi
    
    if [ "$num" -lt "$min" ] || [ "$num" -gt "$max" ]; then
        print_error "Wert muss zwischen $min und $max liegen!"
        return 1
    fi
    
    return 0
}

validate_quota_size() {
    local size="$1"
    
    if [[ ! "$size" =~ ^[0-9]+[KMGTPkmgtp]?$ ]]; then
        print_error "Ungültiges Quota-Format! Beispiele: 1M, 100K, 1G"
        return 1
    fi
    
    return 0
}

validate_grace_period() {
    local period="$1"
    
    if ! [[ "$period" =~ ^[0-9]+$ ]]; then
        print_error "Ungültige Eingabe! Bitte eine Zahl eingeben."
        return 1
    fi
    
    if [ "$period" -lt 0 ] || [ "$period" -gt 31536000 ]; then
        print_error "Wert muss zwischen 0 und 31536000 Sekunden (1 Jahr) liegen!"
        return 1
    fi
    
    return 0
}

################################################################################
# Eingabe-Funktionen
################################################################################

get_base_path() {
    print_header
    print_step "Schritt 3: Basis-Pfad konfigurieren"
    
    print_info "Gib den Basis-Pfad auf dem PowerScale an."
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Basis-Pfad:${NC} )" BASE_PATH
        
        if [ -z "$BASE_PATH" ]; then
            print_error "Pfad darf nicht leer sein!"
            continue
        fi
        
        if [[ ! "$BASE_PATH" =~ ^/ifs ]]; then
            print_error "Pfad muss mit /ifs beginnen!"
            continue
        fi
        
        # Check existence via API
        local response=$(api_request "GET" "/namespace${BASE_PATH}?metadata")
        local http_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | sed '$d')

        if [ "$http_code" != "200" ]; then
            print_warning "Pfad existiert noch nicht: $BASE_PATH"
            echo
            
            if confirm_action "Möchtest du den Pfad jetzt erstellen?"; then
                print_info "Erstelle Verzeichnisstruktur: $BASE_PATH"

                # Try to create parent directories step by step if needed
                local current_path="/ifs"
                local remaining_path="${BASE_PATH#/ifs/}"

                IFS='/' read -ra path_parts <<< "$remaining_path"
                for part in "${path_parts[@]}"; do
                    if [ -n "$part" ]; then
                        current_path="$current_path/$part"

                        # Check if this part exists
                        local check_response=$(api_request "GET" "/namespace${current_path}?metadata")
                        local check_http_code=$(echo "$check_response" | tail -n1)

                        if [ "$check_http_code" != "200" ]; then
                            # Create this directory level
                            local mkdir_response=$(api_request "PUT" "/namespace${current_path}" "" "x-isi-ifs-target-type: container")
                            local mkdir_http_code=$(echo "$mkdir_response" | tail -n1)

                            if [ "$mkdir_http_code" = "200" ] || [ "$mkdir_http_code" = "201" ] || [ "$mkdir_http_code" = "204" ]; then
                                print_info "Erstellt: $current_path"
                            elif [ "$mkdir_http_code" = "401" ]; then
                                print_error "Authentifizierung fehlgeschlagen! Session möglicherweise abgelaufen."
                                print_info "Versuche eine neue Authentifizierung..."
                                CLUSTER_ADDRESS=""
                                API_USER=""
                                API_PASSWORD=""
                                break 2  # Break out of both loops to restart connection
                            else
                                local mkdir_body=$(echo "$mkdir_response" | sed '$d')
                                check_api_error "$mkdir_body" "Pfad erstellen ($current_path)" "$mkdir_http_code"
                                continue 2  # Continue with next path attempt
                            fi
                        fi
                    fi
                done

                # Final check if the full path was created successfully
                local final_check=$(api_request "GET" "/namespace${BASE_PATH}?metadata")
                local final_http_code=$(echo "$final_check" | tail -n1)

                if [ "$final_http_code" = "200" ]; then
                    print_success "Pfad erfolgreich erstellt: $BASE_PATH"
                    break
                fi
            else
                continue
            fi
        else
            print_success "Pfad existiert: $BASE_PATH"
            break
        fi
    done
    
    press_any_key
}

get_prefix() {
    print_header
    print_step "Schritt 4: Verzeichnis-Präfix"
    
    read -p "$(echo -e ${WHITE}${ARROW} Präfix [${GREEN}$PREFIX${WHITE}]:${NC} )" input
    if [ -n "$input" ]; then
        PREFIX="$input"
    fi
    print_success "Präfix gesetzt: $PREFIX"
    press_any_key
}

get_count() {
    print_header
    print_step "Schritt 5: Anzahl der Verzeichnisse"
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Anzahl [${GREEN}$COUNT${WHITE}]:${NC} )" input
        if [ -z "$input" ]; then input=$COUNT; fi
        
        if validate_number "$input" 1 100000; then
            COUNT=$input
            print_success "Anzahl gesetzt: $COUNT"
            break
        fi
    done
    press_any_key
}

get_owner_settings() {
    print_header
    print_step "Schritt 6: Verzeichnis-Owner"
    
    print_info "Owner-Einstellungen via API erfordern UID/GID oder genaue Namen."
    print_info "Aktuell wird der API-User als Owner verwendet, wenn nichts anderes angegeben."
    echo
    
    if confirm_action "Owner manuell festlegen?"; then
        SET_OWNER="y"
        
        read -p "$(echo -e ${WHITE}${ARROW} User Name/UID:${NC} )" OWNER_USER
        read -p "$(echo -e ${WHITE}${ARROW} Group Name/GID:${NC} )" OWNER_GROUP
        
        # Resolve names to IDs via API if possible, or trust input
        # For simplicity, we'll assume the user provides valid inputs or we'll try to resolve later
        # API: GET /platform/1/auth/users/<name>
        
        print_success "Owner gesetzt: $OWNER_USER:$OWNER_GROUP"
    else
        SET_OWNER="n"
        print_info "Standard-Owner wird verwendet."
    fi
    
    press_any_key
}

get_quota_configuration() {
    print_header
    print_step "Schritt 7: Quota-Konfiguration"
    
    # Hard Threshold
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Hard Threshold [${GREEN}$QUOTA_HARD${WHITE}]:${NC} )" input
        if [ -z "$input" ]; then input=$QUOTA_HARD; fi
        
        if validate_quota_size "$input"; then
            QUOTA_HARD=$input
            break
        fi
    done
    
    # Soft Threshold
    read -p "$(echo -e ${WHITE}${ARROW} Soft Threshold [leer]:${NC} )" input
    if [ -n "$input" ] && validate_quota_size "$input"; then
        QUOTA_SOFT=$input
    else
        QUOTA_SOFT=""
    fi
    
    # Advisory Threshold
    read -p "$(echo -e ${WHITE}${ARROW} Advisory Threshold [leer]:${NC} )" input
    if [ -n "$input" ] && validate_quota_size "$input"; then
        QUOTA_ADVISORY=$input
    else
        QUOTA_ADVISORY=""
    fi
    
    # Grace Period
    if [ -n "$QUOTA_SOFT" ]; then
        while true; do
            read -p "$(echo -e ${WHITE}${ARROW} Grace Period [${GREEN}$QUOTA_SOFT_GRACE${WHITE}]:${NC} )" input
            if [ -z "$input" ]; then input=$QUOTA_SOFT_GRACE; fi
            if validate_grace_period "$input"; then
                QUOTA_SOFT_GRACE=$input
                break
            fi
        done
    fi
    
    press_any_key
}

get_quota_advanced_options() {
    print_header
    print_step "Schritt 8: Erweiterte Optionen"
    
    echo -e "${WHITE}1)${NC} applogicalsize (Standard)"
    echo -e "${WHITE}2)${NC} fslogicalsize"
    echo -e "${WHITE}3)${NC} physicalsize"
    
    read -p "$(echo -e ${WHITE}${ARROW} Auswahl [${GREEN}1${WHITE}]:${NC} )" input
    case $input in
        2) QUOTA_THRESHOLDS_ON="fslogicalsize" ;;
        3) QUOTA_THRESHOLDS_ON="physicalsize" ;;
        *) QUOTA_THRESHOLDS_ON="applogicalsize" ;;
    esac
    
    if confirm_action "Snapshots einbeziehen?"; then
        QUOTA_INCLUDE_SNAPSHOTS="true"
    else
        QUOTA_INCLUDE_SNAPSHOTS="false"
    fi
    
    press_any_key
}

get_parallel_settings() {
    print_header
    print_step "Schritt 9: Performance"
    
    if [ "$PARALLEL_AVAILABLE" = true ]; then
        if confirm_action "Parallele Verarbeitung aktivieren?"; then
            USE_PARALLEL="y"
            read -p "$(echo -e ${WHITE}${ARROW} Jobs [${GREEN}$PARALLEL_JOBS${WHITE}]:${NC} )" input
            if [ -n "$input" ] && validate_number "$input" 1 50; then
                PARALLEL_JOBS=$input
            fi
        fi
    fi
    press_any_key
}

show_summary() {
    print_header
    print_step "Zusammenfassung"
    
    echo -e "Cluster: $CLUSTER_ADDRESS"
    echo -e "Pfad: $BASE_PATH"
    echo -e "Präfix: $PREFIX"
    echo -e "Anzahl: $COUNT"
    echo -e "Quota: Hard=$QUOTA_HARD, Soft=$QUOTA_SOFT"
    echo
    print_warning "Nach dem Start können keine Änderungen mehr vorgenommen werden!"
    echo
}

################################################################################
# Ausführungs-Funktionen
################################################################################

# Helper to convert size string (1M, 1G) to bytes for API
size_to_bytes() {
    local size=$1
    local unit=${size: -1}
    local val=${size%?}
    
    case $unit in
        K|k) echo $(($val * 1024)) ;;
        M|m) echo $(($val * 1024 * 1024)) ;;
        G|g) echo $(($val * 1024 * 1024 * 1024)) ;;
        T|t) echo $(($val * 1024 * 1024 * 1024 * 1024)) ;;
        *) echo $size ;; # Assume bytes if no unit or unknown
    esac
}

create_dir_with_quota_api() {
    local i=$1
    local dir_name="${PREFIX}_$(printf "%04d" $i)"
    local dir_path="${BASE_PATH}/${dir_name}"

    # 1. Create Directory
    local mkdir_response=$(api_request "PUT" "/namespace${dir_path}" "" "x-isi-ifs-target-type: container")
    local mkdir_http_code=$(echo "$mkdir_response" | tail -n1)

    if [ "$mkdir_http_code" != "200" ] && [ "$mkdir_http_code" != "201" ] && [ "$mkdir_http_code" != "204" ]; then
        echo "MKDIR_ERROR: $dir_name (HTTP $mkdir_http_code)"
        return 1
    fi

    # 2. Create Quota using jq for proper JSON construction
    local hard_bytes=$(size_to_bytes "$QUOTA_HARD")

    local quota_json=$(jq -n \
        --arg type "directory" \
        --arg path "$dir_path" \
        --argjson hard "$hard_bytes" \
        --arg thresholds_on "$QUOTA_THRESHOLDS_ON" \
        --arg include_snaps "$QUOTA_INCLUDE_SNAPSHOTS" \
        '{type: $type, path: $path, thresholds: {hard: $hard}, thresholds_on: $thresholds_on, include_snapshots: ($include_snaps | test("true"; "i"))}')

    # Add soft threshold if specified
    if [ -n "$QUOTA_SOFT" ]; then
        local soft_bytes=$(size_to_bytes "$QUOTA_SOFT")
        quota_json=$(echo "$quota_json" | jq \
            --argjson soft "$soft_bytes" \
            --argjson grace "$QUOTA_SOFT_GRACE" \
            '.thresholds.soft = $soft | .soft_grace = $grace')
    fi

    # Add advisory threshold if specified
    if [ -n "$QUOTA_ADVISORY" ]; then
        local adv_bytes=$(size_to_bytes "$QUOTA_ADVISORY")
        quota_json=$(echo "$quota_json" | jq \
            --argjson advisory "$adv_bytes" \
            '.thresholds.advisory = $advisory')
    fi

    local quota_resp=$(api_request "POST" "/platform/1/quota/quotas" "$quota_json")
    local quota_http_code=$(echo "$quota_resp" | tail -n1)
    local quota_body=$(echo "$quota_resp" | sed '$d')

    if [ "$quota_http_code" = "201" ] || [ "$quota_http_code" = "200" ]; then
        return 0
    else
        echo "QUOTA_ERROR: $dir_name (HTTP $quota_http_code)"
        if [ -n "$quota_body" ] && command -v jq >/dev/null 2>&1; then
            local err_msg=$(echo "$quota_body" | jq -r '.errors[0].message // "Unknown error"' 2>/dev/null)
            echo "QUOTA_ERROR_MSG: $err_msg"
        fi
        return 1
    fi
}

execute_creation() {
    print_header
    print_step "Ausführung"

    local start_time=$(date +%s)
    local success=0
    local failed=0

    if [ "$USE_PARALLEL" = "y" ] && [ "$PARALLEL_AVAILABLE" = true ]; then
        # Export all necessary variables and functions for parallel execution
        export -f create_dir_with_quota_api size_to_bytes api_request check_api_error refresh_session
        export BASE_PATH PREFIX QUOTA_HARD QUOTA_SOFT QUOTA_ADVISORY QUOTA_SOFT_GRACE
        export QUOTA_THRESHOLDS_ON QUOTA_INCLUDE_SNAPSHOTS COOKIE_FILE API_BASE_URL ISI_CSRF_TOKEN
        export API_USER API_PASSWORD

        print_info "Starte parallele Ausführung mit $PARALLEL_JOBS Jobs..."

        # Use parallel with proper error handling
        local result_file="/tmp/quota_results_$$"
        seq 1 $COUNT | parallel --bar -j $PARALLEL_JOBS "create_dir_with_quota_api {} && echo SUCCESS || echo FAILED" > "$result_file"

        success=$(grep -c "SUCCESS" "$result_file" 2>/dev/null || echo 0)
        failed=$(grep -c "FAILED" "$result_file" 2>/dev/null || echo 0)
        rm -f "$result_file"
    else
        print_info "Starte sequentielle Ausführung..."

        for i in $(seq 1 $COUNT); do
            if create_dir_with_quota_api "$i"; then
                ((success++))
            else
                ((failed++))
            fi

            if [ $((i % 10)) -eq 0 ]; then
                echo -ne "\rFortschritt: $i / $COUNT (Erfolgreich: $success, Fehlgeschlagen: $failed)"
            fi
        done
    fi

    local end_time=$(date +%s)
    echo
    print_success "Ausführung beendet in $((end_time - start_time))s"
    print_success "Erfolgreich: $success"
    if [ $failed -gt 0 ]; then
        print_error "Fehlgeschlagen: $failed"
    fi
}

################################################################################
# Main
################################################################################

main() {
    check_system
    connect_cluster
    
    # Only Creation Mode implemented for API version v1
    get_base_path
    get_prefix
    get_count
    get_owner_settings
    get_quota_configuration
    get_quota_advanced_options
    get_parallel_settings
    
    show_summary
    
    if confirm_action "Starten?"; then
        execute_creation
    fi
}

main
