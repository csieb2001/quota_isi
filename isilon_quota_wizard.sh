#!/bin/bash

################################################################################
# PowerScale/Isilon Directory & Quota Creation Wizard
# Interaktiver Assistent zur Erstellung von Verzeichnissen mit Quotas
#
# Copyright (c) 2024 Christopher Siebert
# Contact: christopher.siebert@concat.de
#
# Licensed under the MIT License - see LICENSE file for details
# https://opensource.org/licenses/MIT
#
# Version: 1.0
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
    echo -e "${WHITE}${BOLD}        PowerScale/Isilon Quota Wizard v1.0                         ${NC}"
    echo -e ""
    echo -e "        ${WHITE}Copyright © 2024 Christopher Siebert${NC}"
    echo -e "        ${CYAN}christopher.siebert@concat.de${NC}"
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

################################################################################
# Validierungsfunktionen
################################################################################

check_system() {
    print_header
    print_step "Schritt 1: System-Überprüfung"
    
    local errors=0
    
    # Prüfe ob isi verfügbar ist
    if command -v isi &> /dev/null; then
        print_success "OneFS CLI (isi) gefunden"
    else
        print_error "OneFS CLI (isi) nicht gefunden!"
        print_info "Dieses Script muss auf einem PowerScale/Isilon Node ausgeführt werden."
        ((errors++))
    fi
    
    # Prüfe OneFS Version
    if command -v isi &> /dev/null; then
        local onefs_version=$(isi version | grep "Isilon OneFS" | awk '{print $3}')
        if [ -n "$onefs_version" ]; then
            print_success "OneFS Version: $onefs_version"
        fi
    fi
    
    # Prüfe Berechtigungen
    if [ "$EUID" -eq 0 ]; then
        print_success "Root-Berechtigung vorhanden"
    else
        print_warning "Läuft nicht als root (möglicherweise ausreichende Rechte nötig)"
    fi
    
    # Prüfe ob GNU Parallel verfügbar ist
    if command -v parallel &> /dev/null; then
        print_success "GNU Parallel verfügbar (für schnellere Verarbeitung)"
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
    
    if [ ! -d "$path" ]; then
        print_error "Pfad existiert nicht: $path"
        return 1
    fi
    
    return 0
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

validate_user() {
    local user="$1"
    
    # Prüfe ob User existiert (mit id Befehl)
    if id "$user" &>/dev/null; then
        return 0
    else
        print_error "User '$user' existiert nicht auf dem System!"
        print_info "Tipp: Verwende 'id <username>' um zu prüfen, ob ein User existiert"
        return 1
    fi
}

validate_group() {
    local group="$1"
    
    # Prüfe ob Group existiert
    if getent group "$group" &>/dev/null; then
        return 0
    else
        print_error "Gruppe '$group' existiert nicht auf dem System!"
        print_info "Tipp: Verwende 'getent group <groupname>' um zu prüfen, ob eine Gruppe existiert"
        return 1
    fi
}

################################################################################
# Eingabe-Funktionen
################################################################################

get_base_path() {
    print_header
    print_step "Schritt 1: Basis-Pfad konfigurieren"
    
    print_info "Gib den Basis-Pfad auf dem PowerScale an, unter dem die"
    print_info "Verzeichnisse erstellt werden sollen."
    echo
    print_info "Beispiele: /ifs/data/projects, /ifs/home/testdirs"
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Basis-Pfad:${NC} )" BASE_PATH
        
        # Leere Eingabe prüfen
        if [ -z "$BASE_PATH" ]; then
            print_error "Pfad darf nicht leer sein!"
            echo
            continue
        fi
        
        # Prüfen ob Pfad mit /ifs beginnt
        if [[ ! "$BASE_PATH" =~ ^/ifs ]]; then
            print_error "Pfad muss mit /ifs beginnen!"
            echo
            continue
        fi
        
        # Prüfen ob Pfad existiert
        if [ ! -d "$BASE_PATH" ]; then
            print_warning "Pfad existiert noch nicht: $BASE_PATH"
            echo
            
            if confirm_action "Möchtest du den Pfad jetzt erstellen?"; then
                # Versuche Pfad anzulegen
                if mkdir -p "$BASE_PATH" 2>/dev/null; then
                    print_success "Pfad erfolgreich erstellt: $BASE_PATH"
                    
                    # Prüfe Schreibrechte
                    local test_file="${BASE_PATH}/.quota_wizard_test_$$"
                    if touch "$test_file" 2>/dev/null; then
                        rm -f "$test_file"
                        print_success "Pfad ist beschreibbar"
                        break
                    else
                        print_error "Keine Schreibrechte auf dem erstellten Pfad!"
                        # Aufräumen: erstellten Pfad wieder löschen
                        rmdir "$BASE_PATH" 2>/dev/null
                    fi
                else
                    print_error "Konnte Pfad nicht erstellen! Überprüfe Berechtigungen."
                    print_info "Möglicherweise existiert das übergeordnete Verzeichnis nicht"
                    print_info "oder du hast keine ausreichenden Berechtigungen."
                fi
            else
                print_info "Bitte gib einen existierenden Pfad an oder erstelle ihn manuell."
            fi
            echo
            continue
        fi
        
        # Pfad existiert - Prüfe Schreibrechte
        local test_file="${BASE_PATH}/.quota_wizard_test_$$"
        if touch "$test_file" 2>/dev/null; then
            rm -f "$test_file"
            print_success "Pfad ist gültig und beschreibbar: $BASE_PATH"
            
            # Prüfe ob Pfad leer ist oder bereits Inhalte hat
            local existing_count=$(find "$BASE_PATH" -maxdepth 1 -type d -name "${PREFIX}_*" 2>/dev/null | wc -l)
            if [ $existing_count -gt 0 ]; then
                print_warning "Achtung: Es existieren bereits $existing_count Verzeichnisse mit dem Präfix '${PREFIX}_*'"
                echo
                if ! confirm_action "Trotzdem fortfahren?"; then
                    continue
                fi
            fi
            
            break
        else
            print_error "Keine Schreibrechte auf: $BASE_PATH"
            echo
        fi
    done
    
    press_any_key
}

