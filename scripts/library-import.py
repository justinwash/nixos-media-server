"""One-time library steps after an install (docs/install.md, first-boot checklist).

Usage, on lapNAS:
  python3 library-import.py <media-wiring.json> [options] survey|arr|plex-paths [--apply]

  survey      Read-only: what Plex has, and what Sonarr/Radarr already have.
  arr         Add every movie and show in Plex to Radarr/Sonarr, at its existing folder,
              by the TMDB/TVDB id Plex matched it to. No searches, no downloads; ones
              already there are skipped. Turns off quality upgrades on the profiles it
              uses, so the import doesn't start downloading "better" copies.
  plex-paths  Move Plex's library folders from an old mount path (--old-prefix) to /srv/share: add the
              new folder, scan, check every item has a copy there, drop the old folder,
              scan, check every item (and so its watch history) is still there.
Without --apply, arr and plex-paths only print what they would do.

Options:
  --keys DIR         API key files (default: keysDir from the config; root-only)
  --plex-token FILE  file holding the Plex token (default: read Plex's Preferences.xml)
  --hints FILE       JSON with old per-item settings: {"sonarr": {"<tvdbId>":
                     {"seriesType": "anime", "seasonFolder": false, "profile": "..."}},
                     "radarr": {"<tmdbId>": {"profile": "..."}}}, and ids for folders
                     Plex matched wrongly: {"folders": {"<folder>": {"tvdb": "..."}}}

media-wiring.json is in the lapnas-media-wiring unit: systemctl cat lapnas-media-wiring.
Python standard library only; reuses media-wiring.py from the same folder.
"""

import argparse
import importlib.util
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

_spec = importlib.util.spec_from_file_location(
    "media_wiring", os.path.join(os.path.dirname(os.path.abspath(__file__)), "media-wiring.py"))
w = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(w)
log = w.log

# Where the media drive was mounted before (set with --old-prefix), and where it is now.
OLD_PREFIX = "/run/media/USER/share"
NEW_PREFIX = "/srv/share"
DEFAULT_PROFILE = "HD - 720p/1080p"
SERIES_TYPES = {0: "standard", 1: "daily", 2: "anime"}


def new_path(p: str) -> str:
    return NEW_PREFIX + p[len(OLD_PREFIX):] if p.startswith(OLD_PREFIX) else p


class Plex:
    """Plex's API. The token goes in a header, so it never shows up in errors or logs."""

    def __init__(self, base: str, token: str):
        self.base, self.token = base.rstrip("/"), token

    def call(self, method: str, path: str, params=None):
        url = self.base + path
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params, doseq=True)
        req = urllib.request.Request(url, method=method, headers={
            "Accept": "application/json", "X-Plex-Token": self.token})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"Plex: {method} {path} -> HTTP {e.code}") from None
        return json.loads(raw) if raw.strip() else None

    def get(self, path: str, params=None):
        return (self.call("GET", path, params) or {}).get("MediaContainer", {})

    def sections(self) -> list:
        return self.get("/library/sections").get("Directory", [])

    def section(self, key: str) -> dict:
        return next(s for s in self.sections() if s["key"] == key)

    def items(self, key: str, plex_type: int) -> list:
        return self.get(f"/library/sections/{key}/all",
                        {"type": plex_type, "includeGuids": 1}).get("Metadata", [])


def guid_ids(item: dict) -> dict:
    """{"tmdb": "603", "tvdb": "...", "imdb": "tt..."} from new- and old-agent guids."""
    ids = {}
    for g in item.get("Guid", []):
        scheme, _, value = g.get("id", "").partition("://")
        ids[scheme] = value
    old = item.get("guid", "")
    for agent, scheme in (("themoviedb", "tmdb"), ("thetvdb", "tvdb"), ("imdb", "imdb")):
        prefix = f"com.plexapp.agents.{agent}://"
        if old.startswith(prefix):
            ids.setdefault(scheme, old[len(prefix):].split("?")[0].split("/")[0])
    return ids


def parts(item: dict) -> list:
    return [p["file"] for m in item.get("Media", []) for p in m.get("Part", []) if "file" in p]


# ---- survey / arr


def top_folder(file: str, roots: list) -> str | None:
    """The folder right under a library root that holds this file (files can sit deeper)."""
    for root in roots:
        rel = file[len(root):].lstrip("/") if file.startswith(root.rstrip("/") + "/") else None
        if rel and "/" in rel:
            return new_path(root.rstrip("/") + "/" + rel.split("/")[0])
    return None


