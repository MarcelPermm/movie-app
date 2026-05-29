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


def _reset_pool():
    """Сбрасывает пул соединений. Вызывается когда Neon закрыл соединения со своей стороны."""
    global _pool
    with _pool_lock:
        if _pool is not None:
            try:
                _pool.closeall()
            except Exception:
                pass
            _pool = None


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
        try:
            self._conn = _get_pool().getconn()
            # Проверяем что соединение живое
            self._conn.cursor().execute("SELECT 1")
        except Exception:
            # Соединение мёртвое (Neon заснул) — сбрасываем пул и переподключаемся
            _reset_pool()
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

        # Migrations: add new columns if they don't exist
        cur.execute("ALTER TABLE watchlist ADD COLUMN IF NOT EXISTS category     TEXT NOT NULL DEFAULT 'not_sure'")
        cur.execute("ALTER TABLE watchlist ADD COLUMN IF NOT EXISTS release_year INT  DEFAULT NULL")
        cur.execute("ALTER TABLE watchlist ADD COLUMN IF NOT EXISTS country      TEXT DEFAULT NULL")
        cur.execute("ALTER TABLE watched   ADD COLUMN IF NOT EXISTS platform     TEXT DEFAULT NULL")
        cur.execute("ALTER TABLE watched   ADD COLUMN IF NOT EXISTS watched_date DATE DEFAULT NULL")

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


def rate_watched(movie_id: int, rating: int, review: str = None, media_type: str = "movie", user_id: int = 1,
                 platform: str = None, watched_date=None) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            """UPDATE watched SET user_rating = %s, review = %s,
               platform = COALESCE(%s, platform),
               watched_date = COALESCE(%s, watched_date)
               WHERE movie_id = %s AND media_type = %s AND user_id = %s""",
            (rating, review, platform, watched_date, movie_id, media_type, user_id)
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
            INSERT INTO watchlist (user_id, movie_id, media_type, title, genres, overview, poster_path, vote_average, release_year, country, category)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id, movie_id, media_type) DO NOTHING
        """, (
            user_id, movie["id"], media_type, movie["title"],
            json.dumps(movie.get("genres", [])),
            movie.get("overview", ""),
            movie.get("poster_path", ""),
            movie.get("vote_average", 0.0),
            movie.get("release_year"),
            movie.get("country"),
            movie.get("category", "not_sure"),
        ))
        inserted = cur.rowcount > 0
        conn.commit()
        return inserted
    finally:
        conn.close()


def update_watchlist_category(movie_id: int, category: str, media_type: str = "movie", user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "UPDATE watchlist SET category = %s WHERE movie_id = %s AND media_type = %s AND user_id = %s",
            (category, movie_id, media_type, user_id)
        )
        updated = cur.rowcount > 0
        conn.commit()
        return updated
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


# ─── Книги ────────────────────────────────────────────────────────────────────

def init_books_tables():
    """Создаёт таблицы books_read и books_wishlist если их нет."""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS books_read (
                id             SERIAL PRIMARY KEY,
                user_id        INTEGER NOT NULL DEFAULT 1,
                book_id        TEXT    NOT NULL,
                title          TEXT    NOT NULL,
                author         TEXT,
                cover          TEXT,
                genres         TEXT DEFAULT '[]',
                page_count     INTEGER,
                published_date TEXT,
                user_rating    INTEGER DEFAULT NULL,
                review         TEXT DEFAULT NULL,
                added_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, book_id)
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS books_wishlist (
                id       SERIAL PRIMARY KEY,
                user_id  INTEGER NOT NULL DEFAULT 1,
                book_id  TEXT    NOT NULL,
                title    TEXT    NOT NULL,
                author   TEXT,
                cover    TEXT,
                added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, book_id)
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_books_read_user     ON books_read     (user_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_books_wishlist_user ON books_wishlist (user_id)")
        conn.commit()
    finally:
        conn.close()


def get_books_read(user_id: int = 1) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM books_read WHERE user_id = %s ORDER BY added_at DESC",
            (user_id,)
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


def add_book_read(book: dict, user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO books_read (user_id, book_id, title, author, cover, genres, page_count, published_date)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id, book_id) DO NOTHING
        """, (
            user_id,
            book["id"],
            book.get("title", ""),
            book.get("author", ""),
            book.get("cover", ""),
            json.dumps(book.get("genres", [])),
            book.get("page_count"),
            book.get("published_date", ""),
        ))
        inserted = cur.rowcount > 0
        conn.commit()
        return inserted
    finally:
        conn.close()


