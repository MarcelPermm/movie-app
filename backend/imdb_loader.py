"""
imdb_loader.py — IMDb рейтинги через PostgreSQL (Neon).

Скачивает только title.ratings.tsv.gz (~8MB) раз в 7 дней.
Поиск осуществляется напрямую по IMDb ID, который берётся из TMDB /external_ids.
"""

import gzip
import io
import asyncio
import httpx
import os
import psycopg2
import psycopg2.extras
from datetime import datetime, timedelta

RATINGS_URL = "https://datasets.imdbws.com/title.ratings.tsv.gz"


def _get_conn():
    url = os.getenv("DATABASE_URL", "")
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)
    return psycopg2.connect(url, cursor_factory=psycopg2.extras.RealDictCursor)


def init_imdb_tables():
    conn = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS imdb_ratings (
                    imdb_id    TEXT PRIMARY KEY,
                    rating     REAL,
                    vote_count INTEGER
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS imdb_meta (
                    key   TEXT PRIMARY KEY,
                    value TEXT
                )
            """)
        conn.commit()
    finally:
        conn.close()


def get_last_update() -> datetime | None:
    try:
        conn = _get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT value FROM imdb_meta WHERE key='last_update'")
                row = cur.fetchone()
                return datetime.fromisoformat(row["value"]) if row else None
        finally:
            conn.close()
    except Exception:
        return None


def needs_update() -> bool:
    last = get_last_update()
    if last is None:
        return True
    # Если данных меньше 100k — считаем загрузку незавершённой
    if not has_imdb_data():
        return True
    return datetime.now() - last > timedelta(days=7)


def has_imdb_data() -> bool:
    try:
        conn = _get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) AS c FROM imdb_ratings")
                row = cur.fetchone()
                return row["c"] > 100_000
        finally:
            conn.close()
    except Exception:
        return False


def get_imdb_stats_batch(imdb_ids: list) -> dict:
    """Батч-поиск: {imdb_id: {rating, vote_count}} для всех переданных ID."""
    if not imdb_ids:
        return {}
    try:
        conn = _get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT imdb_id, rating, vote_count FROM imdb_ratings WHERE imdb_id = ANY(%s)",
                    (imdb_ids,)
                )
                return {
                    row["imdb_id"]: {"rating": float(row["rating"]), "vote_count": int(row["vote_count"])}
                    for row in cur.fetchall()
                }
        finally:
            conn.close()
    except Exception:
        return {}


def get_imdb_stats_by_id(imdb_id: str) -> dict | None:
    """Прямой поиск по IMDb ID — точный, быстрый."""
    if not imdb_id:
        return None
    try:
        conn = _get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT rating, vote_count FROM imdb_ratings WHERE imdb_id = %s",
                    (imdb_id,)
                )
                row = cur.fetchone()
                if row:
                    return {"rating": float(row["rating"]), "vote_count": int(row["vote_count"])}
                return None
        finally:
            conn.close()
    except Exception:
        return None


def _sync_load(content: bytes) -> int:
    """Синхронная загрузка в PostgreSQL — запускается в отдельном потоке.
    Использует UPSERT вместо TRUNCATE+INSERT — старые данные остаются
    валидными даже если загрузка прервётся на середине.
    """
    conn = _get_conn()
    try:
        total = 0
        batch = []
        with gzip.open(io.BytesIO(content)) as f:
            next(f)  # пропускаем заголовок
            for line in f:
                parts = line.decode().strip().split("\t")
                if len(parts) == 3:
                    try:
                        batch.append((parts[0], float(parts[1]), int(parts[2])))
                    except Exception:
                        pass
                if len(batch) >= 100_000:
                    with conn.cursor() as cur:
                        psycopg2.extras.execute_values(
                            cur,
                            """INSERT INTO imdb_ratings (imdb_id, rating, vote_count) VALUES %s
                               ON CONFLICT (imdb_id) DO UPDATE
                               SET rating = EXCLUDED.rating, vote_count = EXCLUDED.vote_count""",
                            batch,
                        )
                    conn.commit()
                    total += len(batch)
                    batch = []

        if batch:
            with conn.cursor() as cur:
                psycopg2.extras.execute_values(
                    cur,
                    """INSERT INTO imdb_ratings (imdb_id, rating, vote_count) VALUES %s
                       ON CONFLICT (imdb_id) DO UPDATE
                       SET rating = EXCLUDED.rating, vote_count = EXCLUDED.vote_count""",
                    batch,
                )
            conn.commit()
            total += len(batch)

        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO imdb_meta (key, value) VALUES (%s, %s)
                   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value""",
                ("last_update", datetime.now().isoformat()),
            )
        conn.commit()
        return total
    finally:
        conn.close()


async def download_and_load():
    """Скачивает IMDb рейтинги и загружает в PostgreSQL в отдельном потоке."""
    try:
        print("📥 Скачиваем IMDb ratings (~8MB)...")
        async with httpx.AsyncClient(timeout=180, follow_redirects=True) as client:
            r = await client.get(RATINGS_URL)

        # Запускаем синхронную загрузку в потоке — не блокируем event loop
        loop = asyncio.get_event_loop()
        total = await loop.run_in_executor(None, _sync_load, r.content)
        print(f"✅ Загружено {total:,} рейтингов IMDb")
        print("🎉 IMDb данные готовы!")
    except Exception as e:
        print(f"⚠️  Ошибка загрузки IMDb: {e}")