def plex_library(plex: Plex, hints: dict | None = None):
    """[(kind, title, ids, folder)] for every movie and show in Plex.

    hints["folders"] = {"<new folder path>": {"tvdb": "..."}} overrides a wrong Plex match."""
    overrides = (hints or {}).get("folders", {})
    out = []
    for s in plex.sections():
        roots = [l["path"] for l in s.get("Location", [])]
        if s["type"] == "movie":
            for m in plex.items(s["key"], 1):
                files = parts(m)
                folder = top_folder(files[0], roots) if files else None
                ids = {**guid_ids(m), **overrides.get(folder, {})}
                out.append(("movie", f"{m.get('title')} ({m.get('year')})", ids, folder))
        elif s["type"] == "show":
            for m in plex.items(s["key"], 2):
                locs = [l["path"] for l in m.get("Location", [])]
                if not locs:  # not in the section listing on every Plex version
                    meta = plex.get(f"/library/metadata/{m['ratingKey']}").get("Metadata", [{}])[0]
                    locs = [l["path"] for l in meta.get("Location", [])]
                folder = new_path(locs[0]) if locs else None
                out.append(("show", m.get("title"), {**guid_ids(m), **overrides.get(folder, {})}, folder))
    return out


def pick_profile(profiles: list, name: str | None) -> dict:
    by_name = {p["name"]: p for p in profiles}
    return by_name.get(name or "") or by_name.get(DEFAULT_PROFILE) or profiles[0]


def run_arr(plex: Plex, sonarr: w.Api, radarr: w.Api, hints: dict, apply: bool) -> int:
    lib = plex_library(plex, hints)
    have = {
        "movie": {str(m.get("tmdbId")) for m in radarr.get("/api/v3/movie")},
        "show": {str(s.get("tvdbId")) for s in sonarr.get("/api/v3/series")},
    }
    profiles = {"movie": radarr.get("/api/v3/qualityprofile"), "show": sonarr.get("/api/v3/qualityprofile")}
    api = {"movie": radarr, "show": sonarr}
    used = {"movie": {}, "show": {}}
    problems = []
    added = skipped = 0

    for kind, title, ids, folder in sorted(lib, key=lambda x: (x[0], x[1] or "")):
        key = ids.get("tmdb" if kind == "movie" else "tvdb")
        if not folder:
            problems.append(f"{kind} {title}: Plex has no file/folder for it")
            continue
        if not key:
            problems.append(f"{kind} {title}: Plex has no {'TMDB' if kind == 'movie' else 'TVDB'} id ({ids})")
            continue
        if key in have[kind]:
            skipped += 1
            continue
        hint = hints.get("radarr" if kind == "movie" else "sonarr", {}).get(key, {})
        prof = pick_profile(profiles[kind], hint.get("profile"))
        used[kind][prof["id"]] = prof
        if kind == "movie":
            body = radarr.get(f"/api/v3/movie/lookup/tmdb?tmdbId={key}")
            body.update(qualityProfileId=prof["id"], path=folder, monitored=True,
                        minimumAvailability="released",
                        addOptions={"searchForMovie": False, "monitor": "movieOnly"})
            body.pop("id", None)
            extra = ""
        else:
            found = sonarr.get(f"/api/v3/series/lookup?term=tvdb:{key}")
            if not found:
                problems.append(f"show {title}: Sonarr can't find TVDB {key}")
                continue
            body = found[0]
            stype = hint.get("seriesType", "standard")
            season_folder = hint.get("seasonFolder",
                                     any(n.lower().startswith("season") for n in safe_listdir(folder)))
            body.update(qualityProfileId=prof["id"], path=folder, monitored=True,
                        seasonFolder=season_folder, seriesType=stype,
                        addOptions={"monitor": "all", "searchForMissingEpisodes": False,
                                    "searchForCutoffUnmetEpisodes": False})
            body.pop("id", None)
            extra = f", {stype}, season folders {'on' if season_folder else 'off'}"
        log(f"{'add' if apply else 'would add'} {kind}: {title} -> {body.get('title')} "
            f"({body.get('year')}) at {folder} [{prof['name']}{extra}]")
        if body.get("title") is None:
            problems.append(f"{kind} {title}: lookup returned nothing for {key}")
            continue
        if apply:
            try:
                api[kind].call("POST", "/api/v3/" + ("movie" if kind == "movie" else "series"), body=body)
                have[kind].add(key)
                added += 1
            except RuntimeError as e:
                problems.append(f"{kind} {title}: {e}")
        else:
            added += 1

    for kind, profs in used.items():
        for p in profs.values():
            if p.get("upgradeAllowed"):
                log(f"{'turn' if apply else 'would turn'} off upgrades: {api[kind].name} profile '{p['name']}'")
                if apply:
                    p["upgradeAllowed"] = False
                    api[kind].call("PUT", f"/api/v3/qualityprofile/{p['id']}", body=p)

    log(f"\n{'Added' if apply else 'Would add'} {added}, already there {skipped}, problems {len(problems)}")
    for p in problems:
        log(f"  - {p}")
    return 1 if problems else 0