get_prefix() {
    print_header
    print_step "Schritt 2: Verzeichnis-Präfix"
    
    print_info "Die Verzeichnisse werden nummeriert erstellt."
    print_info "Standard-Präfix: 'dir' → Ergebnis: dir_0001, dir_0002, ..."
    echo
    
    read -p "$(echo -e ${WHITE}${ARROW} Präfix [${GREEN}$PREFIX${WHITE}]:${NC} )" input
    
    if [ -n "$input" ]; then
        PREFIX="$input"
    fi
    
    print_success "Präfix gesetzt: $PREFIX"
    print_info "Beispiel: ${PREFIX}_0001, ${PREFIX}_0002, ..."
    
    press_any_key
}

get_count() {
    print_header
    print_step "Schritt 3: Anzahl der Verzeichnisse"
    
    print_info "Wie viele Verzeichnisse sollen erstellt werden?"
    print_info "Erlaubter Bereich: 1 - 100000"
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Anzahl [${GREEN}$COUNT${WHITE}]:${NC} )" input
        
        if [ -z "$input" ]; then
            input=$COUNT
        fi
        
        if validate_number "$input" 1 100000; then
            COUNT=$input
            print_success "Anzahl gesetzt: $COUNT Verzeichnisse"
            break
        fi
        echo
    done
    
    press_any_key
}

get_owner_settings() {
    print_header
    print_step "Schritt 4: Verzeichnis-Owner"
    
    print_info "Möchtest du einen spezifischen Owner (User/Group) für die"
    print_info "Verzeichnisse festlegen?"
    echo
    print_info "Standard: Verzeichnisse werden mit dem aktuellen User erstellt"
    print_info "Aktueller User: $(whoami)"
    echo
    
    if confirm_action "Owner manuell festlegen?"; then
        SET_OWNER="y"
        echo
        
        # User abfragen
        print_info "${BOLD}User (Owner)${NC}"
        print_info "Gib den Benutzernamen an, dem die Verzeichnisse gehören sollen."
        echo
        
        while true; do
            read -p "$(echo -e ${WHITE}${ARROW} User:${NC} )" OWNER_USER
            
            if [ -z "$OWNER_USER" ]; then
                print_error "User darf nicht leer sein!"
                echo
                continue
            fi
            
            if validate_user "$OWNER_USER"; then
                local user_id=$(id -u "$OWNER_USER" 2>/dev/null)
                print_success "User gesetzt: $OWNER_USER (UID: $user_id)"
                break
            fi
            echo
        done
        
        echo
        
        # Group abfragen
        print_info "${BOLD}Gruppe (Group)${NC}"
        print_info "Gib die Gruppe an, der die Verzeichnisse gehören sollen."
        print_info "Standard-Gruppe von $OWNER_USER: $(id -gn "$OWNER_USER" 2>/dev/null)"
        echo
        
        while true; do
            read -p "$(echo -e ${WHITE}${ARROW} Gruppe [${GREEN}$(id -gn "$OWNER_USER" 2>/dev/null)${WHITE}]:${NC} )" input
            
            if [ -z "$input" ]; then
                OWNER_GROUP=$(id -gn "$OWNER_USER" 2>/dev/null)
            else
                OWNER_GROUP="$input"
            fi
            
            if validate_group "$OWNER_GROUP"; then
                local group_id=$(getent group "$OWNER_GROUP" | cut -d: -f3)
                print_success "Gruppe gesetzt: $OWNER_GROUP (GID: $group_id)"
                break
            fi
            echo
        done
        
        echo
        print_success "Owner-Konfiguration abgeschlossen: $OWNER_USER:$OWNER_GROUP"
        
    else
        SET_OWNER="n"
        OWNER_USER=$(whoami)
        OWNER_GROUP=$(id -gn)
        print_info "Verwende aktuellen User: $OWNER_USER:$OWNER_GROUP"
    fi
    
    press_any_key
}

get_quota_configuration() {
    print_header
    print_step "Schritt 5: Quota-Konfiguration"
    
    # Hard Threshold (Pflicht)
    print_info "${BOLD}Hard Threshold${NC} (Pflicht)"
    print_info "Die maximale Größe, die nicht überschritten werden kann."
    print_info "Format: Zahl + Einheit (K=KB, M=MB, G=GB, T=TB)"
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Hard Threshold [${GREEN}$QUOTA_HARD${WHITE}]:${NC} )" input
        
        if [ -z "$input" ]; then
            input=$QUOTA_HARD
        fi
        
        if validate_quota_size "$input"; then
            QUOTA_HARD=$input
            print_success "Hard Threshold gesetzt: $QUOTA_HARD"
            break
        fi
        echo
    done
    
    echo
    
    # Soft Threshold (Optional)
    print_info "${BOLD}Soft Threshold${NC} (Optional - leer lassen für keine Soft Quota)"
    print_info "Warnschwelle, ab der eine Grace Period beginnt."
    print_info "Beispiel: 800K (bei 1M Hard Threshold = 80%)"
    echo
    
    read -p "$(echo -e ${WHITE}${ARROW} Soft Threshold [leer]:${NC} )" input
    
    if [ -n "$input" ]; then
        if validate_quota_size "$input"; then
            QUOTA_SOFT=$input
            print_success "Soft Threshold gesetzt: $QUOTA_SOFT"
        else
            print_warning "Ungültige Eingabe, Soft Threshold wird nicht gesetzt"
            QUOTA_SOFT=""
        fi
    else
        print_info "Kein Soft Threshold gesetzt"
    fi
    
    echo
    
    # Advisory Threshold (Optional)
    print_info "${BOLD}Advisory Threshold${NC} (Optional - leer lassen für keine Advisory Quota)"
    print_info "Informationsschwelle ohne Einschränkungen."
    print_info "Beispiel: 500K (bei 1M Hard Threshold = 50%)"
    echo
    
    read -p "$(echo -e ${WHITE}${ARROW} Advisory Threshold [leer]:${NC} )" input
    
    if [ -n "$input" ]; then
        if validate_quota_size "$input"; then
            QUOTA_ADVISORY=$input
            print_success "Advisory Threshold gesetzt: $QUOTA_ADVISORY"
        else
            print_warning "Ungültige Eingabe, Advisory Threshold wird nicht gesetzt"
            QUOTA_ADVISORY=""
        fi
    else
        print_info "Kein Advisory Threshold gesetzt"
    fi
    
    # Soft Grace Period (nur wenn Soft Threshold gesetzt)
    if [ -n "$QUOTA_SOFT" ]; then
        echo
        print_info "${BOLD}Soft Grace Period${NC}"
        print_info "Zeit in Sekunden, die nach Erreichen des Soft Threshold"
        print_info "noch geschrieben werden darf."
        print_info "Standard: 604800 Sekunden (7 Tage)"
        print_info "Weitere Optionen: 86400=1 Tag, 259200=3 Tage, 1209600=2 Wochen"
        echo
        
        while true; do
            read -p "$(echo -e ${WHITE}${ARROW} Grace Period in Sekunden [${GREEN}$QUOTA_SOFT_GRACE${WHITE}]:${NC} )" input
            
            if [ -z "$input" ]; then
                input=$QUOTA_SOFT_GRACE
            fi
            
            if validate_grace_period "$input"; then
                QUOTA_SOFT_GRACE=$input
                local days=$((input / 86400))
                print_success "Grace Period gesetzt: $QUOTA_SOFT_GRACE Sekunden (~$days Tage)"
                break
            fi
            echo
        done
    fi
    
    press_any_key
}

