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
OUTPUT_MODE="compact"

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

# No cleanup needed for Basic Auth

################################################################################
# API Helper Functions
################################################################################

api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local extra_header="$4"

    if [ -z "$API_USER" ] || [ -z "$API_PASSWORD" ]; then
        print_error "API-Anmeldedaten fehlen"
        return 1
    fi

    local cmd=(curl -s -k -w "\n%{http_code}" -u "${API_USER}:${API_PASSWORD}" -X "$method")
    cmd+=(-H "Content-Type: application/json")
    cmd+=(-H "Accept: application/json")

    if [ -n "$extra_header" ]; then
        cmd+=(-H "$extra_header")
    fi

    if [ -n "$data" ]; then
        cmd+=(-d "$data")
    fi

    cmd+=("${API_BASE_URL}${endpoint}")

    "${cmd[@]}"
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

        print_info "Teste Basic Auth zu $CLUSTER_ADDRESS..."

        # Test Basic Auth with a simple API call
        local test_response=$(api_request "GET" "/platform/1/cluster/identity")
        local test_http_code=$(echo "$test_response" | tail -n1)

        if [ "$test_http_code" = "200" ]; then
            print_success "Verbindung erfolgreich!"
            print_info "Basic Auth funktioniert"

            # Export credentials for use in script
            export API_USER API_PASSWORD
            break
        elif [ "$test_http_code" = "401" ]; then
            print_error "Authentifizierung fehlgeschlagen! Bitte Anmeldedaten prüfen."
            CLUSTER_ADDRESS=""
            API_USER=""
            API_PASSWORD=""
        else
            local response_body=$(echo "$test_response" | sed '$d')
            if [ -n "$response_body" ] && command -v jq >/dev/null 2>&1; then
                local err_msg=$(echo "$response_body" | jq -r '.errors[0].message // "Connection failed"' 2>/dev/null)
                print_error "Verbindung fehlgeschlagen: $err_msg (HTTP $test_http_code)"
            else
                print_error "Verbindung fehlgeschlagen! HTTP $test_http_code"
            fi
            CLUSTER_ADDRESS=""
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
                                print_error "Authentifizierung fehlgeschlagen! Bitte Anmeldedaten prüfen."
                                print_info "Bitte das Skript neu starten."
                                exit 1
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

    echo -e "${WHITE}Verarbeitungsmodus wählen:${NC}"
    echo -e "${WHITE}1)${NC} Sequenziell (ein Verzeichnis nach dem anderen)"
    echo -e "${WHITE}2)${NC} Parallel (mehrere Verzeichnisse gleichzeitig mit Background-Jobs)"
    echo

    read -p "$(echo -e ${WHITE}${ARROW} Auswahl [${GREEN}1${WHITE}]:${NC} )" input
    case $input in
        2)
            USE_PARALLEL="y"
            echo
            print_info "Parallele Verarbeitung aktiviert (native Bash Background-Jobs)"
            while true; do
                read -p "$(echo -e ${WHITE}${ARROW} Anzahl parallele Jobs [${GREEN}$PARALLEL_JOBS${WHITE}]:${NC} )" jobs_input
                if [ -z "$jobs_input" ]; then jobs_input=$PARALLEL_JOBS; fi
                if validate_number "$jobs_input" 1 50; then
                    PARALLEL_JOBS=$jobs_input
                    print_success "Parallele Jobs: $PARALLEL_JOBS"
                    break
                fi
            done
            ;;
        *)
            USE_PARALLEL="n"
            print_success "Sequenzielle Verarbeitung gewählt"
            ;;
    esac

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

    if [ "$USE_PARALLEL" = "y" ]; then
        echo -e "Modus: Parallel ($PARALLEL_JOBS Jobs)"
    else
        echo -e "Modus: Sequenziell"
    fi

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
    local log_file="${2:-}"
    local dir_name="${PREFIX}_$(printf "%04d" $i)"
    local dir_path="${BASE_PATH}/${dir_name}"

    # Detailliertes Logging wenn gewünscht
    if [ -n "$log_file" ]; then
        echo "================== JOB #$i ==================" >> "$log_file"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
        echo "Directory: $dir_name" >> "$log_file"
        echo "Full Path: $dir_path" >> "$log_file"
        echo "" >> "$log_file"
    fi

    # 1. Create Directory via API
    if [ -n "$log_file" ]; then
        echo "[API REQUEST - CREATE DIR]" >> "$log_file"
        echo "Method: PUT" >> "$log_file"
        echo "Endpoint: /namespace${dir_path}" >> "$log_file"
        echo "Headers: x-isi-ifs-target-type: container" >> "$log_file"
        echo "" >> "$log_file"
    fi

    local mkdir_response=$(api_request "PUT" "/namespace${dir_path}" "" "x-isi-ifs-target-type: container")
    local mkdir_http_code=$(echo "$mkdir_response" | tail -n1)
    local mkdir_body=$(echo "$mkdir_response" | sed '$d')

    if [ -n "$log_file" ]; then
        echo "[API RESPONSE - CREATE DIR]" >> "$log_file"
        echo "HTTP Status: $mkdir_http_code" >> "$log_file"
        [ -n "$mkdir_body" ] && echo "Response: $mkdir_body" >> "$log_file"
        echo "" >> "$log_file"
    fi

    if [ "$mkdir_http_code" != "200" ] && [ "$mkdir_http_code" != "201" ] && [ "$mkdir_http_code" != "204" ]; then
        echo "API_MKDIR_ERROR: $dir_name (HTTP $mkdir_http_code)" >&2

        # Debug: Output API error message
        if [ -n "$mkdir_body" ] && command -v jq >/dev/null 2>&1; then
            local mkdir_err_msg=$(echo "$mkdir_body" | jq -r '.errors[0].message // "Unknown error"' 2>/dev/null)
            echo "API_DEBUG: $dir_name - $mkdir_err_msg" >&2
            [ -n "$log_file" ] && echo "[ERROR] Directory creation failed: $mkdir_err_msg" >> "$log_file"
        else
            [ -n "$log_file" ] && echo "[ERROR] Directory creation failed" >> "$log_file"
        fi
        return 1
    fi

    # 2. Create Quota using jq for proper JSON construction
    local hard_bytes=$(size_to_bytes "$QUOTA_HARD")

    local quota_json=$(jq -n \
        --arg type "directory" \
        --arg path "$dir_path" \
        --argjson hard "$hard_bytes" \
        --arg include_snaps "$QUOTA_INCLUDE_SNAPSHOTS" \
        '{
            type: $type,
            path: $path,
            enforced: true,
            container: true,
            include_snapshots: ($include_snaps | test("true"; "i")),
            thresholds: {
                hard: $hard
            },
            thresholds_include_overhead: false
        }')

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

    # Execute Quota API Call
    if [ -n "$log_file" ]; then
        echo "[API REQUEST - CREATE QUOTA]" >> "$log_file"
        echo "Method: POST" >> "$log_file"
        echo "Endpoint: /platform/1/quota/quotas" >> "$log_file"
        echo "Request Body:" >> "$log_file"
        echo "$quota_json" | jq '.' >> "$log_file" 2>/dev/null || echo "$quota_json" >> "$log_file"
        echo "" >> "$log_file"
    fi

    local quota_resp=$(api_request "POST" "/platform/1/quota/quotas" "$quota_json")
    local quota_http_code=$(echo "$quota_resp" | tail -n1)
    local quota_body=$(echo "$quota_resp" | sed '$d')

    if [ -n "$log_file" ]; then
        echo "[API RESPONSE - CREATE QUOTA]" >> "$log_file"
        echo "HTTP Status: $quota_http_code" >> "$log_file"
        if [ -n "$quota_body" ]; then
            echo "Response Body:" >> "$log_file"
            echo "$quota_body" | jq '.' >> "$log_file" 2>/dev/null || echo "$quota_body" >> "$log_file"
        fi
        echo "" >> "$log_file"
    fi

    if [ "$quota_http_code" = "201" ] || [ "$quota_http_code" = "200" ]; then
        echo "API_SUCCESS: $dir_name" >&1
        [ -n "$log_file" ] && echo "[SUCCESS] Operation completed successfully" >> "$log_file"
        return 0
    else
        echo "API_QUOTA_ERROR: $dir_name (HTTP $quota_http_code)" >&2
        if [ -n "$quota_body" ] && command -v jq >/dev/null 2>&1; then
            local err_msg=$(echo "$quota_body" | jq -r '.errors[0].message // "Unknown error"' 2>/dev/null)
            echo "API_DEBUG: $dir_name - $err_msg" >&2
            [ -n "$log_file" ] && echo "[ERROR] Quota creation failed: $err_msg" >> "$log_file"
        else
            [ -n "$log_file" ] && echo "[ERROR] Quota creation failed" >> "$log_file"
        fi
        return 1
    fi
}

