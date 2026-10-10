"""Тесты «Итогов года». Запуск: cd backend && python -m pytest tests"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from wrapped import build_wrapped  # noqa: E402


def movie(title, added, rating=None, genres=(), cast=(), media="movie", director=None):
    return {
        "movie_id": hash(title) % 10000,
        "title": title,
        "added_at": added,
        "user_rating": rating,
        "genres": list(genres),
        "cast_names": list(cast),
        "media_type": media,
        "director": director,
        "poster_path": f"/{title}.jpg",
    }


def test_only_the_requested_year_is_counted():
    watched = [
        movie("Дюна", "2026-03-01 20:00:00", 9),
        movie("Интерстеллар", "2025-12-31 23:00:00", 10),
    ]
    result = build_wrapped(2026, watched, [], [], [])
    assert result["cinema"]["movies"] == 1
    assert [m["title"] for m in result["cinema"]["top_rated"]] == ["Дюна"]


def test_movies_and_shows_are_split_and_genres_ranked():
    watched = [
        movie("A", "2026-01-05", 8, genres=["Драма", "Комедия"]),
        movie("B", "2026-01-20", 6, genres=["Драма"]),
        movie("C", "2026-02-02", None, genres=[{"name": "Фантастика"}], media="tv"),
    ]
    cinema = build_wrapped(2026, watched, [], [], [])["cinema"]
    assert cinema["movies"] == 2
    assert cinema["shows"] == 1
    assert cinema["top_genres"][0] == {"name": "Драма", "count": 2}
    # Жанры приходят то строками, то объектами TMDB — оба понимаем.
    assert {"name": "Фантастика", "count": 1} in cinema["top_genres"]
    assert cinema["avg_rating"] == 7.0
    assert cinema["busiest_month"]["name"] == "январь"
    assert cinema["monthly"][:3] == [2, 1, 0]


def test_favourite_actors_come_from_cast_names():
    watched = [
        movie("A", "2026-04-01", cast=["Райан Гослинг", "Эмма Стоун"]),
        movie("B", "2026-05-01", cast=["Райан Гослинг"]),
    ]
    actors = build_wrapped(2026, watched, [], [], [])["cinema"]["top_actors"]
    assert actors[0] == {"name": "Райан Гослинг", "count": 2}


def test_books_pages_and_authors():
    books = [
        {"title": "Дюна", "author": "Герберт", "page_count": 700, "added_at": "2026-02-01", "user_rating": 10},
        {"title": "Мессия", "author": "Герберт", "page_count": None, "added_at": "2026-03-01", "user_rating": 7},
        {"title": "Старое", "author": "Кто-то", "page_count": 100, "added_at": "2024-03-01"},
    ]
    reading = build_wrapped(2026, [], books, [], [])["reading"]
    assert reading["count"] == 2
    assert reading["pages"] == 700  # пустое число страниц не роняет подсчёт
    assert reading["top_authors"][0] == {"name": "Герберт", "count": 2}
    assert reading["top_rated"][0]["title"] == "Дюна"


def test_money_includes_trips_as_their_own_category():
    expenses = [
        {"date": "2026-09-03", "amount": 1000, "cat_name": "Продукты", "cat_emoji": "🛒", "merchant": "Пятёрочка"},
        {"date": "2026-09-10", "amount": 500, "cat_name": "Продукты", "cat_emoji": "🛒", "merchant": "пятёрочка"},
        {"date": "2026-10-01", "amount": 300, "cat_name": None, "merchant": ""},
    ]
    trips = [
        {"id": 1, "name": "Вкусная еда", "event_type": "group", "start_date": "2026-09-17", "actual_total": 0},
        {"id": 2, "name": "Тбилиси", "event_type": "trip", "parent_id": 1,
         "start_date": "2026-09-26", "end_date": "2026-09-28", "actual_total": 7300},
    ]
    money = build_wrapped(2026, [], [], expenses, trips)["money"]
    assert money["own_total"] == 1800
    assert money["trips_total"] == 7300
    assert money["total"] == 9100
    assert money["by_category"][0]["name"] == "Поездки"
    assert {"name": "Без категории", "emoji": "💸", "amount": 300} in money["by_category"]
    # Один магазин, записанный в разном регистре, — одно место.
    assert money["top_merchant"]["count"] == 2
    assert money["biggest_month"]["name"] == "сентябрь"


def test_travel_lists_cities_not_groups_and_counts_days():
    trips = [
        {"id": 1, "name": "Вкусная еда", "event_type": "group", "start_date": "2026-09-17", "actual_total": 0},
        {"id": 2, "name": "Питер", "event_type": "trip", "parent_id": 1,
         "start_date": "2026-09-17", "end_date": "2026-09-19", "actual_total": 31900},
        # Перепутанные даты не дают отрицательных дней.
        {"id": 3, "name": "Алания", "event_type": "trip", "parent_id": 1,
         "start_date": "2026-09-27", "end_date": "2026-09-25", "actual_total": 35400},
        {"id": 4, "name": "Свадьба", "event_type": "event", "start_date": "2026-06-01", "actual_total": 50000},
    ]
    travel = build_wrapped(2026, [], [], [], trips)["travel"]
    assert [p["name"] for p in travel["places"]] == ["Питер", "Алания"]
    assert travel["places"][0]["trip"] == "Вкусная еда"
    assert travel["days"] == 3 + 3
    assert travel["spent"] == 31900 + 35400


def test_empty_year_is_flagged():
    result = build_wrapped(2026, [], [], [], [])
    assert result["has_data"] is False
    assert result["money"]["biggest_month"] is None
    assert result["title"] == "Всё только начинается"
