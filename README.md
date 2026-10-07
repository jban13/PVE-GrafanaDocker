# Proxmox-Monitoring mit Prometheus, Grafana und Loki

Dieses Repository richtet eine Monitoring-Umgebung für Proxmox VE mit Docker ein. Dabei werden der Prometheus-PVE-Exporter, Prometheus und Grafana installiert und als Docker-Container gestartet.

Optional kann zusätzlich Grafana Loki für die zentrale Sammlung und Abfrage von Logdateien installiert werden. Die Übertragung der Logdateien zu Loki erfolgt über Grafana Alloy. Alloy wird nicht durch dieses Repository installiert, da Alloy üblicherweise direkt auf dem System beziehungsweise LXC-Container läuft, dessen Logdateien überwacht werden sollen.

Die Konfigurationsdateien für den PVE-Exporter und Prometheus bleiben zur besseren Übersicht in eigenen Verzeichnissen im Repository. Das Installationsskript kopiert die Dateien in das Home-Verzeichnis des ausführenden Benutzers und öffnet die jeweiligen Kopien vor der zugehörigen Installation zur Bearbeitung.

Wenn Loki installiert werden soll, lädt das Skript die zur ausgewählten Loki-Version passende offizielle Konfigurationsdatei herunter. Diese kann vor dem Start des Loki-Containers optional im Texteditor bearbeitet werden.

## Komponenten

Das Installationsskript kann folgende Komponenten einrichten:

- Prometheus-PVE-Exporter
- Prometheus
- Grafana Enterprise
- optional Grafana Loki

Grafana Alloy ist nicht Bestandteil der Installation. Alloy muss separat auf den Systemen installiert werden, von denen Logdateien an Loki übertragen werden sollen.

## Repository-Struktur

```text
PVE-GrafanaDocker/
├── prometheus/
│   └── prometheus.yml
├── pve/
│   └── pve.yml
├── .gitattributes
├── CHANGELOG.md
├── LICENSE
├── README.md
└── SetupMonitoring.sh
```

Für Loki ist keine Konfigurationsvorlage im Repository erforderlich. Das Installationsskript lädt die offizielle Konfigurationsdatei passend zur ausgewählten Loki-Version herunter.

## Voraussetzungen

- Ein Linux-System auf Basis von Debian oder Ubuntu
- Ausführung des Skripts mit ausreichenden administrativen Berechtigungen
- Netzwerkzugriff auf den Proxmox-VE-Host
- Internetzugriff zum Installieren von Paketen und Herunterladen der Docker-Images
- Internetzugriff auf GitHub, falls Loki installiert werden soll
- Ein in Proxmox VE eingerichteter Monitoring-Benutzer oder API-Token mit den erforderlichen Leserechten
- Ein Texteditor wie `nano` oder `vi`
- Freie Netzwerkports für die zu installierenden Dienste

Docker und `curl` werden bei Bedarf durch das Skript installiert.

## Verwendete Ports

Standardmäßig werden folgende Ports verwendet:

- `9221` für den Prometheus-PVE-Exporter
- `9090` für Prometheus
- `3000` für Grafana
- `3100` für Loki, falls Loki installiert wird

Die Ports müssen auf dem Docker-Host verfügbar sein.

## Proxmox-Benutzer vorbereiten

Vor der Installation muss in Proxmox VE ein Benutzer oder API-Token für das Monitoring eingerichtet werden. In der vorhandenen Beispielkonfiguration wird ein Benutzer verwendet.

Der verwendete Zugang sollte nur die für das Auslesen der Monitoring-Daten erforderlichen Rechte erhalten. Anschließend werden die Zugangsdaten in der kopierten Datei `pve.yml` eingetragen.

Es sollten keine produktiven Zugangsdaten in der Konfigurationsvorlage innerhalb des GitHub-Repositories gespeichert werden.

## Installation

### 1. Git installieren

```bash
apt-get update
apt-get install -y git
```

### 2. Repository klonen