def safe_listdir(path: str) -> list:
    try:
        return os.listdir(path)
    except OSError:
        return []


def survey(plex: Plex, sonarr: w.Api, radarr: w.Api, prowlarr: w.Api) -> int:
    for s in plex.sections():
        locs = [l["path"] for l in s.get("Location", [])]
        log(f"Plex section {s['key']} '{s['title']}' ({s['type']}, {s.get('agent')}): {locs}")
    lib = plex_library(plex)
    for kind in ("movie", "show"):
        rows = [x for x in lib if x[0] == kind]
        idk = "tmdb" if kind == "movie" else "tvdb"
        log(f"Plex {kind}s: {len(rows)}, with a {idk} id: {sum(1 for x in rows if x[2].get(idk))}")
        for _, title, ids, folder in rows:
            if not ids.get(idk) or not folder:
                log(f"  no {idk} id or folder: {title} {ids} {folder}")
    log(f"Radarr: {len(radarr.get('/api/v3/movie'))} movies; Sonarr: {len(sonarr.get('/api/v3/series'))} series")
    for name, api in (("Radarr", radarr), ("Sonarr", sonarr)):
        log(f"{name} profiles: " + ", ".join(
            f"{p['name']} (upgrades {'on' if p.get('upgradeAllowed') else 'off'})"
            for p in api.get("/api/v3/qualityprofile")))
    idx = prowlarr.get("/api/v1/indexer")
    apps = prowlarr.get("/api/v1/applications")
    log(f"Prowlarr: {len(idx)} indexers ({sum(1 for i in idx if i.get('enable'))} on), "
        f"apps: {[a['name'] for a in apps]}")
    return 0


# ---- plex-paths


ITEM_TYPE = {"movie": 1, "show": 4, "artist": 10}  # what to count per section: movies, episodes, tracks


def snapshot(plex: Plex, key: str, plex_type: int) -> dict:
    """{ratingKey: (viewCount, [files])} for every item in the section."""
    return {m["ratingKey"]: (int(m.get("viewCount", 0)), parts(m)) for m in plex.items(key, plex_type)}


def scan(plex: Plex, key: str) -> None:
    plex.call("GET", f"/library/sections/{key}/refresh")
    time.sleep(5)
    deadline = time.monotonic() + 3600
    while plex.section(key).get("refreshing"):
        if time.monotonic() > deadline:
            raise RuntimeError(f"section {key} still scanning after an hour")
        time.sleep(5)


def set_locations(plex: Plex, s: dict, locations: list) -> None:
    plex.call("PUT", f"/library/sections/{s['key']}", {"agent": s["agent"], "location": locations})
    got = [l["path"] for l in plex.section(s["key"]).get("Location", [])]
    if sorted(got) != sorted(locations):
        raise RuntimeError(f"section {s['key']}: asked for {locations}, Plex has {got}")