show_job_monitor() {
    local temp_dir="$1"
    local job_id="$2"

    clear
    echo -e "${CYAN}========================================================================${NC}"
    echo -e "${WHITE}${BOLD}                     JOB MONITOR - API Details                         ${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    echo

    if [ "$job_id" = "list" ]; then
        # Liste alle Jobs
        echo -e "${WHITE}Verfügbare Job-Logs:${NC}"
        echo
        printf "%-10s %-30s %-10s\n" "Job #" "Verzeichnis" "Status"
        echo -e "${CYAN}------------------------------------------------------------------------${NC}"

        for i in $(seq 1 $COUNT); do
            local log_file="$temp_dir/logs/job_$i.log"
            if [ -f "$log_file" ]; then
                local dir_name="${PREFIX}_$(printf "%04d" $i)"
                local status="${YELLOW}RUNNING${NC}"
                [ -f "$temp_dir/success_$i" ] && status="${GREEN}SUCCESS${NC}"
                [ -f "$temp_dir/failed_$i" ] && status="${RED}FAILED${NC}"
                printf "%-10s %-30s " "$i" "$dir_name"
                echo -e "$status"
            fi
        done
    elif [ -f "$temp_dir/logs/job_$job_id.log" ]; then
        # Zeige spezifischen Job
        echo -e "${WHITE}Job #$job_id - API Request/Response Details:${NC}"
        echo -e "${CYAN}------------------------------------------------------------------------${NC}"
        cat "$temp_dir/logs/job_$job_id.log"
        echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    else
        echo -e "${RED}Job #$job_id nicht gefunden oder noch nicht gestartet${NC}"
    fi

    echo
    echo -e "${WHITE}Drücke eine Taste zum Fortfahren...${NC}"
    read -n1 -s
}

