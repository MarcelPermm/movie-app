"""
imdb_loader.py — загрузка IMDb рейтингов для фильтрации ноунеймов.

Скачивает два датасета с imdbws.com раз в 7 дней:
- title.ratings.tsv.gz (~8MB)   — vote_count
- title.basics.tsv.gz  (~200MB) — названия+год для поиска по имени

Поиск: точное название+год, затем по индексу по заранее посчитанным ключам (без функции на каждой строке таблицы).
"""

import gzip
import sqlite3
import asyncio
import httpx
import threading
import unicodedata
from pathlib import Path
from datetime import datetime, timedelta

DB_PATH     = Path(__file__).parent / "favorites.db"
RATINGS_URL = "https://datasets.imdbws.com/title.ratings.tsv.gz"
BASICS_URL  = "https://datasets.imdbws.com/title.basics.tsv.gz"

_backfill_guard = threading.Lock()

# Турецкий/латиница и диакритика → ASCII
_TO_ASCII = str.maketrans({
    "ğ": "g", "Ğ": "g", "ü": "u", "Ü": "u", "ş": "s", "Ş": "s",
    "ı": "i", "İ": "i", "ç": "c", "Ç": "c", "ö": "o", "Ö": "o",
    "â": "a", "Â": "a", "î": "i", "Î": "i", "û": "u", "Û": "u",
    "ô": "o", "Ô": "o", "ë": "e", "Ë": "e", "ï": "i", "Ï": "i",
    "à": "a", "á": "a", "è": "e", "é": "e", "ù": "u", "ú": "u",
    "ñ": "n", "Ñ": "n", "ß": "ss",
    # Кириллица → латиница (для сопоставления TMDB кириллицы с IMDb транслитерацией)
    "а": "a",  "б": "b",  "в": "v",  "г": "g",  "д": "d",
    "е": "e",  "ё": "e",  "ж": "zh", "з": "z",  "и": "i",
    "й": "i",  "к": "k",  "л": "l",  "м": "m",  "н": "n",
    "о": "o",  "п": "p",  "р": "r",  "с": "s",  "т": "t",
    "у": "u",  "ф": "f",  "х": "kh", "ц": "ts", "ч": "ch",
    "ш": "sh", "щ": "shch","ъ": "",  "ы": "y",  "ь": "",
    "э": "e",  "ю": "yu", "я": "ya",
    "А": "a",  "Б": "b",  "В": "v",  "Г": "g",  "Д": "d",
    "Е": "e",  "Ё": "e",  "Ж": "zh", "З": "z",  "И": "i",
    "Й": "i",  "К": "k",  "Л": "l",  "М": "m",  "Н": "n",
    "О": "o",  "П": "p",  "Р": "r",  "С": "s",  "Т": "t",
    "У": "u",  "Ф": "f",  "Х": "kh", "Ц": "ts", "Ч": "ch",
    "Ш": "sh", "Щ": "shch","Ъ": "",  "Ы": "y",  "Ь": "",
    "Э": "e",  "Ю": "yu", "Я": "ya",
})


def _normalize_title_for_match(s: str) -> str:
    """Ключ для сопоставления с IMDb: кириллица→латиница, диакритика, регистр → ASCII."""
    if not s:
        return ""
    s = s.strip().translate(_TO_ASCII).lower()
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = "".join(c if c.isalnum() or c.isspace() else " " for c in s)
    return " ".join(s.split())


