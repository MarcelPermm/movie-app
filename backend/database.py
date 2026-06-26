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

def create_user(username: str, display_name: str, password_hash: str = "") -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO users (username, display_name, password_hash)
            VALUES (%s, %s, %s)
            ON CONFLICT (username) DO NOTHING
            RETURNING id, username, display_name
        """, (username, display_name, password_hash))
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def get_user_by_username(username: str) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, username, display_name, password_hash FROM users WHERE LOWER(username) = LOWER(%s)", (username,))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_user_by_id(user_id: int) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, username, display_name FROM users WHERE id = %s", (user_id,))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


# ─── Друзья и виш-лист ────────────────────────────────────────────────────────

def init_wishlist_tables():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS friendships (
                id           SERIAL PRIMARY KEY,
                requester_id INTEGER NOT NULL,
                recipient_id INTEGER NOT NULL,
                status       TEXT NOT NULL DEFAULT 'pending',
                created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(requester_id, recipient_id)
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS wishlist_items (
                id         SERIAL PRIMARY KEY,
                user_id    INTEGER NOT NULL DEFAULT 1,
                url        TEXT,
                title      TEXT NOT NULL,
                image      TEXT,
                price      NUMERIC,
                currency   TEXT DEFAULT 'RUB',
                note       TEXT,
                priority   INTEGER NOT NULL DEFAULT 2,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS wishlist_reservations (
                item_id     INTEGER PRIMARY KEY,
                reserved_by INTEGER NOT NULL,
                created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS wishlist_contributions (
                id             SERIAL PRIMARY KEY,
                item_id        INTEGER NOT NULL,
                contributor_id INTEGER NOT NULL,
                amount         NUMERIC NOT NULL,
                created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(item_id, contributor_id)
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_friendships_recipient        ON friendships (recipient_id, status)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_friendships_requester        ON friendships (requester_id, status)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_wishlist_items_user          ON wishlist_items (user_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_wishlist_contributions_item  ON wishlist_contributions (item_id)")
        conn.commit()
    finally:
        conn.close()


def find_user_public(username: str) -> dict | None:
    """Поиск пользователя по логину — без password_hash, для добавления в друзья."""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, username, display_name FROM users WHERE LOWER(username) = LOWER(%s)", (username,))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_friendship(user_a: int, user_b: int) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT * FROM friendships
            WHERE (requester_id = %s AND recipient_id = %s)
               OR (requester_id = %s AND recipient_id = %s)
        """, (user_a, user_b, user_b, user_a))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def are_friends(user_a: int, user_b: int) -> bool:
    f = get_friendship(user_a, user_b)
    return bool(f and f["status"] == "accepted")


def create_friend_request(requester_id: int, recipient_id: int) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO friendships (requester_id, recipient_id, status)
            VALUES (%s, %s, 'pending')
            ON CONFLICT (requester_id, recipient_id) DO NOTHING
            RETURNING id, requester_id, recipient_id, status, created_at
        """, (requester_id, recipient_id))
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def accept_friend_request(friendship_id: int, recipient_id: int) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            UPDATE friendships SET status = 'accepted'
            WHERE id = %s AND recipient_id = %s AND status = 'pending'
        """, (friendship_id, recipient_id))
        updated = cur.rowcount > 0
        conn.commit()
        return updated
    finally:
        conn.close()


def decline_friend_request(friendship_id: int, user_id: int) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            DELETE FROM friendships
            WHERE id = %s AND (requester_id = %s OR recipient_id = %s)
        """, (friendship_id, user_id, user_id))
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def remove_friend(user_a: int, user_b: int) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            DELETE FROM friendships
            WHERE status = 'accepted'
              AND ((requester_id = %s AND recipient_id = %s)
                OR (requester_id = %s AND recipient_id = %s))
        """, (user_a, user_b, user_b, user_a))
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def get_friends(user_id: int) -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT u.id, u.username, u.display_name
            FROM friendships f
            JOIN users u ON u.id = CASE WHEN f.requester_id = %s THEN f.recipient_id ELSE f.requester_id END
            WHERE f.status = 'accepted' AND (f.requester_id = %s OR f.recipient_id = %s)
            ORDER BY u.display_name
        """, (user_id, user_id, user_id))
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()


def get_incoming_requests(user_id: int) -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT f.id, u.id AS user_id, u.username, u.display_name, f.created_at
            FROM friendships f
            JOIN users u ON u.id = f.requester_id
            WHERE f.recipient_id = %s AND f.status = 'pending'
            ORDER BY f.created_at DESC
        """, (user_id,))
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()


