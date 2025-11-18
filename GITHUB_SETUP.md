# GitHub Repository Setup Guide

Anleitung zur Einrichtung des PowerScale Quota Wizard als GitHub Repository.

## 📦 Repository erstellen

### 1. Neues Repository auf GitHub erstellen

Gehe zu [github.com/new](https://github.com/new) und erstelle ein neues Repository:

- **Repository Name:** `isilon-quota-wizard` (oder dein gewünschter Name)
- **Description:** `Interactive wizard for automated directory and quota creation on Dell PowerScale/Isilon storage systems`
- **Visibility:** Public
- **DO NOT** initialize with README, .gitignore, or license (wir haben bereits eigene)

### 2. Lokales Repository initialisieren

```bash
# Wechsle in das Verzeichnis mit den Dateien
cd /pfad/zu/deinen/dateien

# Git Repository initialisieren
git init

# Alle Dateien hinzufügen
git add .

# Ersten Commit erstellen
git commit -m "Initial commit: PowerScale Quota Wizard v1.0"

# Main Branch umbenennen (optional, falls du main statt master möchtest)
git branch -M main

# Remote Repository hinzufügen (ersetze <username> mit deinem GitHub-Username)
git remote add origin https://github.com/<username>/isilon-quota-wizard.git

# Zum Repository pushen
git push -u origin main
```

## 🏷️ Tags und Releases

### Ersten Release erstellen

```bash
# Tag für Version 1.0 erstellen
git tag -a v1.0 -m "Release version 1.0"

# Tag pushen
git push origin v1.0
```

### Release auf GitHub erstellen

1. Gehe zu deinem Repository auf GitHub
2. Klicke auf "Releases" → "Create a new release"
3. Wähle den Tag `v1.0`
4. **Release Title:** `PowerScale Quota Wizard v1.0`
5. **Description:**

```markdown
## 🎉 Initial Release

First stable release of the PowerScale Quota Wizard!

### ✨ Features
- Interactive step-by-step wizard
- Comprehensive quota configuration (Hard, Soft, Advisory thresholds)
- Directory owner management
- Parallel processing support
- Input validation with helpful error messages
- Progress display with time estimation
- Colorful output with Unicode symbols

### 📋 Requirements
- Dell PowerScale/Isilon with OneFS
- SSH access to cluster node
- Sufficient permissions for directory creation and quota management

### 🚀 Quick Start
```bash
curl -o isilon_quota_wizard.sh https://raw.githubusercontent.com/<username>/isilon-quota-wizard/main/isilon_quota_wizard.sh
chmod +x isilon_quota_wizard.sh
./isilon_quota_wizard.sh
```

### 📝 Documentation
See [README.md](https://github.com/<username>/isilon-quota-wizard/blob/main/README.md) for full documentation.
```

6. Klicke auf "Publish release"

## 🔧 Repository-Einstellungen

### Issues aktivieren

1. Gehe zu "Settings" → "General"
2. Unter "Features" stelle sicher, dass "Issues" aktiviert ist
3. Optional: Aktiviere "Projects" für Projektmanagement

### Branch Protection Rules (optional, für Collaboration)

1. Gehe zu "Settings" → "Branches"
2. Klicke auf "Add rule"
3. Branch name pattern: `main`
4. Aktiviere:
   - ☑️ Require a pull request before merging
   - ☑️ Require approvals (1)
   - ☑️ Dismiss stale pull request approvals when new commits are pushed

### GitHub Pages (optional, für Dokumentation)

1. Gehe zu "Settings" → "Pages"
2. Source: Deploy from a branch
3. Branch: `main` / `(root)`
4. Speichern

## 📝 README anpassen

Bearbeite die README.md und ersetze `<your-repo>` und `<your-username>` mit deinen tatsächlichen Werten:

```bash
# In README.md suchen und ersetzen:
# <your-repo> → isilon-quota-wizard
# <your-username> → dein-github-username
```

## 🏷️ Topics hinzufügen

1. Gehe zu deinem Repository
2. Klicke auf das Zahnrad neben "About"
3. Füge folgende Topics hinzu:
   - `powerscale`
   - `isilon`
   - `dell-emc`
   - `storage`
   - `quota-management`
   - `bash`
   - `shell-script`
   - `onefs`
   - `wizard`
   - `automation`

## 📊 Badges aktualisieren

Die Badges in der README sind bereits eingefügt:
- MIT License Badge
- Shell Script Badge
- PowerScale Badge

Optional kannst du weitere Badges hinzufügen:
- GitHub Stars: `![GitHub stars](https://img.shields.io/github/stars/<username>/isilon-quota-wizard?style=social)`
- GitHub Forks: `![GitHub forks](https://img.shields.io/github/forks/<username>/isilon-quota-wizard?style=social)`
- Last Commit: `![GitHub last commit](https://img.shields.io/github/last-commit/<username>/isilon-quota-wizard)`

## 🔗 Social Media

Teile dein Repository:
- LinkedIn
- Twitter/X mit #PowerScale #Dell #Storage
- Dell PowerScale Community
- Reddit r/sysadmin

## 📧 Support & Contact

Stelle sicher, dass deine E-Mail-Adresse im README korrekt ist:
- christopher.siebert@concat.de

## ✅ Checklist

- [ ] Repository erstellt
- [ ] Dateien committed und gepusht
- [ ] Tag v1.0 erstellt
- [ ] Release v1.0 veröffentlicht
- [ ] README mit GitHub-Username aktualisiert
- [ ] Topics hinzugefügt
- [ ] Issues aktiviert
- [ ] License sichtbar
- [ ] Repository Description gesetzt
- [ ] Website/Link gesetzt (falls vorhanden)

## 🎉 Fertig!

Dein Repository ist jetzt bereit und öffentlich verfügbar!

Repository URL: `https://github.com/<username>/isilon-quota-wizard`