```bash
git clone https://github.com/jban13/PVE-GrafanaDocker
cd PVE-GrafanaDocker
```

### 3. Installationsskript ausführbar machen

```bash
chmod +x SetupMonitoring.sh
```

### 4. Installationsskript starten

Wenn das Skript als Benutzer mit ausreichenden Berechtigungen ausgeführt wird:

```bash
./SetupMonitoring.sh
```

Falls administrative Berechtigungen über `sudo` benötigt werden:

```bash
sudo ./SetupMonitoring.sh
```

Das Skript führt die nachfolgend beschriebenen Schritte in der angegebenen Reihenfolge aus.

## Ablauf des Installationsskripts

### 1. Docker und curl installieren

Das Skript aktualisiert zuerst die Paketlisten und installiert Docker sowie `curl`:

```bash
apt-get update
apt-get install -y docker.io curl
systemctl enable --now docker
```

Anschließend steht Docker für die Installation der Monitoring-Komponenten zur Verfügung.

### 2. PVE-Konfiguration kopieren und bearbeiten

Die Vorlage aus dem Repository:

```text
pve/pve.yml
```

wird nach folgendem Ziel kopiert:

```text
~/pve/pve.yml
```

Direkt nach dem Kopieren wird die Zieldatei im ausgewählten Texteditor geöffnet. Dort müssen insbesondere die Proxmox-Zugangsdaten und die TLS-Einstellung kontrolliert und angepasst werden.

Beispiel:

```yaml
default:
  user: monitoring@pve
  password: CHANGE_ME
  verify_ssl: false
```

Nach dem Speichern und Schließen des Editors wird die Installation automatisch fortgesetzt. Erst danach lädt das Skript das Image für den Prometheus-PVE-Exporter herunter und startet den Container.

### 3. PVE-Exporter installieren

Der PVE-Exporter wird auf Port `9221` bereitgestellt. Die zuvor bearbeitete Konfigurationsdatei wird schreibgeschützt in den Container eingebunden:

```text
~/pve/pve.yml -> /etc/prometheus/pve.yml
```

Der lokale Endpunkt ist anschließend unter folgender Adresse erreichbar:

```text
http://localhost:9221
```

Ein beispielhafter Aufruf für einen Proxmox-Host lautet:

```text
http://DOCKER-HOST:9221/pve?target=PROXMOX-IP
```

Dabei sind `DOCKER-HOST` und `PROXMOX-IP` durch die tatsächlichen IP-Adressen zu ersetzen.

### 4. Prometheus-Konfiguration kopieren und bearbeiten

Nach dem Start des PVE-Exporters wird die Prometheus-Vorlage aus dem Repository:

```text
prometheus/prometheus.yml
```

nach folgendem Ziel kopiert:

```text
~/prometheus/prometheus.yml
```

Die kopierte Datei wird ebenfalls automatisch im Texteditor geöffnet.

Vor dem Speichern müssen insbesondere folgende Werte kontrolliert werden:

- IP-Adresse oder Hostname des Proxmox-VE-Hosts
- IP-Adresse oder Hostname des Docker-Hosts
- Port des PVE-Exporters, standardmäßig `9221`
- Modul-, Cluster- und Node-Einstellungen

Die Adresse unter `replacement` muss auf den PVE-Exporter zeigen. In der Regel ist dies die IP-Adresse des Docker-Hosts mit Port `9221`, nicht `localhost`.

Beispiel:

```yaml
scrape_configs:
  - job_name: "pve"
    static_configs:
      - targets:
          - "192.168.2.10"
    metrics_path: /pve
    params:
      module: [default]
      cluster: ["1"]
      node: ["1"]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: "192.168.2.11:9221"
```

Nach dem Speichern und Schließen des Editors beginnt die Prometheus-Installation.

### 5. Prometheus installieren

Das Skript erstellt das persistente Docker-Volume:

```text
prometheus-data
```

Anschließend wird Prometheus auf Port `9090` gestartet.

Die bearbeitete Konfigurationsdatei wird schreibgeschützt eingebunden:

