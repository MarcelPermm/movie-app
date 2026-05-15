import os
import json
import threading
import psycopg2
import psycopg2.extras
import psycopg2.errors as pg_errors
from psycopg2 import pool as pg_pool


def _parse_list(val) -> list:
    if not val:
        return []
    if isinstance(val, list):
        return val
    try:
        return json.loads(val)
    except (json.JSONDecodeError, TypeError):
        if isinstance(val, str) and val.startswith("{") and val.endswith("}"):
            inner = val[1:-1]
            return [x.strip().strip('"') for x in inner.split(",") if x.strip()]
        return []


# ─── Connection pool ──────────────────────────────────────────────────────────
# Переиспользуем соединения между запросами. Это убирает ~500-2000мс на каждый
# вызов БД (TCP handshake + Postgres auth). Особенно важно для Neon free tier.

_pool = None
_pool_lock = threading.Lock()


def _build_pool():
    url = os.getenv("DATABASE_URL", "")
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)
    return pg_pool.ThreadedConnectionPool(
        minconn=1, maxconn=10, dsn=url,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )


def _get_pool():
    global _pool
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                _pool = _build_pool()
    return _pool


class _Conn:
    """Контекст-менеджер: берёт соединение из пула, возвращает обратно."""
    def __enter__(self):
        self._conn = _get_pool().getconn()
        return self._conn
    def __exit__(self, exc_type, exc_val, exc_tb):
        try:
            if exc_type is not None:
                self._conn.rollback()
        finally:
            _get_pool().putconn(self._conn)


def _get_conn():
    """Возвращает контекст-менеджер для использования через `with _get_conn() as conn:`.
    Старый код `conn = _get_conn(); try: ... finally: conn.close()` тоже работает
    благодаря дублирующей реализации в _LegacyConn ниже."""
    return _LegacyConn()


class _LegacyConn:
    """Обратная совместимость со старым стилем conn = _get_conn() / conn.close()."""
    def __init__(self):
        self._conn = _get_pool().getconn()
    def cursor(self, *a, **kw):
        return self._conn.cursor(*a, **kw)
    def commit(self):
        return self._conn.commit()
    def rollback(self):
        return self._conn.rollback()
    def close(self):
        _get_pool().putconn(self._conn)
    def __getattr__(self, name):
        return getattr(self._conn, name)


def init_imdb_map_table():
    """Таблица кэша tmdb_id → imdb_id, заполняется при первом открытии деталей."""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS tmdb_imdb_map (
                tmdb_id    INTEGER  NOT NULL,
                media_type TEXT     NOT NULL DEFAULT 'movie',
                imdb_id    TEXT     NOT NULL,
                PRIMARY KEY (tmdb_id, media_type)
            )
        """)
        conn.commit()
    finally:
        conn.close()


def save_imdb_mapping(tmdb_id: int, imdb_id: str, media_type: str = "movie"):
    if not imdb_id:
        return
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO tmdb_imdb_map (tmdb_id, media_type, imdb_id)
            VALUES (%s, %s, %s)
            ON CONFLICT (tmdb_id, media_type) DO NOTHING
        """, (tmdb_id, media_type, imdb_id))
        conn.commit()
    finally:
        conn.close()


def get_imdb_mappings_batch(tmdb_ids: list, media_type: str = "movie") -> dict:
    """Возвращает {tmdb_id: imdb_id} для известных маппингов."""
    if not tmdb_ids:
        return {}
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT tmdb_id, imdb_id FROM tmdb_imdb_map WHERE tmdb_id = ANY(%s) AND media_type = %s",
            (tmdb_ids, media_type)
        )
        return {row["tmdb_id"]: row["imdb_id"] for row in cur.fetchall()}
    finally:
        conn.close()