def get_outgoing_requests(user_id: int) -> list[dict]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT f.id, u.id AS user_id, u.username, u.display_name, f.created_at
            FROM friendships f
            JOIN users u ON u.id = f.recipient_id
            WHERE f.requester_id = %s AND f.status = 'pending'
            ORDER BY f.created_at DESC
        """, (user_id,))
        return [dict(row) for row in cur.fetchall()]
    finally:
        conn.close()


def add_wishlist_item(user_id: int, title: str, url: str = None, image: str = None,
                       price: float = None, currency: str = "RUB", note: str = None,
                       priority: int = 2) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO wishlist_items (user_id, url, title, image, price, currency, note, priority)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING *
        """, (user_id, url, title, image, price, currency, note, priority))
        row = cur.fetchone()
        conn.commit()
        item = dict(row)
        item["price"] = float(item["price"]) if item["price"] is not None else None
        return item
    finally:
        conn.close()


def get_wishlist_item(item_id: int) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM wishlist_items WHERE id = %s", (item_id,))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def update_wishlist_item(item_id: int, user_id: int, **fields) -> bool:
    if not fields:
        return False
    conn = _get_conn()
    try:
        cur = conn.cursor()
        set_clause = ", ".join(f"{k} = %s" for k in fields)
        cur.execute(
            f"UPDATE wishlist_items SET {set_clause} WHERE id = %s AND user_id = %s",
            (*fields.values(), item_id, user_id)
        )
        updated = cur.rowcount > 0
        conn.commit()
        return updated
    finally:
        conn.close()


def delete_wishlist_item(item_id: int, user_id: int) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM wishlist_reservations WHERE item_id = %s", (item_id,))
        cur.execute("DELETE FROM wishlist_contributions WHERE item_id = %s", (item_id,))
        cur.execute("DELETE FROM wishlist_items WHERE id = %s AND user_id = %s", (item_id, user_id))
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def get_wishlist_items(owner_id: int, viewer_id: int) -> list[dict]:
    """Список вещей из вишлиста. Если смотрит сам владелец — статус резерва и
    складчины скрывается полностью, чтобы не испортить сюрприз подарка."""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM wishlist_items WHERE user_id = %s ORDER BY priority ASC, created_at DESC",
            (owner_id,)
        )
        items = [dict(row) for row in cur.fetchall()]
        for it in items:
            it["price"] = float(it["price"]) if it["price"] is not None else None

        if not items or viewer_id == owner_id:
            return items

        item_ids = [it["id"] for it in items]

        cur.execute("""
            SELECT wr.item_id, wr.reserved_by, u.display_name AS reserver_name
            FROM wishlist_reservations wr
            JOIN users u ON u.id = wr.reserved_by
            WHERE wr.item_id = ANY(%s)
        """, (item_ids,))
        reservations = {row["item_id"]: dict(row) for row in cur.fetchall()}

        cur.execute("""
            SELECT wc.item_id, wc.contributor_id, wc.amount, u.display_name AS contributor_name
            FROM wishlist_contributions wc
            JOIN users u ON u.id = wc.contributor_id
            WHERE wc.item_id = ANY(%s)
        """, (item_ids,))
        contributions: dict[int, list] = {}
        for row in cur.fetchall():
            d = dict(row)
            d["amount"] = float(d["amount"])
            contributions.setdefault(d["item_id"], []).append(d)

        for it in items:
            res = reservations.get(it["id"])
            contribs = contributions.get(it["id"], [])
            it["is_reserved"] = res is not None
            it["reserved_by_me"] = bool(res and res["reserved_by"] == viewer_id)
            it["reserver_name"] = res["reserver_name"] if res else None
            it["contributions"] = contribs
            it["contributed_total"] = sum(c["amount"] for c in contribs)
            mine = next((c for c in contribs if c["contributor_id"] == viewer_id), None)
            it["my_contribution"] = mine["amount"] if mine else None
        return items
    finally:
        conn.close()