get_quota_advanced_options() {
    print_header
    print_step "Schritt 6: Erweiterte Quota-Optionen"
    
    # Thresholds On
    print_info "${BOLD}Quota-Berechnungsgrundlage${NC}"
    print_info "Wie soll die Quota-Größe berechnet werden?"
    echo
    echo -e "${WHITE}1)${NC} applogicalsize   ${CYAN}(Standard - logische Größe der App-Daten)${NC}"
    echo -e "${WHITE}2)${NC} fslogicalsize    ${CYAN}(logische Dateisystemgröße)${NC}"
    echo -e "${WHITE}3)${NC} physicalsize     ${CYAN}(physische Größe auf Disk inkl. Overhead)${NC}"
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Auswahl [${GREEN}1${WHITE}]:${NC} )" input
        
        if [ -z "$input" ]; then
            input=1
        fi
        
        case $input in
            1)
                QUOTA_THRESHOLDS_ON="applogicalsize"
                print_success "Berechnungsgrundlage: applogicalsize"
                break
                ;;
            2)
                QUOTA_THRESHOLDS_ON="fslogicalsize"
                print_success "Berechnungsgrundlage: fslogicalsize"
                break
                ;;
            3)
                QUOTA_THRESHOLDS_ON="physicalsize"
                print_success "Berechnungsgrundlage: physicalsize"
                break
                ;;
            *)
                print_error "Ungültige Auswahl! Bitte 1, 2 oder 3 eingeben."
                ;;
        esac
        echo
    done
    
    echo
    
    # Include Snapshots
    print_info "${BOLD}Snapshots in Quota einbeziehen?${NC}"
    print_info "Sollen Snapshots zur Quota-Berechnung hinzugezählt werden?"
    echo
    
    if confirm_action "Snapshots einbeziehen?"; then
        QUOTA_INCLUDE_SNAPSHOTS="true"
        print_success "Snapshots werden in Quota einbezogen"
    else
        QUOTA_INCLUDE_SNAPSHOTS="false"
        print_success "Snapshots werden NICHT in Quota einbezogen"
    fi
    
    press_any_key
}

get_parallel_settings() {
    print_header
    print_step "Schritt 7: Performance-Einstellungen"
    
    if [ "$PARALLEL_AVAILABLE" = true ] || command -v xargs &> /dev/null; then
        print_info "Möchtest du parallele Verarbeitung aktivieren?"
        print_info "Dies beschleunigt die Erstellung erheblich."
        echo
        
        if confirm_action "Parallele Verarbeitung aktivieren?"; then
            USE_PARALLEL="y"
            echo
            print_info "Anzahl paralleler Jobs (empfohlen: 5-20)"
            
            while true; do
                read -p "$(echo -e ${WHITE}${ARROW} Parallele Jobs [${GREEN}$PARALLEL_JOBS${WHITE}]:${NC} )" input
                
                if [ -z "$input" ]; then
                    input=$PARALLEL_JOBS
                fi
                
                if validate_number "$input" 1 50; then
                    PARALLEL_JOBS=$input
                    print_success "Parallele Jobs gesetzt: $PARALLEL_JOBS"
                    break
                fi
                echo
            done
        else
            USE_PARALLEL="n"
            print_info "Sequentielle Verarbeitung wird verwendet"
        fi
    else
        print_warning "Parallele Verarbeitung nicht verfügbar"
        USE_PARALLEL="n"
    fi
    
    press_any_key
}

show_summary() {
    print_header
    print_step "Schritt 8: Zusammenfassung"
    
    echo -e "${WHITE}${BOLD}Konfiguration:${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    printf "%-32s ${WHITE}%s${NC}\n" "Basis-Pfad:" "$BASE_PATH"
    printf "%-32s ${WHITE}%s${NC}\n" "Verzeichnis-Präfix:" "$PREFIX"
    printf "%-32s ${WHITE}%s${NC}\n" "Anzahl Verzeichnisse:" "$COUNT"
    if [ "$SET_OWNER" = "y" ]; then
        printf "%-32s ${WHITE}%s${NC}\n" "Owner:" "$OWNER_USER:$OWNER_GROUP"
    else
        printf "%-32s ${WHITE}%s${NC}\n" "Owner:" "$OWNER_USER:$OWNER_GROUP (Standard)"
    fi
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    echo -e "${BOLD}Quota-Einstellungen:${NC}"
    printf "  %-30s ${WHITE}%s${NC}\n" "Hard Threshold:" "$QUOTA_HARD"
    if [ -n "$QUOTA_SOFT" ]; then
        printf "  %-30s ${WHITE}%s${NC}\n" "Soft Threshold:" "$QUOTA_SOFT"
        printf "  %-30s ${WHITE}%s Sek (~%d Tage)${NC}\n" "Grace Period:" "$QUOTA_SOFT_GRACE" "$((QUOTA_SOFT_GRACE / 86400))"
    else
        printf "  %-30s ${WHITE}%s${NC}\n" "Soft Threshold:" "(nicht gesetzt)"
    fi
    if [ -n "$QUOTA_ADVISORY" ]; then
        printf "  %-30s ${WHITE}%s${NC}\n" "Advisory Threshold:" "$QUOTA_ADVISORY"
    else
        printf "  %-30s ${WHITE}%s${NC}\n" "Advisory Threshold:" "(nicht gesetzt)"
    fi
    printf "  %-30s ${WHITE}%s${NC}\n" "Berechnungsgrundlage:" "$QUOTA_THRESHOLDS_ON"
    if [ "$QUOTA_INCLUDE_SNAPSHOTS" = "true" ]; then
        printf "  %-30s ${WHITE}%s${NC}\n" "Snapshots:" "Einbezogen"
    else
        printf "  %-30s ${WHITE}%s${NC}\n" "Snapshots:" "NICHT einbezogen"
    fi
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    if [ "$USE_PARALLEL" = "y" ]; then
        printf "%-32s ${WHITE}%s${NC}\n" "Verarbeitungsmodus:" "Parallel ($PARALLEL_JOBS Jobs)"
    else
        printf "%-32s ${WHITE}%s${NC}\n" "Verarbeitungsmodus:" "Sequentiell"
    fi
    echo -e "${CYAN}========================================================================${NC}"
    echo
    
    # Schätzung der Dauer
    local estimated_time
    if [ "$USE_PARALLEL" = "y" ]; then
        estimated_time=$((COUNT / PARALLEL_JOBS / 10))  # grobe Schätzung: 10 pro Sekunde
    else
        estimated_time=$((COUNT / 5))  # grobe Schätzung: 5 pro Sekunde
    fi
    
    if [ $estimated_time -gt 60 ]; then
        local minutes=$((estimated_time / 60))
        print_info "Geschätzte Dauer: ca. $minutes Minuten"
    else
        print_info "Geschätzte Dauer: ca. $estimated_time Sekunden"
    fi
    
    echo
    print_warning "Nach dem Start können keine Änderungen mehr vorgenommen werden!"
    echo
}