def init_db():
    conn = _get_conn()
    try:
        cur = conn.cursor()

        cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id           SERIAL PRIMARY KEY,
                username     TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS watched (
                id           SERIAL PRIMARY KEY,
                user_id      INTEGER NOT NULL DEFAULT 1,
                movie_id     INTEGER NOT NULL,
                media_type   TEXT NOT NULL DEFAULT 'movie',
                title        TEXT NOT NULL,
                genres       TEXT NOT NULL DEFAULT '[]',
                overview     TEXT,
                poster_path  TEXT,
                vote_average REAL,
                user_rating  INTEGER DEFAULT NULL,
                review       TEXT DEFAULT NULL,
                director     TEXT DEFAULT NULL,
                cast_names   TEXT DEFAULT NULL,
                added_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, movie_id, media_type)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS watchlist (
                id           SERIAL PRIMARY KEY,
                user_id      INTEGER NOT NULL DEFAULT 1,
                movie_id     INTEGER NOT NULL,
                media_type   TEXT NOT NULL DEFAULT 'movie',
                title        TEXT NOT NULL,
                genres       TEXT NOT NULL DEFAULT '[]',
                overview     TEXT,
                poster_path  TEXT,
                vote_average REAL,
                added_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, movie_id, media_type)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS dismissed (
                user_id      INTEGER NOT NULL DEFAULT 1,
                movie_id     INTEGER NOT NULL,
                media_type   TEXT NOT NULL DEFAULT 'movie',
                title        TEXT,
                genres       TEXT DEFAULT '[]',
                cast_names   TEXT DEFAULT '[]',
                country      TEXT DEFAULT NULL,
                studio_names TEXT DEFAULT '[]',
                dismissed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY(user_id, movie_id, media_type)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS favorite_actors (
                id           SERIAL PRIMARY KEY,
                user_id      INTEGER NOT NULL DEFAULT 1,
                actor_id     INTEGER NOT NULL,
                actor_name   TEXT NOT NULL,
                profile_path TEXT,
                added_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, actor_id)
            )
        """)

        # Композитные индексы — критичны для SELECT ... WHERE user_id=? AND media_type=?
        # Без них Postgres делает full table scan, что при 100+ записях даёт +100-500мс.
        cur.execute("CREATE INDEX IF NOT EXISTS idx_watched_user_media   ON watched   (user_id, media_type)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_watchlist_user_media ON watchlist (user_id, media_type)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_dismissed_user_media ON dismissed (user_id, media_type)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_favactors_user       ON favorite_actors (user_id)")

        conn.commit()
    finally:
        conn.close()


# ─── Пользователи ─────────────────────────────────────────────────────────────

def create_user(username: str, display_name: str) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO users (username, display_name)
            VALUES (%s, %s)
            ON CONFLICT (username) DO NOTHING
            RETURNING id, username, display_name
        """, (username, display_name))
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def get_user_by_username(username: str) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, username, display_name FROM users WHERE LOWER(username) = LOWER(%s)", (username,))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


# ─── Просмотренное ────────────────────────────────────────────────────────────

def add_watched(movie: dict, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO watched
                (user_id, movie_id, media_type, title, genres, overview, poster_path, vote_average, director, cast_names)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id, movie_id, media_type) DO NOTHING
        """, (
            user_id, movie["id"], media_type, movie["title"],
            json.dumps(movie.get("genres", [])),
            movie.get("overview", ""),
            movie.get("poster_path", ""),
            movie.get("vote_average", 0.0),
            movie.get("director"),
            json.dumps(movie.get("cast_names", [])),
        ))
        inserted = cur.rowcount > 0
        conn.commit()
        return inserted
    finally:
        conn.close()


def rate_watched(movie_id: int, rating: int, review: str = None, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "UPDATE watched SET user_rating = %s, review = %s WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (rating, review, movie_id, media_type, user_id)
        )
        updated = cur.rowcount > 0
        conn.commit()
        return updated
    finally:
        conn.close()


def remove_watched(movie_id: int, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM watched WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (movie_id, media_type, user_id)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def get_watched(media_type: str = "movie", user_id: int = 1) -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM watched WHERE media_type = %s AND user_id = %s ORDER BY added_at DESC",
            (media_type, user_id)
        )
        rows = cur.fetchall()
        result = []
        for row in rows:
            m = dict(row)
            m["genres"]     = _parse_list(m.get("genres"))
            m["cast_names"] = _parse_list(m.get("cast_names"))
            result.append(m)
        return result
    finally:
        conn.close()


def is_watched(movie_id: int, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT 1 FROM watched WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (movie_id, media_type, user_id)
        )
        return cur.fetchone() is not None
    finally:
        conn.close()


def get_watched_map(media_type: str = "movie", user_id: int = 1) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT movie_id, user_rating, review FROM watched WHERE media_type = %s AND user_id = %s",
            (media_type, user_id)
        )
        return {row["movie_id"]: {"user_rating": row["user_rating"], "review": row["review"]}
                for row in cur.fetchall()}
    finally:
        conn.close()


def get_watchlist_ids(media_type: str = "movie", user_id: int = 1) -> set:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT movie_id FROM watchlist WHERE media_type = %s AND user_id = %s",
            (media_type, user_id)
        )
        return {row["movie_id"] for row in cur.fetchall()}
    finally:
        conn.close()


def get_watched_entry(movie_id: int, media_type: str = "movie", user_id: int = 1) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT user_rating, review FROM watched WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (movie_id, media_type, user_id)
        )
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_watched_rating(movie_id: int, media_type: str = "movie", user_id: int = 1):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT user_rating FROM watched WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (movie_id, media_type, user_id)
        )
        row = cur.fetchone()
        return row["user_rating"] if row else None
    finally:
        conn.close()


# ─── К просмотру ──────────────────────────────────────────────────────────────

def add_watchlist(movie: dict, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO watchlist (user_id, movie_id, media_type, title, genres, overview, poster_path, vote_average)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id, movie_id, media_type) DO NOTHING
        """, (
            user_id, movie["id"], media_type, movie["title"],
            json.dumps(movie.get("genres", [])),
            movie.get("overview", ""),
            movie.get("poster_path", ""),
            movie.get("vote_average", 0.0),
        ))
        inserted = cur.rowcount > 0
        conn.commit()
        return inserted
    finally:
        conn.close()