```text
~/prometheus/prometheus.yml -> /etc/prometheus/prometheus.yml
```

Prometheus ist anschließend erreichbar unter:

```text
http://DOCKER-HOST:9090
```

### 6. Grafana installieren

Für Grafana wird das persistente Docker-Volume:

```text
grafana-storage
```

erstellt.

Grafana Enterprise wird anschließend auf Port `3000` gestartet und ist unter folgender Adresse erreichbar:

```text
http://DOCKER-HOST:3000
```

Bei einer neuen Grafana-Installation lauten die standardmäßigen Anmeldedaten normalerweise:

```text
Benutzername: admin
Passwort:      admin
```

Beim ersten Anmelden kann Grafana zur Änderung des Passworts auffordern.

### 7. Optionale Loki-Installation

Nach der Grafana-Installation fragt das Skript:

```text
Soll Loki installiert werden? [j/N]:
```

Mit `n` oder durch Drücken der Eingabetaste wird die Loki-Installation übersprungen.

Mit `j` wird die Loki-Installation gestartet.

#### Loki-Version auswählen

Das Skript fragt anschließend nach der gewünschten Loki-Version:

```text
Gewuenschte Loki-Version, z.B. 3.7.7, oder Enter fuer die neueste stabile Version:
```

Eine bestimmte Version kann ohne oder mit vorangestelltem `v` eingegeben werden.

Beispiele:

```text
3.7.7
```

oder:

```text
v3.7.7
```

Wenn keine Version eingegeben wird, ermittelt das Skript über die GitHub-API die neueste stabile Loki-Version.

Das Docker-Image und die heruntergeladene Konfigurationsdatei verwenden immer dieselbe Loki-Version.

#### Loki-Konfiguration herunterladen

Die offizielle Loki-Konfiguration wird passend zur ausgewählten Version heruntergeladen.

Beispiel für Version `3.7.7`:

```text
https://raw.githubusercontent.com/grafana/loki/v3.7.7/cmd/loki/loki-local-config.yaml
```

Die Datei wird unter folgendem Pfad gespeichert:

```text
~/loki/loki-config.yaml
```

Wenn dort bereits eine Konfigurationsdatei vorhanden ist, erstellt das Skript vor dem Überschreiben eine Sicherung mit Zeitstempel.

Beispiel:

```text
loki-config.yaml.bak.20260902-121500
```

#### Loki-Konfiguration optional bearbeiten

Nach dem Download fragt das Skript:

```text
Soll die Loki-Konfiguration vor der Installation geoeffnet werden? [j/N]:
```

Mit `j` wird die Datei im ausgewählten Texteditor geöffnet.

Mit `n` oder durch Drücken der Eingabetaste wird die offizielle Konfiguration unverändert verwendet.

Nach dem Speichern und Schließen des Editors wird die Installation automatisch fortgesetzt.

#### Loki-Konfiguration validieren

Vor dem Erstellen des Loki-Containers prüft das Skript die Konfiguration mit genau der zuvor ausgewählten Loki-Version.

Dadurch können unter anderem folgende Fehler erkannt werden:

- ungültige YAML-Syntax
- falsche Einrückungen
- unbekannte Konfigurationsfelder
- Konfigurationsfelder, die nicht zur ausgewählten Loki-Version passen

Wenn die Prüfung fehlschlägt, wird kein neuer Loki-Container erstellt und ein vorhandener Loki-Container nicht entfernt.

#### Loki-Container erstellen

Für Loki wird das persistente Docker-Volume:

```text
loki-data
```

erstellt.

Der Container erhält den Namen:

```text
loki
```

Loki wird auf Port `3100` bereitgestellt.

Die Konfigurationsdatei wird schreibgeschützt eingebunden:

```text
~/loki/loki-config.yaml -> /etc/loki/loki-config.yaml
```

Das persistente Volume wird in den von der offiziellen lokalen Konfiguration verwendeten Datenpfad eingebunden:

```text
loki-data -> /tmp/loki
```

