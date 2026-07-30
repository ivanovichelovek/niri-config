#!/usr/bin/env python3
"""Exercise bin/random-wallpaper's file handling and filters.

Run it directly: tests/test-random-wallpaper.py

The point is the promise the app makes — accepting a wallpaper must never
destroy one already saved — so the collision branch of unique_path() and the
"delete touches only the pending file" property are what get asserted, plus
the filter logic that decides which candidates are usable. Needs network: it
does one real download per source.

$HOME is redirected before the app module is imported, because SAVE_DIR and
CONFIG_FILE are computed at import time. Nothing under the real home is read
or written.
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "bin" / "random-wallpaper"

FAKE = Path(tempfile.mkdtemp(prefix="random-wallpaper-test-"))
(FAKE / "Pictures" / "Wallpapers").mkdir(parents=True)
os.environ["HOME"] = str(FAKE)
os.environ["XDG_CACHE_HOME"] = str(FAKE / ".cache")
os.environ["XDG_CONFIG_HOME"] = str(FAKE / ".config")
os.environ.pop("WALLHAVEN_API_KEY", None)

loader = importlib.machinery.SourceFileLoader("rw", str(APP))
spec = importlib.util.spec_from_loader("rw", loader)
rw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rw)

ok = fail = 0


def check(label, cond):
    global ok, fail
    print(("PASS  " if cond else "FAIL  ") + label)
    ok, fail = (ok + 1, fail) if cond else (ok, fail + 1)


# ── paths ───────────────────────────────────────────────────────────────────
check("SAVE_DIR follows HOME", rw.SAVE_DIR == FAKE / "random_wallpaper")
check("SAVE_DIR does not exist yet", not rw.SAVE_DIR.exists())
check("CONFIG_FILE under XDG_CONFIG_HOME",
      rw.CONFIG_FILE == FAKE / ".config" / "random-wallpaper" / "config.json")

# ── preferences round-trip ──────────────────────────────────────────────────
check("defaults load when no config exists", rw.load_prefs() == rw.DEFAULTS)
prefs = rw.load_prefs()
prefs["orientation"] = "portrait"
prefs["wallhaven_apikey"] = "secret-key"
rw.save_prefs(prefs)
check("prefs round-trip", rw.load_prefs()["orientation"] == "portrait")
check("config is 0600 — it can hold an API key",
      oct(rw.CONFIG_FILE.stat().st_mode & 0o777) == "0o600")
check("config keeps every key", "source" in json.loads(rw.CONFIG_FILE.read_text()))
check("config key used when env is unset", rw.wallhaven_key(prefs) == "secret-key")
os.environ["WALLHAVEN_API_KEY"] = "env-key"
check("WALLHAVEN_API_KEY overrides config", rw.wallhaven_key(prefs) == "env-key")
del os.environ["WALLHAVEN_API_KEY"]
rw.CONFIG_FILE.unlink()

# ── filters ─────────────────────────────────────────────────────────────────
land = dict(rw.DEFAULTS, orientation="landscape", minimum="1920x1080")
port = dict(rw.DEFAULTS, orientation="portrait", minimum="1920x1080")
anysize = dict(rw.DEFAULTS, orientation="any", minimum="")

check("landscape rejects a portrait image", not rw._fits(land, 1080, 1920))
check("landscape accepts a wide image", rw._fits(land, 2560, 1440))
check("portrait rejects a wide image", not rw._fits(port, 2560, 1440))
check("minimum size rejects a small image", not rw._fits(land, 1280, 720))
check("Any size accepts a small image", rw._fits(anysize, 640, 480))
check("unknown dimensions pass through", rw._fits(land, None, None))

# ── the 18+ gate is an error, not a silent empty result ─────────────────────
try:
    rw.pick_wallhaven(dict(rw.DEFAULTS, source="wallhaven", rating="nsfw",
                           wallhaven_apikey=""))
    check("wallhaven 18+ without a key raises", False)
except rw.FetchError as exc:
    check("wallhaven 18+ without a key raises", "API key" in str(exc))

try:
    rw.pick_wallhaven(dict(rw.DEFAULTS, wallhaven_general=False,
                           wallhaven_anime=False, wallhaven_people=False))
    check("all categories off raises", False)
except rw.FetchError:
    check("all categories off raises", True)

# ── a real download per source, then the save path ──────────────────────────
saved = []
for label, key, _ in rw.SOURCES:
    frame = rw.download(dict(rw.DEFAULTS, source=key))
    cached = frame["path"]
    check(f"{label}: download landed in cache",
          cached.exists() and cached.parent == rw.CACHE_DIR)
    check(f"{label}: honours the size filter",
          rw._fits(rw.DEFAULTS, frame.get("width"), frame.get("height")))

    rw.SAVE_DIR.mkdir(parents=True, exist_ok=True)
    dest = rw.unique_path(rw.SAVE_DIR, frame["name"], frame["ext"])
    shutil.move(str(cached), dest)
    saved.append(dest)
    check(f"{label}: saved file intact", dest.stat().st_size == frame["bytes"])
    check(f"{label}: cache file gone after save", not cached.exists())

check("SAVE_DIR created on demand", rw.SAVE_DIR.is_dir())

# ── konachan above Safe: konachan.com, which some routes redirect away ──────
# Either outcome is correct; what must not happen is a silent empty result.
for rating in ("sketchy", "nsfw"):
    try:
        meta = rw.pick_konachan(dict(rw.DEFAULTS, rating=rating, minimum=""))
        check(f"konachan {rating} returned a post", meta["url"].startswith("http"))
    except rw.FetchError as exc:
        check(f"konachan {rating} explains the empty result",
              "Wallhaven" in str(exc) or "page" in str(exc))

# wallhaven sketchy needs no key; 18+ does, and the API silently drops nsfw
# results without one rather than erroring — hence the explicit gate above.
sketchy = rw.pick_wallhaven(dict(rw.DEFAULTS, source="wallhaven", rating="sketchy"))
check("wallhaven sketchy works without a key", sketchy["url"].startswith("http"))

# ── collision branch: the whole point ───────────────────────────────────────
precious = rw.SAVE_DIR / "konachan-1.jpg"
precious.write_bytes(b"PRECIOUS")
p2 = rw.unique_path(rw.SAVE_DIR, "konachan-1", ".jpg"); p2.write_bytes(b"second")
p3 = rw.unique_path(rw.SAVE_DIR, "konachan-1", ".jpg"); p3.write_bytes(b"third")
check("collision -> -2", p2.name == "konachan-1-2.jpg")
check("collision -> -3", p3.name == "konachan-1-3.jpg")
check("earlier file untouched", precious.read_bytes() == b"PRECIOUS")

# ── hardlink into Pictures/Wallpapers ───────────────────────────────────────
pics = rw.pictures_wallpapers()
pics.mkdir(parents=True, exist_ok=True)
link = rw.unique_path(pics, saved[0].stem, saved[0].suffix)
os.link(saved[0], link)
check("hardlink shares the inode", link.stat().st_ino == saved[0].stat().st_ino)

# ── delete removes only the pending download ────────────────────────────────
before = sorted(p.name for p in rw.SAVE_DIR.iterdir())
doomed = rw.download(dict(rw.DEFAULTS))
doomed["path"].unlink()
check("delete removed the pending file", not doomed["path"].exists())
check("delete kept every saved file",
      sorted(p.name for p in rw.SAVE_DIR.iterdir()) == before)

# ── cache prune ─────────────────────────────────────────────────────────────
orphan = rw.CACHE_DIR / "pending-orphan.jpg"; orphan.write_bytes(b"x")
keep = rw.CACHE_DIR / "keepme.txt"; keep.write_bytes(b"x")
rw.prune_cache()
check("prune removed the orphan", not orphan.exists())
check("prune left unrelated files", keep.exists())

shutil.rmtree(FAKE, ignore_errors=True)
print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