################################################################################
# Ausführungs-Funktionen
################################################################################

create_dirs_sequential() {
    local success=0
    local failed=0
    local start_time=$(date +%s)
    local current_operation=""

    for i in $(seq 1 $COUNT); do
        local dir_name="${PREFIX}_$(printf "%04d" $i)"
        local dir_path="${BASE_PATH}/${dir_name}"

        # Aktuelle Operation anzeigen
        current_operation="Erstelle Verzeichnis: $dir_name"
        printf "\r${BLUE}${current_operation}${NC} ${CYAN}(%d/%d)${NC}" "$i" "$COUNT"

        # Verzeichnis erstellen
        if mkdir -p "$dir_path" 2>/dev/null; then
            # Owner setzen (falls gewünscht)
            if [ "$SET_OWNER" = "y" ]; then
                current_operation="Setze Owner: $dir_name"
                printf "\r${BLUE}${current_operation}${NC} ${CYAN}(%d/%d)${NC}" "$i" "$COUNT"

                if ! chown "$OWNER_USER:$OWNER_GROUP" "$dir_path" 2>/dev/null; then
                    printf "\r${RED}${CROSS}${NC} Owner-Fehler: $dir_name ${CYAN}(%d/%d)${NC}\n" "$i" "$COUNT"
                    ((failed++))
                    continue
                fi
            fi

            # Quota erstellen anzeigen
            current_operation="Erstelle Quota: $dir_name"
            printf "\r${BLUE}${current_operation}${NC} ${CYAN}(%d/%d)${NC}" "$i" "$COUNT"

            # Quota-Befehl zusammenbauen
            local quota_cmd="isi quota quotas create \"$dir_path\" directory --hard-threshold \"$QUOTA_HARD\""
            quota_cmd="$quota_cmd --thresholds-on \"$QUOTA_THRESHOLDS_ON\""
            quota_cmd="$quota_cmd --include-snapshots $QUOTA_INCLUDE_SNAPSHOTS"

            # Soft Threshold hinzufügen (optional)
            if [ -n "$QUOTA_SOFT" ]; then
                quota_cmd="$quota_cmd --soft-threshold \"$QUOTA_SOFT\""
                quota_cmd="$quota_cmd --soft-grace $QUOTA_SOFT_GRACE"
            fi

            # Advisory Threshold hinzufügen (optional)
            if [ -n "$QUOTA_ADVISORY" ]; then
                quota_cmd="$quota_cmd --advisory-threshold \"$QUOTA_ADVISORY\""
            fi

            # Quota erstellen
            if eval "$quota_cmd" 2>/dev/null; then
                printf "\r${GREEN}${CHECK}${NC} Erfolgreich: $dir_name ${CYAN}(%d/%d)${NC}\n" "$i" "$COUNT"
                ((success++))
            else
                printf "\r${RED}${CROSS}${NC} Quota-Fehler: $dir_name ${CYAN}(%d/%d)${NC}\n" "$i" "$COUNT"
                ((failed++))
            fi
        else
            printf "\r${RED}${CROSS}${NC} Verzeichnis-Fehler: $dir_name ${CYAN}(%d/%d)${NC}\n" "$i" "$COUNT"
            ((failed++))
        fi

        # Detaillierter Fortschritt alle 25 Items oder bei wichtigen Meilensteinen
        if [ $((i % 25)) -eq 0 ] || [ $i -eq $COUNT ] || [ $i -eq 1 ]; then
            local percent=$((i * 100 / COUNT))
            local elapsed=$(($(date +%s) - start_time))
            local remaining=$((COUNT - i))
            local eta=0
            if [ $i -gt 0 ]; then
                eta=$((elapsed * remaining / i))
            fi

            echo
            echo -e "${CYAN}========================================${NC}"
            printf "${YELLOW}Status:${NC} [%-20s] ${WHITE}%d%%${NC}\n" "$(printf '#%.0s' $(seq 1 $((percent / 5))))" "$percent"
            printf "${YELLOW}Fortschritt:${NC} ${WHITE}%d${NC} von ${WHITE}%d${NC} Quotas erstellt\n" "$i" "$COUNT"
            printf "${YELLOW}Erfolgreich:${NC} ${GREEN}%d${NC} | ${YELLOW}Fehlgeschlagen:${NC} ${RED}%d${NC}\n" "$success" "$failed"
            printf "${YELLOW}Zeit:${NC} %dm %ds | ${YELLOW}ETA:${NC} %dm %ds\n" "$((elapsed / 60))" "$((elapsed % 60))" "$((eta / 60))" "$((eta % 60))"
            echo -e "${CYAN}========================================${NC}"
            echo
        fi
    done

    echo
    return $((success > 0 ? 0 : 1))
}