Nach dem Start prüft das Skript den Readiness-Endpunkt:

```text
http://localhost:3100/ready
```

Direkt nach dem Start kann Loki vorübergehend folgende Meldung zurückgeben:

```text
Ingester not ready: waiting for 15s after being ready
```

Das Skript wartet in diesem Fall automatisch und wiederholt die Prüfung.

Bei erfolgreichem Start liefert der Endpunkt:

```text
ready
```

### 8. Verhalten bei vorhandenem Loki-Container

Wenn bereits ein Container mit dem Namen `loki` existiert, zeigt das Skript zunächst dessen verwendetes Docker-Image an.

Anschließend erscheint die Abfrage:

```text
Soll der vorhandene Loki-Container mit Version X.Y.Z neu erstellt werden? [j/N]:
```

Mit `j` wird der vorhandene Container entfernt und mit der ausgewählten Version sowie der neuen Konfiguration neu erstellt.

Mit `n` oder durch Drücken der Eingabetaste bleibt der vorhandene Loki-Container unverändert bestehen.

Das Docker-Volume `loki-data` wird beim Entfernen des Containers nicht automatisch gelöscht. Die darin gespeicherten Loki-Daten bleiben daher erhalten.

## Loki in Grafana einbinden

Nach erfolgreicher Loki-Installation muss Loki einmalig als Datenquelle in Grafana eingetragen werden.

In Grafana:

```text
Connections
-> Data sources
-> Add new data source
-> Loki
```

Als URL wird die Adresse des Docker-Hosts mit Port `3100` eingetragen:

```text
http://DOCKER-HOST-IP:3100
```

Beispiel:

```text
http://192.168.2.11:3100
```

Anschließend wird die Verbindung über `Save & test` geprüft.

## Grafana Alloy auf einem anderen LXC

Grafana Alloy wird nicht durch dieses Repository installiert.

Alloy muss auf dem System oder LXC-Container betrieben werden, auf dem die zu überwachenden Logdateien liegen.

Die Loki-Zieladresse für Alloy lautet:

```text
http://LOKI-HOST-IP:3100/loki/api/v1/push
```

Beispiel:

```text
http://192.168.2.11:3100/loki/api/v1/push
```

Ein minimales Beispiel für eine Alloy-Konfiguration zur Übertragung lokaler Logdateien:

```alloy
loki.source.file "application_logs" {
  targets = [
    {
      __path__ = "/var/log/application/*.log",
      job      = "application",
      instance = "application-lxc",
    },
  ]

  file_match {
    enabled = true
  }

  forward_to     = [loki.write.loki.receiver]
  tail_from_end  = true
}

loki.write "loki" {
  endpoint {
    url = "http://LOKI-HOST-IP:3100/loki/api/v1/push"
  }
}
```

Die Pfade, Labels und die Loki-IP-Adresse müssen an die jeweilige Umgebung angepasst werden.

## Logdateien in Grafana abfragen

Nachdem Alloy Logdateien an Loki übertragen hat, können die Einträge in Grafana unter `Explore` abgefragt werden.

Beispiel:

```logql
{job="application"}
```

Suche nach einem bestimmten Text:

```logql
{job="application"} |= "error"
```

Beispiel für NGINX Proxy Manager:

```logql
{job="nginx-proxy-manager"}
```

Suche nach kritischen NGINX-Meldungen:

```logql
{job="nginx-proxy-manager"} |= "[emerg]"
```

## Editor auswählen

Das Skript verwendet den Editor in dieser Reihenfolge:

1. Editor aus der Umgebungsvariable `EDITOR`
2. `nano`
3. `vi`

Das Skript kann beispielsweise ausdrücklich mit `nano` gestartet werden:

```bash
EDITOR=nano ./SetupMonitoring.sh
```

Oder mit `vim`:

```bash
EDITOR=vim ./SetupMonitoring.sh
```

Das Installationsskript wartet jeweils, bis der Editor geschlossen wurde. Erst danach wird der nächste Schritt ausgeführt.