def rate_book(book_id: str, rating: int, review: str = None, user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "UPDATE books_read SET user_rating = %s, review = %s WHERE book_id = %s AND user_id = %s",
            (rating, review, book_id, user_id)
        )
        updated = cur.rowcount > 0
        conn.commit()
        return updated
    finally:
        conn.close()


def remove_book_read(book_id: str, user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM books_read WHERE book_id = %s AND user_id = %s",
            (book_id, user_id)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def is_book_read(book_id: str, user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT 1 FROM books_read WHERE book_id = %s AND user_id = %s",
            (book_id, user_id)
        )
        return cur.fetchone() is not None
    finally:
        conn.close()


def get_book_read_entry(book_id: str, user_id: int = 1):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM books_read WHERE book_id = %s AND user_id = %s",
            (book_id, user_id)
        )
        row = cur.fetchone()
        if not row:
            return None
        m = dict(row)
        m["genres"] = _parse_list(m.get("genres"))
        return m
    finally:
        conn.close()


def get_books_wishlist(user_id: int = 1) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM books_wishlist WHERE user_id = %s ORDER BY added_at DESC",
            (user_id,)
        )
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()


def add_book_wishlist(book: dict, user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO books_wishlist (user_id, book_id, title, author, cover)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (user_id, book_id) DO NOTHING
        """, (
            user_id,
            book["id"],
            book.get("title", ""),
            book.get("author", ""),
            book.get("cover", ""),
        ))
        inserted = cur.rowcount > 0
        conn.commit()
        return inserted
    finally:
        conn.close()


def remove_book_wishlist(book_id: str, user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM books_wishlist WHERE book_id = %s AND user_id = %s",
            (book_id, user_id)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def is_book_wishlist(book_id: str, user_id: int = 1) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT 1 FROM books_wishlist WHERE book_id = %s AND user_id = %s",
            (book_id, user_id)
        )
        return cur.fetchone() is not None
    finally:
        conn.close()


# ─── Тетрадь: Задачи ──────────────────────────────────────────────────────────

def init_tasks_table():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id            SERIAL PRIMARY KEY,
                user_id       INTEGER     NOT NULL DEFAULT 1,
                title         TEXT        NOT NULL,
                date          DATE        NOT NULL DEFAULT CURRENT_DATE,
                status        VARCHAR(10) NOT NULL DEFAULT 'todo',
                cancel_reason TEXT,
                time_str      VARCHAR(20),
                tag           VARCHAR(50),
                priority      VARCHAR(10) DEFAULT 'normal',
                created_at    TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_tasks_user_date ON tasks(user_id, date)")
        # Recurring tasks support
        cur.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS recurrence TEXT DEFAULT NULL")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS task_completions (
                id         SERIAL PRIMARY KEY,
                task_id    INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                date       DATE    NOT NULL,
                UNIQUE(task_id, date)
            )
        """)
        conn.commit()
    finally:
        conn.close()


def get_tasks(user_id: int, date: str) -> list:
    """Returns one-time tasks for date + recurring tasks that apply to this weekday."""
    import datetime
    d = datetime.date.fromisoformat(date)
    dow = d.weekday()  # 0=Mon, 6=Sun

    conn = _get_conn()
    try:
        cur = conn.cursor()

        # One-time tasks for this date
        cur.execute(
            "SELECT *, NULL::boolean as done_today FROM tasks "
            "WHERE user_id=%s AND date=%s AND recurrence IS NULL "
            "ORDER BY created_at ASC",
            (user_id, date)
        )
        one_time = [dict(r) for r in cur.fetchall()]

        # Daily recurring tasks
        cur.execute(
            "SELECT t.*, (tc.task_id IS NOT NULL) as done_today FROM tasks t "
            "LEFT JOIN task_completions tc ON tc.task_id = t.id AND tc.date = %s "
            "WHERE t.user_id=%s AND t.recurrence = 'daily' ORDER BY t.created_at ASC",
            (date, user_id)
        )
        daily = [dict(r) for r in cur.fetchall()]

        # Weekly recurring tasks — fetch all, filter in Python by weekday
        cur.execute(
            "SELECT t.*, (tc.task_id IS NOT NULL) as done_today FROM tasks t "
            "LEFT JOIN task_completions tc ON tc.task_id = t.id AND tc.date = %s "
            "WHERE t.user_id=%s AND t.recurrence LIKE 'weekly:%%' ORDER BY t.created_at ASC",
            (date, user_id)
        )
        weekly_all = [dict(r) for r in cur.fetchall()]
        weekly = [r for r in weekly_all if str(dow) in r['recurrence'].split(':', 1)[1].split(',')]

        return one_time + daily + weekly
    finally:
        conn.close()