def reserve_wishlist_item(item_id: int, user_id: int) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO wishlist_reservations (item_id, reserved_by)
            VALUES (%s, %s)
            ON CONFLICT (item_id) DO NOTHING
        """, (item_id, user_id))
        inserted = cur.rowcount > 0
        conn.commit()
        return inserted
    finally:
        conn.close()


def unreserve_wishlist_item(item_id: int, user_id: int) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM wishlist_reservations WHERE item_id = %s AND reserved_by = %s",
            (item_id, user_id)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


def upsert_contribution(item_id: int, contributor_id: int, amount: float) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO wishlist_contributions (item_id, contributor_id, amount)
            VALUES (%s, %s, %s)
            ON CONFLICT (item_id, contributor_id) DO UPDATE SET amount = EXCLUDED.amount
            RETURNING *
        """, (item_id, contributor_id, amount))
        row = cur.fetchone()
        conn.commit()
        item = dict(row)
        item["amount"] = float(item["amount"])
        return item
    finally:
        conn.close()


def remove_contribution(item_id: int, contributor_id: int) -> bool:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM wishlist_contributions WHERE item_id = %s AND contributor_id = %s",
            (item_id, contributor_id)
        )
        deleted = cur.rowcount > 0
        conn.commit()
        return deleted
    finally:
        conn.close()


# ─── Шахматы ──────────────────────────────────────────────────────────────────

CHESS_INITIAL_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

def init_chess_tables():
    # 1. Добавляем password_hash к users (отдельная транзакция)
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT DEFAULT ''")
        conn.commit()
    except Exception as e:
        print(f"alter users password_hash: {e}")
        conn.rollback()
    finally:
        conn.close()

    # 2. Создаём chess_games
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS chess_games (
                id             SERIAL PRIMARY KEY,
                code           VARCHAR(8) UNIQUE NOT NULL,
                fen            TEXT NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
                status         VARCHAR(20) DEFAULT 'waiting',
                white_user_id  INTEGER REFERENCES users(id),
                black_user_id  INTEGER REFERENCES users(id),
                winner         VARCHAR(10) DEFAULT NULL,
                moves_pgn      TEXT DEFAULT '',
                created_at     TIMESTAMP DEFAULT NOW(),
                updated_at     TIMESTAMP DEFAULT NOW()
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_chess_white ON chess_games (white_user_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_chess_black ON chess_games (black_user_id)")
        conn.commit()
    finally:
        conn.close()


def create_chess_game(code: str, white_user_id, black_user_id) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO chess_games (code, white_user_id, black_user_id, fen, status)
            VALUES (%s, %s, %s, %s, 'waiting')
            RETURNING *
        """, (code, white_user_id, black_user_id, CHESS_INITIAL_FEN))
        row = cur.fetchone()
        conn.commit()
        return dict(row)
    finally:
        conn.close()


def get_chess_game(code: str) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT cg.*,
                   wu.display_name AS white_name, wu.username AS white_username,
                   bu.display_name AS black_name,  bu.username AS black_username
            FROM chess_games cg
            LEFT JOIN users wu ON cg.white_user_id = wu.id
            LEFT JOIN users bu ON cg.black_user_id = bu.id
            WHERE cg.code = %s
        """, (code,))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def join_chess_game(code: str, user_id: int, color: str) -> dict | None:
    """color = 'white' | 'black' — заполняет свободный слот"""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        col = "white_user_id" if color == "white" else "black_user_id"
        cur.execute(f"""
            UPDATE chess_games
            SET {col} = %s, status = 'active', updated_at = NOW()
            WHERE code = %s AND {col} IS NULL
            RETURNING *
        """, (user_id, code))
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def update_chess_game(code: str, fen=None, status=None, winner=None, moves_pgn=None) -> dict | None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        fields, vals = [], []
        if fen       is not None: fields.append("fen = %s");       vals.append(fen)
        if status    is not None: fields.append("status = %s");    vals.append(status)
        if winner    is not None: fields.append("winner = %s");    vals.append(winner)
        if moves_pgn is not None: fields.append("moves_pgn = %s"); vals.append(moves_pgn)
        if not fields:
            return None
        fields.append("updated_at = NOW()")
        vals.append(code)
        cur.execute(f"UPDATE chess_games SET {', '.join(fields)} WHERE code = %s RETURNING *", vals)
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def get_chess_stats(user_id: int) -> list:
    """Статистика личных встреч с каждым соперником"""
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                opp.id            AS opponent_id,
                opp.display_name  AS opponent_name,
                opp.username      AS opponent_username,
                COUNT(*)          AS total,
                COUNT(*) FILTER (WHERE
                    (cg.winner = 'white' AND cg.white_user_id = %(uid)s) OR
                    (cg.winner = 'black' AND cg.black_user_id = %(uid)s)
                ) AS wins,
                COUNT(*) FILTER (WHERE
                    (cg.winner = 'white' AND cg.black_user_id = %(uid)s) OR
                    (cg.winner = 'black' AND cg.white_user_id = %(uid)s)
                ) AS losses,
                COUNT(*) FILTER (WHERE cg.winner = 'draw') AS draws
            FROM chess_games cg
            JOIN users opp ON (
                CASE WHEN cg.white_user_id = %(uid)s
                     THEN cg.black_user_id
                     ELSE cg.white_user_id END = opp.id
            )
            WHERE (cg.white_user_id = %(uid)s OR cg.black_user_id = %(uid)s)
              AND cg.status = 'finished'
            GROUP BY opp.id, opp.display_name, opp.username
            ORDER BY total DESC
        """, {"uid": user_id})
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()


def get_chess_history(user_id: int, limit: int = 20) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT cg.*,
                   wu.display_name AS white_name,
                   bu.display_name AS black_name
            FROM chess_games cg
            LEFT JOIN users wu ON cg.white_user_id = wu.id
            LEFT JOIN users bu ON cg.black_user_id = bu.id
            WHERE (cg.white_user_id = %s OR cg.black_user_id = %s)
              AND cg.status = 'finished'
            ORDER BY cg.updated_at DESC
            LIMIT %s
        """, (user_id, user_id, limit))
        return [dict(r) for r in cur.fetchall()]
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
        cur.execute("ALTER TABLE budget_categories ADD COLUMN IF NOT EXISTS plan_max INTEGER DEFAULT 0")
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