def remove_watchlist(movie_id: int, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM watchlist WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (movie_id, media_type, user_id)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def get_watchlist(media_type: str = "movie", user_id: int = 1) -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM watchlist WHERE media_type = %s AND user_id = %s ORDER BY added_at DESC",
            (media_type, user_id)
        )
        rows = cur.fetchall()
        result = []
        for row in rows:
            m = dict(row)
            m["genres"] = _parse_list(m.get("genres"))
            result.append(m)
        return result
    finally:
        conn.close()


def is_watchlist(movie_id: int, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT 1 FROM watchlist WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (movie_id, media_type, user_id)
        )
        return cur.fetchone() is not None
    finally:
        conn.close()


# ─── Отклонённые ──────────────────────────────────────────────────────────────

def dismiss_movie(movie: dict, media_type: str = "movie", user_id: int = 1):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO dismissed
                (user_id, movie_id, media_type, title, genres, cast_names, country, studio_names)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id, movie_id, media_type) DO UPDATE SET
                dismissed_at = CURRENT_TIMESTAMP
        """, (
            user_id, movie["id"], media_type,
            movie.get("title", ""),
            json.dumps(movie.get("genres", [])),
            json.dumps(movie.get("cast_names", [])),
            movie.get("country"),
            json.dumps(movie.get("studio_names", [])),
        ))
        conn.commit()
    finally:
        conn.close()


def remove_dismissed(movie_id: int, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM dismissed WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (movie_id, media_type, user_id)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def get_dismissed(media_type: str = "movie", user_id: int = 1) -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM dismissed WHERE media_type = %s AND user_id = %s ORDER BY dismissed_at DESC",
            (media_type, user_id)
        )
        rows = cur.fetchall()
        result = []
        for row in rows:
            m = dict(row)
            m["genres"]       = _parse_list(m.get("genres"))
            m["cast_names"]   = _parse_list(m.get("cast_names"))
            m["studio_names"] = _parse_list(m.get("studio_names"))
            result.append(m)
        return result
    finally:
        conn.close()


def get_dismissed_ids(media_type: str = "movie", user_id: int = 1) -> set:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT movie_id FROM dismissed WHERE media_type = %s AND user_id = %s",
            (media_type, user_id)
        )
        return {row["movie_id"] for row in cur.fetchall()}
    finally:
        conn.close()


# ─── Избранные актёры ─────────────────────────────────────────────────────────

def add_favorite_actor(actor_id: int, actor_name: str, profile_path: str = None, user_id: int = 1):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO favorite_actors (user_id, actor_id, actor_name, profile_path)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (user_id, actor_id) DO UPDATE SET
                actor_name   = EXCLUDED.actor_name,
                profile_path = EXCLUDED.profile_path
        """, (user_id, actor_id, actor_name, profile_path))
        conn.commit()
    finally:
        conn.close()


def remove_favorite_actor(actor_id: int, user_id: int = 1):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM favorite_actors WHERE actor_id = %s AND user_id = %s", (actor_id, user_id))
        conn.commit()
    finally:
        conn.close()


def get_favorite_actors(user_id: int = 1) -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM favorite_actors WHERE user_id = %s ORDER BY added_at ASC", (user_id,))
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()


def is_favorite_actor(actor_id: int, user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT 1 FROM favorite_actors WHERE actor_id = %s AND user_id = %s", (actor_id, user_id))
        return cur.fetchone() is not None
    finally:
        conn.close()
