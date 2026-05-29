"""
Переносит данные из локального SQLite в Neon PostgreSQL.
Запускать один раз: python migrate_to_neon.py
"""

import sqlite3
import json
import os
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

load_dotenv()

SQLITE_PATH = "favorites.db"

def get_pg_conn():
    url = os.getenv("DATABASE_URL", "")
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)
    return psycopg2.connect(url, cursor_factory=psycopg2.extras.RealDictCursor)

def migrate():
    sqlite = sqlite3.connect(SQLITE_PATH)
    sqlite.row_factory = sqlite3.Row
    pg = get_pg_conn()

    try:
        # ── watched ──────────────────────────────────────────────────────────
        rows = sqlite.execute("SELECT * FROM watched").fetchall()
        ok = skip = 0
        with pg.cursor() as cur:
            for r in rows:
                genres     = json.loads(r["genres"])     if r["genres"]     else []
                cast_names = json.loads(r["cast_names"]) if r["cast_names"] else []
                try:
                    cur.execute("""
                        INSERT INTO watched
                            (movie_id, title, genres, overview, poster_path,
                             vote_average, user_rating, review, director, cast_names,
                             added_at, media_type)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                        ON CONFLICT (movie_id, media_type) DO NOTHING
                    """, (
                        r["movie_id"], r["title"], genres, r["overview"], r["poster_path"],
                        r["vote_average"], r["user_rating"], r["review"], r["director"],
                        cast_names, r["added_at"], r["media_type"] or "movie"
                    ))
                    ok += 1
                except Exception as e:
                    print(f"  ⚠️  watched {r['title']}: {e}")
                    skip += 1
        pg.commit()
        print(f"✅ watched: {ok} перенесено, {skip} пропущено")

        # ── watchlist ─────────────────────────────────────────────────────────
        rows = sqlite.execute("SELECT * FROM watchlist").fetchall()
        ok = skip = 0
        with pg.cursor() as cur:
            for r in rows:
                genres = json.loads(r["genres"]) if r["genres"] else []
                try:
                    cur.execute("""
                        INSERT INTO watchlist
                            (movie_id, title, genres, overview, poster_path,
                             vote_average, added_at, media_type)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                        ON CONFLICT (movie_id, media_type) DO NOTHING
                    """, (
                        r["movie_id"], r["title"], genres, r["overview"], r["poster_path"],
                        r["vote_average"], r["added_at"], r["media_type"] or "movie"
                    ))
                    ok += 1
                except Exception as e:
                    print(f"  ⚠️  watchlist {r['title']}: {e}")
                    skip += 1
        pg.commit()
        print(f"✅ watchlist: {ok} перенесено, {skip} пропущено")

        # ── dismissed ─────────────────────────────────────────────────────────
        rows = sqlite.execute("SELECT * FROM dismissed").fetchall()
        ok = skip = 0
        with pg.cursor() as cur:
            for r in rows:
                genres      = json.loads(r["genres"])       if r["genres"]       else []
                cast_names  = json.loads(r["cast_names"])   if r["cast_names"]   else []
                studio_names= json.loads(r["studio_names"]) if r["studio_names"] else []
                try:
                    cur.execute("""
                        INSERT INTO dismissed
                            (movie_id, title, genres, cast_names, country,
                             studio_names, dismissed_at, media_type)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                        ON CONFLICT (movie_id, media_type) DO NOTHING
                    """, (
                        r["movie_id"], r["title"], genres, cast_names, r["country"],
                        studio_names, r["dismissed_at"], r["media_type"] or "movie"
                    ))
                    ok += 1
                except Exception as e:
                    print(f"  ⚠️  dismissed {r['title']}: {e}")
                    skip += 1
        pg.commit()
        print(f"✅ dismissed: {ok} перенесено, {skip} пропущено")

        # ── favorite_actors ───────────────────────────────────────────────────
        rows = sqlite.execute("SELECT * FROM favorite_actors").fetchall()
        ok = skip = 0
        with pg.cursor() as cur:
            for r in rows:
                try:
                    cur.execute("""
                        INSERT INTO favorite_actors
                            (actor_id, actor_name, profile_path, added_at)
                        VALUES (%s,%s,%s,%s)
                        ON CONFLICT (actor_id) DO NOTHING
                    """, (r["actor_id"], r["actor_name"], r["profile_path"], r["added_at"]))
                    ok += 1
                except Exception as e:
                    print(f"  ⚠️  actor {r['actor_name']}: {e}")
                    skip += 1
        pg.commit()
        print(f"✅ favorite_actors: {ok} перенесено, {skip} пропущено")

    finally:
        sqlite.close()
        pg.close()

    print("\n🎉 Миграция завершена!")

if __name__ == "__main__":
    migrate()