def add_budget_category(user_id: int, name: str, emoji: str, plan_monthly: int = 0, plan_max: int = 0) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO budget_categories (user_id,name,emoji,plan_monthly,plan_max) VALUES (%s,%s,%s,%s,%s) RETURNING *",
                    (user_id, name, emoji, plan_monthly, plan_max))
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def update_budget_category(cat_id: int, user_id: int, name: str = None, emoji: str = None,
                           plan_monthly: int = None, plan_max: int = None) -> dict:
    fields = {k: v for k, v in {"name": name, "emoji": emoji, "plan_monthly": plan_monthly, "plan_max": plan_max}.items() if v is not None}
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
        cur.execute("ALTER TABLE trip_expenses ADD COLUMN IF NOT EXISTS planned_max INTEGER")
        cur.execute("ALTER TABLE trip_expenses ADD COLUMN IF NOT EXISTS subcategory TEXT DEFAULT ''")
        cur.execute("ALTER TABLE trip_expenses ADD COLUMN IF NOT EXISTS day TEXT DEFAULT ''")
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

# ─── Цели (месяц / год) ───────────────────────────────────────────────────────

def init_goals_table():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS goals (
                id          SERIAL PRIMARY KEY,
                user_id     INTEGER NOT NULL DEFAULT 1,
                period      VARCHAR(10) NOT NULL,   -- 'month' | 'year'
                period_key  VARCHAR(10) NOT NULL,   -- '2026-06' | '2026'
                text        TEXT NOT NULL,
                done        BOOLEAN DEFAULT FALSE,
                sort        INTEGER DEFAULT 0,
                created_at  TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        conn.commit()
    finally:
        conn.close()

def get_goals(user_id: int, period: str, period_key: str) -> list:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM goals WHERE user_id=%s AND period=%s AND period_key=%s "
            "ORDER BY done ASC, sort ASC, created_at ASC",
            (user_id, period, period_key))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()

