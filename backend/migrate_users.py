"""
Добавляет систему пользователей в Neon.
Запускать один раз: python -X utf8 migrate_users.py
"""
import os, psycopg2, psycopg2.extras
from dotenv import load_dotenv
load_dotenv()

def get_conn():
    url = os.getenv("DATABASE_URL", "").replace("postgres://", "postgresql://", 1)
    return psycopg2.connect(url, cursor_factory=psycopg2.extras.RealDictCursor)

def migrate():
    conn = get_conn()
    cur = conn.cursor()

    # 1. Создаём таблицу users
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id           SERIAL PRIMARY KEY,
            username     TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 2. Создаём AdminMihaylov
    cur.execute("""
        INSERT INTO users (username, display_name)
        VALUES ('AdminMihaylov', 'AdminMihaylov')
        ON CONFLICT (username) DO NOTHING
    """)
    cur.execute("SELECT id FROM users WHERE username = 'AdminMihaylov'")
    admin_id = cur.fetchone()["id"]
    print(f"AdminMihaylov id = {admin_id}")

    # 3. Добавляем user_id в watched
    cur.execute("ALTER TABLE watched ADD COLUMN IF NOT EXISTS user_id INTEGER DEFAULT 1")
    cur.execute(f"UPDATE watched SET user_id = {admin_id} WHERE user_id IS NULL OR user_id = 1")
    # Меняем UNIQUE constraint
    cur.execute("ALTER TABLE watched DROP CONSTRAINT IF EXISTS watched_movie_id_media_type_key")
    cur.execute("DROP INDEX IF EXISTS watched_movie_id_media_type_key")
    cur.execute("""
        DO $$ BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'watched_user_movie_media_key'
            ) THEN
                ALTER TABLE watched ADD CONSTRAINT watched_user_movie_media_key
                UNIQUE (user_id, movie_id, media_type);
            END IF;
        END $$
    """)
    print("✅ watched обновлён")

    # 4. Добавляем user_id в watchlist
    cur.execute("ALTER TABLE watchlist ADD COLUMN IF NOT EXISTS user_id INTEGER DEFAULT 1")
    cur.execute(f"UPDATE watchlist SET user_id = {admin_id} WHERE user_id IS NULL OR user_id = 1")
    cur.execute("ALTER TABLE watchlist DROP CONSTRAINT IF EXISTS watchlist_movie_id_media_type_key")
    cur.execute("""
        DO $$ BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'watchlist_user_movie_media_key'
            ) THEN
                ALTER TABLE watchlist ADD CONSTRAINT watchlist_user_movie_media_key
                UNIQUE (user_id, movie_id, media_type);
            END IF;
        END $$
    """)
    print("✅ watchlist обновлён")

    # 5. Добавляем user_id в dismissed
    cur.execute("ALTER TABLE dismissed ADD COLUMN IF NOT EXISTS user_id INTEGER DEFAULT 1")
    cur.execute(f"UPDATE dismissed SET user_id = {admin_id} WHERE user_id IS NULL OR user_id = 1")
    # dismissed имеет PRIMARY KEY(movie_id, media_type) — пересоздаём
    cur.execute("ALTER TABLE dismissed DROP CONSTRAINT IF EXISTS dismissed_pkey")
    cur.execute("""
        DO $$ BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'dismissed_pkey'
            ) THEN
                ALTER TABLE dismissed ADD PRIMARY KEY (user_id, movie_id, media_type);
            END IF;
        END $$
    """)
    print("✅ dismissed обновлён")

    # 6. Добавляем user_id в favorite_actors
    cur.execute("ALTER TABLE favorite_actors ADD COLUMN IF NOT EXISTS user_id INTEGER DEFAULT 1")
    cur.execute(f"UPDATE favorite_actors SET user_id = {admin_id} WHERE user_id IS NULL OR user_id = 1")
    cur.execute("ALTER TABLE favorite_actors DROP CONSTRAINT IF EXISTS favorite_actors_actor_id_key")
    cur.execute("""
        DO $$ BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'fav_actors_user_actor_key'
            ) THEN
                ALTER TABLE favorite_actors ADD CONSTRAINT fav_actors_user_actor_key
                UNIQUE (user_id, actor_id);
            END IF;
        END $$
    """)
    print("✅ favorite_actors обновлён")

    conn.commit()
    conn.close()
    print("\n🎉 Миграция завершена! AdminMihaylov id =", admin_id)

if __name__ == "__main__":
    migrate()