create_dir_with_quota() {
    local i=$1
    local dir_name="${PREFIX}_$(printf "%04d" $i)"
    local dir_path="${BASE_PATH}/${dir_name}"

    # Verzeichnis erstellen
    if mkdir -p "$dir_path" 2>/dev/null; then
        # Owner setzen (falls gewünscht)
        if [ "$SET_OWNER" = "y" ]; then
            if ! chown "$OWNER_USER:$OWNER_GROUP" "$dir_path" 2>/dev/null; then
                echo "CHOWN_ERROR: $dir_name" >&2
                return 1
            fi
        fi

        # Quota-Befehl zusammenbauen
        local quota_cmd="isi quota quotas create \"$dir_path\" directory --hard-threshold \"$QUOTA_HARD\""
        quota_cmd="$quota_cmd --thresholds-on \"$QUOTA_THRESHOLDS_ON\""
        quota_cmd="$quota_cmd --include-snapshots $QUOTA_INCLUDE_SNAPSHOTS"

        # Soft Threshold hinzufügen (optional)
        if [ -n "$QUOTA_SOFT" ]; then
            quota_cmd="$quota_cmd --soft-threshold \"$QUOTA_SOFT\""
            quota_cmd="$quota_cmd --soft-grace $QUOTA_SOFT_GRACE"
        fi

        # Advisory Threshold hinzufügen (optional)
        if [ -n "$QUOTA_ADVISORY" ]; then
            quota_cmd="$quota_cmd --advisory-threshold \"$QUOTA_ADVISORY\""
        fi

        # Quota erstellen
        if eval "$quota_cmd" 2>/dev/null; then
            echo "SUCCESS: $dir_name" >&1
            return 0
        else
            echo "QUOTA_ERROR: $dir_name" >&2
            return 1
        fi
    else
        echo "MKDIR_ERROR: $dir_name" >&2
        return 1
    fi
}

create_dirs_parallel() {
    export -f create_dir_with_quota
    export BASE_PATH PREFIX QUOTA_HARD QUOTA_SOFT QUOTA_ADVISORY QUOTA_SOFT_GRACE QUOTA_THRESHOLDS_ON QUOTA_INCLUDE_SNAPSHOTS
    export SET_OWNER OWNER_USER OWNER_GROUP

    local start_time=$(date +%s)
    local success=0
    local failed=0
    local temp_dir="/tmp/quota_local_$$"
    mkdir -p "$temp_dir"

    # Vereinfachtes Progress-Monitoring ohne flock
    (
        local last_reported=0
        while [ ! -f "$temp_dir/done" ]; do
            local current_success=$(ls "$temp_dir"/success_* 2>/dev/null | wc -l | tr -d ' ')
            local current_failed=$(ls "$temp_dir"/failed_* 2>/dev/null | wc -l | tr -d ' ')
            local current_total=$((current_success + current_failed))

            if [ $current_total -gt $last_reported ]; then
                local percent=$((current_total * 100 / COUNT))
                local elapsed=$(($(date +%s) - start_time))
                local remaining=$((COUNT - current_total))
                local eta=0
                if [ $current_total -gt 0 ]; then
                    eta=$((elapsed * remaining / current_total))
                fi

                printf "\r${CYAN}Parallel-Fortschritt:${NC} [%-30s] ${WHITE}%d%%${NC} ${CYAN}(%d/%d)${NC}" \
                    "$(printf '#%.0s' $(seq 1 $((percent / 3))))" \
                    "$percent" "$current_total" "$COUNT"
                printf " ${GREEN}\u2713%d${NC} ${RED}\u2717%d${NC} ${YELLOW}ETA:%dm%ds${NC}" \
                    "$current_success" "$current_failed" "$((eta / 60))" "$((eta % 60))"

                # Detaillierte Updates alle 50 Items
                if [ $((current_total % 50)) -eq 0 ] && [ $current_total -gt $last_reported ]; then
                    echo
                    echo -e "${CYAN}===== Zwischenstand (Parallel-Modus) =====${NC}"
                    printf "${YELLOW}Verarbeitet:${NC} ${WHITE}%d${NC} von ${WHITE}%d${NC} Quotas\n" "$current_total" "$COUNT"
                    printf "${YELLOW}Erfolgreich:${NC} ${GREEN}%d${NC} | ${YELLOW}Fehlgeschlagen:${NC} ${RED}%d${NC}\n" "$current_success" "$current_failed"
                    printf "${YELLOW}Laufzeit:${NC} %dm %ds | ${YELLOW}Restzeit:${NC} %dm %ds\n" "$((elapsed / 60))" "$((elapsed % 60))" "$((eta / 60))" "$((eta % 60))"
                    printf "${YELLOW}Jobs parallel:${NC} ${WHITE}%d${NC}\n" "$PARALLEL_JOBS"
                    echo -e "${CYAN}===========================================${NC}"
                fi
                last_reported=$current_total
            fi
            sleep 1
        done
    ) &
    local progress_pid=$!

    # Parallele Ausführung mit vereinfachtem Tracking
    if command -v parallel &> /dev/null; then
        # GNU Parallel mit File-basiertem Tracking
        seq 1 $COUNT | parallel -j $PARALLEL_JOBS "
            dir_name=\"${PREFIX}_\$(printf '%04d' {})\"
            if create_dir_with_quota {} >/dev/null 2>&1; then
                touch \"$temp_dir/success_{}\"
                echo \"${GREEN}\u2713${NC} \$dir_name\"
            else
                touch \"$temp_dir/failed_{}\"
                echo \"${RED}\u2717${NC} \$dir_name\"
            fi
        " 2>/dev/null
    else
        # xargs Fallback mit File-basiertem Tracking
        seq 1 $COUNT | xargs -P $PARALLEL_JOBS -I {} bash -c '
            dir_name="${PREFIX}_$(printf "%04d" $1)"
            if create_dir_with_quota "$1" >/dev/null 2>&1; then
                touch "'$temp_dir'/success_$1"
                printf "${GREEN}\u2713${NC} %s\n" "$dir_name"
            else
                touch "'$temp_dir'/failed_$1"
                printf "${RED}\u2717${NC} %s\n" "$dir_name"
            fi
        ' _ {}
    fi

    # Signal für Progress-Monitor
    touch "$temp_dir/done"

    # Progress-Monitoring stoppen
    kill $progress_pid 2>/dev/null
    wait $progress_pid 2>/dev/null

    # Finale Statistiken
    success=$(ls "$temp_dir"/success_* 2>/dev/null | wc -l | tr -d ' ')
    failed=$(ls "$temp_dir"/failed_* 2>/dev/null | wc -l | tr -d ' ')

    # Cleanup
    rm -rf "$temp_dir"

    local elapsed=$(($(date +%s) - start_time))
    echo
    echo
    echo -e "${GREEN}${BOLD}===== Parallel-Verarbeitung Abgeschlossen =====${NC}"
    printf "${YELLOW}Verarbeitungszeit:${NC} ${WHITE}%dm %ds${NC}\n" "$((elapsed / 60))" "$((elapsed % 60))"
    printf "${YELLOW}Erfolgreich:${NC} ${GREEN}%d${NC} | ${YELLOW}Fehlgeschlagen:${NC} ${RED}%d${NC}\n" "$success" "$failed"
    if [ $success -gt 0 ]; then
        local avg_time=$((elapsed * 1000 / success))
        printf "${YELLOW}Durchschnitt:${NC} ${WHITE}%dms${NC} pro erfolgreichem Verzeichnis\n" "$avg_time"
    fi
    echo -e "${GREEN}=============================================${NC}"
}

