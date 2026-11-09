"""Connect the lapNAS media apps to each other through their APIs.

Usage: media-wiring.py <config.json>   (written by hosts/lapnas/media-wiring.nix)

For each connection: find it by name (or the one existing item of the same kind),
create it if it's missing, fix it if it differs. It never deletes anything, so
things added by hand in the apps' UIs survive. Safe to run any number of times.

Python standard library only.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

failures: list[str] = []


def log(msg: str) -> None:
    print(msg, flush=True)


class Api:
    def __init__(self, name: str, base: str, key: str | None = None):
        self.name, self.base, self.key = name, base.rstrip("/"), key

    def call(self, method: str, path: str, body=None, form=None):
        headers = {"Accept": "application/json"}
        data = None
        if self.key:
            headers["X-Api-Key"] = self.key
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        elif form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:500]
            raise RuntimeError(f"{self.name}: {method} {path} -> HTTP {e.code}: {detail}") from None
        if not raw:
            return None
        try:
            return json.loads(raw)
        except ValueError:
            return raw.decode(errors="replace")

    def get(self, path: str):
        return self.call("GET", path)

    def wait(self, path: str, timeout: int = 600) -> bool:
        deadline = time.monotonic() + timeout
        while True:
            try:
                self.get(path)
                return True
            except (OSError, RuntimeError) as e:
                if time.monotonic() > deadline:
                    log(f"{self.name}: not answering after {timeout}s ({e})")
                    return False
                time.sleep(5)


def step(title: str, fn, *args) -> None:
    """Run one wiring step; log a failure and carry on with the rest."""
    try:
        fn(*args)
    except Exception as e:  # noqa: BLE001  (report everything, keep going)
        failures.append(f"{title}: {e}")
        log(f"FAILED {title}: {e}")


def read_key(keys_dir: str, app: str) -> str:
    with open(os.path.join(keys_dir, f"{app}.env")) as f:
        for line in f:
            name, _, value = line.strip().partition("=")
            if name.endswith("__AUTH__APIKEY"):
                return value
    raise RuntimeError(f"no API key in {keys_dir}/{app}.env")


def plex_token(prefs_path: str) -> str | None:
    try:
        return ET.parse(prefs_path).getroot().get("PlexOnlineToken") or None
    except (OSError, ET.ParseError):
        return None


# ---- Sonarr / Radarr / Prowlarr "provider" items (download clients, notifications, apps)


def set_fields(item: dict, fields: dict) -> None:
    names = {f["name"] for f in item.get("fields", [])}
    missing = set(fields) - names
    if missing:
        raise RuntimeError(f"{item.get('implementation')} has no field(s) {sorted(missing)}")
    for f in item["fields"]:
        if f["name"] in fields:
            f["value"] = fields[f["name"]]


def differs(item: dict, fields: dict, extra: dict) -> bool:
    current = {f["name"]: f.get("value") for f in item.get("fields", [])}
    if any(current.get(k) != v for k, v in fields.items()):
        return True  # secret fields come back masked, so they always count as changed
    return any(item.get(k) != v for k, v in extra.items())


def ensure_provider(api: Api, prefix: str, kind: str, name: str, implementation: str,
                    fields: dict, extra=None) -> None:
    """extra: dict of top-level properties, or a function item -> dict."""
    items = api.get(f"{prefix}/{kind}") or []
    match = next((i for i in items if i.get("name") == name), None)
    if match is None:
        same = [i for i in items if i.get("implementation") == implementation]
        match = same[0] if len(same) == 1 else None

    if match is None:
        schema = api.get(f"{prefix}/{kind}/schema")
        item = next((s for s in schema if s.get("implementation") == implementation), None)
        if item is None:
            raise RuntimeError(f"{api.name} has no {kind} type {implementation}")
        item["name"] = name
    else:
        item = match

    extras = extra(item) if callable(extra) else (extra or {})
    if match is not None and not differs(match, fields, extras):
        log(f"{api.name}: {kind} '{item['name']}' ok")
        return
    set_fields(item, fields)
    item.update(extras)
    if match is None:
        api.call("POST", f"{prefix}/{kind}?forceSave=true", body=item)
        log(f"{api.name}: {kind} '{name}' created")
    else:
        api.call("PUT", f"{prefix}/{kind}/{item['id']}?forceSave=true", body=item)
        log(f"{api.name}: {kind} '{item['name']}' updated")


def ensure_root_folder(api: Api, path: str) -> None:
    roots = api.get("/api/v3/rootfolder") or []
    if any(r.get("path", "").rstrip("/") == path.rstrip("/") for r in roots):
        log(f"{api.name}: root folder {path} ok")
        return
    api.call("POST", "/api/v3/rootfolder", body={"path": path})
    log(f"{api.name}: root folder {path} added")


def plex_events(item: dict) -> dict:
    """Turn on every event the Plex connection supports (import, upgrade, rename, delete...)."""
    return {"on" + k[len("supportsOn"):]: True
            for k, v in item.items() if k.startswith("supportsOn") and v}


# ---- qBittorrent


def ensure_categories(qbt: Api, categories: dict) -> None:
    existing = qbt.get("/api/v2/torrents/categories") or {}
    for name, path in categories.items():
        if name not in existing:
            qbt.call("POST", "/api/v2/torrents/createCategory", form={"category": name, "savePath": path})
            log(f"qBittorrent: category {name} -> {path} created")
        elif existing[name].get("savePath", "").rstrip("/") != path.rstrip("/"):
            qbt.call("POST", "/api/v2/torrents/editCategory", form={"category": name, "savePath": path})
            log(f"qBittorrent: category {name} -> {path} updated")
        else:
            log(f"qBittorrent: category {name} ok")


# Stop every torrent the moment it finishes downloading (ratio limit 0, action Stop).
# Sonarr and Radarr then import it and remove it from qBittorrent, files included; the
# library keeps its own copy. Removing straight away in qBittorrent would race the import.
# Stop is 0 in qBittorrent's max_ratio_act; 1 and 3 remove the torrent, 2 super-seeds.
QBT_NO_SEEDING = {"max_ratio_enabled": True, "max_ratio": 0, "max_ratio_act": 0}


def ensure_no_seeding(qbt: Api) -> None:
    prefs = qbt.get("/api/v2/app/preferences") or {}
    if all(prefs.get(k) == v for k, v in QBT_NO_SEEDING.items()):
        log("qBittorrent: stop on completion ok")
        return
    qbt.call("POST", "/api/v2/app/setPreferences", form={"json": json.dumps(QBT_NO_SEEDING)})
    log("qBittorrent: stop on completion set")


# ---- Seerr


def ensure_seerr(cfg: dict, arr: dict) -> None:
    try:
        with open(cfg["seerrSettings"]) as f:
            key = json.load(f)["main"]["apiKey"]
    except (OSError, ValueError, KeyError):
        log("Seerr: not set up yet (no settings.json); skipping. Finish its setup page, then re-run this.")
        return
    seerr = Api("Seerr", cfg["seerr"]["url"], key)
    if not seerr.wait("/api/v1/status"):
        raise RuntimeError("not answering")
    if not seerr.get("/api/v1/settings/public").get("initialized"):
        log("Seerr: setup not finished; skipping. Finish its setup page, then re-run this.")
        return

    for app in ("sonarr", "radarr"):
        a = arr[app]
        profiles = a["api"].get("/api/v3/qualityprofile") or []
        if not profiles:
            raise RuntimeError(f"{app} has no quality profiles")
        entries = seerr.get(f"/api/v1/settings/{app}") or []
        wanted = {
            "hostname": "127.0.0.1",
            "port": a["port"],
            "apiKey": a["key"],
            "useSsl": False,
            "baseUrl": "",
            "activeDirectory": a["root"],
        }
        if not entries:
            p = profiles[0]
            body = {
                "name": app.capitalize(),
                **wanted,
                "activeProfileId": p["id"],
                "activeProfileName": p["name"],
                "is4k": False,
                "isDefault": True,
                "syncEnabled": False,
                "preventSearch": False,
                "tags": [],
            }
            if app == "sonarr":
                body.update(enableSeasonFolders=True, animeTags=[])
            else:
                body.update(minimumAvailability="released")
            seerr.call("POST", f"/api/v1/settings/{app}", body=body)
            log(f"Seerr: {app} server created")
            continue
        for e in entries:
            new = {**e, **wanted}
            ids = {p["id"]: p["name"] for p in profiles}
            if e.get("activeProfileId") not in ids:
                by_name = next((p for p in profiles if p["name"] == e.get("activeProfileName")), profiles[0])
                new["activeProfileId"], new["activeProfileName"] = by_name["id"], by_name["name"]
            if new == e:
                log(f"Seerr: {app} server '{e.get('name')}' ok")
                continue
            # Seerr 3.5 rejects "id" in the body (read-only); it's in the URL.
            body = {k: v for k, v in new.items() if k != "id"}
            seerr.call("PUT", f"/api/v1/settings/{app}/{e['id']}", body=body)
            log(f"Seerr: {app} server '{e.get('name')}' updated")


# ---- main


def main() -> int:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)

    keys = {app: read_key(cfg["keysDir"], app) for app in ("sonarr", "radarr", "prowlarr")}
    arr = {}
    for app in ("sonarr", "radarr"):
        c = cfg[app]
        arr[app] = {**c, "key": keys[app], "api": Api(app.capitalize(), c["url"], keys[app])}
    prowlarr = Api("Prowlarr", cfg["prowlarr"]["url"], keys["prowlarr"])
    qbt = Api("qBittorrent", cfg["qbittorrent"]["url"])

    up = {
        "sonarr": arr["sonarr"]["api"].wait("/api/v3/system/status"),
        "radarr": arr["radarr"]["api"].wait("/api/v3/system/status"),
        "prowlarr": prowlarr.wait("/api/v1/system/status"),
        "qbittorrent": qbt.wait("/api/v2/app/version"),
    }
    for name, ok in up.items():
        if not ok:
            failures.append(f"{name} not answering")

    token = plex_token(cfg["plexPreferences"])
    if token is None:
        log("Plex: not signed in yet (no token); skipping the Plex connections. Sign in, then re-run this.")
    else:
        # Sonarr/Radarr test the Plex connection before saving it, so Plex must be answering.
        plex = Api("Plex", f"http://{cfg['plex']['host']}:{cfg['plex']['port']}")
        if not plex.wait("/identity"):
            failures.append("plex not answering")
            token = None

    if up["qbittorrent"]:
        step("qBittorrent categories", ensure_categories, qbt, cfg["qbittorrent"]["categories"])
        step("qBittorrent stop on completion", ensure_no_seeding, qbt)

    for app, a in arr.items():
        if not up[app]:
            continue
        api = a["api"]
        category_field = "tvCategory" if app == "sonarr" else "movieCategory"
        step(f"{app} root folder", ensure_root_folder, api, a["root"])
        if up["qbittorrent"]:
            step(f"{app} -> qBittorrent", ensure_provider, api, "/api/v3", "downloadclient",
                 "qBittorrent", "QBittorrent",
                 {"host": cfg["qbittorrent"]["host"], "port": cfg["qbittorrent"]["port"],
                  "useSsl": False, "username": "", "password": "", category_field: a["category"]},
                 # Remove each download from qBittorrent (with its files) once imported.
                 {"enable": True, "removeCompletedDownloads": True, "removeFailedDownloads": True})
        if token:
            step(f"{app} -> Plex", ensure_provider, api, "/api/v3", "notification",
                 "Plex", "PlexServer",
                 {"host": cfg["plex"]["host"], "port": cfg["plex"]["port"], "useSsl": False,
                  "authToken": token, "updateLibrary": True},
                 plex_events)
        if up["prowlarr"]:
            step(f"Prowlarr -> {app}", ensure_provider, prowlarr, "/api/v1", "applications",
                 app.capitalize(), app.capitalize(),
                 {"prowlarrUrl": cfg["prowlarr"]["url"], "baseUrl": a["url"], "apiKey": a["key"]},
                 {"syncLevel": "fullSync"})

    if up["sonarr"] and up["radarr"]:
        step("Seerr -> Sonarr/Radarr", ensure_seerr, cfg, arr)

    if failures:
        log(f"\n{len(failures)} step(s) failed:")
        for f in failures:
            log(f"  - {f}")
        return 1
    log("\nAll media connections in place.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