def plex_paths(plex: Plex, apply: bool, relink: bool, only: str | None) -> int:
    prefs = {p["id"]: p.get("value") for p in plex.get("/:/prefs").get("Setting", [])}
    auto_empty = prefs.get("autoEmptyTrash") in (True, "1", 1, "true")
    log(f"Plex 'empty trash automatically after every scan': {'on' if auto_empty else 'off'}")
    todo = []
    for s in plex.sections():
        if only and s["title"] != only:
            continue
        locs = [l["path"] for l in s.get("Location", [])]
        target = list(dict.fromkeys(new_path(p) for p in locs))
        if locs == target:
            log(f"section '{s['title']}': {locs} ok")
            continue
        if s["type"] not in ITEM_TYPE:
            log(f"section '{s['title']}' ({s['type']}): don't know how to check it; skipped")
            continue
        missing = [p for p in target if not os.path.isdir(p)]
        if missing:
            log(f"section '{s['title']}': new folder(s) {missing} not there; skipped")
            continue
        log(f"section '{s['title']}': {locs} -> {target}")
        todo.append((s, locs, target))
    if not apply or not todo:
        return 0

    if auto_empty:  # so nothing is deleted for good if a scan goes wrong; turned back on at the end
        plex.call("PUT", "/:/prefs", {"autoEmptyTrash": 0})
        log("auto empty trash turned off for now")
    ok = True
    for s, locs, target in todo:
        t = ITEM_TYPE[s["type"]]
        before = snapshot(plex, s["key"], t)
        log(f"\n'{s['title']}': {len(before)} items, {sum(1 for v, _ in before.values() if v)} watched")

        both = locs + [p for p in target if p not in locs]
        if both != locs:
            set_locations(plex, s, both)
            log("  added the new folder; scanning")
            scan(plex, s["key"])
        mid = snapshot(plex, s["key"], t)
        no_new = [k for k in before if not any(f.startswith(NEW_PREFIX) for f in mid.get(k, (0, []))[1])]
        if no_new and not relink:
            # Seen on lapNAS: with the old path a symlink to the new one, Plex keeps the old paths.
            log(f"  STOP: {len(no_new)} items have no copy under {NEW_PREFIX}; old folder kept. "
                f"--relink drops the old folder anyway and lets Plex re-link the files (undone "
                f"automatically if any item goes missing).")
            ok = False
            continue

        set_locations(plex, s, target)
        log("  removed the old folder; scanning")
        scan(plex, s["key"])
        after = snapshot(plex, s["key"], t)
        lost = [k for k in before if k not in after]
        fewer = [k for k in before if k in after and after[k][0] < before[k][0]]
        stale = [k for k, (_, files) in after.items() if any(f.startswith(OLD_PREFIX) for f in files)]
        log(f"  now {len(after)} items, {sum(1 for v, _ in after.values() if v)} watched")
        if lost or fewer or stale:
            log(f"  PROBLEM: {len(lost)} items gone, {len(fewer)} lost plays, {len(stale)} still on the "
                f"old path, e.g. {[before[k][1][:1] for k in (lost + fewer)[:3]]}. Putting the old folder back.")
            set_locations(plex, s, both)
            scan(plex, s["key"])
            back = snapshot(plex, s["key"], t)
            log(f"  undone: {sum(1 for k in before if k in back)}/{len(before)} items back")
            ok = False
        else:
            log("  ok: every item kept, with its watch history")

    if auto_empty and ok:
        plex.call("PUT", "/:/prefs", {"autoEmptyTrash": 1})
        log("auto empty trash back on")
    elif auto_empty:
        log("auto empty trash left OFF because something needs a look")
    return 0 if ok else 1


# ---- main


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("config")
    ap.add_argument("mode", choices=["survey", "arr", "plex-paths"])
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--keys")
    ap.add_argument("--plex-token")
    ap.add_argument("--hints")
    ap.add_argument("--relink", action="store_true")
    ap.add_argument("--section", help="plex-paths: only this library, by name")
    ap.add_argument("--old-prefix", help="plex-paths: the old mount path of the media drive")
    a = ap.parse_args()
    global OLD_PREFIX
    if a.old_prefix:
        OLD_PREFIX = a.old_prefix.rstrip("/")

    with open(a.config) as f:
        cfg = json.load(f)
    keys_dir = a.keys or cfg["keysDir"]
    if a.plex_token:
        with open(a.plex_token) as f:
            token = f.read().strip()
    else:
        token = w.plex_token(cfg["plexPreferences"])
    if not token:
        log("No Plex token: sign Plex in first.")
        return 1
    hints = {}
    if a.hints:
        with open(a.hints) as f:
            hints = json.load(f)

    plex = Plex(f"http://{cfg['plex']['host']}:{cfg['plex']['port']}", token)
    sonarr = w.Api("Sonarr", cfg["sonarr"]["url"], w.read_key(keys_dir, "sonarr"))
    radarr = w.Api("Radarr", cfg["radarr"]["url"], w.read_key(keys_dir, "radarr"))
    prowlarr = w.Api("Prowlarr", cfg["prowlarr"]["url"], w.read_key(keys_dir, "prowlarr"))

    if a.mode == "survey":
        return survey(plex, sonarr, radarr, prowlarr)
    if a.mode == "arr":
        return run_arr(plex, sonarr, radarr, hints, a.apply)
    return plex_paths(plex, a.apply, a.relink, a.section)


if __name__ == "__main__":
    sys.exit(main())