Der ausgewählte Editor wird sowohl für die PVE- und Prometheus-Konfiguration als auch für die optionale Bearbeitung der Loki-Konfiguration verwendet.

## Alternatives Zielverzeichnis

Standardmäßig werden die Konfigurationsdateien im Home-Verzeichnis des ausführenden Benutzers abgelegt:

```text
~/pve/pve.yml
~/prometheus/prometheus.yml
~/loki/loki-config.yaml
```

Über die Umgebungsvariable `TARGET_ROOT` kann ein anderes Stammverzeichnis verwendet werden:

```bash
mkdir -p /opt/monitoring
TARGET_ROOT=/opt/monitoring ./SetupMonitoring.sh
```

Die Dateien werden dann hier abgelegt:

```text
/opt/monitoring/pve/pve.yml
/opt/monitoring/prometheus/prometheus.yml
/opt/monitoring/loki/loki-config.yaml
```

Wird das Skript nicht als `root` ausgeführt, müssen die Berechtigungen für das alternative Zielverzeichnis entsprechend gesetzt werden.

Beispiel:

```bash
sudo mkdir -p /opt/monitoring
sudo chown "$USER:$USER" /opt/monitoring
TARGET_ROOT=/opt/monitoring ./SetupMonitoring.sh
```

## Sicherung vorhandener Konfigurationen

Wenn am Ziel bereits eine gleichnamige Konfigurationsdatei vorhanden ist, erstellt das Skript vor dem Ersetzen eine Sicherung mit Zeitstempel.

Beispiele:

```text
pve.yml.bak.20260828-102000
prometheus.yml.bak.20260828-102100
loki-config.yaml.bak.20260902-121500
```

Bei PVE und Prometheus wird anschließend die aktuelle Vorlage aus dem Repository kopiert und zur Bearbeitung geöffnet.

Bei Loki wird die zur ausgewählten Version passende offizielle Konfiguration heruntergeladen. Anschließend kann die heruntergeladene Datei optional zur Bearbeitung geöffnet werden.

> **Hinweis:** Bei einer erneuten Ausführung des Skripts werden vorhandene Konfigurationsdateien gesichert, aber anschließend durch die Repository-Vorlage beziehungsweise die offizielle Loki-Vorlage ersetzt. Individuelle Einstellungen müssen daher erneut kontrolliert werden.

## Container, Volumes und Ports

Nach erfolgreicher Installation laufen folgende Container:

- `prometheus-pve-exporter` auf Port `9221`
- `prometheus` auf Port `9090`
- `grafana` auf Port `3000`
- optional `loki` auf Port `3100`

Folgende persistente Docker-Volumes werden verwendet:

- `prometheus-data`
- `grafana-storage`
- optional `loki-data`

Die Container verwenden die Neustart-Richtlinie:

```text
unless-stopped
```

Die Container werden dadurch nach einem Neustart des Docker-Hosts normalerweise automatisch wieder gestartet.

Status prüfen:

```bash
docker ps
```

Auch gestoppte Container anzeigen:

```bash
docker ps -a
```

## Container-Logs anzeigen

PVE-Exporter:

```bash
docker logs prometheus-pve-exporter
```

Prometheus:

```bash
docker logs prometheus
```

Grafana:

```bash
docker logs grafana
```

Loki:

```bash
docker logs loki
```

Nur die letzten 50 Loki-Meldungen anzeigen:

```bash
docker logs loki --tail 50
```

Loki-Meldungen live verfolgen:

```bash
docker logs -f loki
```

## Vorhandene Container

Falls einer der folgenden Container bereits existiert, ersetzt das Skript ihn nicht automatisch:

- `prometheus-pve-exporter`
- `prometheus`
- `grafana`

Das Skript zeigt stattdessen einen entsprechenden Hinweis an.

Bei einem vorhandenen Loki-Container fragt das Skript, ob dieser mit der ausgewählten Loki-Version und Konfiguration neu erstellt werden soll.

Vor einer vollständigen Neuinstallation können Container manuell entfernt werden:

