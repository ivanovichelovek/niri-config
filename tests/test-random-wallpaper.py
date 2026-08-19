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
os.environ.pop("PIXABAY_API_KEY", None)

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
os.environ["PIXABAY_API_KEY"] = "env-pixabay"
check("PIXABAY_API_KEY overrides config",
      rw.pixabay_key(dict(prefs, pixabay_apikey="cfg")) == "env-pixabay")
del os.environ["PIXABAY_API_KEY"]
rw.CONFIG_FILE.unlink()

# ── ratings are gone: a config written by an older version must not revive
# them, and nothing may read prefs["rating"] any more ────────────────────────
check("no rating in defaults", "rating" not in rw.DEFAULTS)
rw.CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
rw.CONFIG_FILE.write_text(json.dumps({"rating": "nsfw", "orientation": "portrait"}))
stale = rw.load_prefs()
check("old rating dropped on load", "rating" not in stale)
check("other keys of an old config survive", stale["orientation"] == "portrait")
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

# ── a missing key is an error that says where to get one ────────────────────
try:
    rw.pick_pixabay(dict(rw.DEFAULTS, source="pixabay", pixabay_apikey=""))
    check("pixabay without a key raises", False)
except rw.FetchError as exc:
    check("pixabay without a key raises", "API key" in str(exc))

# Without full API access only the 1280px copy is downloadable, so that — not
# the original's dimensions — is what the size filter must judge.
hit = {"imageWidth": 6000, "imageHeight": 4000,
       "largeImageURL": "https://pixabay.com/x_1280.jpg"}
url, w, h, full = rw._pixabay_download(hit)
check("pixabay falls back to the 1280px copy", url.endswith("_1280.jpg") and not full)
check("pixabay reports the size it can really download", (w, h) == (1280, 853))
check("that size fails a 1920x1080 minimum",
      not rw._fits(dict(rw.DEFAULTS, minimum="1920x1080"), w, h))
full_hit = dict(hit, imageURL="https://pixabay.com/orig.jpg")
url, w, h, full = rw._pixabay_download(full_hit)
check("full API access uses the original", full and (w, h) == (6000, 4000))

try:
    rw.pick_wallhaven(dict(rw.DEFAULTS, wallhaven_general=False,
                           wallhaven_anime=False, wallhaven_people=False))
    check("all categories off raises", False)
except rw.FetchError:
    check("all categories off raises", True)

# ── API answers are cached for a day: Pixabay's terms require it ────────────
import time as _time

feed = "https://konachan.net/post.json?tags=rating%3Asafe&limit=1&page=1"
first = rw._get_json(feed)
check("a live answer came back", isinstance(first, list))
slot = next(rw.API_CACHE_DIR.glob("*.json"))
check("API answer cached on disk", slot.is_file())
slot.write_text(json.dumps({"marker": "from-cache"}))
check("a cached answer is served without a request",
      rw._get_json(feed) == {"marker": "from-cache"})
check("an expired entry is refetched",
      rw._get_json(feed, ttl=0) != {"marker": "from-cache"})
_time.sleep(0)
os.utime(slot, (0, 0))
rw.prune_cache()
check("prune drops expired API answers", not slot.exists())
check("the URL is never written to disk — it carries the key",
      all("key=" not in p.read_text() for p in rw.API_CACHE_DIR.glob("*.json")))

# ── a real download per source, then the save path ──────────────────────────
saved = []
for label, key, _ in rw.SOURCES:
    if key == "pixabay" and not rw.pixabay_key(rw.DEFAULTS):
        print(f"SKIP  {label}: no API key in config or PIXABAY_API_KEY")
        continue
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

# ── wallhaven works without a key; the key only lifts the rate limit ────────
anon = rw.pick_wallhaven(dict(rw.DEFAULTS, source="wallhaven", wallhaven_apikey=""))
check("wallhaven works without a key", anon["url"].startswith("http"))

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
