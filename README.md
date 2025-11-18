# PowerScale/Isilon Quota Wizard

Ein interaktiver Shell-Wizard zur automatisierten Erstellung von Verzeichnissen mit Quotas auf Dell PowerScale (ehemals Isilon) Storage-Systemen.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![PowerScale](https://img.shields.io/badge/PowerScale-OneFS-blue.svg)](https://www.dell.com/powerscale)

## 🎯 Features

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
- ✅ **Farbige Ausgabe** mit Unicode-Symbolen für bessere Lesbarkeit
- ✅ **Quota-Übersicht** am Ende mit nützlichen Kommandos

## 📋 Voraussetzungen

- Dell PowerScale / Isilon mit OneFS
- Zugriff auf einen Cluster-Node via SSH
- Ausreichende Berechtigungen für:
  - Verzeichnis-Erstellung
  - Quota-Management (`isi quota` Befehle)
  - Optional: `chown` für Owner-Änderungen
- Bash Shell

### Optional für bessere Performance:
- GNU Parallel (empfohlen für große Anzahl Verzeichnisse)
- Falls nicht vorhanden: `xargs` wird als Fallback verwendet

## 🚀 Installation

### Methode 1: Direkt auf PowerScale

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

### Methode 2: Via Git Clone

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

## 📖 Verwendung

### Wizard starten

```bash
./isilon_quota_wizard.sh
```

### Wizard-Schritte

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

## 💡 Beispiele

### Beispiel 1: Einfache Verwendung

1000 Verzeichnisse mit 1MB Hard Quota:

```
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
Basis-Pfad: /ifs/home
Präfix: user
Anzahl: 50
Owner: testuser:users
Hard Threshold: 20G
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

Empfohlene Anzahl paralleler Jobs je nach Anzahl Verzeichnisse:

- 1-100 Verzeichnisse: 5 Jobs
- 100-1000 Verzeichnisse: 10 Jobs (Standard)
- 1000-10000 Verzeichnisse: 15-20 Jobs
- 10000+ Verzeichnisse: 20-30 Jobs

## 📊 Performance

Typische Durchlaufzeiten (abhängig von Cluster-Last):

| Anzahl Verzeichnisse | Sequentiell | Parallel (10 Jobs) |
|---------------------|-------------|-------------------|
| 100 | ~20s | ~3-5s |
| 1000 | ~3-4min | ~20-30s |
| 10000 | ~30-40min | ~3-5min |

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

# Mehrere Quotas löschen (Vorsicht!)
for i in $(seq 1 100); do
  isi quota delete /ifs/data/testdirs/dir_$(printf "%04d" $i)
done
```

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

### Version 1.0 (November 2024)
- Initiales Release
- Interaktiver Wizard mit 8 Schritten
- Umfassende Quota-Konfiguration
- Owner-Management
- Parallele Verarbeitung
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