# Keep legacy signature for range queries
def get_tasks_one_time(user_id: int, date: str) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM tasks WHERE user_id=%s AND date=%s AND recurrence IS NULL ORDER BY created_at ASC",
            (user_id, date)
        )
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()


def get_tasks_range(user_id: int, date_from: str, date_to: str) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM tasks WHERE user_id=%s AND date BETWEEN %s AND %s ORDER BY date ASC, created_at ASC",
            (user_id, date_from, date_to)
        )
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()


def add_task(user_id: int, title: str, date: str, time_str: str = None,
             tag: str = None, priority: str = "normal",
             recurrence: str = None) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO tasks (user_id,title,date,time_str,tag,priority,recurrence) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s) RETURNING *",
            (user_id, title, date, time_str, tag, priority, recurrence)
        )
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()


def add_task_completion(task_id: int, date: str):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO task_completions (task_id, date) VALUES (%s, %s) ON CONFLICT DO NOTHING",
            (task_id, date)
        )
        conn.commit()
    finally:
        conn.close()


def remove_task_completion(task_id: int, date: str):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM task_completions WHERE task_id=%s AND date=%s", (task_id, date))
        conn.commit()
    finally:
        conn.close()


def update_task(task_id: int, user_id: int, **fields) -> dict:
    allowed = {"title", "status", "cancel_reason", "time_str", "tag", "priority", "date", "recurrence"}
    fields = {k: v for k, v in fields.items() if k in allowed}
    if not fields:
        raise ValueError("No valid fields")
    conn = _get_conn()
    try:
        cur = conn.cursor()
        set_clause = ", ".join(f"{k}=%s" for k in fields)
        cur.execute(
            f"UPDATE tasks SET {set_clause} WHERE id=%s AND user_id=%s RETURNING *",
            (*fields.values(), task_id, user_id)
        )
        row = cur.fetchone()
        conn.commit()
        if not row:
            raise ValueError("Not found")
        return dict(row)
    finally:
        conn.close()