execute_creation() {
    print_header
    print_step "Ausführung"
    
    print_info "Starte Erstellung der Verzeichnisse und Quotas..."
    echo
    
    local start_time=$(date +%s)
    
    if [ "$USE_PARALLEL" = "y" ]; then
        create_dirs_parallel
    else
        create_dirs_sequential
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    echo -e "${GREEN}${BOLD}====================================================================${NC}"
    echo -e "${GREEN}${BOLD}                    Erstellung abgeschlossen!                       ${NC}"
    echo -e "${GREEN}${BOLD}====================================================================${NC}"
    echo
    
    # Statistiken
    local created=$(find "$BASE_PATH" -maxdepth 1 -type d -name "${PREFIX}_*" 2>/dev/null | wc -l)
    print_success "Erstellte Verzeichnisse: $created von $COUNT"
    print_success "Gesamtdauer: ${duration}s"
    
    if [ $created -gt 0 ]; then
        local avg_time=$((duration * 1000 / created))
        print_info "Durchschnitt: ${avg_time}ms pro Verzeichnis"
    fi
    
    echo
}

show_quota_overview() {
    if confirm_action "Möchtest du eine Quota-Übersicht sehen?"; then
        echo
        print_info "Lade Quota-Informationen..."
        echo
        
        # Variante 1: Alle Quotas auflisten und nach Base Path filtern
        print_info "Erstellte Quotas unter $BASE_PATH:"
        echo
        
        isi quota list 2>/dev/null | grep "$BASE_PATH/${PREFIX}_" | head -n 30
        
        local total=$(isi quota list 2>/dev/null | grep -c "$BASE_PATH/${PREFIX}_")
        
        if [ $total -eq 0 ]; then
            print_warning "Keine Quotas gefunden. Möglicherweise dauert die Synchronisation noch einen Moment."
            echo
            print_info "Versuche es mit: isi quota list | grep '$BASE_PATH'"
        elif [ $total -gt 30 ]; then
            echo
            print_info "(Zeige erste 30 von $total Quotas)"
        else
            echo
            print_success "Insgesamt $total Quotas gefunden"
        fi
        
        echo
        echo -e "${CYAN}====================================================================${NC}"
        print_info "Nützliche Kommandos:"
        echo -e "${WHITE}  # Alle Quotas anzeigen:${NC}"
        echo -e "${CYAN}  isi quota list${NC}"
        echo
        echo -e "${WHITE}  # Nur deine erstellten Quotas:${NC}"
        echo -e "${CYAN}  isi quota list | grep '$BASE_PATH/${PREFIX}_'${NC}"
        echo
        echo -e "${WHITE}  # Details zu einer spezifischen Quota:${NC}"
        echo -e "${CYAN}  isi quota view '$BASE_PATH/${PREFIX}_0001'${NC}"
        echo
        echo -e "${WHITE}  # Quota-Nutzung überwachen:${NC}"
        echo -e "${CYAN}  isi quota list --format table${NC}"
        echo -e "${CYAN}====================================================================${NC}"
    fi
}

################################################################################
# Quota-Löschfunktionen
################################################################################

get_delete_path() {
    print_header
    print_step "Schritt 1: Pfad für Quota-Löschung"
    
    print_warning "ACHTUNG: Diese Funktion löscht Quotas!"
    print_info "Gib den Basis-Pfad an, dessen Quotas gelöscht werden sollen."
    echo
    print_info "Beispiele: /ifs/data/projects, /ifs/testdirs"
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Pfad:${NC} )" DELETE_PATH
        
        if [ -z "$DELETE_PATH" ]; then
            print_error "Pfad darf nicht leer sein!"
            echo
            continue
        fi
        
        if [[ ! "$DELETE_PATH" =~ ^/ifs ]]; then
            print_error "Pfad muss mit /ifs beginnen!"
            echo
            continue
        fi
        
        if [ ! -d "$DELETE_PATH" ]; then
            print_error "Pfad existiert nicht: $DELETE_PATH"
            echo
            continue
        fi
        
        print_success "Pfad gesetzt: $DELETE_PATH"
        break
    done
    
    press_any_key
}

get_delete_options() {
    print_header
    print_step "Schritt 2: Quota-Typ auswählen"
    
    print_info "Welche Quota-Typen sollen gelöscht werden?"
    echo
    echo -e "${WHITE}1)${NC} Nur ${CYAN}Directory${NC} Quotas"
    echo -e "${WHITE}2)${NC} Nur ${CYAN}User${NC} Quotas"
    echo -e "${WHITE}3)${NC} ${CYAN}Beide${NC} (Directory + User Quotas)"
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Auswahl [${GREEN}1${WHITE}]:${NC} )" choice
        
        if [ -z "$choice" ]; then
            choice=1
        fi
        
        case $choice in
            1)
                DELETE_TYPES="directory"
                print_success "Typ gesetzt: Nur Directory Quotas"
                break
                ;;
            2)
                DELETE_TYPES="user"
                print_success "Typ gesetzt: Nur User Quotas"
                break
                ;;
            3)
                DELETE_TYPES="both"
                print_success "Typ gesetzt: Directory + User Quotas"
                break
                ;;
            *)
                print_error "Ungültige Auswahl! Bitte 1, 2 oder 3 eingeben."
                ;;
        esac
        echo
    done
    
    echo
    
    # Rekursiv oder nur direkte Unterverzeichnisse?
    print_info "Sollen Quotas ${BOLD}rekursiv${NC} (inkl. aller Unterverzeichnisse) gelöscht werden?"
    echo
    
    if confirm_action "Rekursiv löschen?"; then
        DELETE_RECURSIVE="yes"
        print_success "Rekursives Löschen aktiviert"
    else
        DELETE_RECURSIVE="no"
        print_info "Nur direkte Unterverzeichnisse werden berücksichtigt"
    fi
    
    echo
    
    # Sollen auch die Verzeichnisse gelöscht werden?
    print_warning "Sollen die Verzeichnisse nach dem Löschen der Quotas auch gelöscht werden?"
    print_info "Standard: NEIN - nur Quotas werden gelöscht, Verzeichnisse bleiben bestehen"
    echo
    
    if confirm_action "Verzeichnisse auch löschen?"; then
        DELETE_DIRECTORIES="yes"
        print_warning "Verzeichnisse werden NACH dem Löschen der Quotas gelöscht!"
    else
        DELETE_DIRECTORIES="no"
        print_success "Verzeichnisse bleiben bestehen"
    fi
    
    press_any_key
}