def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_imdb_tables():
    with get_conn() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS imdb_ratings (
                imdb_id    TEXT PRIMARY KEY,
                rating     REAL,
                vote_count INTEGER
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS imdb_basics (
                imdb_id        TEXT PRIMARY KEY,
                primary_title  TEXT,
                original_title TEXT,
                start_year     INTEGER
            )
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_basics_title_year ON imdb_basics(primary_title, start_year)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_basics_orig_year  ON imdb_basics(original_title, start_year)")
        conn.execute("""
            CREATE TABLE IF NOT EXISTS imdb_meta (
                key TEXT PRIMARY KEY, value TEXT
            )
        """)
        _migrate_imdb_key_columns(conn)
        conn.commit()


def _migrate_imdb_key_columns(conn: sqlite3.Connection) -> None:
    """Колонки key_* + индексы + однократный backfill (после апгрейда без полной перезаливки)."""
    cols = {row[1] for row in conn.execute("PRAGMA table_info(imdb_basics)")}
    if "key_primary" not in cols:
        conn.execute("ALTER TABLE imdb_basics ADD COLUMN key_primary TEXT NOT NULL DEFAULT ''")
    if "key_original" not in cols:
        conn.execute("ALTER TABLE imdb_basics ADD COLUMN key_original TEXT NOT NULL DEFAULT ''")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_basics_keyp_year ON imdb_basics(key_primary, start_year)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_basics_keyo_year ON imdb_basics(key_original, start_year)")
    # Пересчитываем ключи если изменилась функция нормализации
    # Детектируем по версии — если не совпадает, сбрасываем все ключи
    NORM_VERSION = "v2-cyrillic"
    cur_ver = conn.execute(
        "SELECT value FROM imdb_meta WHERE key='norm_version'"
    ).fetchone()
    if cur_ver is None or cur_ver["value"] != NORM_VERSION:
        conn.execute("UPDATE imdb_basics SET key_primary = '', key_original = ''")
        conn.execute(
            "INSERT OR REPLACE INTO imdb_meta (key, value) VALUES ('norm_version', ?)",
            (NORM_VERSION,)
        )
        conn.commit()

    n_empty = conn.execute(
        """SELECT COUNT(*) AS c FROM imdb_basics
           WHERE COALESCE(key_primary, '') = '' AND primary_title IS NOT NULL AND primary_title != ''"""
    ).fetchone()["c"]
    if n_empty > 0:
        threading.Thread(target=_backfill_title_keys_worker, name="imdb-keys", daemon=True).start()


def _backfill_title_keys_worker() -> None:
    if not _backfill_guard.acquire(blocking=False):
        return
    try:
        with get_conn() as conn:
            _backfill_title_keys_if_needed(conn)
    except Exception as e:
        print(f"⚠️  IMDb key backfill: {e}")
    finally:
        _backfill_guard.release()


def _backfill_title_keys_if_needed(conn: sqlite3.Connection) -> None:
    n_empty = conn.execute(
        """SELECT COUNT(*) AS c FROM imdb_basics
           WHERE COALESCE(key_primary, '') = '' AND primary_title IS NOT NULL AND primary_title != ''"""
    ).fetchone()["c"]
    if n_empty == 0:
        return
    print(f"⚙️  Индексируем ключи названий IMDb ({n_empty:,} строк, один раз после обновления)…")
    batch = 10_000
    total = 0
    while True:
        rows = conn.execute(
            """SELECT imdb_id, primary_title, original_title FROM imdb_basics
               WHERE COALESCE(key_primary, '') = '' AND primary_title IS NOT NULL AND primary_title != ''
               LIMIT ?""",
            (batch,),
        ).fetchall()
        if not rows:
            break
        updates = []
        for r in rows:
            kp = _normalize_title_for_match(r["primary_title"] or "")
            ot = (r["original_title"] or "").strip()
            ko = _normalize_title_for_match(ot) if ot else ""
            if ko == kp:
                ko = ""
            updates.append((kp, ko, r["imdb_id"]))
        conn.executemany(
            "UPDATE imdb_basics SET key_primary = ?, key_original = ? WHERE imdb_id = ?",
            updates,
        )
        conn.commit()
        total += len(updates)
    print(f"✅ Проиндексировано ключей: {total:,}")


def get_last_update() -> datetime | None:
    try:
        with get_conn() as conn:
            row = conn.execute("SELECT value FROM imdb_meta WHERE key='last_update'").fetchone()
            return datetime.fromisoformat(row["value"]) if row else None
    except:
        return None


def needs_update() -> bool:
    last = get_last_update()
    if last is None:
        return True
    return datetime.now() - last > timedelta(days=7)


def _lookup_imdb_stats(title: str, year: int | None) -> dict | None:
    """Один вариант названия → vote_count + rating или None."""
    if not title:
        return None
    try:
        with get_conn() as conn:
            if year:
                queries = [
                    (
                        """
                        SELECT r.vote_count, r.rating FROM imdb_basics b
                        JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                        WHERE b.primary_title = ? AND b.start_year = ?
                        LIMIT 1
                        """,
                        (title, year),
                    ),
                    (
                        """
                        SELECT r.vote_count, r.rating FROM imdb_basics b
                        JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                        WHERE b.original_title = ? AND b.start_year = ?
                        LIMIT 1
                        """,
                        (title, year),
                    ),
                    (
                        """
                        SELECT r.vote_count, r.rating FROM imdb_basics b
                        JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                        WHERE b.primary_title = ? AND ABS(b.start_year - ?) <= 1
                        LIMIT 1
                        """,
                        (title, year),
                    ),
                ]
                for sql, params in queries:
                    row = conn.execute(sql, params).fetchone()
                    if row:
                        return {"vote_count": int(row["vote_count"]), "rating": float(row["rating"])}
                # Быстрый fuzzy: по заранее посчитанным key_* (индекс), без функции на всей таблице
                key = _normalize_title_for_match(title)
                if key:
                    fuzzy = [
                        (
                            """
                            SELECT r.vote_count, r.rating FROM imdb_basics b
                            JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                            WHERE b.key_primary = ? AND b.start_year = ?
                            LIMIT 1
                            """,
                            (key, year),
                        ),
                        (
                            """
                            SELECT r.vote_count, r.rating FROM imdb_basics b
                            JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                            WHERE b.key_original != '' AND b.key_original = ? AND b.start_year = ?
                            LIMIT 1
                            """,
                            (key, year),
                        ),
                        (
                            """
                            SELECT r.vote_count, r.rating FROM imdb_basics b
                            JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                            WHERE b.key_primary = ? AND ABS(b.start_year - ?) <= 1
                            LIMIT 1
                            """,
                            (key, year),
                        ),
                    ]
                    for sql, params in fuzzy:
                        row = conn.execute(sql, params).fetchone()
                        if row:
                            return {"vote_count": int(row["vote_count"]), "rating": float(row["rating"])}
            else:
                row = conn.execute(
                    """
                    SELECT r.vote_count, r.rating FROM imdb_basics b
                    JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                    WHERE b.primary_title = ?
                    LIMIT 1
                    """,
                    (title,),
                ).fetchone()
                if row:
                    return {"vote_count": int(row["vote_count"]), "rating": float(row["rating"])}
                key = _normalize_title_for_match(title)
                if key:
                    for sql, params in [
                        (
                            """
                            SELECT r.vote_count, r.rating FROM imdb_basics b
                            JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                            WHERE b.key_primary = ?
                            LIMIT 1
                            """,
                            (key,),
                        ),
                        (
                            """
                            SELECT r.vote_count, r.rating FROM imdb_basics b
                            JOIN imdb_ratings r ON b.imdb_id = r.imdb_id
                            WHERE b.key_original != '' AND b.key_original = ?
                            LIMIT 1
                            """,
                            (key,),
                        ),
                    ]:
                        row = conn.execute(sql, params).fetchone()
                        if row:
                            return {"vote_count": int(row["vote_count"]), "rating": float(row["rating"])}
            return None
    except Exception:
        return None


def get_imdb_stats_for_movie(original_title: str, title: str, year: int | None) -> dict | None:
    """Сначала original_title (ближе к IMDb), затем локализованный title."""
    titles: list[str] = []
    ot = (original_title or "").strip()
    tt = (title or "").strip()
    if ot:
        titles.append(ot)
    if tt and tt not in titles:
        titles.append(tt)
    for t in titles:
        stats = _lookup_imdb_stats(t, year)
        if stats:
            return stats
    return None


def get_vote_count(title: str, year: int | None) -> int | None:
    """Ищет vote_count в IMDb по названию и году (совместимость)."""
    stats = _lookup_imdb_stats(title, year)
    return stats["vote_count"] if stats else None


def has_imdb_data() -> bool:
    """Проверяет загружены ли данные IMDb."""
    try:
        with get_conn() as conn:
            count = conn.execute("SELECT COUNT(*) as c FROM imdb_ratings").fetchone()["c"]
            return count > 100000
    except:
        return False


async def download_and_load():
    """Скачивает и загружает IMDb датасеты."""
    print("📥 Скачиваем IMDb ratings (~8MB)...")

    async with httpx.AsyncClient(timeout=180, follow_redirects=True) as client:

        # ── Ratings ───────────────────────────────────────────────────────────
        r = await client.get(RATINGS_URL)
        ratings_data = gzip.decompress(r.content).decode("utf-8")

        print("💾 Загружаем ratings в базу...")
        ratings_rows = []
        for line in ratings_data.strip().split("\n")[1:]:
            parts = line.split("\t")
            if len(parts) == 3:
                try:
                    ratings_rows.append((parts[0], float(parts[1]), int(parts[2])))
                except:
                    pass

        with get_conn() as conn:
            conn.execute("DELETE FROM imdb_ratings")
            conn.executemany(
                "INSERT OR REPLACE INTO imdb_ratings (imdb_id, rating, vote_count) VALUES (?, ?, ?)",
                ratings_rows
            )
            conn.commit()
        print(f"✅ Загружено {len(ratings_rows):,} рейтингов")

        # ── Basics (~200MB) ───────────────────────────────────────────────────
        print("📥 Скачиваем IMDb basics (~200MB, займёт ~60 сек)...")
        r = await client.get(BASICS_URL)
        basics_data = gzip.decompress(r.content).decode("utf-8")

        print("💾 Загружаем basics в базу (фильмы + сериалы)...")
        basics_rows = []
        for line in basics_data.strip().split("\n")[1:]:
            parts = line.split("\t")
            if len(parts) >= 6:
                imdb_id, title_type, primary_title, original_title, _, start_year = parts[:6]
                if title_type not in ("movie", "tvMovie", "tvSeries", "tvMiniSeries"):
                    continue
                try:
                    year = int(start_year) if start_year != "\\N" else None
                    kp = _normalize_title_for_match(primary_title or "")
                    ko_raw = (original_title or "").strip()
                    ko = _normalize_title_for_match(ko_raw) if ko_raw and ko_raw != "\\N" else ""
                    if ko == kp:
                        ko = ""
                    basics_rows.append((imdb_id, primary_title, original_title, year, kp, ko))
                except:
                    pass

        with get_conn() as conn:
            conn.execute("DELETE FROM imdb_basics")
            conn.executemany(
                """INSERT OR REPLACE INTO imdb_basics
                   (imdb_id, primary_title, original_title, start_year, key_primary, key_original)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                basics_rows,
            )
            # Обновляем дату
            conn.execute(
                "INSERT OR REPLACE INTO imdb_meta (key, value) VALUES ('last_update', ?)",
                (datetime.now().isoformat(),)
            )
            conn.commit()
        print(f"✅ Загружено {len(basics_rows):,} фильмов из IMDb basics")
        print("🎉 IMDb данные готовы!")
