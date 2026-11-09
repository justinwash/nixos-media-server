"""Set a few keys in qBittorrent.conf and leave everything else alone.

Usage: qbt-config.py <qBittorrent.conf> <managed.json>

managed.json maps INI section -> {key: value}. Runs before qBittorrent starts, so
the Web UI password and any setting changed in the UI survive restarts.
"""

import configparser
import json
import os
import sys


def main() -> None:
    conf_path, managed_path = sys.argv[1], sys.argv[2]
    with open(managed_path) as f:
        managed = json.load(f)

    # Only "=" separates key from value: qBittorrent values often contain ":".
    ini = configparser.RawConfigParser(strict=False, delimiters=("=",), interpolation=None)
    ini.optionxform = str  # keep key case: qBittorrent keys are case-sensitive
    if os.path.exists(conf_path):
        ini.read(conf_path, encoding="utf-8")

    changed = False
    for section, values in managed.items():
        if not ini.has_section(section):
            ini.add_section(section)
        for key, value in values.items():
            if ini.get(section, key, fallback=None) != value:
                ini.set(section, key, value)
                changed = True

    if not changed:
        return

    os.makedirs(os.path.dirname(conf_path), exist_ok=True)
    tmp = conf_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        ini.write(f, space_around_delimiters=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, conf_path)
    print(f"qbt-config: updated {conf_path}")


if __name__ == "__main__":
    main()