execute_creation() {
    print_header
    print_step "Ausführung"

    local start_time=$(date +%s)
    local success=0
    local failed=0

    if [ "$USE_PARALLEL" = "y" ]; then
        print_info "Starte parallele Ausführung mit $PARALLEL_JOBS Jobs..."
        echo

        # Temporäre Verzeichnisse für Tracking und Output-Sammlung
        local temp_dir="/tmp/quota_api_$$"
        mkdir -p "$temp_dir"
        mkdir -p "$temp_dir/logs"

        local running_jobs=0
        local job_pids=()
        local completed=0

        # Sammle Ergebnisse für sauberen Output
        local output_file="$temp_dir/output.txt"
        > "$output_file"

        # Monitor-Control-Datei
        local monitor_control="$temp_dir/monitor_control"
        echo "running" > "$monitor_control"

        # Fortschritts-Tracker mit interaktiver Monitor-Option
        (
            while [ "$(cat $monitor_control 2>/dev/null)" = "running" ]; do
                local current_success=$(ls "$temp_dir"/success_* 2>/dev/null | wc -l | tr -d ' ')
                local current_failed=$(ls "$temp_dir"/failed_* 2>/dev/null | wc -l | tr -d ' ')
                local current_total=$((current_success + current_failed))

                if [ $current_total -ge $COUNT ]; then
                    echo "done" > "$monitor_control"
                    break
                fi

                if [ $current_total -gt 0 ]; then
                    local percent=$((current_total * 100 / COUNT))
                    local elapsed=$(($(date +%s) - start_time))
                    local remaining=$((COUNT - current_total))
                    local eta=0
                    if [ $current_total -gt 0 ]; then
                        eta=$((elapsed * remaining / current_total))
                    fi

                    # Statuszeile
                    printf "\r${CYAN}Parallel:${NC} [%-20s] ${WHITE}%3d%%${NC} ${CYAN}(%d/%d)${NC} ${GREEN}✓%d${NC} ${RED}✗%d${NC} ${YELLOW}ETA:%dm%ds${NC}     " \
                        "$(printf '#%.0s' $(seq 1 $((percent / 5))))" \
                        "$percent" "$current_total" "$COUNT" \
                        "$current_success" "$current_failed" \
                        "$((eta / 60))" "$((eta % 60))"
                fi
                sleep 0.5
            done
        ) &
        local progress_pid=$!

        # Worker-Funktion
        process_worker() {
            local worker_id=$1
            local start_idx=$2
            local end_idx=$3
            local worker_log="$temp_dir/logs/worker_${worker_id}.log"

            for i in $(seq $start_idx $end_idx); do
                [ $i -gt $COUNT ] && break

                local dir_name="${PREFIX}_$(printf "%04d" $i)"

                # Führe Aktion aus mit detailliertem Logging
                local job_log="$temp_dir/logs/job_$i.log"

                # Capture stderr for debug messages in parallel mode
                local error_output
                if error_output=$(create_dir_with_quota_api "$i" "$job_log" 2>&1 >/dev/null); then
                    touch "$temp_dir/success_$i"
                    echo "SUCCESS:$i:$dir_name" >> "$worker_log"
                    echo "[FINAL STATUS] SUCCESS" >> "$job_log"
                else
                    touch "$temp_dir/failed_$i"
                    echo "FAILED:$i:$dir_name" >> "$worker_log"
                    echo "[FINAL STATUS] FAILED" >> "$job_log"
                    # Add debug messages to job log
                    if [ -n "$error_output" ]; then
                        echo "[DEBUG MESSAGES]" >> "$job_log"
                        echo "$error_output" >> "$job_log"
                    fi
                fi
            done
        }

        # Starte Worker für Batch-Verarbeitung
        local items_per_worker=$(( (COUNT + PARALLEL_JOBS - 1) / PARALLEL_JOBS ))

        for w in $(seq 1 $PARALLEL_JOBS); do
            local start_idx=$(( (w - 1) * items_per_worker + 1 ))
            local end_idx=$(( w * items_per_worker ))

            process_worker $w $start_idx $end_idx &
            job_pids+=($!)
        done

        # Warte auf alle Worker mit Option für Monitor
        echo
        echo -e "${CYAN}Jobs laufen...${NC}"
        echo -e "${YELLOW}Drücke 'Enter' für Job-Monitor oder warte auf Abschluss${NC}"
        echo

        local all_done=0
        while [ $all_done -eq 0 ]; do
            # Check ob alle Jobs fertig sind
            local still_running=0
            for pid in "${job_pids[@]}"; do
                if kill -0 $pid 2>/dev/null; then
                    still_running=1
                    break
                fi
            done

            if [ $still_running -eq 0 ]; then
                all_done=1
            else
                # Warte kurz und prüfe auf User-Input
                if read -t 1 -n1 key; then
                    echo
                    echo -e "${YELLOW}Job-Monitor Menü:${NC}"
                    echo -e "  ${WHITE}l${NC}  - Liste alle Jobs"
                    echo -e "  ${WHITE}1-$COUNT${NC} - Zeige spezifischen Job  "
                    echo -e "  ${WHITE}c${NC}  - Weiter mit Ausführung"
                    echo
                    read -p "$(echo -e ${WHITE}${ARROW} Auswahl:${NC} )" choice

                    case "$choice" in
                        l|L|list)
                            show_job_monitor "$temp_dir" "list"
                            ;;
                        c|C|"")
                            echo "Weiter mit Ausführung..."
                            ;;
                        *)
                            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$COUNT" ]; then
                                show_job_monitor "$temp_dir" "$choice"
                            else
                                echo -e "${RED}Ungültige Eingabe${NC}"
                            fi
                            ;;
                    esac
                    echo
                fi
            fi
        done

        # Warte auf alle Worker (sicherheitshalber)
        for pid in "${job_pids[@]}"; do
            wait $pid 2>/dev/null
        done
        completed=$COUNT

        # Stoppe Monitoring-Prozesse
        echo "done" > "$monitor_control"
        kill $progress_pid 2>/dev/null
        wait $progress_pid 2>/dev/null

        # Neue Zeile für sauberen Abschluss
        echo
        echo

        # Sammle und sortiere alle Ergebnisse für strukturierte Ausgabe
        echo -e "${CYAN}===== Verarbeitungsergebnisse =====${NC}"

        # Sortiere Logs und zeige Ergebnisse
        for log in "$temp_dir"/logs/worker_*.log; do
            [ -f "$log" ] && cat "$log"
        done | sort -t':' -k2 -n | while IFS=':' read status idx name; do
            if [ "$status" = "SUCCESS" ]; then
                printf "${GREEN}✓${NC} %-30s ${CYAN}[#%04d]${NC}\n" "$name" "$idx"
            else
                printf "${RED}✗${NC} %-30s ${CYAN}[#%04d]${NC}\n" "$name" "$idx"
            fi
        done

        # Finale Statistiken
        success=$(ls "$temp_dir"/success_* 2>/dev/null | wc -l | tr -d ' ')
        failed=$(ls "$temp_dir"/failed_* 2>/dev/null | wc -l | tr -d ' ')

        # Cleanup
        rm -rf "$temp_dir"

        echo
        echo -e "${GREEN}${BOLD}===== API Parallel-Verarbeitung Abgeschlossen =====${NC}"
    else
        print_info "Starte sequentielle API-Ausführung..."
        echo

        for i in $(seq 1 $COUNT); do
            local dir_name="${PREFIX}_$(printf "%04d" $i)"

            # Aktuelle Operation detailliert anzeigen
            printf "\r${BLUE}Erstelle via API: $dir_name${NC} ${CYAN}(%d/%d)${NC}" "$i" "$COUNT"

            # Capture stderr to show debug messages
            local error_output
            if error_output=$(create_dir_with_quota_api "$i" 2>&1 >/dev/null); then
                printf "\r${GREEN}${CHECK}${NC} API Erfolgreich: $dir_name ${CYAN}(%d/%d)${NC}\n" "$i" "$COUNT"
                ((success++))
            else
                printf "\r${RED}${CROSS}${NC} API Fehler: $dir_name ${CYAN}(%d/%d)${NC}\n" "$i" "$COUNT"
                # Show debug messages
                if [ -n "$error_output" ]; then
                    echo "$error_output" | grep "API_DEBUG:" | while read line; do
                        echo "  $line"
                    done
                fi
                ((failed++))
            fi

            # Detaillierter Fortschritt alle 20 Items oder bei wichtigen Meilensteinen
            if [ $((i % 20)) -eq 0 ] || [ $i -eq $COUNT ] || [ $i -eq 1 ]; then
                local percent=$((i * 100 / COUNT))
                local elapsed=$(($(date +%s) - start_time))
                local remaining=$((COUNT - i))
                local eta=0
                if [ $i -gt 0 ]; then
                    eta=$((elapsed * remaining / i))
                fi

                echo
                echo -e "${CYAN}======= API Sequenzielle Verarbeitung =======${NC}"
                printf "${YELLOW}Status:${NC} [%-20s] ${WHITE}%d%%${NC}\n" "$(printf '#%.0s' $(seq 1 $((percent / 5))))" "$percent"
                printf "${YELLOW}API-Calls:${NC} ${WHITE}%d${NC} von ${WHITE}%d${NC} abgeschlossen\n" "$i" "$COUNT"
                printf "${YELLOW}Erfolgreich:${NC} ${GREEN}%d${NC} | ${YELLOW}Fehlgeschlagen:${NC} ${RED}%d${NC}\n" "$success" "$failed"
                printf "${YELLOW}Zeit:${NC} %dm %ds | ${YELLOW}ETA:${NC} %dm %ds\n" "$((elapsed / 60))" "$((elapsed % 60))" "$((eta / 60))" "$((eta % 60))"
                printf "${YELLOW}Cluster:${NC} ${WHITE}%s${NC}\n" "$CLUSTER_ADDRESS"
                echo -e "${CYAN}===========================================${NC}"
                echo
            fi
        done
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo
    echo -e "${GREEN}${BOLD}===== API Ausführung Abgeschlossen =====${NC}"
    printf "${YELLOW}Gesamtdauer:${NC} ${WHITE}%dm %ds${NC}\n" "$((duration / 60))" "$((duration % 60))"
    printf "${YELLOW}Erfolgreich:${NC} ${GREEN}%d${NC} | ${YELLOW}Fehlgeschlagen:${NC} ${RED}%d${NC}\n" "$success" "$failed"
    if [ $success -gt 0 ]; then
        local avg_time=$((duration * 1000 / success))
        printf "${YELLOW}Durchschnitt:${NC} ${WHITE}%dms${NC} pro erfolgreichem API-Call\n" "$avg_time"
    fi
    printf "${YELLOW}API-Endpunkt:${NC} ${WHITE}%s${NC}\n" "$API_BASE_URL"
    echo -e "${GREEN}=========================================${NC}"
}