```bash
docker rm -f prometheus-pve-exporter
docker rm -f prometheus
docker rm -f grafana
docker rm -f loki
```

> **Achtung:** Das Entfernen eines Containers entfernt nicht automatisch die persistenten Docker-Volumes. Konfigurations-, Mess- und Logdaten sollten trotzdem vor größeren Änderungen gesichert werden.

## Fehlerbehebung

### PVE-Exporter antwortet nicht

Containerstatus und Logs prüfen:

```bash
docker ps -a --filter name=prometheus-pve-exporter
docker logs prometheus-pve-exporter
```

Außerdem prüfen:

- Sind Benutzername und Passwort beziehungsweise API-Token korrekt?
- Besitzt der Proxmox-Benutzer ausreichende Leserechte?
- Ist der Proxmox-Host vom Docker-Host erreichbar?
- Ist `verify_ssl` passend zur TLS-Konfiguration gesetzt?

### Prometheus erreicht den Exporter nicht

Prüfen, ob der Exporter vom Docker-Host erreichbar ist:

```bash
curl http://localhost:9221/
```

Danach in `~/prometheus/prometheus.yml` kontrollieren, ob `replacement` auf die korrekte Adresse verweist:

```yaml
replacement: "DOCKER-HOST-IP:9221"
```

Nach einer Konfigurationsänderung muss Prometheus neu gestartet werden:

```bash
docker restart prometheus
```

### Loki startet nicht

Containerstatus prüfen:

```bash
docker ps -a --filter name=loki
```

Loki-Logs anzeigen:

```bash
docker logs loki --tail 100
```

Konfigurationsdatei kontrollieren:

```bash
cat ~/loki/loki-config.yaml
```

Readiness-Endpunkt prüfen:

```bash
curl http://localhost:3100/ready
```

Direkt nach dem Start kann Loki für kurze Zeit noch nicht bereit sein. Nach ungefähr 15 bis 30 Sekunden sollte folgende Ausgabe erscheinen:

```text
ready
```

### Loki-Konfiguration ist ungültig

Das Installationsskript validiert die heruntergeladene oder bearbeitete Loki-Konfiguration vor dem Erstellen des Containers.

Typische Ursachen für eine ungültige Konfiguration sind:

- fehlerhafte YAML-Einrückung
- unbekannte Konfigurationsfelder
- Konfiguration und Loki-Version passen nicht zusammen
- ein Abschnitt wurde versehentlich einem falschen übergeordneten Abschnitt zugeordnet

In diesem Fall sollte die Sicherungsdatei geprüft oder die Konfiguration erneut passend zur ausgewählten Loki-Version heruntergeladen werden.

### Grafana erreicht Loki nicht

Vom Grafana- beziehungsweise Docker-Host prüfen:

```bash
curl http://localhost:3100/ready
```

Von einem anderen LXC oder Server:

```bash
curl http://LOKI-HOST-IP:3100/ready
```

Wenn lokal `ready` zurückgegeben wird, aber entfernte Systeme Loki nicht erreichen, müssen insbesondere folgende Punkte geprüft werden:

- korrekte IP-Adresse des Loki-Hosts
- Firewall-Regeln
- Proxmox-Firewall
- Netzwerkverbindung zwischen den LXC-Containern
- Portfreigabe `3100:3100` des Loki-Containers

### Alloy sendet keine Logdateien an Loki

Vom Alloy-System zuerst Loki prüfen:

```bash
curl http://LOKI-HOST-IP:3100/ready
```

Anschließend die Alloy-Logs kontrollieren:

```bash
docker logs alloy --tail 100
```

Auf Meldungen wie die folgenden achten:

```text
connection refused
permission denied
failed to tail file
no such file or directory
```

Falls Alloy als Docker-Container läuft, müssen die Logverzeichnisse schreibgeschützt in den Container eingebunden werden.

Beispiel:

```bash
-v "/data/logs:/var/log/application:ro"
```