def delete_task(task_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM tasks WHERE id=%s AND user_id=%s", (task_id, user_id))
        conn.commit()
    finally:
        conn.close()


# ─── Тетрадь: Списки ──────────────────────────────────────────────────────────

def init_lists_tables():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notebook_lists (
                id         SERIAL PRIMARY KEY,
                user_id    INTEGER NOT NULL DEFAULT 1,
                name       TEXT NOT NULL,
                emoji      VARCHAR(10) DEFAULT '📋',
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notebook_list_items (
                id         SERIAL PRIMARY KEY,
                list_id    INTEGER NOT NULL REFERENCES notebook_lists(id) ON DELETE CASCADE,
                user_id    INTEGER NOT NULL DEFAULT 1,
                title      TEXT NOT NULL,
                done       BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        conn.commit()
    finally:
        conn.close()

def get_lists(user_id: int) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM notebook_lists WHERE user_id=%s ORDER BY created_at ASC", (user_id,))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def add_list(user_id: int, name: str, emoji: str = "📋") -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO notebook_lists (user_id,name,emoji) VALUES (%s,%s,%s) RETURNING *", (user_id, name, emoji))
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def delete_list(list_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM notebook_lists WHERE id=%s AND user_id=%s", (list_id, user_id))
        conn.commit()
    finally:
        conn.close()

def get_list_items(list_id: int, user_id: int) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM notebook_list_items WHERE list_id=%s AND user_id=%s ORDER BY created_at ASC", (list_id, user_id))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def add_list_item(list_id: int, user_id: int, title: str) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO notebook_list_items (list_id,user_id,title) VALUES (%s,%s,%s) RETURNING *", (list_id, user_id, title))
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def toggle_list_item(item_id: int, user_id: int, done: bool) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE notebook_list_items SET done=%s WHERE id=%s AND user_id=%s RETURNING *", (done, item_id, user_id))
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {}
    finally:
        conn.close()

def delete_list_item(item_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM notebook_list_items WHERE id=%s AND user_id=%s", (item_id, user_id))
        conn.commit()
    finally:
        conn.close()


# ─── Тетрадь: Заметки ─────────────────────────────────────────────────────────

def init_notes_table():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notebook_notes (
                id         SERIAL PRIMARY KEY,
                user_id    INTEGER NOT NULL DEFAULT 1,
                title      TEXT DEFAULT '',
                body       TEXT NOT NULL DEFAULT '',
                color      VARCHAR(20) DEFAULT 'yellow',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        conn.commit()
    finally:
        conn.close()

def get_notes(user_id: int) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM notebook_notes WHERE user_id=%s ORDER BY updated_at DESC", (user_id,))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def add_note(user_id: int, body: str = "", title: str = "", color: str = "yellow") -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO notebook_notes (user_id,title,body,color) VALUES (%s,%s,%s,%s) RETURNING *", (user_id, title, body, color))
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def update_note(note_id: int, user_id: int, **fields) -> dict:
    allowed = {"title", "body", "color"}
    fields = {k: v for k, v in fields.items() if k in allowed}
    if not fields:
        return {}
    conn = _get_conn()
    try:
        cur = conn.cursor()
        set_clause = ", ".join(f"{k}=%s" for k in fields) + ", updated_at=NOW()"
        cur.execute(f"UPDATE notebook_notes SET {set_clause} WHERE id=%s AND user_id=%s RETURNING *",
                    (*fields.values(), note_id, user_id))
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {}
    finally:
        conn.close()

def delete_note(note_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM notebook_notes WHERE id=%s AND user_id=%s", (note_id, user_id))
        conn.commit()
    finally:
        conn.close()


# ─── Тетрадь: Бюджет ──────────────────────────────────────────────────────────

def init_budget_tables():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS budget_categories (
                id           SERIAL PRIMARY KEY,
                user_id      INTEGER NOT NULL DEFAULT 1,
                name         TEXT NOT NULL,
                emoji        VARCHAR(10) DEFAULT '💰',
                plan_monthly INTEGER DEFAULT 0
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS budget_expenses (
                id          SERIAL PRIMARY KEY,
                user_id     INTEGER NOT NULL DEFAULT 1,
                date        DATE NOT NULL DEFAULT CURRENT_DATE,
                amount      INTEGER NOT NULL,
                category_id INTEGER REFERENCES budget_categories(id) ON DELETE SET NULL,
                note        TEXT,
                created_at  TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        cur.execute("ALTER TABLE budget_expenses ADD COLUMN IF NOT EXISTS merchant TEXT")
        conn.commit()
    finally:
        conn.close()

def get_budget_categories(user_id: int) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM budget_categories WHERE user_id=%s ORDER BY id ASC", (user_id,))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def add_budget_category(user_id: int, name: str, emoji: str, plan_monthly: int = 0) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO budget_categories (user_id,name,emoji,plan_monthly) VALUES (%s,%s,%s,%s) RETURNING *",
                    (user_id, name, emoji, plan_monthly))
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def update_budget_category(cat_id: int, user_id: int, name: str = None, emoji: str = None, plan_monthly: int = None) -> dict:
    fields = {k: v for k, v in {"name": name, "emoji": emoji, "plan_monthly": plan_monthly}.items() if v is not None}
    if not fields:
        return {}
    conn = _get_conn()
    try:
        cur = conn.cursor()
        set_clause = ", ".join(f"{k}=%s" for k in fields)
        cur.execute(f"UPDATE budget_categories SET {set_clause} WHERE id=%s AND user_id=%s RETURNING *",
                    (*fields.values(), cat_id, user_id))
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {}
    finally:
        conn.close()

def delete_budget_category(cat_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM budget_categories WHERE id=%s AND user_id=%s", (cat_id, user_id))
        conn.commit()
    finally:
        conn.close()

def get_budget_expenses(user_id: int, year: int, month: int) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT e.*, c.name as cat_name, c.emoji as cat_emoji
            FROM budget_expenses e
            LEFT JOIN budget_categories c ON c.id = e.category_id
            WHERE e.user_id=%s AND EXTRACT(YEAR FROM e.date)=%s AND EXTRACT(MONTH FROM e.date)=%s
            ORDER BY e.date DESC, e.created_at DESC
        """, (user_id, year, month))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def add_budget_expense(user_id: int, date: str, amount: int,
                       category_id: int = None, note: str = None,
                       merchant: str = None) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO budget_expenses (user_id,date,amount,category_id,note,merchant) "
            "VALUES (%s,%s,%s,%s,%s,%s) RETURNING *",
            (user_id, date, amount, category_id, note, merchant)
        )
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()


def get_merchant_suggestions(user_id: int) -> list:
    """Уникальные merchant-ы пользователя для автодополнения."""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT DISTINCT merchant FROM budget_expenses "
            "WHERE user_id=%s AND merchant IS NOT NULL AND merchant != '' "
            "ORDER BY merchant ASC",
            (user_id,)
        )
        return [row["merchant"] for row in cur.fetchall()]
    finally:
        conn.close()

def delete_budget_expense(exp_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM budget_expenses WHERE id=%s AND user_id=%s", (exp_id, user_id))
        conn.commit()
    finally:
        conn.close()

def update_budget_expense(exp_id: int, user_id: int,
                          amount: int = None, note: str = None,
                          category_id: int = None, merchant: str = None) -> dict:
    fields = {}
    if amount is not None:      fields["amount"] = amount
    if note is not None:        fields["note"]   = note
    if category_id is not None: fields["category_id"] = category_id
    if merchant is not None:    fields["merchant"] = merchant
    if not fields:
        return {}
    conn = _get_conn()
    try:
        cur = conn.cursor()
        set_clause = ", ".join(f"{k}=%s" for k in fields)
        cur.execute(
            f"UPDATE budget_expenses SET {set_clause} WHERE id=%s AND user_id=%s RETURNING *",
            (*fields.values(), exp_id, user_id)
        )
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {}
    finally:
        conn.close()

def delete_budget_expenses_month(user_id: int, year: int, month: int) -> int:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM budget_expenses WHERE user_id=%s AND EXTRACT(YEAR FROM date)=%s AND EXTRACT(MONTH FROM date)=%s",
            (user_id, year, month)
        )
        deleted = cur.rowcount
        conn.commit()
        return deleted
    finally:
        conn.close()

def delete_budget_expenses_all(user_id: int) -> int:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM budget_expenses WHERE user_id=%s", (user_id,))
        deleted = cur.rowcount
        conn.commit()
        return deleted
    finally:
        conn.close()


# ─── Тетрадь: Поездки ─────────────────────────────────────────────────────────

def init_trips_tables():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS trips (
                id            SERIAL PRIMARY KEY,
                user_id       INTEGER NOT NULL DEFAULT 1,
                name          TEXT NOT NULL,
                emoji         VARCHAR(10) DEFAULT '✈️',
                start_date    DATE,
                end_date      DATE,
                planned_total INTEGER DEFAULT 0,
                status        VARCHAR(20) DEFAULT 'upcoming',
                created_at    TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        cur.execute("ALTER TABLE trips ADD COLUMN IF NOT EXISTS event_type TEXT DEFAULT 'trip'")
        cur.execute("ALTER TABLE trips ADD COLUMN IF NOT EXISTS subtitle TEXT DEFAULT ''")
        cur.execute("ALTER TABLE trips ADD COLUMN IF NOT EXISTS parent_id INTEGER DEFAULT NULL REFERENCES trips(id) ON DELETE SET NULL")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS trip_day_notes (
                id       SERIAL PRIMARY KEY,
                trip_id  INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
                date     DATE NOT NULL,
                note     TEXT DEFAULT '',
                title    TEXT DEFAULT '',
                UNIQUE(trip_id, date)
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS trip_expenses (
                id             SERIAL PRIMARY KEY,
                trip_id        INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
                user_id        INTEGER NOT NULL DEFAULT 1,
                date           DATE NOT NULL,
                amount         INTEGER NOT NULL DEFAULT 0,
                planned_amount INTEGER,
                category       TEXT DEFAULT '',
                note           TEXT DEFAULT '',
                emoji          VARCHAR(10) DEFAULT '',
                created_at     TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        cur.execute("ALTER TABLE trip_expenses ADD COLUMN IF NOT EXISTS planned_amount INTEGER")
        cur.execute("ALTER TABLE trip_expenses ADD COLUMN IF NOT EXISTS city TEXT DEFAULT ''")
        conn.commit()
    finally:
        conn.close()

def get_trips(user_id: int) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT t.*, COALESCE(SUM(e.amount),0) as actual_total
            FROM trips t LEFT JOIN trip_expenses e ON e.trip_id = t.id
            WHERE t.user_id=%s GROUP BY t.id ORDER BY t.start_date DESC NULLS LAST
        """, (user_id,))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def get_trips_for_month(user_id: int, year: int, month: int) -> list:
    """Возвращает поездки/события, чьи даты пересекаются с указанным месяцем.
    Также включает дочерние поездки групп, которые попадают в месяц, даже если
    у ребёнка нет точного совпадения дат — чтобы фронтенд мог корректно строить группы."""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            WITH month_trips AS (
                SELECT t.id
                FROM trips t
                WHERE t.user_id = %s
                  AND t.event_type != 'group'
                  AND t.parent_id IS NULL
                  AND (
                      EXTRACT(YEAR FROM t.start_date) = %s AND EXTRACT(MONTH FROM t.start_date) = %s
                      OR EXTRACT(YEAR FROM t.end_date)   = %s AND EXTRACT(MONTH FROM t.end_date)   = %s
                      OR (t.start_date <= make_date(%s, %s, 28) AND t.end_date >= make_date(%s, %s, 1))
                  )
            ),
            month_groups AS (
                SELECT t.id
                FROM trips t
                WHERE t.user_id = %s
                  AND t.event_type = 'group'
                  AND (
                      EXTRACT(YEAR FROM t.start_date) = %s AND EXTRACT(MONTH FROM t.start_date) = %s
                      OR EXTRACT(YEAR FROM t.end_date)   = %s AND EXTRACT(MONTH FROM t.end_date)   = %s
                      OR (t.start_date <= make_date(%s, %s, 28) AND t.end_date >= make_date(%s, %s, 1))
                  )
            ),
            relevant_ids AS (
                SELECT id FROM month_trips
                UNION
                SELECT id FROM month_groups
                UNION
                -- Дети групп, попавших в месяц
                SELECT t.id FROM trips t WHERE t.parent_id IN (SELECT id FROM month_groups) AND t.user_id = %s
            )
            SELECT t.*, COALESCE(SUM(e.amount), 0) AS actual_total
            FROM trips t
            LEFT JOIN trip_expenses e ON e.trip_id = t.id
            WHERE t.id IN (SELECT id FROM relevant_ids)
            GROUP BY t.id
            ORDER BY t.start_date DESC NULLS LAST
        """, (
            user_id, year, month, year, month, year, month, year, month,  # month_trips (9)
            user_id, year, month, year, month, year, month, year, month,  # month_groups (9)
            user_id,                                                        # children of groups (1)
        ))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def add_trip(user_id: int, name: str, emoji: str = "✈️",
             start_date: str = None, end_date: str = None, planned_total: int = 0,
             event_type: str = "trip", subtitle: str = "") -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO trips (user_id,name,emoji,start_date,end_date,planned_total,event_type,subtitle) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *",
            (user_id, name, emoji, start_date, end_date, planned_total, event_type, subtitle)
        )
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def get_trip_day_notes(trip_id: int) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM trip_day_notes WHERE trip_id=%s ORDER BY date ASC", (trip_id,))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def upsert_trip_day_note(trip_id: int, date: str, note: str = "", title: str = "") -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO trip_day_notes (trip_id, date, note, title)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (trip_id, date) DO UPDATE SET note=EXCLUDED.note, title=EXCLUDED.title
            RETURNING *
        """, (trip_id, date, note, title))
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def group_trips(trip_id_a: int, trip_id_b: int, user_id: int, group_name: str = None, group_emoji: str = "📁") -> dict:
    """Объединяет две поездки в группу. Если одна из них уже группа — добавляет вторую к ней.
    Иначе создаёт новую группу и помещает обе внутрь.
    Возвращает dict группы."""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        # Находим обе поездки
        cur.execute("SELECT * FROM trips WHERE id=ANY(%s) AND user_id=%s", ([trip_id_a, trip_id_b], user_id))
        rows = {r["id"]: dict(r) for r in cur.fetchall()}
        if len(rows) < 2:
            raise ValueError("Поездки не найдены")

        trip_a, trip_b = rows[trip_id_a], rows[trip_id_b]

        # Если одна уже группа — добавляем вторую в неё
        if trip_a.get("event_type") == "group":
            group_id = trip_id_a
            child_id = trip_id_b
        elif trip_b.get("event_type") == "group":
            group_id = trip_id_b
            child_id = trip_id_a
        else:
            # Создаём новую группу-папку
            name = group_name or f"{trip_a['name']} · {trip_b['name']}"
            # Диапазон дат — объединение
            dates = [d for d in [trip_a.get("start_date"), trip_b.get("start_date")] if d]
            ends  = [d for d in [trip_a.get("end_date"),   trip_b.get("end_date")]   if d]
            sd = str(min(dates)) if dates else None
            ed = str(max(ends))  if ends  else None
            plan = (trip_a.get("planned_total") or 0) + (trip_b.get("planned_total") or 0)
            cur.execute(
                "INSERT INTO trips (user_id,name,emoji,start_date,end_date,planned_total,event_type) "
                "VALUES (%s,%s,%s,%s,%s,%s,'group') RETURNING id",
                (user_id, name, group_emoji, sd, ed, plan)
            )
            group_id = cur.fetchone()["id"]
            # Добавляем trip_a в группу
            cur.execute("UPDATE trips SET parent_id=%s WHERE id=%s AND user_id=%s", (group_id, trip_id_a, user_id))
            child_id = trip_id_b

        # Добавляем child в группу
        cur.execute("UPDATE trips SET parent_id=%s WHERE id=%s AND user_id=%s", (group_id, child_id, user_id))

        # Обновляем даты и бюджет группы: берём мин. start и макс. end всех детей
        cur.execute("""
            UPDATE trips SET
              start_date = (SELECT MIN(c.start_date) FROM trips c WHERE c.parent_id = trips.id AND c.start_date IS NOT NULL),
              end_date   = (SELECT MAX(c.end_date)   FROM trips c WHERE c.parent_id = trips.id AND c.end_date   IS NOT NULL),
              planned_total = (SELECT COALESCE(SUM(c.planned_total), 0) FROM trips c WHERE c.parent_id = trips.id)
            WHERE trips.id = %s
        """, (group_id,))
        conn.commit()

        cur.execute("SELECT * FROM trips WHERE id=%s", (group_id,))
        return dict(cur.fetchone())
    finally:
        conn.close()

def ungroup_trip(trip_id: int, user_id: int):
    """Убирает поездку из группы, обновляет даты и бюджет группы-родителя."""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        # Находим родителя перед разгруппировкой
        cur.execute("SELECT parent_id FROM trips WHERE id=%s AND user_id=%s", (trip_id, user_id))
        row = cur.fetchone()
        parent_id = row["parent_id"] if row else None

        cur.execute("UPDATE trips SET parent_id=NULL WHERE id=%s AND user_id=%s", (trip_id, user_id))

        # Обновляем группу-родителя если она есть
        if parent_id:
            cur.execute("""
                UPDATE trips SET
                  start_date = (SELECT MIN(c.start_date) FROM trips c WHERE c.parent_id = trips.id AND c.start_date IS NOT NULL),
                  end_date   = (SELECT MAX(c.end_date)   FROM trips c WHERE c.parent_id = trips.id AND c.end_date   IS NOT NULL),
                  planned_total = (SELECT COALESCE(SUM(c.planned_total), 0) FROM trips c WHERE c.parent_id = trips.id)
                WHERE trips.id = %s
            """, (parent_id,))
        conn.commit()
    finally:
        conn.close()

def delete_trip(trip_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM trips WHERE id=%s AND user_id=%s", (trip_id, user_id))
        conn.commit()
    finally:
        conn.close()

def get_trip_expenses(trip_id: int, user_id: int) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM trip_expenses WHERE trip_id=%s AND user_id=%s ORDER BY date ASC, created_at ASC",
                    (trip_id, user_id))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def add_trip_expense(trip_id: int, user_id: int, date: str, amount: int,
                     planned_amount: int = None, category: str = "",
                     note: str = "", emoji: str = "", city: str = "") -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO trip_expenses "
            "(trip_id,user_id,date,amount,planned_amount,category,note,emoji,city) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *",
            (trip_id, user_id, date, amount, planned_amount, category, note, emoji, city)
        )
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def update_trip_expense_amount(exp_id: int, user_id: int, amount: int) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE trip_expenses SET amount=%s WHERE id=%s AND user_id=%s RETURNING *",
                    (amount, exp_id, user_id))
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {}
    finally:
        conn.close()

def delete_trip_expense(exp_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM trip_expenses WHERE id=%s AND user_id=%s", (exp_id, user_id))
        conn.commit()
    finally:
        conn.close()
