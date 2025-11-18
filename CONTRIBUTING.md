# Beitragen zum PowerScale Quota Wizard

Vielen Dank für dein Interesse, zum PowerScale Quota Wizard beizutragen! 🎉

## 📋 Inhaltsverzeichnis

- [Code of Conduct](#code-of-conduct)
- [Wie kann ich beitragen?](#wie-kann-ich-beitragen)
- [Entwicklungsumgebung einrichten](#entwicklungsumgebung-einrichten)
- [Pull Request Prozess](#pull-request-prozess)
- [Coding Standards](#coding-standards)
- [Testing](#testing)

## Code of Conduct

Bitte sei respektvoll und konstruktiv in der Kommunikation mit anderen Contributors und Maintainern.

## Wie kann ich beitragen?

### 🐛 Bugs melden

Wenn du einen Bug findest:

1. Prüfe, ob der Bug bereits gemeldet wurde (Issues durchsuchen)
2. Wenn nicht, erstelle ein neues Issue mit:
   - Beschreibung des Problems
   - Schritte zur Reproduktion
   - Erwartetes vs. tatsächliches Verhalten
   - PowerScale/OneFS Version
   - Relevante Log-Ausgaben

### 💡 Features vorschlagen

Für Feature-Vorschläge:

1. Prüfe, ob das Feature bereits vorgeschlagen wurde
2. Erstelle ein Issue mit:
   - Detaillierte Beschreibung des Features
   - Use Case / Anwendungsfall
   - Mögliche Implementierungsideen

### 🔧 Code beitragen

1. Fork das Repository
2. Erstelle einen Feature-Branch
3. Implementiere deine Änderungen
4. Teste gründlich auf einem PowerScale-System
5. Committe mit aussagekräftigen Commit-Messages
6. Erstelle einen Pull Request

## Entwicklungsumgebung einrichten

### Voraussetzungen

- Zugang zu einem PowerScale/Isilon Test-System
- Bash Shell Kenntnisse
- Git

### Setup

```bash
# Repository forken und klonen
git clone https://github.com/<your-username>/isilon-quota-wizard.git
cd isilon-quota-wizard

# Feature-Branch erstellen
git checkout -b feature/mein-neues-feature

# Script bearbeiten
vim isilon_quota_wizard.sh

# Auf Test-System kopieren und testen
scp isilon_quota_wizard.sh root@<test-powerscale>:/root/
ssh root@<test-powerscale>
```

## Pull Request Prozess

1. **Branch aktualisieren**
   ```bash
   git checkout main
   git pull upstream main
   git checkout feature/mein-neues-feature
   git rebase main
   ```

2. **Code überprüfen**
   - Folgt der Code den Coding Standards?
   - Sind alle Änderungen getestet?
   - Ist die Dokumentation aktualisiert?

3. **Pull Request erstellen**
   - Beschreibe die Änderungen klar
   - Verlinke relevante Issues
   - Füge Screenshots hinzu (falls UI-Änderungen)

4. **Review-Prozess**
   - Reagiere auf Feedback
   - Nimm angeforderte Änderungen vor
   - Halte die Diskussion konstruktiv

## Coding Standards

### Bash Script Best Practices

```bash
# Gute Variablennamen verwenden
QUOTA_HARD="1M"  # Gut
x="1M"           # Schlecht

# Funktionen dokumentieren
# Erstellt ein Verzeichnis mit Quota
# Args:
#   $1 - Verzeichnisnummer
#   $2 - Pfad
create_dir_with_quota() {
    # ...
}

# Fehlerbehandlung
if ! mkdir -p "$dir_path" 2>/dev/null; then
    print_error "Konnte Verzeichnis nicht erstellen: $dir_path"
    return 1
fi

# Quoting beachten
rm -rf "$dir_path"      # Gut
rm -rf $dir_path        # Schlecht (Probleme bei Leerzeichen)
```

### Commit Messages

```
feat: Add advisory threshold support
fix: Correct quota list filtering
docs: Update README with new examples
refactor: Improve error handling in create_dir_with_quota
test: Add validation tests for user input
```

Präfixe:
- `feat:` - Neues Feature
- `fix:` - Bugfix
- `docs:` - Dokumentations-Änderungen
- `refactor:` - Code-Refactoring
- `test:` - Test-Änderungen
- `chore:` - Build/Tool-Änderungen

### Code-Stil

- **Einrückung:** 4 Spaces (keine Tabs)
- **Zeilenlänge:** Max. 120 Zeichen
- **Funktionen:** Kleine, fokussierte Funktionen
- **Kommentare:** Erkläre das "Warum", nicht das "Was"
- **Fehlerbehandlung:** Immer Fehler abfangen und behandeln

## Testing

### Manuelle Tests

Teste auf einem PowerScale-System:

```bash
# Test 1: Grundfunktionalität
# - 10 Verzeichnisse erstellen
# - Mit 1MB Hard Quota
# - Prüfen ob alle erstellt wurden

# Test 2: Quota-Optionen
# - Soft Threshold testen
# - Advisory Threshold testen
# - Grace Period verifizieren

# Test 3: Owner-Setting
# - Mit spezifischem User/Group
# - Verifizieren mit ls -la

# Test 4: Fehlerbehandlung
# - Ungültige Pfade
# - Nicht-existierende User
# - Fehlende Berechtigungen
```

### Test-Checklist

- [ ] Script startet ohne Fehler
- [ ] Alle Wizard-Schritte funktionieren
- [ ] Eingabe-Validierung funktioniert
- [ ] Verzeichnisse werden erstellt
- [ ] Quotas werden gesetzt
- [ ] Owner wird korrekt gesetzt (falls aktiviert)
- [ ] Parallele Verarbeitung funktioniert
- [ ] Fehlerbehandlung funktioniert
- [ ] Quota-Übersicht zeigt korrekte Daten

## Fragen?

Bei Fragen kannst du:
- Ein Issue erstellen
- Eine E-Mail senden an: christopher.siebert@concat.de

Vielen Dank für deine Beiträge! 🙏
