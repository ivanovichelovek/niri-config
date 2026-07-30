#!/usr/bin/env python3
"""Exercise bin/random-wallpaper's save/discard logic against a throwaway HOME.

Run it directly: tests/test-random-wallpaper.py

The point is the promise the app makes — accepting a wallpaper must never
destroy one already saved — so the collision branch of unique_path() and the
"discard touches only the pending file" property are what get asserted. Needs
network: two real downloads, one per source.

$HOME is redirected before the app module is imported, because SAVE_DIR is
computed at import time. Nothing under the real home is read or written.
"""
import importlib.machinery, importlib.util, os, shutil, sys, tempfile
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "bin" / "random-wallpaper"

FAKE = Path(tempfile.mkdtemp(prefix="random-wallpaper-test-"))
(FAKE / "Pictures" / "Wallpapers").mkdir(parents=True)
os.environ["HOME"] = str(FAKE)
os.environ["XDG_CACHE_HOME"] = str(FAKE / ".cache")

loader = importlib.machinery.SourceFileLoader("rw", str(APP))
spec = importlib.util.spec_from_loader("rw", loader)
rw = importlib.util.module_from_spec(spec); spec.loader.exec_module(rw)

ok = fail = 0
def check(label, cond):
    global ok, fail
    print(("PASS  " if cond else "FAIL  ") + label)
    ok, fail = (ok + 1, fail) if cond else (ok, fail + 1)

check("SAVE_DIR follows HOME", rw.SAVE_DIR == FAKE / "random_wallpaper")
check("SAVE_DIR does not exist yet", not rw.SAVE_DIR.exists())

# --- unique_path collision branch, the thing that protects saved wallpapers ---
rw.SAVE_DIR.mkdir()
precious = rw.SAVE_DIR / "konachan-1.jpg"
precious.write_bytes(b"PRECIOUS")
p2 = rw.unique_path(rw.SAVE_DIR, "konachan-1", ".jpg"); p2.write_bytes(b"second")
p3 = rw.unique_path(rw.SAVE_DIR, "konachan-1", ".jpg"); p3.write_bytes(b"third")
check("collision -> -2", p2.name == "konachan-1-2.jpg")
check("collision -> -3", p3.name == "konachan-1-3.jpg")
check("original untouched", precious.read_bytes() == b"PRECIOUS")

# --- a real download, saved via Window.save() logic (no GTK) --------------
meta = rw.download(0)
cached = meta["path"]
check("download landed in cache", cached.exists() and cached.parent == rw.CACHE_DIR)

dest = rw.unique_path(rw.SAVE_DIR, meta["name"], meta["ext"])
import shutil as sh; sh.move(str(cached), dest)
check("saved file exists", dest.exists() and dest.stat().st_size == meta["bytes"])
check("cache file gone after save", not cached.exists())

# link_into_pictures, called without a GTK instance
d = rw.pictures_wallpapers(); d.mkdir(parents=True, exist_ok=True)
link = rw.unique_path(d, dest.stem, dest.suffix); os.link(dest, link)
check("hardlinked into Pictures/Wallpapers", link.exists() and link.stat().st_ino == dest.stat().st_ino)

# --- discard: unlinks only the pending file -------------------------------
before = sorted(p.name for p in rw.SAVE_DIR.iterdir())
meta2 = rw.download(1)
meta2["path"].unlink()
check("discard removed pending", not meta2["path"].exists())
check("discard kept every saved file", sorted(p.name for p in rw.SAVE_DIR.iterdir()) == before)

# --- prune_cache ----------------------------------------------------------
orphan = rw.CACHE_DIR / "pending-orphan.jpg"; orphan.write_bytes(b"x")
keep = rw.CACHE_DIR / "keepme.txt"; keep.write_bytes(b"x")
rw.prune_cache()
check("prune removed orphan", not orphan.exists())
check("prune left unrelated files", keep.exists())

# --- SAVE_DIR auto-creation ----------------------------------------------
shutil.rmtree(rw.SAVE_DIR)
rw.SAVE_DIR.mkdir(parents=True, exist_ok=True)
check("SAVE_DIR created when missing", rw.SAVE_DIR.is_dir())

shutil.rmtree(FAKE, ignore_errors=True)
print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