def add_goal(user_id: int, period: str, period_key: str, text: str) -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO goals (user_id,period,period_key,text) VALUES (%s,%s,%s,%s) RETURNING *",
            (user_id, period, period_key, text))
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def update_goal(goal_id: int, user_id: int, fields: dict) -> dict:
    allowed = ("text", "done", "sort")
    sets, vals = [], []
    for k in allowed:
        if k in fields:
            sets.append(f"{k}=%s"); vals.append(fields[k])
    if not sets:
        return {}
    conn = _get_conn()
    try:
        cur = conn.cursor()
        vals += [goal_id, user_id]
        cur.execute(f"UPDATE goals SET {', '.join(sets)} WHERE id=%s AND user_id=%s RETURNING *", vals)
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {}
    finally:
        conn.close()

def delete_goal(goal_id: int, user_id: int):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM goals WHERE id=%s AND user_id=%s", (goal_id, user_id))
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
                     note: str = "", emoji: str = "", city: str = "",
                     planned_max: int = None, subcategory: str = "", day: str = "") -> dict:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO trip_expenses "
            "(trip_id,user_id,date,amount,planned_amount,category,note,emoji,city,planned_max,subcategory,day) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *",
            (trip_id, user_id, date, amount, planned_amount, category, note, emoji, city,
             planned_max, subcategory, day)
        )
        row = dict(cur.fetchone())
        conn.commit()
        return row
    finally:
        conn.close()

def update_trip_expense(exp_id: int, user_id: int, fields: dict) -> dict:
    allowed = ("amount", "planned_amount", "planned_max", "category",
               "subcategory", "day", "note", "emoji", "city", "date")
    sets, vals = [], []
    for k in allowed:
        if k in fields:
            sets.append(f"{k}=%s"); vals.append(fields[k])
    if not sets:
        return {}
    conn = _get_conn()
    try:
        cur = conn.cursor()
        vals += [exp_id, user_id]
        cur.execute(f"UPDATE trip_expenses SET {', '.join(sets)} WHERE id=%s AND user_id=%s RETURNING *", vals)
        row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {}
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


# ─── Дурак ────────────────────────────────────────────────────────────────────

