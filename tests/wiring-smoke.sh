#!/usr/bin/env bash
# Smoke test for scripts/media-wiring.py and scripts/qbt-config.py against the real
# apps from the flake's pinned nixpkgs. No VM or systemd needed, so it runs in Docker
# on the Windows PC:
#
#   docker run --rm -v lapnas-nix-store:/nix -v "<repo>:/repo" nixos/nix:2.28.3 \
#     nix --extra-experimental-features "nix-command flakes" shell --inputs-from /repo \
#       nixpkgs#bash nixpkgs#python3 nixpkgs#curl nixpkgs#jq nixpkgs#sonarr nixpkgs#radarr \
#       nixpkgs#prowlarr nixpkgs#qbittorrent-nox -c bash /repo/tests/wiring-smoke.sh
#
# It runs the wiring twice: the first run must create everything, the second must
# find everything already in place.
set -euo pipefail
cd "$(dirname "$0")/.."

T=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
mkdir -p "$T/keys" "$T/plex/Plex Media Server" \
  "$T/share/downloads/tv" "$T/share/downloads/movies" "$T/share/plex/shows" "$T/share/plex/movies"

echo "SONARR__AUTH__APIKEY=11111111111111111111111111111111" > "$T/keys/sonarr.env"
echo "RADARR__AUTH__APIKEY=22222222222222222222222222222222" > "$T/keys/radarr.env"
echo "PROWLARR__AUTH__APIKEY=33333333333333333333333333333333" > "$T/keys/prowlarr.env"
echo '<?xml version="1.0" encoding="utf-8"?><Preferences PlexOnlineToken="test-token"/>' \
  > "$T/plex/Plex Media Server/Preferences.xml"

cat > "$T/wiring.json" <<EOF
{
  "keysDir": "$T/keys",
  "plexPreferences": "$T/plex/Plex Media Server/Preferences.xml",
  "seerrSettings": "$T/seerr/settings.json",
  "plex": {"host": "127.0.0.1", "port": 32400},
  "qbittorrent": {"url": "http://127.0.0.1:8080", "host": "127.0.0.1", "port": 8080,
    "categories": {"tv-sonarr": "$T/share/downloads/tv", "radarr": "$T/share/downloads/movies"}},
  "prowlarr": {"url": "http://127.0.0.1:9696"},
  "sonarr": {"url": "http://127.0.0.1:8989", "port": 8989, "root": "$T/share/plex/shows", "category": "tv-sonarr"},
  "radarr": {"url": "http://127.0.0.1:7878", "port": 7878, "root": "$T/share/plex/movies", "category": "radarr"},
  "seerr": {"url": "http://127.0.0.1:5055"}
}
EOF

cat > "$T/qbt-managed.json" <<EOF
{
  "LegalNotice": {"Accepted": "true"},
  "BitTorrent": {"Session\\\\DefaultSavePath": "$T/share/downloads", "Session\\\\TempPathEnabled": "false",
                 "Session\\\\Port": "24116", "Session\\\\DisableAutoTMMByDefault": "false"},
  "Preferences": {"WebUI\\\\Port": "8080", "WebUI\\\\LocalHostAuth": "false"}
}
EOF

echo "== qbt-config"
QCONF="$T/qbt/qBittorrent/config/qBittorrent.conf"
mkdir -p "$(dirname "$QCONF")"
printf '[Preferences]\nWebUI\\Password_PBKDF2="@ByteArray(keep:me)"\nWebUI\\Port=9999\n' > "$QCONF"
python3 scripts/qbt-config.py "$QCONF" "$T/qbt-managed.json"
grep -q 'Password_PBKDF2="@ByteArray(keep:me)"' "$QCONF" || { echo "qbt-config lost the password"; exit 1; }
grep -q 'WebUI\\Port=8080' "$QCONF" || { echo "qbt-config did not set the port"; exit 1; }
cat "$QCONF"

