#!/usr/bin/env python3
"""Exercise bin/bookshelf: the store, the catalogue lookups, and every control.

Run it directly: tests/test-bookshelf.py

Three things are worth asserting here. That a rating or an impression, once
given, survives a restart — the app is the only place those live. That a book
Claude invented is never dressed up as a real one: anything the catalogues do
not confirm has to come back verified=False. And that each button in the window
does what its label says, since the whole app is buttons and a real click is
the one thing a unit test usually cannot reach.

The last part builds a real window and drives the widgets the way a click
would, so it needs a display; `claude` and the network are stubbed out, except
in the marked catalogue section, which does hit FantLab and Open Library.

$HOME is redirected before the module is imported, because the data and config
paths are computed at import time. Nothing under the real home is touched.
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import sys
import time
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "bin" / "bookshelf"

FAKE = Path(tempfile.mkdtemp(prefix="bookshelf-test-"))
os.environ["HOME"] = str(FAKE)
os.environ["XDG_DATA_HOME"] = str(FAKE / ".local/share")
os.environ["XDG_CONFIG_HOME"] = str(FAKE / ".config")

loader = importlib.machinery.SourceFileLoader("bs", str(APP))
spec = importlib.util.spec_from_loader("bs", loader)
bs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bs)

ok = fail = 0


def check(label, cond):
    global ok, fail
    print(("PASS  " if cond else "FAIL  ") + label)
    ok, fail = (ok + 1, fail) if cond else (ok, fail + 1)


# ── paths ───────────────────────────────────────────────────────────────────
check("profiles follow XDG_DATA_HOME",
      bs.PROFILE_DIR == FAKE / ".local/share/bookshelf/profiles")
check("config follows XDG_CONFIG_HOME",
      bs.CONFIG_FILE == FAKE / ".config/bookshelf/config.json")

# ── name matching ───────────────────────────────────────────────────────────
check("ё and case fold together", bs.norm("Тёмный Травник") == bs.norm("темный травник"))
check("surname ignores initials", bs.surname("Дем Михайлов") == "михайлов")
check("a shared surname is not the same author",
      not bs.author_matches("John Bierce", "Ambrose Bierce"))
check("the same author matches", bs.author_matches("John Bierce", "John Bierce"))
check("a bare surname still matches the full name",
      bs.author_matches("Bierce", "John Bierce"))
check("slug survives Cyrillic", bs.slugify("Иван Петров") == "иван-петров")

# ── the store ───────────────────────────────────────────────────────────────
profile = bs.Profile.create("Тестер", "208739")
book = profile.add({"title": "Тёмный травник", "author": "Михаил Атаманов", "lang": "ru"})
check("add() fills in an id", bool(book["id"]))
check("add() defaults to the shelf", book["status"] == "recommended")
check("knows() matches a known book", profile.knows("тёмный травник", "Атаманов"))
check("knows() rejects another book", not profile.knows("Путь Шамана", "Маханенко"))

book["my_rating"] = 9
book["impression"] = "Отлично зашло"
profile.save()
reloaded = bs.Profile.load(profile.path)
check("rating survives a reload", reloaded.books[0]["my_rating"] == 9)
check("impression survives a reload", reloaded.books[0]["impression"] == "Отлично зашло")
check("rated() lists it", len(reloaded.rated()) == 1)

# ── two writers, one file ───────────────────────────────────────────────────
first = bs.Profile.load(profile.path)
second = bs.Profile.load(profile.path)
second.add({"title": "Добавлено снаружи", "author": "Кто-то", "lang": "ru"})
second.save()
first.books[0]["impression"] = "правка из окна"
first.save()
after = json.loads(profile.path.read_text("utf-8"))["books"]
check("a save does not revert the other writer's addition",
      any(b["title"] == "Добавлено снаружи" for b in after))
check("and still writes its own change",
      [b for b in after if b["title"] == "Тёмный травник"][0]["impression"] == "правка из окна")

third = bs.Profile.load(profile.path)
fourth = bs.Profile.load(profile.path)
fourth.data["books"] = [b for b in fourth.books if b["title"] != "Добавлено снаружи"]
third.books[0]["my_rating"] = 10
third.save()
fourth.save()
after = json.loads(profile.path.read_text("utf-8"))["books"]
check("a deletion is not undone by the merge",
      not any(b["title"] == "Добавлено снаружи" for b in after))
check("and the other writer's rating survives it",
      [b for b in after if b["title"] == "Тёмный травник"][0]["my_rating"] == 10)

# ── conditional fetching ────────────────────────────────────────────────────
data, etag, modified = bs.http_bytes("https://covers.openlibrary.org/b/id/9963334-L.jpg")
check("a first fetch returns the bytes", data is not None and len(data) > 2000)
if etag or modified:
    again, _, _ = bs.http_bytes("https://covers.openlibrary.org/b/id/9963334-L.jpg",
                                etag=etag, modified=modified)
    check("an unchanged file downloads nothing the second time", again is None)
else:
    check("server offered no validator — skipped", True)

# ── seeding from a markdown log ─────────────────────────────────────────────
bs.LEGACY_LOG.parent.mkdir(parents=True, exist_ok=True)
bs.LEGACY_LOG.write_text(
    "| Дата | Книга | Автор | Почему | Статус | Оценка |\n"
    "|---|---|---|---|---|---|\n"
    "| 2026-08-18 | Cradle | Will Wight | Прогрессия | — | — |\n"
    "| 2026-08-18 | Выдумка | Никто | — | не советую | — |\n", "utf-8")
seeded = bs.Profile.create("Импорт")
added = bs.import_legacy_log(seeded)
check("log rows become books", added == 2)
check("an English title is tagged en",
      [b for b in seeded.books if b["title"] == "Cradle"][0]["lang"] == "en")
check("a rejected row lands as skipped",
      [b for b in seeded.books if b["title"] == "Выдумка"][0]["status"] == "skipped")

# ── the prompt sent to Claude ───────────────────────────────────────────────
prompt = bs.build_prompt(reloaded, "магическая академия", 5)
check("prompt carries the high marks", "Тёмный травник" in prompt)
check("prompt carries the impression", "Отлично зашло" in prompt)
check("prompt carries the extra wish", "магическая академия" in prompt)
check("prompt asks for the right count", "5 рекомендаций" in prompt)

# ── parsing what the CLI returns ────────────────────────────────────────────
class FakeProc:
    def __init__(self, payload):
        self.payload = payload

    def communicate(self, timeout=None):
        return self.payload, ""

    def poll(self):
        return 0


def run_with(payload):
    job = bs.ClaudeRun("prompt", "sonnet", False)
    bs.subprocess.Popen = lambda *a, **k: FakeProc(payload)
    return job.run()


real_popen = bs.subprocess.Popen
books, err = run_with(json.dumps({
    "is_error": False, "subtype": "success",
    "result": '```json\n[{"title":"Гибрид","author":"Лисина","lang":"ru","why":"Академия"}]\n```'}))
check("fenced JSON is unwrapped", len(books) == 1 and books[0]["title"] == "Гибрид")
check("no error on a good answer", err == "")

books, err = run_with(json.dumps({"is_error": True, "subtype": "error", "result": "нет доступа"}))
check("an error envelope is reported", not books and "нет доступа" in err)

books, err = run_with(json.dumps({"is_error": False, "subtype": "success", "result": "простите, не знаю"}))
check("a non-JSON answer is reported, not crashed", not books and err)
bs.subprocess.Popen = real_popen

# ── cover quality ───────────────────────────────────────────────────────────
def fake_cover(width, height):
    """A PNG of noise — flat colour compresses below the "this is not an image"
    size gate, which would make the shape checks below pass for the wrong
    reason."""
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf, GLib
    noise = bytearray(os.urandom(width * height * 3))
    pixbuf = GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(bytes(noise)),
                                             GdkPixbuf.Colorspace.RGB, False, 8,
                                             width, height, width * 3)
    return pixbuf.save_to_bufferv("png", [], [])[1]


check("a book-shaped image is accepted", bs.usable_cover(fake_cover(300, 460)) is not None)
check("a landscape photo is rejected", bs.usable_cover(fake_cover(500, 281)) is None)
check("a square tile is rejected", bs.usable_cover(fake_cover(500, 500)) is None)
check("a thumbnail is rejected", bs.usable_cover(fake_cover(60, 90)) is None)
check("junk bytes are rejected", bs.usable_cover(b"302 Found") is None)

rejected = {"id": "shape-test", "cover_url": "https://covers.openlibrary.org/b/id/8777018-L.jpg"}
check("a book whose only cover is a photograph gets none",
      bs.cover_path(rejected) is None)
check("and the bad url is cleared, so the book stays in the retry queue",
      rejected["cover_url"] == "" and rejected.get("cover_rejected"))

offers = bs.openlibrary_neighbours("The Black Magician Trilogy", "Trudi Canavan")
check("the separate volumes are offered instead",
      any(o["cover_url"] for o in offers))

# ── catalogues (network) ────────────────────────────────────────────────────
found = bs.resolve("За последним порогом", "Андрей Стоев", "ru")
check("FantLab confirms a real cycle", found["verified"] and found["source"] == "fantlab")
check("it comes back with a cover", found["cover_url"].startswith("https://fantlab.ru"))
check("it comes back with an annotation", len(found["annotation"]) > 50)
check("its public rating is on the 10 scale",
      1 <= float(found["public_rating"] or 0) <= 10)

invented = bs.resolve("Юркина Академия", "Артём Каменистый", "ru")
check("an invented title stays unverified", not invented["verified"])
check("the invented title is not silently replaced", invented["title"] == "Юркина Академия")

merged = bs.catalogued({"title": "Cradle", "author": "Will Wight"},
                       {"verified": True, "title": "Unsouled : Cradle",
                        "author": "Will Wight", "annotation": "текст"})
check("a confirmed book keeps the name it was recommended under",
      "title" not in merged and merged["catalog_title"] == "Unsouled : Cradle")
check("the catalogue's other fields still come through", merged["annotation"] == "текст")
check("an identical title is not recorded twice",
      "catalog_author" not in merged)
check("a miss still offers somewhere to look", invented["source_url"].startswith("https://"))

missed = bs.resolve("Mage Errant", "John Bierce", "en")
check("a series filed under its first volume is not adopted silently",
      not missed["verified"] and missed["title"] == "Mage Errant")
check("but the neighbours are offered with their covers",
      any(n.get("cover_url") for n in missed.get("neighbours") or []))
check("an apostrophe in the author no longer hides the book",
      bs.resolve("The Iron Prince (Warformed: Stormweaver)", "Bryce O'Connor", "en")["verified"])

rr = bs.royalroad_lookup("Mother of Learning", "Domagoj Kurmaic")
check("Royal Road answers for a serial it hosts", rr is not None and bool(rr["annotation"]))
check("and it is not confused by a similar title",
      bs.royalroad_lookup("Mage Errant", "John Bierce") is None)

at = bs.authortoday_lookup("Ниочема", "mrSecond")
check("Author.Today answers for Russian боярка", at is not None and bool(at["cover_url"]))
check("and checks the author", bs.authortoday_lookup("Ниочема", "Дем Михайлов") is None)

check("Google Books stays quiet without a key",
      bs.googlebooks_lookup("Cradle", "Will Wight") is None)

chained = bs.resolve("Mother of Learning", "Domagoj Kurmaic", "en")
check("a later catalogue fills an annotation the first one lacked",
      bool(chained["annotation"]) and chained.get("annotation_from") == "royalroad")
check("and its cover is kept as another candidate",
      len(chained.get("cover_candidates") or []) > 1)

story = bs.fantlab_fill(39829, "Артур Конан Дойл")   # «Пропавший регбист»
check("a story with no edition borrows the cycle cover", bool(story["cover_url"]))
check("and says whose cover it is", story.get("cover_from") == "Шерлок Холмс")
check("a story ends up with a blurb one way or another", bool(story["annotation"]))
text, name = bs.cycle_annotation(39350)
check("the cycle has a blurb to lend", bool(text))
check("and it is named so a borrowed one can be labelled", name == "Шерлок Холмс")
check("the cycle cover is cached", 39350 in bs._CYCLE_COVERS)

# ── every control in the window ─────────────────────────────────────────────
import gi                                                     # noqa: E402
gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk                           # noqa: E402

if not Gtk.init_check():
    print("\nno display — skipping the widget checks")
    shutil.rmtree(FAKE, ignore_errors=True)
    print(f"\n{ok} passed, {fail} failed")
    sys.exit(1 if fail else 0)

# The window has to be built inside a started GApplication: GTK4 segfaults in
# gtk_window_set_application() if the application has not run its startup yet.
runner = Gtk.Application(application_id="dev.ivanc.BookshelfTest")

# One profile with a known shape, so counts below are predictable.
for stale in bs.Profile.all():
    stale.unlink()
bs.CONFIG_FILE.unlink(missing_ok=True)
bs.LEGACY_LOG.unlink()

demo = bs.Profile.create("Читатель", "208739")
for i, (title, status, mark) in enumerate([
        ("Полка раз", "recommended", None), ("Полка два", "recommended", None),
        ("Читаю сейчас", "reading", None), ("Отложено", "skipped", None),
        ("Прочитано А", "read", 9), ("Прочитано Б", "read", 5)]):
    demo.add({"title": title, "author": "Автор %d" % i, "lang": "ru", "why": "—",
              "status": status, "my_rating": mark, "verified": True, "annotation": "текст",
              "cover_url": "", "kind": "роман", "public_rating": 7.5, "public_votes": 10})
demo.save()

# no network from here on: the widget checks must not depend on catalogues
bs.openlibrary_neighbours = lambda title, author: []
bs.fantlab_fill = lambda work_id, author="": {}
bs.cycle_books = lambda cycle_id: []
bs.resolve = lambda title, author, lang, key="": {
    "verified": True, "source": "fantlab", "source_url": "https://fantlab.ru/work1",
    "title": title, "author": author, "kind": "роман", "year": 2020, "annotation": "текст",
    "public_rating": 8.0, "public_votes": 100, "cover_url": ""}

def cards(grid):
    """Titles currently drawn in a BookGrid."""
    out, child = [], grid.get_first_child()
    while child is not None:
        card = child.get_child() if isinstance(child, Gtk.FlowBoxChild) else child
        if isinstance(card, bs.BookCard):
            body = card.get_child().get_last_child()
            out.append(body.get_first_child().get_text())
        child = child.get_next_sibling()
    return out


def widget_checks(app):
    win = bs.Bookshelf(app)

    check("tabs are all present",
          [win.stack.get_child_by_name(n) is not None
           for n in ("shelf", "ratings", "discover", "profiles")] == [True] * 4)

    # Полка — the filter dropdown
    check("shelf opens on the recommendations", sorted(cards(win.shelf)) == ["Полка два", "Полка раз"])
    win.shelf_filter.set_selected(1)
    check("filter → Читаю", cards(win.shelf) == ["Читаю сейчас"])
    win.shelf_filter.set_selected(2)
    check("filter → Отложено", cards(win.shelf) == ["Отложено"])
    win.shelf_filter.set_selected(3)
    check("filter → Все книги", len(cards(win.shelf)) == 6)
    win.shelf_filter.set_selected(0)

    # Оценки — sorting and search
    check("ratings tab lists only what was rated", sorted(cards(win.ratings)) == ["Прочитано А", "Прочитано Б"])
    win.ratings_sort.set_selected(0)
    check("sort → сначала высокие", cards(win.ratings)[0] == "Прочитано А")
    win.ratings_sort.set_selected(1)
    check("sort → сначала низкие", cards(win.ratings)[0] == "Прочитано Б")
    win.ratings_search.set_text("прочитано а")
    check("search narrows the list", cards(win.ratings) == ["Прочитано А"])
    win.ratings_search.set_text("")

    # The book window: rating strip, status, impression, save, delete
    shelf = win.profile                                    # the window has its own copy
    target = [b for b in shelf.books if b["title"] == "Полка раз"][0]
    sheet = bs.BookWindow(win, win, target)
    strip = None
    row = sheet.get_child()
    sheet.rating_strip = None
    for widget in (target,):                                      # locate the strip by type
        pass


    def find(widget, kind):
        if isinstance(widget, kind):
            return widget
        child = widget.get_first_child()
        while child is not None:
            found = find(child, kind)
            if found is not None:
                return found
            child = child.get_next_sibling()
        return None


    strip = find(sheet, bs.RatingStrip)
    check("the book window has a rating strip", strip is not None)
    strip.buttons[7].emit("clicked")                              # «8»
    check("clicking 8 sets the mark", target["my_rating"] == 8)
    check("a rated book stops being a recommendation", target["status"] == "read")
    check("the mark is on disk at once",
          json.loads(shelf.path.read_text("utf-8"))["books"][0]["my_rating"] == 8)
    strip.buttons[7].emit("clicked")
    check("clicking the same number clears it", target["my_rating"] is None)
    strip.buttons[9].emit("clicked")

    sheet.impression.get_buffer().set_text("Прочитал за вечер")
    sheet.status.set_selected(1)                                  # Читаю
    sheet._save(None)
    saved = json.loads(shelf.path.read_text("utf-8"))["books"][0]
    check("Сохранить writes the impression", saved["impression"] == "Прочитал за вечер")
    check("Сохранить writes the status", saved["status"] == "reading")
    check("Сохранить stamps the date", bool(saved.get("rated")))

    doomed = [b for b in shelf.books if b["title"] == "Отложено"][0]
    sheet2 = bs.BookWindow(win, win, doomed)
    sheet2._delete(None)
    check("Удалить с полки removes the book", not shelf.knows("Отложено", "Автор 3"))
    check("and the removal is on disk",
          len(json.loads(shelf.path.read_text("utf-8"))["books"]) == 5)

    # Подбор — the picker, with the CLI stubbed
    class InstantJob:
        cancelled = False

        def __init__(self, prompt, model, web):
            InstantJob.seen = (prompt, model, web)

        def run(self):
            return [{"title": "Новая книга", "author": "Новый автор", "lang": "ru", "why": "подходит"}], ""

        def cancel(self):
            InstantJob.cancelled = True


    bs.ClaudeRun = InstantJob
    win.ask.get_buffer().set_text("что-нибудь про академию")
    win.count.set_selected(2)                                     # 8
    win.model.set_selected(1)                                     # opus
    win.web.set_active(False)
    win._start_run()
    check("Новые рекомендации disables itself while running", not win.go_btn.get_sensitive())
    check("Отменить becomes available", win.cancel_btn.get_sensitive())
    check("the picker passes the typed wish", "что-нибудь про академию" in InstantJob.seen[0])
    check("the picker passes the chosen model", InstantJob.seen[1] == "opus")
    check("the picker passes the web toggle", InstantJob.seen[2] is False)

    deadline = time.time() + 20
    while win.run_job is not None and time.time() < deadline:
        while GLib.MainContext.default().pending():
            GLib.MainContext.default().iteration(False)
        time.sleep(0.05)

    check("the run finishes and re-enables the button", win.go_btn.get_sensitive())
    check("Отменить goes back to disabled", not win.cancel_btn.get_sensitive())
    check("the new book lands on the shelf", shelf.knows("Новая книга", "Новый автор"))
    check("the run is written to the history", len(shelf.data.get("runs", [])) == 1)
    check("the picker switches to the shelf", win.stack.get_visible_child_name() == "shelf")

    win._cancel_run()                                             # nothing running: must not raise
    check("Отменить on an idle picker is harmless", win.run_job is None)

    # What a launch decides to do
    for book in win.profile.books:
        book["checked_at"] = time.strftime("%Y-%m-%d %H:%M")
        book.setdefault("verified", True)
        book["cover_url"] = book.get("cover_url") or "https://example.invalid/c.jpg"
        book["annotation"] = book.get("annotation") or "текст"
    missing, stale = win.refresh_plan()
    check("a complete shelf checked just now needs nothing", not missing and not stale)

    hole = win.profile.books[0]
    hole["annotation"] = ""
    hole["checked_at"] = "2020-01-01 00:00"
    missing, stale = win.refresh_plan()
    check("a book with a hole is queued", hole in missing)
    check("and it is not counted as merely stale", hole not in stale)
    for book in win.profile.books:
        book["checked_at"] = "2020-01-01 00:00"
    missing, stale = win.refresh_plan()
    check("old entries come up for revalidation", len(stale) > 0)
    check("but never more than the per-launch budget", len(stale) <= bs.STALE_PER_LAUNCH)
    win.profile.books[0]["checked_at"] = time.strftime("%Y-%m-%d %H:%M")
    missing, _ = win.refresh_plan()
    check("a hole retried an hour ago is not retried again",
          win.profile.books[0] not in missing)

    # Rating one volume from inside a cycle
    cycle = win.profile.add({"title": "Цикл", "author": "Автор", "lang": "ru",
                             "status": "recommended", "verified": True,
                             "fantlab_work_id": 111, "kind": "цикл"})
    win.profile.save()
    sheet3 = bs.BookWindow(win, win, cycle)
    volume = {"work_id": 222, "title": "Второй том", "kind": "роман",
              "year": 2021, "rating": 7.5, "votes": 40}
    sheet3._rate_child(volume, 9)
    added = [b for b in win.profile.books if b.get("fantlab_work_id") == 222]
    check("rating a volume puts it on the shelf", len(added) == 1)
    check("with the mark that was clicked", added[0]["my_rating"] == 9)
    check("and marked as read", added[0]["status"] == "read")
    check("the mark is on disk at once",
          any(b.get("my_rating") == 9 for b in
              json.loads(win.profile.path.read_text("utf-8"))["books"]
              if b.get("fantlab_work_id") == 222))
    sheet3._rate_child(volume, 6)
    check("re-rating updates the same book",
          len([b for b in win.profile.books if b.get("fantlab_work_id") == 222]) == 1
          and added[0]["my_rating"] == 6)
    sheet3._rate_child(volume, None)
    check("and it can be cleared", added[0]["my_rating"] is None)

    # Обновить обложки — an unresolved book must come back with a card
    raw = win.profile.add({"title": "Без карточки", "author": "Кто-то", "lang": "ru",
                           "why": "—", "verified": False})
    win.profile.save()
    win._enrich_shelf()
    deadline = time.time() + 20
    while not raw.get("enrich_tried") and time.time() < deadline:
        while GLib.MainContext.default().pending():
            GLib.MainContext.default().iteration(False)
        time.sleep(0.05)
    check("Обновить обложки resolves a pending book", raw.get("verified") is True)
    check("and marks it so it is not re-queried", raw.get("enrich_tried") is True)

    # Открыть карточку — the link out to the catalogue
    linked = bs.BookWindow(win, win, dict(target, source_url="https://fantlab.ru/work1268218",
                                          verified=True))
    link = find(linked, Gtk.LinkButton)
    check("a verified book links to its catalogue page",
          link is not None and link.get_uri().startswith("https://fantlab.ru"))
    unknown = bs.BookWindow(win, win, dict(target, verified=False,
                                           source_url="https://fantlab.ru/searchmain?searchstr=x"))
    check("an unverified book offers a search instead",
          find(unknown, Gtk.LinkButton).get_label() == "Искать вручную")

    # Загрузить оценки — the FantLab import button, with the network stubbed
    pulled = {}

    def fake_import(profile, user_id, progress=lambda t: None):
        pulled["id"] = user_id
        progress("страница 1")
        profile.add({"title": "Из FantLab", "author": "Кто-то", "lang": "ru",
                     "status": "read", "my_rating": 7})
        profile.save()
        return 1

    bs.import_fantlab_marks = fake_import
    win.fantlab_id.set_text("208739")
    win._import_marks()
    deadline = time.time() + 20
    while "id" not in pulled and time.time() < deadline:
        time.sleep(0.05)
    while GLib.MainContext.default().pending():
        GLib.MainContext.default().iteration(False)
    check("Загрузить оценки passes the id from the field", pulled.get("id") == "208739")
    check("and the pulled book lands in the profile", win.profile.knows("Из FantLab", "Кто-то"))

    # Профили — save, create, switch, delete
    win.stack.set_visible_child_name("profiles")
    win.taste.get_buffer().set_text("Любит ЛитРПГ")
    win.fantlab_id.set_text("208739")
    win._save_profile()
    check("Сохранить профиль stores the taste note",
          json.loads(shelf.path.read_text("utf-8"))["taste_note"] == "Любит ЛитРПГ")
    check("Сохранить профиль stores the FantLab id",
          json.loads(shelf.path.read_text("utf-8"))["fantlab_user_id"] == "208739")

    win.new_name.set_text("Второй читатель")
    win._create_profile()
    check("Создать makes a profile", len(bs.Profile.all()) == 2)
    check("Создать switches to it", win.profile.name == "Второй читатель")
    check("a new reader starts with an empty shelf", win.profile.books == [])
    check("the choice is remembered in the config",
          json.loads(bs.CONFIG_FILE.read_text("utf-8"))["profile"] == str(win.profile.path))
    check("the name field is cleared", win.new_name.get_text() == "")
    check("typing is not clobbered by a refresh",
          (lambda buf: (win.taste.get_buffer().set_text("черновик"), win.refresh(),
                        buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False))[2])
          (win.taste.get_buffer()) == "черновик")

    win._delete_profile()
    check("Удалить профиль removes it", len(bs.Profile.all()) == 1)
    check("and falls back to the one that is left", win.profile.name == "Читатель")
    win._delete_profile()
    check("the last profile cannot be deleted", len(bs.Profile.all()) == 1)


runner.connect("activate", lambda a: (widget_checks(a), a.quit()))
runner.run([])

shutil.rmtree(FAKE, ignore_errors=True)
print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
