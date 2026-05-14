import os
import json
import psycopg2
import psycopg2.extras
import psycopg2.errors as pg_errors


def _parse_list(val) -> list:
    """Парсит список из JSON строки, PostgreSQL массива {a,b} или уже готового списка."""
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


def _get_conn():
    url = os.getenv("DATABASE_URL", "")
    # Render/Heroku могут вернуть "postgres://..." — psycopg2 требует "postgresql://"
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)
    return psycopg2.connect(url, cursor_factory=psycopg2.extras.RealDictCursor)


def init_db():
    conn = _get_conn()
    try:
        cur = conn.cursor()

        cur.execute("""
            CREATE TABLE IF NOT EXISTS watched (
                id           SERIAL PRIMARY KEY,
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
                UNIQUE(movie_id, media_type)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS watchlist (
                id           SERIAL PRIMARY KEY,
                movie_id     INTEGER NOT NULL,
                media_type   TEXT NOT NULL DEFAULT 'movie',
                title        TEXT NOT NULL,
                genres       TEXT NOT NULL DEFAULT '[]',
                overview     TEXT,
                poster_path  TEXT,
                vote_average REAL,
                added_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(movie_id, media_type)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS dismissed (
                movie_id     INTEGER NOT NULL,
                media_type   TEXT NOT NULL DEFAULT 'movie',
                title        TEXT,
                genres       TEXT DEFAULT '[]',
                cast_names   TEXT DEFAULT '[]',
                country      TEXT DEFAULT NULL,
                studio_names TEXT DEFAULT '[]',
                dismissed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY(movie_id, media_type)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS favorite_actors (
                id           SERIAL PRIMARY KEY,
                actor_id     INTEGER NOT NULL UNIQUE,
                actor_name   TEXT NOT NULL,
                profile_path TEXT,
                added_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.commit()
    finally:
        conn.close()


# ─── Просмотренное ────────────────────────────────────────────────────────────

def add_watched(movie: dict, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO watched
                (movie_id, media_type, title, genres, overview, poster_path, vote_average, director, cast_names)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (movie_id, media_type) DO NOTHING
        """, (
            movie["id"], media_type, movie["title"],
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


def rate_watched(movie_id: int, rating: int, review: str = None, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "UPDATE watched SET user_rating = %s, review = %s WHERE movie_id = %s AND media_type = %s",
            (rating, review, movie_id, media_type)
        )
        updated = cur.rowcount > 0
        conn.commit()
        return updated
    finally:
        conn.close()


def remove_watched(movie_id: int, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM watched WHERE movie_id = %s AND media_type = %s",
            (movie_id, media_type)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def get_watched(media_type: str = "movie") -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM watched WHERE media_type = %s ORDER BY added_at DESC",
            (media_type,)
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


def is_watched(movie_id: int, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT 1 FROM watched WHERE movie_id = %s AND media_type = %s",
            (movie_id, media_type)
        )
        return cur.fetchone() is not None
    finally:
        conn.close()


def get_watched_rating(movie_id: int, media_type: str = "movie"):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT user_rating FROM watched WHERE movie_id = %s AND media_type = %s",
            (movie_id, media_type)
        )
        row = cur.fetchone()
        return row["user_rating"] if row else None
    finally:
        conn.close()


# ─── К просмотру ──────────────────────────────────────────────────────────────

def add_watchlist(movie: dict, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO watchlist (movie_id, media_type, title, genres, overview, poster_path, vote_average)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (movie_id, media_type) DO NOTHING
        """, (
            movie["id"], media_type, movie["title"],
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


def remove_watchlist(movie_id: int, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM watchlist WHERE movie_id = %s AND media_type = %s",
            (movie_id, media_type)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def get_watchlist(media_type: str = "movie") -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM watchlist WHERE media_type = %s ORDER BY added_at DESC",
            (media_type,)
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


def is_watchlist(movie_id: int, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT 1 FROM watchlist WHERE movie_id = %s AND media_type = %s",
            (movie_id, media_type)
        )
        return cur.fetchone() is not None
    finally:
        conn.close()


# ─── Отклонённые ──────────────────────────────────────────────────────────────

def dismiss_movie(movie: dict, media_type: str = "movie"):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO dismissed
                (movie_id, media_type, title, genres, cast_names, country, studio_names)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (movie_id, media_type) DO UPDATE SET
                title        = EXCLUDED.title,
                genres       = EXCLUDED.genres,
                cast_names   = EXCLUDED.cast_names,
                country      = EXCLUDED.country,
                studio_names = EXCLUDED.studio_names,
                dismissed_at = CURRENT_TIMESTAMP
        """, (
            movie["id"], media_type,
            movie.get("title", ""),
            json.dumps(movie.get("genres", [])),
            json.dumps(movie.get("cast_names", [])),
            movie.get("country"),
            json.dumps(movie.get("studio_names", [])),
        ))
        conn.commit()
    finally:
        conn.close()


def remove_dismissed(movie_id: int, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM dismissed WHERE movie_id = %s AND media_type = %s",
            (movie_id, media_type)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def get_dismissed(media_type: str = "movie") -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM dismissed WHERE media_type = %s ORDER BY dismissed_at DESC",
            (media_type,)
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


def get_dismissed_ids(media_type: str = "movie") -> set:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT movie_id FROM dismissed WHERE media_type = %s",
            (media_type,)
        )
        return {row["movie_id"] for row in cur.fetchall()}
    finally:
        conn.close()


def is_dismissed(movie_id: int, media_type: str = "movie") -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT 1 FROM dismissed WHERE movie_id = %s AND media_type = %s",
            (movie_id, media_type)
        )
        return cur.fetchone() is not None
    finally:
        conn.close()


# ─── Избранные актёры ─────────────────────────────────────────────────────────

def add_favorite_actor(actor_id: int, actor_name: str, profile_path: str = None):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO favorite_actors (actor_id, actor_name, profile_path)
            VALUES (%s, %s, %s)
            ON CONFLICT (actor_id) DO UPDATE SET
                actor_name   = EXCLUDED.actor_name,
                profile_path = EXCLUDED.profile_path
        """, (actor_id, actor_name, profile_path))
        conn.commit()
    finally:
        conn.close()


def remove_favorite_actor(actor_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM favorite_actors WHERE actor_id = %s", (actor_id,))
        conn.commit()
    finally:
        conn.close()


def get_favorite_actors() -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM favorite_actors ORDER BY added_at ASC")
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()


def is_favorite_actor(actor_id: int) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT 1 FROM favorite_actors WHERE actor_id = %s", (actor_id,))
        return cur.fetchone() is not None
    finally:
        conn.close()