Der Pfad in `config.alloy` muss dem Pfad innerhalb des Alloy-Containers entsprechen.

### In Grafana werden keine Loki-Logs angezeigt

Unter Grafana `Explore` die Loki-Datenquelle auswählen und zunächst eine allgemeine Anfrage ausführen:

```logql
{job=~".+"}
```

Danach die Abfrage auf das gewünschte Label einschränken:

```logql
{job="nginx-proxy-manager"}
```

Zusätzlich prüfen:

- Ist der gewählte Zeitraum groß genug?
- Existieren seit dem Alloy-Start neue Logeinträge?
- Wird `tail_from_end = true` verwendet?
- Hat Alloy die Logdatei bereits erkannt?
- Ist die Loki-Datenquelle in Grafana erfolgreich verbunden?

Wenn `tail_from_end = true` gesetzt ist, beginnt Alloy beim ersten Erkennen einer Datei am Dateiende. Bereits vorhandene Einträge werden dann nicht übertragen. Zum Testen muss nach dem Start von Alloy eine neue Zeile in die überwachte Datei geschrieben werden.

### Ports sind bereits belegt

Belegte Ports können beispielsweise so geprüft werden:

```bash
ss -lntp | grep -E ':9221|:9090|:3000|:3100'
```

Wenn einer der Ports bereits verwendet wird, muss entweder der bestehende Dienst beendet oder die Portzuordnung im Installationsskript angepasst werden.

## Aktualisierung

Die Container für PVE-Exporter, Prometheus und Grafana werden bei einer erneuten Ausführung des Skripts beibehalten, sofern gleichnamige Container bereits existieren.

Für Loki kann beim erneuten Ausführen eine bestimmte oder die neueste stabile Version ausgewählt werden. Wenn bereits ein Loki-Container existiert, fragt das Skript, ob dieser neu erstellt werden soll.

Vor einer Aktualisierung sollten insbesondere folgende Daten gesichert werden:

- `~/pve/pve.yml`
- `~/prometheus/prometheus.yml`
- `~/loki/loki-config.yaml`
- Docker-Volume `prometheus-data`
- Docker-Volume `grafana-storage`
- Docker-Volume `loki-data`

## Sicherheitshinweise

- Keine echten Zugangsdaten in `pve/pve.yml` im Repository speichern.
- Für Proxmox nach Möglichkeit einen eigenen Monitoring-Benutzer oder API-Token mit minimal erforderlichen Rechten verwenden.
- Die Weboberflächen nicht ungeschützt aus dem Internet erreichbar machen.
- Für produktive Systeme Firewall-Regeln, TLS und sichere Grafana-Zugangsdaten konfigurieren.
- Das Grafana-Standardpasswort unmittelbar nach der ersten Anmeldung ändern.
- Loki besitzt in dieser Konfiguration keine eigene Authentifizierung.
- Port `3100` sollte nur aus vertrauenswürdigen Netzen erreichbar sein.
- Der Zugriff auf Loki sollte über Firewall-Regeln eingeschränkt werden.
- Für eine öffentlich erreichbare Loki-Instanz sollte ein authentifizierender Reverse Proxy eingesetzt werden.
- Konfigurationsdateien werden schreibgeschützt in die Docker-Container eingebunden.
- Persistente Docker-Volumes sollten in die Sicherungsstrategie aufgenommen werden.
- Vor einer Loki-Aktualisierung sollten Konfiguration und Daten gesichert werden.

## Lizenz und Nutzung

Die Nutzung und Weitergabe dieses Projekts richtet sich nach der im Repository enthaltenen Datei:

```text
LICENSE
```

## Star History

<a href="https://www.star-history.com/?repos=jban13%2Fpve-grafanadocker&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=jban13/pve-grafanadocker&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=jban13/pve-grafanadocker&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=jban13/pve-grafanadocker&type=date&legend=top-left" />
 </picture>
</a>

Vor einer produktiven Verwendung sollten das Installationsskript und die Konfigurationen geprüft und an die eigene Umgebung angepasst werden.
``
