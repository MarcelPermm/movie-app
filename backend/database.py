"""
database.py — отвечает за хранение избранных фильмов пользователя.
Используем SQLite: это обычный файл на диске, не нужен отдельный сервер.
"""

import sqlite3
import json
from pathlib import Path

DB_PATH = Path(__file__).parent / "favorites.db"


def get_connection():
    """Открывает соединение с базой данных."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row  # чтобы получать строки как словари
    return conn


def init_db():
    """Создаёт таблицу при первом запуске, если её ещё нет."""
    with get_connection() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS favorites (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                movie_id INTEGER UNIQUE NOT NULL,   -- ID фильма из TMDB
                title TEXT NOT NULL,
                genres TEXT NOT NULL,               -- хранится как JSON-строка
                overview TEXT,
                poster_path TEXT,
                vote_average REAL,
                added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()


def add_favorite(movie: dict) -> bool:
    """
    Добавляет фильм в избранное.
    Возвращает True если добавлен, False если уже был в избранном.
    """
    try:
        with get_connection() as conn:
            conn.execute("""
                INSERT INTO favorites (movie_id, title, genres, overview, poster_path, vote_average)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                movie["id"],
                movie["title"],
                json.dumps(movie.get("genres", [])),   # список → строка JSON
                movie.get("overview", ""),
                movie.get("poster_path", ""),
                movie.get("vote_average", 0.0),
            ))
            conn.commit()
            return True
    except sqlite3.IntegrityError:
        # UNIQUE ограничение: фильм уже в избранном
        return False


def remove_favorite(movie_id: int) -> bool:
    """Удаляет фильм из избранного по его TMDB ID."""
    with get_connection() as conn:
        cursor = conn.execute("DELETE FROM favorites WHERE movie_id = ?", (movie_id,))
        conn.commit()
        return cursor.rowcount > 0  # True если строка была удалена


def get_favorites() -> list[dict]:
    """Возвращает все фильмы из избранного."""
    with get_connection() as conn:
        rows = conn.execute("SELECT * FROM favorites ORDER BY added_at DESC").fetchall()
        result = []
        for row in rows:
            movie = dict(row)
            movie["genres"] = json.loads(movie["genres"])  # строка JSON → список
            result.append(movie)
        return result


def is_favorite(movie_id: int) -> bool:
    """Проверяет, находится ли фильм в избранном."""
    with get_connection() as conn:
        row = conn.execute(
            "SELECT 1 FROM favorites WHERE movie_id = ?", (movie_id,)
        ).fetchone()
        return row is not None