show_delete_preview() {
    print_header
    print_step "Schritt 3: Vorschau"
    
    print_info "Suche nach Quotas unter: $DELETE_PATH"
    echo
    
    # Quotas finden
    local dir_quotas=0
    local user_quotas=0
    
    if [ "$DELETE_TYPES" = "directory" ] || [ "$DELETE_TYPES" = "both" ]; then
        dir_quotas=$(isi quota list 2>/dev/null | grep -c "^directory.*$DELETE_PATH")
    fi
    
    if [ "$DELETE_TYPES" = "user" ] || [ "$DELETE_TYPES" = "both" ]; then
        user_quotas=$(isi quota list 2>/dev/null | grep -c "^user.*$DELETE_PATH")
    fi
    
    local total_quotas=$((dir_quotas + user_quotas))
    
    echo -e "${WHITE}${BOLD}Gefundene Quotas:${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    
    if [ "$DELETE_TYPES" = "directory" ] || [ "$DELETE_TYPES" = "both" ]; then
        printf "%-30s ${WHITE}%d${NC}\n" "Directory Quotas:" "$dir_quotas"
    fi
    
    if [ "$DELETE_TYPES" = "user" ] || [ "$DELETE_TYPES" = "both" ]; then
        printf "%-30s ${WHITE}%d${NC}\n" "User Quotas:" "$user_quotas"
    fi
    
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    printf "%-30s ${WHITE}${BOLD}%d${NC}\n" "GESAMT:" "$total_quotas"
    echo -e "${CYAN}========================================================================${NC}"
    
    echo
    
    if [ $total_quotas -eq 0 ]; then
        print_warning "Keine Quotas gefunden!"
        echo
        if ! confirm_action "Trotzdem fortfahren?"; then
            print_info "Abgebrochen."
            exit 0
        fi
    else
        print_info "Beispiel der zu löschenden Quotas (erste 10):"
        echo
        
        if [ "$DELETE_TYPES" = "directory" ] || [ "$DELETE_TYPES" = "both" ]; then
            isi quota list 2>/dev/null | grep "^directory.*$DELETE_PATH" | head -n 10
        fi
        
        if [ "$DELETE_TYPES" = "user" ] || [ "$DELETE_TYPES" = "both" ]; then
            isi quota list 2>/dev/null | grep "^user.*$DELETE_PATH" | head -n 10
        fi
        
        echo
    fi
    
    press_any_key
}

confirm_delete() {
    print_header
    print_step "Schritt 4: Bestätigung"
    
    echo -e "${RED}${BOLD}WARNUNG: Diese Aktion kann nicht rückgängig gemacht werden!${NC}"
    echo
    echo -e "${WHITE}${BOLD}Zusammenfassung:${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    printf "%-30s ${WHITE}%s${NC}\n" "Pfad:" "$DELETE_PATH"
    
    if [ "$DELETE_TYPES" = "directory" ]; then
        printf "%-30s ${WHITE}%s${NC}\n" "Quota-Typen:" "Directory"
    elif [ "$DELETE_TYPES" = "user" ]; then
        printf "%-30s ${WHITE}%s${NC}\n" "Quota-Typen:" "User"
    else
        printf "%-30s ${WHITE}%s${NC}\n" "Quota-Typen:" "Directory + User"
    fi
    
    if [ "$DELETE_RECURSIVE" = "yes" ]; then
        printf "%-30s ${WHITE}%s${NC}\n" "Modus:" "Rekursiv (alle Unterverzeichnisse)"
    else
        printf "%-30s ${WHITE}%s${NC}\n" "Modus:" "Nur direkte Unterverzeichnisse"
    fi
    
    if [ "$DELETE_DIRECTORIES" = "yes" ]; then
        printf "%-30s ${RED}%s${NC}\n" "Verzeichnisse löschen:" "JA - Verzeichnisse werden gelöscht!"
    else
        printf "%-30s ${GREEN}%s${NC}\n" "Verzeichnisse löschen:" "NEIN - Verzeichnisse bleiben"
    fi
    echo -e "${CYAN}========================================================================${NC}"
    
    echo
    print_warning "Bist du dir absolut sicher?"
    echo
    
    read -p "$(echo -e ${RED}Tippe \"DELETE\" um zu bestätigen:${NC} )" confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        print_warning "Abgebrochen! (Eingabe war nicht \"DELETE\")"
        exit 0
    fi
    
    print_success "Bestätigung erhalten - starte Löschvorgang..."
    press_any_key
}

