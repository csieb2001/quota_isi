# PowerScale/Isilon Quota Wizard

Ein interaktiver Shell-Wizard zur automatisierten Erstellung und Verwaltung von Verzeichnissen mit Quotas auf Dell PowerScale (ehemals Isilon) Storage-Systemen.

**Verfügbar in zwei Versionen:**
- 🔄 **SSH-Version** (Original): Läuft direkt auf PowerScale Nodes via SSH
- 🌐 **API-Version** (Neu): Remote-Execution via OneFS REST API mit Basic Authentication

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![PowerScale](https://img.shields.io/badge/PowerScale-OneFS-blue.svg)](https://www.dell.com/powerscale)
[![API](https://img.shields.io/badge/API-OneFS_REST-orange.svg)](https://developer.dell.com)

## 🎯 Features

### 🚀 Zwei Ausführungsversionen

#### 🔄 SSH-Version (`isilon_quota_wizard.sh`)
- ✅ Läuft direkt auf PowerScale/Isilon Nodes
- ✅ Verwendet native OneFS CLI (`isi` Kommandos)
- ✅ ERSTELLEN und LÖSCHEN Modi verfügbar
- ✅ Vollständige Funktionalität

#### 🌐 API-Version (`isilon_quota_wizard_api.sh`)
- ✅ **Remote-Execution** - Läuft von jedem System mit Internet/Netzwerk-Zugang
- ✅ **OneFS REST API** mit Basic Authentication
- ✅ **Keine SSH-Verbindung** zum PowerScale erforderlich
- ✅ **Cross-Platform** - Läuft auf Linux, macOS, Windows (WSL)
- ✅ **Native Bash-Parallelität** - Keine externen Tools erforderlich
- ✅ Fokus auf ERSTELLEN-Modus (optimiert für API-Operationen)

### ✨ Betriebsmodi (SSH-Version)

- ✅ **ERSTELLEN-Modus** - Erstelle Verzeichnisse mit Quotas
- ✅ **LÖSCHEN-Modus** - Lösche Quotas rekursiv (optional mit Verzeichnissen)

### 📁 Erstellen-Modus

- ✅ **Interaktiver Wizard** mit Schritt-für-Schritt-Anleitung
- ✅ **Automatische Pfad-Erstellung** falls nicht vorhanden
- ✅ **Umfassende Quota-Konfiguration**
  - Hard Threshold (Pflicht)
  - Soft Threshold mit Grace Period (Optional)
  - Advisory Threshold (Optional)
  - Konfigurierbare Berechnungsgrundlage (applogicalsize, fslogicalsize, physicalsize)
  - Snapshot-Einbeziehung wählbar
- ✅ **Owner-Management** - Setze User und Group für erstellte Verzeichnisse
- ✅ **Parallele Verarbeitung** für maximale Performance
- ✅ **Validierung** aller Eingaben mit hilfreichen Fehlermeldungen
- ✅ **Fortschrittsanzeige** mit Zeitschätzung

### 🗑️ Löschen-Modus (NEU!)

- ✅ **Rekursives Quota-Löschen** für Verzeichnisstrukturen
- ✅ **Flexible Auswahl** - Directory, User oder beide Quota-Typen
- ✅ **Sichere Vorschau** - Zeigt was gelöscht wird vor der Ausführung
- ✅ **Optionales Verzeichnis-Löschen** - Verzeichnisse können mit gelöscht werden
- ✅ **Bestätigung erforderlich** - User muss "DELETE" tippen
- ✅ **Korrekte Reihenfolge** - Quotas werden VOR Verzeichnissen gelöscht

### 🎨 User Experience

- ✅ **Farbige Ausgabe** mit Unicode-Symbolen für bessere Lesbarkeit
- ✅ **ASCII-kompatibel** - Funktioniert auf allen Terminals
- ✅ **Detaillierte Statistiken** - Performance-Metriken nach Abschluss
- ✅ **Quota-Übersicht** am Ende mit nützlichen Kommandos

## 📋 Voraussetzungen

### 🔄 SSH-Version
- Dell PowerScale / Isilon mit OneFS
- Zugriff auf einen Cluster-Node via SSH
- Ausreichende Berechtigungen für:
  - Verzeichnis-Erstellung
  - Quota-Management (`isi quota` Befehle)
  - Optional: `chown` für Owner-Änderungen
- Bash Shell
- Optional: GNU Parallel (empfohlen für große Anzahl Verzeichnisse)

### 🌐 API-Version
- Dell PowerScale / Isilon mit OneFS (beliebige Version mit REST API)
- **Netzwerk-Zugang** zum PowerScale Cluster (Port 8080/HTTPS)
- **API-Benutzer** mit ausreichenden Berechtigungen:
  - Namespace API (Verzeichnis-Erstellung)
  - Quota API (Quota-Management)
- **Client-System** mit:
  - Bash Shell
  - `curl` (HTTP Client)
  - `jq` (JSON Parser)
- **Keine SSH-Verbindung** erforderlich!

## 🚀 Installation

### 🔄 SSH-Version Installation

#### Methode 1: Direkt auf PowerScale

```bash
# Via SSH auf PowerScale/Isilon Node einloggen
ssh root@<powerscale-ip>

# Script herunterladen
curl -o isilon_quota_wizard.sh https://raw.githubusercontent.com/<your-repo>/isilon-quota-wizard/main/isilon_quota_wizard.sh

# Ausführbar machen
chmod +x isilon_quota_wizard.sh

# Starten
./isilon_quota_wizard.sh
```

#### Methode 2: Via Git Clone

```bash
# Repository klonen
git clone https://github.com/<your-repo>/isilon-quota-wizard.git
cd isilon-quota-wizard

# Auf PowerScale kopieren
scp isilon_quota_wizard.sh root@<powerscale-ip>:/root/

# Auf PowerScale einloggen und ausführen
ssh root@<powerscale-ip>
chmod +x /root/isilon_quota_wizard.sh
./isilon_quota_wizard.sh
```

### 🌐 API-Version Installation

#### Auf jedem System mit Bash (Linux, macOS, Windows WSL)

```bash
# Repository klonen
git clone https://github.com/<your-repo>/isilon-quota-wizard.git
cd isilon-quota-wizard

# Abhängigkeiten prüfen
which curl jq || echo "Bitte installieren: curl jq"

# API-Version ausführbar machen
chmod +x isilon_quota_wizard_api.sh

# Starten (Remote zu PowerScale)
./isilon_quota_wizard_api.sh
```

#### Abhängigkeiten installieren

**macOS (Homebrew):**
```bash
brew install curl jq
```

**Ubuntu/Debian:**
```bash
sudo apt install curl jq
```

**CentOS/RHEL:**
```bash
sudo yum install curl jq
```

**Windows WSL:**
```bash
sudo apt update && sudo apt install curl jq
```

## 📖 Verwendung

### SSH-Version starten

```bash
./isilon_quota_wizard.sh
```

### API-Version starten

```bash
./isilon_quota_wizard_api.sh
```

**Eingaben für API-Version:**
- **Cluster IP/Hostname**: IP-Adresse oder Hostname des PowerScale Clusters
- **Username**: API-Benutzer (z.B. `root` oder spezieller API-User)
- **Password**: Passwort des API-Benutzers

### Betriebs-Modus wählen

Beim Start wirst du gefragt, was du tun möchtest:

```
========================================================================
        PowerScale/Isilon Quota Wizard v1.0                         

        Copyright © 2024 Christopher Siebert
        christopher.siebert@concat.de
========================================================================

Was möchtest du tun?

1) Verzeichnisse mit Quotas ERSTELLEN
2) Quotas LÖSCHEN (rekursiv)
3) Wizard beenden

→ Deine Wahl [1]:
```

---

## 📁 ERSTELLEN-Modus

### Wizard-Schritte (Erstellen)

Der Wizard führt dich durch folgende Schritte:

1. **System-Überprüfung**
   - Prüft OneFS CLI Verfügbarkeit
   - Zeigt OneFS Version
   - Prüft Berechtigungen

2. **Basis-Pfad**
   - Eingabe des Zielpfads (z.B. `/ifs/data/projects`)
   - Automatische Erstellung falls nicht vorhanden
   - Validierung von Schreibrechten

3. **Verzeichnis-Präfix**
   - Präfix für die nummerierten Verzeichnisse
   - Standard: `dir` → Ergebnis: `dir_0001`, `dir_0002`, ...

4. **Anzahl**
   - Wie viele Verzeichnisse erstellt werden sollen
   - Bereich: 1 - 100.000

5. **Verzeichnis-Owner**
   - Optional: Spezifischen User und Gruppe festlegen
   - Validierung der Existenz
   - Anzeige von UID/GID

6. **Quota-Konfiguration**
   - Hard Threshold (Pflicht)
   - Soft Threshold (Optional)
   - Advisory Threshold (Optional)
   - Grace Period bei Soft Threshold

7. **Erweiterte Quota-Optionen**
   - Berechnungsgrundlage wählen
   - Snapshot-Einbeziehung

8. **Performance-Einstellungen**
   - Parallele Verarbeitung aktivieren
   - Anzahl paralleler Jobs konfigurieren

9. **Zusammenfassung & Start**
   - Übersicht aller Einstellungen
   - Bestätigung vor Start

---

## 🗑️ LÖSCHEN-Modus

### Wizard-Schritte (Löschen)

Der Lösch-Wizard führt dich durch folgende Schritte:

1. **Pfad auswählen**
   - Eingabe des Basis-Pfads dessen Quotas gelöscht werden sollen
   - Validierung (muss mit /ifs beginnen und existieren)

2. **Quota-Typ auswählen**
   - **Directory Quotas** - Nur Directory-Quotas löschen
   - **User Quotas** - Nur User-Quotas löschen
   - **Beide** - Directory + User Quotas löschen
   - **Rekursiv** - Inkl. aller Unterverzeichnisse
   - **Verzeichnisse löschen** - Optional: Verzeichnisse nach Quota-Löschung auch entfernen

3. **Vorschau**
   - Zeigt Anzahl gefundener Quotas
   - Aufschlüsselung nach Typ (Directory/User)
   - Beispiel-Liste der zu löschenden Quotas
   - Möglichkeit zum Abbruch

4. **Bestätigung**
   - Zusammenfassung aller Einstellungen
   - **Sicherheits-Check:** User muss "DELETE" tippen
   - Warnung über Unwiderruflichkeit

5. **Ausführung**
   - **Schritt 1:** Quotas werden gelöscht (ZUERST!)
   - **Schritt 2:** Verzeichnisse werden gelöscht (falls gewählt)
   - Fortschrittsanzeige mit Statistiken

### ⚠️ Wichtige Hinweise zum Löschen

- **Reihenfolge ist entscheidend:** Quotas werden IMMER vor Verzeichnissen gelöscht
- **Standard-Verhalten:** Nur Quotas werden gelöscht, Verzeichnisse bleiben bestehen
- **Optional:** Verzeichnisse können mit gelöscht werden (nach den Quotas)
- **Unwiderruflich:** Gelöschte Quotas/Verzeichnisse können nicht wiederhergestellt werden
- **Sicherheit:** User muss explizit "DELETE" tippen (nicht nur j/n)

---

## 💡 Beispiele

### Beispiel 1: Verzeichnisse erstellen

1000 Verzeichnisse mit 1MB Hard Quota:

```
Modus: ERSTELLEN
Basis-Pfad: /ifs/data/testdirs
Präfix: project
Anzahl: 1000
Hard Threshold: 1M
```

**Ergebnis:**
```
/ifs/data/testdirs/project_0001  (Quota: 1MB)
/ifs/data/testdirs/project_0002  (Quota: 1MB)
...
/ifs/data/testdirs/project_1000  (Quota: 1MB)
```

### Beispiel 2: Mit Soft Threshold

Projekt-Verzeichnisse mit Warnschwelle:

```
Modus: ERSTELLEN
Basis-Pfad: /ifs/projects
Präfix: proj
Anzahl: 100
Hard Threshold: 10G
Soft Threshold: 8G
Grace Period: 604800 (7 Tage)
```

### Beispiel 3: Mit spezifischem Owner

User-Verzeichnisse mit korrektem Owner:

```
Modus: ERSTELLEN
Basis-Pfad: /ifs/home
Präfix: user
Anzahl: 50
Owner: testuser:users
Hard Threshold: 20G
```

### Beispiel 4: Nur Quotas löschen (Verzeichnisse bleiben)

```
Modus: LÖSCHEN
Pfad: /ifs/data/testdirs
Quota-Typen: Directory
Rekursiv: Ja
Verzeichnisse löschen: NEIN

Ergebnis:
✓ Quotas gelöscht: 1000
✓ Verzeichnisse bleiben bestehen (ohne Quota)
```

### Beispiel 5: Quotas UND Verzeichnisse löschen

```
Modus: LÖSCHEN
Pfad: /ifs/data/testdirs
Quota-Typen: Directory
Rekursiv: Ja
Verzeichnisse löschen: JA

Ergebnis:
✓ Quotas gelöscht: 1000
✓ Verzeichnisse gelöscht: 1000
✓ Komplettes Cleanup durchgeführt
```

### Beispiel 6: Nur User-Quotas löschen

```
Modus: LÖSCHEN
Pfad: /ifs/home
Quota-Typen: User
Rekursiv: Ja
Verzeichnisse löschen: NEIN

Ergebnis:
✓ User-Quotas gelöscht: 50
✓ Directory-Quotas bleiben bestehen
✓ Verzeichnisse bleiben bestehen
```

## 🔧 Erweiterte Konfiguration

### Quota-Berechnungsgrundlagen

| Option | Beschreibung |
|--------|--------------|
| `applogicalsize` | Logische Größe der Anwendungsdaten (Standard) |
| `fslogicalsize` | Logische Dateisystemgröße |
| `physicalsize` | Physische Größe auf Disk inkl. Overhead |

### Grace Period Werte

| Sekunden | Entspricht |
|----------|------------|
| 86400 | 1 Tag |
| 259200 | 3 Tage |
| 604800 | 7 Tage (Standard) |
| 1209600 | 14 Tage |
| 2592000 | 30 Tage |

### Parallele Verarbeitung

#### SSH-Version (mit GNU Parallel)
Empfohlene Anzahl paralleler Jobs je nach Anzahl Verzeichnisse:

- 1-100 Verzeichnisse: 5 Jobs
- 100-1000 Verzeichnisse: 10 Jobs (Standard)
- 1000-10000 Verzeichnisse: 15-20 Jobs
- 10000+ Verzeichnisse: 20-30 Jobs

#### API-Version (native Bash Background-Jobs)
Da jeder API-Call über das Netzwerk läuft, können mehr parallele Jobs verwendet werden:

- 1-100 Verzeichnisse: 10 Jobs
- 100-1000 Verzeichnisse: 20 Jobs (Standard)
- 1000-10000 Verzeichnisse: 30-40 Jobs
- 10000+ Verzeichnisse: 40-50 Jobs

**Vorteile der API-Version:**
- ✅ Keine Abhängigkeit von GNU Parallel
- ✅ Native Bash Background-Jobs (`&` und `wait`)
- ✅ Funktioniert auf jedem System
- ✅ Bessere Netzwerk-Parallelität für API-Calls

## 📊 Performance

### SSH-Version (Lokale OneFS CLI)
Typische Durchlaufzeiten (abhängig von Cluster-Last):

| Anzahl Verzeichnisse | Sequentiell | Parallel (10 Jobs) |
|---------------------|-------------|-------------------|
| 100 | ~20s | ~3-5s |
| 1000 | ~3-4min | ~20-30s |
| 10000 | ~30-40min | ~3-5min |

### API-Version (Remote OneFS REST API)
Typische Durchlaufzeiten (abhängig von Netzwerk-Latenz und Cluster-Last):

| Anzahl Verzeichnisse | Sequentiell | Parallel (20 Jobs) |
|---------------------|-------------|-------------------|
| 100 | ~40-60s | ~5-10s |
| 1000 | ~7-10min | ~30-60s |
| 10000 | ~70-100min | ~5-10min |

**Faktoren für API-Performance:**
- ✅ **Netzwerk-Latenz**: Je näher zum Cluster, desto schneller
- ✅ **Parallelität**: API-Version kann höhere Parallelität nutzen
- ✅ **Cluster-Load**: API teilt sich Ressourcen mit anderen API-Clients
- ✅ **Basic Auth**: Sehr effizient, keine Session-Overhead

## 🛠️ Manuelle Quota-Verwaltung

### Quota anzeigen

```bash
# Alle Quotas auflisten
isi quota list

# Spezifische Quota anzeigen
isi quota view /ifs/data/testdirs/dir_0001

# Nur bestimmte Quotas filtern
isi quota list | grep /ifs/data/testdirs
```

### Quota ändern

```bash
# Hard Threshold ändern
isi quota modify /ifs/data/testdirs/dir_0001 --hard-threshold 5M

# Soft Threshold hinzufügen
isi quota modify /ifs/data/testdirs/dir_0001 --soft-threshold 4M
```

### Quota löschen

```bash
# Einzelne Quota löschen
isi quota delete /ifs/data/testdirs/dir_0001

# Mehrere Quotas löschen (manuell)
for i in $(seq 1 100); do
  isi quota delete /ifs/data/testdirs/dir_$(printf "%04d" $i)
done
```

**💡 Tipp:** Verwende den **LÖSCHEN-Modus** des Wizards für komfortables und sicheres Löschen vieler Quotas!

## 🐛 Troubleshooting

### Problem: "isi command not found"

**Lösung:** Das Script muss auf einem PowerScale/Isilon Node ausgeführt werden, nicht auf einem externen System.

### Problem: "Permission denied"

**Lösung:** 
- Stelle sicher, dass du als `root` oder mit ausreichenden Berechtigungen angemeldet bist
- Prüfe die Berechtigungen auf dem Basis-Pfad

### Problem: "User/Group existiert nicht"

**Lösung:**
- Prüfe mit `id <username>` ob der User existiert
- Prüfe mit `getent group <groupname>` ob die Gruppe existiert
- Auf PowerScale müssen User/Gruppen entweder lokal oder via AD/LDAP existieren

### Problem: Quota wird nicht angezeigt

**Lösung:**
- Quota-Synchronisation kann einige Sekunden dauern
- Verwende `isi quota list` direkt um alle Quotas zu sehen
- Prüfe mit `isi quota view <pfad>` die spezifische Quota

### Problem: Kann Quotas nicht löschen

**Lösung:**
- Stelle sicher, dass die Quotas existieren: `isi quota list | grep <pfad>`
- Prüfe Berechtigungen (root oder ausreichende Rechte erforderlich)
- Bei "Quota does not exist" Fehler: Quota wurde bereits gelöscht oder Pfad ist falsch

### Problem: "Fehler beim Löschen" im Lösch-Modus

**Lösung:**
- Quotas müssen VOR Verzeichnissen gelöscht werden (Script macht das automatisch)
- Falls Verzeichnis bereits manuell gelöscht wurde, kann Quota nicht mehr gelöscht werden
- Prüfe mit `isi quota list` ob Quota noch existiert

### Problem: Verzeichnisse können nicht gelöscht werden

**Lösung:**
- Stelle sicher, dass Quotas zuerst gelöscht wurden
- Prüfe ob Verzeichnis leer ist (oder verwende `rm -rf`)
- Prüfe Berechtigungen auf Verzeichnis
- Verzeichnisse können Inhalte haben, die das Löschen verhindern

## 🤝 Beitragen

Beiträge sind willkommen! Bitte beachte folgende Richtlinien:

1. Fork das Repository
2. Erstelle einen Feature-Branch (`git checkout -b feature/AmazingFeature`)
3. Committe deine Änderungen (`git commit -m 'Add some AmazingFeature'`)
4. Push zum Branch (`git push origin feature/AmazingFeature`)
5. Öffne einen Pull Request

### Entwicklung

```bash
# Repository klonen
git clone https://github.com/<your-repo>/isilon-quota-wizard.git
cd isilon-quota-wizard

# Script bearbeiten
vim isilon_quota_wizard.sh

# Auf Test-System testen
scp isilon_quota_wizard.sh root@<test-powerscale>:/root/
ssh root@<test-powerscale> "/root/isilon_quota_wizard.sh"
```

## 📝 Changelog

### Version 2.0 (November 2024)
- 🚀 **NEU:** API-Version (`isilon_quota_wizard_api.sh`)
- 🌐 **Remote-Execution** via OneFS REST API
- 🔐 **Basic Authentication** - Keine Session-Management nötig
- 🖥️ **Cross-Platform** - Läuft auf Linux, macOS, Windows WSL
- ⚡ **Native Bash-Parallelität** - Keine GNU Parallel Abhängigkeit
- 📡 **Netzwerk-optimiert** - Höhere Parallelität für API-Calls
- 🛠️ **macOS-kompatibel** - Korrekte `head`/`sed` Verwendung
- 📋 **JSON-Schema konform** - Nach offizieller Dell OneFS API
- 🔧 Verbesserte Fehlerbehandlung und HTTP-Status-Codes

### Version 1.1 (November 2024)
- ✨ **NEU:** Löschen-Modus für rekursives Quota-Löschen (SSH-Version)
- ✨ Auswahl zwischen Directory, User oder beiden Quota-Typen
- ✨ Optionales Verzeichnis-Löschen nach Quota-Entfernung
- ✨ Sichere Vorschau vor Löschung
- ✨ Bestätigung mit "DELETE"-Eingabe erforderlich
- 🐛 Korrigierte Lösch-Reihenfolge (Quotas VOR Verzeichnissen)
- 🔧 ASCII-kompatible Ausgabe (keine Unicode-Box-Zeichen mehr)
- 📚 Erweiterte Dokumentation

### Version 1.0 (November 2024)
- Initiales Release (SSH-Version)
- Interaktiver Wizard mit 8 Schritten
- Umfassende Quota-Konfiguration
- Owner-Management
- Parallele Verarbeitung mit GNU Parallel
- Automatische Validierung

## 📄 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe [LICENSE](LICENSE) Datei für Details.

## 👤 Autor

**Christopher Siebert**
- Email: christopher.siebert@concat.de
- GitHub: [@<your-username>](https://github.com/<your-username>)

## 🙏 Danksagungen

- Dell Technologies für PowerScale/OneFS
- Die Open-Source Community
- Alle Tester und Contributor

## ⚠️ Haftungsausschluss

Dieses Tool wird "wie besehen" bereitgestellt. Der Autor übernimmt keine Haftung für Datenverlust oder Schäden durch die Verwendung dieses Tools. Teste immer zuerst in einer Nicht-Produktionsumgebung!

## 🔗 Verwandte Projekte

- [Dell PowerScale OneFS Documentation](https://www.dell.com/support/kbdoc/en-us/000020134/dell-emc-isilon-onefs-documentation)
- [PowerScale CLI Reference](https://www.delltechnologies.com/asset/en-us/products/storage/technical-support/docu94555.pdf)

---

**Made with ❤️ for the PowerScale Community**