echo "== starting apps"
(set -a; . "$T/keys/sonarr.env"; exec Sonarr -nobrowser -data="$T/sonarr") > "$T/sonarr.log" 2>&1 &
(set -a; . "$T/keys/radarr.env"; exec Radarr -nobrowser -data="$T/radarr") > "$T/radarr.log" 2>&1 &
(set -a; . "$T/keys/prowlarr.env"; exec Prowlarr -nobrowser -data="$T/prowlarr") > "$T/prowlarr.log" 2>&1 &
qbittorrent-nox --profile="$T/qbt" --webui-port=8080 > "$T/qbt.log" 2>&1 &
# Plex can't run here, so a stand-in answers the calls Sonarr/Radarr make when they
# test the Plex connection: one TV and one movie library.
python3 - > "$T/fakeplex.log" 2>&1 <<'PY' &
import json, http.server
BODY = json.dumps({"MediaContainer": {"version": "1.43.3.0", "machineIdentifier": "smoke", "size": 2,
    "Directory": [
        {"key": "1", "type": "show", "title": "TV Shows", "agent": "tv.plex.agents.series", "Location": [{"id": 1, "path": "/shows"}]},
        {"key": "2", "type": "movie", "title": "Movies", "agent": "tv.plex.agents.movie", "Location": [{"id": 2, "path": "/movies"}]}]}}).encode()
class H(http.server.BaseHTTPRequestHandler):
    def _ok(self):
        print(self.command, self.path, flush=True)
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(BODY))); self.end_headers(); self.wfile.write(BODY)
    do_GET = do_PUT = do_POST = _ok
http.server.ThreadingHTTPServer(("127.0.0.1", 32400), H).serve_forever()
PY

echo "== wiring, first run"
python3 scripts/media-wiring.py "$T/wiring.json"
echo "== wiring, second run (must change nothing but masked secrets)"
python3 scripts/media-wiring.py "$T/wiring.json" | tee "$T/run2.log"
if grep -E "created|added" "$T/run2.log"; then echo "second run created things again"; exit 1; fi

echo "== result"
S="curl -fsS -H X-Api-Key:11111111111111111111111111111111 http://127.0.0.1:8989/api/v3"
R="curl -fsS -H X-Api-Key:22222222222222222222222222222222 http://127.0.0.1:7878/api/v3"
P="curl -fsS -H X-Api-Key:33333333333333333333333333333333 http://127.0.0.1:9696/api/v1"
f='{name, implementation, fields: [.fields[] | select(.name|test("host|port|Category|baseUrl|prowlarrUrl|updateLibrary")) | {(.name): .value}] | add}'
echo "Sonarr:";   $S/rootfolder | jq -c '[.[].path]'; $S/downloadclient | jq -c ".[] | $f"; $S/notification | jq -c ".[] | $f + {onDownload, onUpgrade, onRename}"
echo "Radarr:";   $R/rootfolder | jq -c '[.[].path]'; $R/downloadclient | jq -c ".[] | $f"; $R/notification | jq -c ".[] | $f + {onDownload, onUpgrade, onRename}"
echo "Prowlarr:"; $P/applications | jq -c ".[] | $f + {syncLevel}"
echo "qBittorrent:"; curl -fsS http://127.0.0.1:8080/api/v2/torrents/categories | jq -c 'map_values(.savePath)'
Q=$(curl -fsS http://127.0.0.1:8080/api/v2/app/preferences | jq -c '{max_ratio_enabled, max_ratio, max_ratio_act}')
echo "$Q"; [ "$Q" = '{"max_ratio_enabled":true,"max_ratio":0,"max_ratio_act":0}' ] || { echo "qBittorrent still seeds"; exit 1; }
for app in "$S" "$R"; do
  D=$($app/downloadclient | jq -c '.[] | {removeCompletedDownloads, removeFailedDownloads}')
  [ "$D" = '{"removeCompletedDownloads":true,"removeFailedDownloads":true}' ] || { echo "download client keeps completed: $D"; exit 1; }
done
echo; echo "SMOKE TEST PASSED"