execute_quota_deletion() {
    print_header
    print_step "Löschvorgang"
    
    print_info "Lösche Quotas..."
    echo
    
    local deleted_count=0
    local failed_count=0
    local start_time=$(date +%s)
    
    # Temporäre Dateien für Quota-Liste und Verzeichnis-Liste
    local quota_list="/tmp/quota_delete_list_$$.txt"
    local dir_list="/tmp/dir_delete_list_$$.txt"
    
    # Quotas sammeln
    if [ "$DELETE_TYPES" = "directory" ]; then
        isi quota list 2>/dev/null | grep "^directory.*$DELETE_PATH" | awk '{print $3}' > "$quota_list"
    elif [ "$DELETE_TYPES" = "user" ]; then
        isi quota list 2>/dev/null | grep "^user.*$DELETE_PATH" | awk '{print $3}' > "$quota_list"
    else
        isi quota list 2>/dev/null | grep "^\(directory\|user\).*$DELETE_PATH" | awk '{print $3}' > "$quota_list"
    fi
    
    # Verzeichnisse merken (falls sie gelöscht werden sollen)
    if [ "$DELETE_DIRECTORIES" = "yes" ]; then
        if [ "$DELETE_TYPES" = "directory" ] || [ "$DELETE_TYPES" = "both" ]; then
            isi quota list 2>/dev/null | grep "^directory.*$DELETE_PATH" | awk '{print $3}' > "$dir_list"
        fi
    fi
    
    local total=$(wc -l < "$quota_list")
    local current=0
    
    if [ $total -eq 0 ]; then
        print_warning "Keine Quotas zum Löschen gefunden!"
        rm -f "$quota_list" "$dir_list"
        return
    fi
    
    print_info "Gefunden: $total Quotas"
    echo
    
    # SCHRITT 1: Quotas löschen (ZUERST!)
    print_info "Schritt 1: Lösche Quotas..."
    echo
    
    while IFS= read -r quota_path; do
        ((current++))
        
        if isi quota delete "$quota_path" 2>/dev/null; then
            ((deleted_count++))
        else
            print_error "Fehler beim Löschen der Quota: $quota_path"
            ((failed_count++))
        fi
        
        # Fortschritt anzeigen
        if [ $((current % 10)) -eq 0 ] || [ $current -eq $total ]; then
            local percent=$((current * 100 / total))
            local elapsed=$(($(date +%s) - start_time))
            printf "\r${CYAN}Fortschritt:${NC} [%-50s] ${WHITE}%d%%${NC} ${CYAN}(%d/%d)${NC} ${YELLOW}Zeit: %ds${NC}" \
                "$(printf '#%.0s' $(seq 1 $((percent / 2))))" \
                "$percent" "$current" "$total" "$elapsed"
        fi
    done < "$quota_list"
    
    echo
    echo
    
    rm -f "$quota_list"
    
    # SCHRITT 2: Verzeichnisse löschen (NUR wenn gewünscht und NACH den Quotas!)
    local deleted_dirs=0
    local failed_dirs=0
    
    if [ "$DELETE_DIRECTORIES" = "yes" ] && [ -f "$dir_list" ]; then
        local dir_total=$(wc -l < "$dir_list")
        
        if [ $dir_total -gt 0 ]; then
            echo
            print_info "Schritt 2: Lösche Verzeichnisse..."
            echo
            
            local dir_current=0
            while IFS= read -r dir_path; do
                ((dir_current++))
                
                if [ -d "$dir_path" ]; then
                    if rm -rf "$dir_path" 2>/dev/null; then
                        ((deleted_dirs++))
                    else
                        print_error "Fehler beim Löschen des Verzeichnisses: $dir_path"
                        ((failed_dirs++))
                    fi
                else
                    print_warning "Verzeichnis existiert nicht mehr: $dir_path"
                fi
                
                # Fortschritt anzeigen
                if [ $((dir_current % 10)) -eq 0 ] || [ $dir_current -eq $dir_total ]; then
                    local dir_percent=$((dir_current * 100 / dir_total))
                    printf "\r${CYAN}Fortschritt:${NC} [%-50s] ${WHITE}%d%%${NC} ${CYAN}(%d/%d)${NC}" \
                        "$(printf '#%.0s' $(seq 1 $((dir_percent / 2))))" \
                        "$dir_percent" "$dir_current" "$dir_total"
                fi
            done < "$dir_list"
            
            echo
            echo
        fi
    fi
    
    rm -f "$dir_list"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "${GREEN}${BOLD}====================================================================${NC}"
    echo -e "${GREEN}${BOLD}                    Löschvorgang abgeschlossen!                     ${NC}"
    echo -e "${GREEN}${BOLD}====================================================================${NC}"
    echo
    
    print_success "Gelöschte Quotas: $deleted_count"
    if [ $failed_count -gt 0 ]; then
        print_error "Fehlgeschlagene Quotas: $failed_count"
    fi
    
    if [ "$DELETE_DIRECTORIES" = "yes" ]; then
        echo
        print_success "Gelöschte Verzeichnisse: $deleted_dirs"
        if [ $failed_dirs -gt 0 ]; then
            print_error "Fehlgeschlagene Verzeichnisse: $failed_dirs"
        fi
    fi
    
    echo
    print_success "Gesamtdauer: ${duration}s"
    
    if [ $deleted_count -gt 0 ]; then
        local avg_time=$((duration * 1000 / deleted_count))
        print_info "Durchschnitt Quotas: ${avg_time}ms pro Quota"
    fi
    
    echo
}

delete_quotas_wizard() {
    get_delete_path
    get_delete_options
    show_delete_preview
    confirm_delete
    execute_quota_deletion
}

################################################################################
# Hauptprogramm
################################################################################

select_operation_mode() {
    print_header
    print_step "Willkommen zum PowerScale Quota Wizard!"
    
    echo -e "${WHITE}${BOLD}Was möchtest du tun?${NC}"
    echo
    echo -e "${GREEN}1)${NC} Verzeichnisse mit Quotas ${GREEN}ERSTELLEN${NC}"
    echo -e "${RED}2)${NC} Quotas ${RED}LÖSCHEN${NC} (rekursiv)"
    echo -e "${YELLOW}3)${NC} Wizard beenden"
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}${ARROW} Deine Wahl [${GREEN}1${WHITE}]:${NC} )" choice
        
        if [ -z "$choice" ]; then
            choice=1
        fi
        
        case $choice in
            1)
                print_success "Modus: Verzeichnisse ERSTELLEN"
                return 0
                ;;
            2)
                print_success "Modus: Quotas LÖSCHEN"
                return 1
                ;;
            3)
                print_info "Wizard wird beendet..."
                exit 0
                ;;
            *)
                print_error "Ungültige Auswahl! Bitte 1, 2 oder 3 eingeben."
                ;;
        esac
        echo
    done
}

main() {
    # System-Überprüfung
    check_system
    
    # Betriebs-Modus wählen
    select_operation_mode
    operation_mode=$?
    
    press_any_key
    
    if [ $operation_mode -eq 0 ]; then
        # ERSTELLEN-Modus
        # Wizard durchlaufen (Base Path zuerst!)
        get_base_path
        get_prefix
        get_count
        get_owner_settings
        get_quota_configuration
        get_quota_advanced_options
        get_parallel_settings
        
        # Zusammenfassung und Bestätigung
        show_summary
        
        if ! confirm_action "Möchtest du die Erstellung jetzt starten?"; then
            print_warning "Abgebrochen!"
            exit 0
        fi
        
        # Ausführung
        execute_creation
        
        # Optional: Quota-Übersicht
        show_quota_overview
    else
        # LÖSCHEN-Modus
        delete_quotas_wizard
    fi
    
    echo
    print_success "Wizard abgeschlossen!"
    echo
}

# Script starten
main