def init_durak_tables():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS durak_games (
                id             SERIAL PRIMARY KEY,
                code           VARCHAR(8) UNIQUE NOT NULL,
                status         VARCHAR(20) DEFAULT 'waiting',
                deck_size      INTEGER DEFAULT 36,
                max_players    INTEGER DEFAULT 2,
                variant        VARCHAR(20) DEFAULT 'podkidnoy',
                neighbors_only BOOLEAN DEFAULT FALSE,
                state          JSONB DEFAULT '{}',
                created_by     INTEGER REFERENCES users(id),
                created_at     TIMESTAMP DEFAULT NOW(),
                updated_at     TIMESTAMP DEFAULT NOW()
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS durak_players (
                id        SERIAL PRIMARY KEY,
                game_id   INTEGER REFERENCES durak_games(id) ON DELETE CASCADE,
                user_id   INTEGER REFERENCES users(id),
                seat      INTEGER,
                joined_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(game_id, user_id)
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_durak_players_game ON durak_players(game_id)")
        conn.commit()
    finally:
        conn.close()


def create_durak_game(code, created_by, deck_size, max_players, variant, neighbors_only):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO durak_games (code, created_by, deck_size, max_players, variant, neighbors_only)
            VALUES (%s, %s, %s, %s, %s, %s) RETURNING *
        """, (code, created_by, deck_size, max_players, variant, neighbors_only))
        game = dict(cur.fetchone())
        cur.execute("INSERT INTO durak_players (game_id, user_id, seat) VALUES (%s, %s, 0)",
                    (game['id'], created_by))
        conn.commit()
        return game
    finally:
        conn.close()


def get_durak_game(code):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM durak_games WHERE code = %s", (code,))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_durak_players(game_id):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT dp.*, u.display_name, u.username
            FROM durak_players dp JOIN users u ON dp.user_id = u.id
            WHERE dp.game_id = %s ORDER BY dp.seat
        """, (game_id,))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()


def join_durak_game(game_id, user_id, seat):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO durak_players (game_id, user_id, seat)
            VALUES (%s, %s, %s) ON CONFLICT DO NOTHING
        """, (game_id, user_id, seat))
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()


def save_durak_state(code, state, status=None):
    import json as _json
    conn = _get_conn()
    try:
        cur = conn.cursor()
        if status:
            cur.execute(
                "UPDATE durak_games SET state=%s, status=%s, updated_at=NOW() WHERE code=%s",
                (_json.dumps(state), status, code))
        else:
            cur.execute(
                "UPDATE durak_games SET state=%s, updated_at=NOW() WHERE code=%s",
                (_json.dumps(state), code))
        conn.commit()
    finally:
        conn.close()


# ─── UNO + 101 (общий шаблон) ─────────────────────────────────────────────────

def _init_card_game_tables(cur, prefix):
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {prefix}_games (
            id          SERIAL PRIMARY KEY,
            code        VARCHAR(8) UNIQUE NOT NULL,
            status      VARCHAR(20) DEFAULT 'waiting',
            max_players INTEGER DEFAULT 4,
            state       JSONB DEFAULT '{{}}',
            created_by  INTEGER REFERENCES users(id),
            created_at  TIMESTAMP DEFAULT NOW(),
            updated_at  TIMESTAMP DEFAULT NOW()
        )
    """)
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {prefix}_players (
            id       SERIAL PRIMARY KEY,
            game_id  INTEGER REFERENCES {prefix}_games(id) ON DELETE CASCADE,
            user_id  INTEGER REFERENCES users(id),
            seat     INTEGER,
            UNIQUE(game_id, user_id)
        )
    """)
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_{prefix}_players_game ON {prefix}_players(game_id)")


def init_uno_tables():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        _init_card_game_tables(cur, 'uno')
        conn.commit()
    finally:
        conn.close()


def init_game101_tables():
    conn = _get_conn()
    try:
        cur = conn.cursor()
        _init_card_game_tables(cur, 'game101')
        conn.commit()
    finally:
        conn.close()


def _create_card_game(prefix, code, created_by, max_players):
    import json as _json
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(f"""
            INSERT INTO {prefix}_games (code, created_by, max_players)
            VALUES (%s, %s, %s) RETURNING *
        """, (code, created_by, max_players))
        game = dict(cur.fetchone())
        cur.execute(f"INSERT INTO {prefix}_players (game_id, user_id, seat) VALUES (%s,%s,0)",
                    (game['id'], created_by))
        conn.commit()
        return game
    finally:
        conn.close()


def _get_card_game(prefix, code):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(f"SELECT * FROM {prefix}_games WHERE code=%s", (code,))
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def _get_card_game_players(prefix, game_id):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(f"""
            SELECT p.*, u.display_name, u.username
            FROM {prefix}_players p JOIN users u ON p.user_id=u.id
            WHERE p.game_id=%s ORDER BY p.seat
        """, (game_id,))
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()


def _join_card_game(prefix, game_id, user_id, seat):
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(f"""
            INSERT INTO {prefix}_players (game_id, user_id, seat)
            VALUES (%s,%s,%s) ON CONFLICT DO NOTHING
        """, (game_id, user_id, seat))
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()


def _save_card_game_state(prefix, code, state, status=None):
    import json as _json
    conn = _get_conn()
    try:
        cur = conn.cursor()
        if status:
            cur.execute(f"UPDATE {prefix}_games SET state=%s,status=%s,updated_at=NOW() WHERE code=%s",
                        (_json.dumps(state), status, code))
        else:
            cur.execute(f"UPDATE {prefix}_games SET state=%s,updated_at=NOW() WHERE code=%s",
                        (_json.dumps(state), code))
        conn.commit()
    finally:
        conn.close()


# Public wrappers
create_uno_game      = lambda code,uid,mp: _create_card_game('uno', code, uid, mp)
get_uno_game         = lambda code:        _get_card_game('uno', code)
get_uno_players      = lambda gid:         _get_card_game_players('uno', gid)
join_uno_game        = lambda gid,uid,seat:_join_card_game('uno', gid, uid, seat)
save_uno_state       = lambda code,st,status=None: _save_card_game_state('uno', code, st, status)

create_game101       = lambda code,uid,mp: _create_card_game('game101', code, uid, mp)
get_game101          = lambda code:        _get_card_game('game101', code)
get_game101_players  = lambda gid:         _get_card_game_players('game101', gid)
join_game101         = lambda gid,uid,seat:_join_card_game('game101', gid, uid, seat)
save_game101_state   = lambda code,st,status=None: _save_card_game_state('game101', code, st, status)