################################################################################
# Quota-Liste Funktionen
################################################################################

list_all_quotas() {
    print_header
    print_step "Quota-Übersicht"

    print_info "Lade alle Quotas vom Cluster..."
    echo

    # API-Aufruf für alle Quotas mit Pagination
    local all_quotas=""
    local resume_token=""
    local page_count=0
    local total_quotas=0

    while true; do
        local api_path="/platform/1/quota/quotas"
        if [ -n "$resume_token" ]; then
            # Bei resume darf limit nicht angegeben werden
            api_path="${api_path}?resume=${resume_token}"
        else
            # Nur beim ersten Aufruf limit setzen
            api_path="${api_path}?limit=3000"
        fi

        local response=$(api_request "GET" "$api_path")
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | sed '$d')

        if [ "$http_code" != "200" ]; then
            print_error "Fehler beim Abrufen der Quotas (HTTP $http_code)"
            if [ -n "$body" ] && command -v jq >/dev/null 2>&1; then
                local err_msg=$(echo "$body" | jq -r '.errors[0].message // "Unknown error"' 2>/dev/null)
                print_error "Details: $err_msg"
            fi
            press_any_key
            return 1
        fi

        ((page_count++))

        # Parse mit jq wenn verfügbar
        if command -v jq >/dev/null 2>&1; then
            # Zähle Quotas auf dieser Seite
            local page_quota_count=$(echo "$body" | jq '.quotas | length' 2>/dev/null || echo 0)
            total_quotas=$((total_quotas + page_quota_count))

            printf "\r${CYAN}Lade Quotas... Seite %d - Bisher %d Quotas gefunden${NC}" "$page_count" "$total_quotas"

            # Sammle Quotas von dieser Seite in temporäre Datei
            local temp_quota_file="/tmp/quotas_page_${page_count}_$$.json"
            echo "$body" | jq '.quotas' > "$temp_quota_file" 2>/dev/null

            # Check für weitere Seiten
            resume_token=$(echo "$body" | jq -r '.resume // ""' 2>/dev/null)

            if [ -z "$resume_token" ] || [ "$resume_token" = "null" ]; then
                break
            fi
        else
            # Fallback ohne jq
            print_warning "jq nicht installiert - Anzeige eingeschränkt"
            echo "$body"
            break
        fi
    done

    echo
    echo

    # Merge alle temporären Dateien zu einem JSON Array
    if command -v jq >/dev/null 2>&1 && [ $page_count -gt 0 ]; then
        # Kombiniere alle Seiten zu einem großen Array
        local merged_quotas_file="/tmp/all_quotas_$$.json"

        # Starte mit leerem Array
        echo "[]" > "$merged_quotas_file"

        # Füge alle Seiten hinzu
        for i in $(seq 1 $page_count); do
            local page_file="/tmp/quotas_page_${i}_$$.json"
            if [ -f "$page_file" ]; then
                jq -s '.[0] + .[1]' "$merged_quotas_file" "$page_file" > "${merged_quotas_file}.tmp" 2>/dev/null
                mv "${merged_quotas_file}.tmp" "$merged_quotas_file"
            fi
        done

        # Erstelle formatierte Tabelle
        echo -e "${CYAN}============================================================================${NC}"
        printf "${WHITE}%-40s %-15s %-15s %-10s${NC}\n" "PFAD" "HARD LIMIT" "SOFT LIMIT" "VERWENDET"
        echo -e "${CYAN}============================================================================${NC}"

        cat "$merged_quotas_file" | jq -r '.[] |
            "\(.path // "N/A")|
            \(if .thresholds.hard then (.thresholds.hard / 1024 / 1024 | tostring) + " MB" else "Kein Limit" end)|
            \(if .thresholds.soft then (.thresholds.soft / 1024 / 1024 | tostring) + " MB" else "Kein Limit" end)|
            \(if .usage.logical then (.usage.logical / 1024 / 1024 | round | tostring) + " MB" else "0 MB" end)"' |
        while IFS='|' read -r path hard soft used; do
            # Kürze Pfad wenn zu lang
            if [ ${#path} -gt 38 ]; then
                path="...${path: -35}"
            fi
            printf "%-40s %-15s %-15s %-10s\n" "$path" "$hard" "$soft" "$used"
        done

        echo -e "${CYAN}============================================================================${NC}"

        # Statistiken
        local with_hard=$(cat "$merged_quotas_file" | jq '[.[] | select(.thresholds.hard)] | length')
        local with_soft=$(cat "$merged_quotas_file" | jq '[.[] | select(.thresholds.soft)] | length')
        local with_advisory=$(cat "$merged_quotas_file" | jq '[.[] | select(.thresholds.advisory)] | length')
        local over_soft=$(cat "$merged_quotas_file" | jq '[.[] | select(.thresholds.soft and .usage.logical > .thresholds.soft)] | length')
        local over_hard=$(cat "$merged_quotas_file" | jq '[.[] | select(.thresholds.hard and .usage.logical > .thresholds.hard)] | length')

        echo
        echo -e "${GREEN}${BOLD}===== QUOTA STATISTIKEN =====${NC}"
        printf "${YELLOW}Gesamt Quotas:${NC} ${WHITE}%d${NC}\n" "$total_quotas"
        printf "${YELLOW}Mit Hard Limit:${NC} ${WHITE}%d${NC}\n" "$with_hard"
        printf "${YELLOW}Mit Soft Limit:${NC} ${WHITE}%d${NC}\n" "$with_soft"
        printf "${YELLOW}Mit Advisory:${NC} ${WHITE}%d${NC}\n" "$with_advisory"

        if [ "$over_soft" -gt 0 ]; then
            printf "${YELLOW}Soft Limit überschritten:${NC} ${RED}%d${NC}\n" "$over_soft"
        fi
        if [ "$over_hard" -gt 0 ]; then
            printf "${YELLOW}Hard Limit überschritten:${NC} ${RED}${BOLD}%d${NC}\n" "$over_hard"
        fi
        echo -e "${GREEN}==============================${NC}"

        # Cleanup temporäre Dateien
        rm -f /tmp/quotas_page_*_$$.json "$merged_quotas_file"
    fi

    echo
    press_any_key
}

main_menu() {
    while true; do
        print_header
        print_step "Hauptmenü"

        echo -e "${GREEN}Verbunden mit:${NC} $CLUSTER_ADDRESS"
        echo -e "${GREEN}Benutzer:${NC} $API_USER"
        echo
        echo -e "${WHITE}Wählen Sie eine Option:${NC}"
        echo
        echo -e "${WHITE}1)${NC} Quotas erstellen (Wizard)"
        echo -e "${WHITE}2)${NC} Quotas anzeigen (Liste aller Quotas)"
        echo -e "${WHITE}3)${NC} Verbindung trennen und beenden"
        echo

        read -p "$(echo -e ${WHITE}${ARROW} Auswahl [1-3]:${NC} )" choice

        case $choice in
            1)
                # Quota-Erstellung
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
                    press_any_key
                fi
                ;;
            2)
                # Quotas anzeigen
                list_all_quotas
                ;;
            3)
                # Beenden
                print_info "Verbindung wird getrennt..."
                echo
                print_success "Programm beendet."
                exit 0
                ;;
            *)
                print_error "Ungültige Auswahl!"
                sleep 1
                ;;
        esac
    done
}

################################################################################
# Main
################################################################################

main() {
    check_system
    connect_cluster
    main_menu
}

main
