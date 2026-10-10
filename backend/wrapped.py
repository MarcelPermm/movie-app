"""
wrapped.py — «Итоги года»: кино, книги, деньги и поездки за год одной сводкой.

Здесь только подсчёт: функция build_wrapped() получает уже загруженные
строки из базы и ничего не знает ни о базе, ни о сети. Так её легко
проверить тестами, а эндпоинт в main.py лишь собирает данные и зовёт её.
"""

from collections import Counter
from datetime import date, datetime

MONTHS_RU = [
    "январь", "февраль", "март", "апрель", "май", "июнь",
    "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь",
]


def _to_date(value):
    """Дата из строки, date или datetime. None, если разобрать не вышло."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _in_year(value, year: int) -> bool:
    d = _to_date(value)
    return d is not None and d.year == year


def _genre_name(g) -> str:
    if isinstance(g, str):
        return g
    if isinstance(g, dict):
        return g.get("name", "")
    return ""


def _busiest_month(dates) -> dict | None:
    """Месяц, в котором случилось больше всего событий."""
    counts = Counter(d.month for d in dates if d)
    if not counts:
        return None
    month, count = counts.most_common(1)[0]
    return {"month": month, "name": MONTHS_RU[month - 1], "count": count}


def _monthly(items, date_of, value_of=lambda _: 1) -> list:
    """Двенадцать чисел — по одному на месяц."""
    out = [0] * 12
    for item in items:
        d = _to_date(date_of(item))
        if d:
            out[d.month - 1] += value_of(item)
    return out


def _trip_days(trip) -> int:
    start, end = _to_date(trip.get("start_date")), _to_date(trip.get("end_date"))
    if not start:
        return 0
    if not end:
        return 1
    # Перепутанные даты (конец раньше начала) не должны давать минус.
    return abs((end - start).days) + 1


def build_wrapped(year: int, watched: list, books: list, expenses: list, trips: list) -> dict:
    """Сводка за год.

    watched  — строки таблицы watched (фильмы и сериалы вместе);
    books    — строки books_read;
    expenses — траты бюджета за год, с cat_name / cat_emoji;
    trips    — строки trips с actual_total (суммой всех трат поездки).
    """
    # ─── Кино ────────────────────────────────────────────────────────────
    seen = [m for m in watched if _in_year(m.get("added_at"), year)]
    movies = [m for m in seen if m.get("media_type", "movie") == "movie"]
    shows = [m for m in seen if m.get("media_type") == "tv"]
    rated = [m for m in seen if m.get("user_rating") is not None]

    genres = Counter(
        _genre_name(g) for m in seen for g in (m.get("genres") or []) if _genre_name(g)
    )
    actors = Counter(name for m in seen for name in (m.get("cast_names") or []) if name)
    directors = Counter(m["director"] for m in seen if m.get("director"))

    top_rated = sorted(
        rated,
        key=lambda m: (m["user_rating"], _to_date(m.get("added_at")) or date.min),
        reverse=True,
    )[:5]

    cinema = {
        "movies": len(movies),
        "shows": len(shows),
        "avg_rating": round(sum(m["user_rating"] for m in rated) / len(rated), 1) if rated else None,
        "top_genres": [{"name": n, "count": c} for n, c in genres.most_common(5)],
        "top_actors": [{"name": n, "count": c} for n, c in actors.most_common(5)],
        "top_directors": [{"name": n, "count": c} for n, c in directors.most_common(3)],
        "top_rated": [
            {
                "id": m.get("movie_id"),
                "title": m.get("title", ""),
                "rating": m["user_rating"],
                "poster_path": m.get("poster_path"),
                "media_type": m.get("media_type", "movie"),
            }
            for m in top_rated
        ],
        "busiest_month": _busiest_month(_to_date(m.get("added_at")) for m in seen),
        "monthly": _monthly(seen, lambda m: m.get("added_at")),
    }

    # ─── Книги ───────────────────────────────────────────────────────────
    read = [b for b in books if _in_year(b.get("added_at"), year)]
    rated_books = [b for b in read if b.get("user_rating") is not None]
    authors = Counter(b["author"] for b in read if b.get("author"))
    book_genres = Counter(
        _genre_name(g) for b in read for g in (b.get("genres") or []) if _genre_name(g)
    )
    best_books = sorted(rated_books, key=lambda b: b["user_rating"], reverse=True)[:3]

    reading = {
        "count": len(read),
        "pages": sum(int(b.get("page_count") or 0) for b in read),
        "top_authors": [{"name": n, "count": c} for n, c in authors.most_common(3)],
        "top_genres": [{"name": n, "count": c} for n, c in book_genres.most_common(3)],
        "top_rated": [
            {
                "title": b.get("title", ""),
                "author": b.get("author"),
                "cover": b.get("cover"),
                "rating": b["user_rating"],
            }
            for b in best_books
        ],
    }

    # ─── Поездки ─────────────────────────────────────────────────────────
    # Группа (многогородняя поездка) — только обёртка: места и траты в её
    # городах. События (свадьба, ремонт) — не путешествия.
    places = [
        t for t in trips
        if t.get("event_type", "trip") == "trip" and _in_year(t.get("start_date"), year)
    ]
    places.sort(key=lambda t: str(t.get("start_date") or ""))
    by_id = {t["id"]: t for t in trips if "id" in t}

    travel = {
        "count": len(places),
        "days": sum(_trip_days(t) for t in places),
        "spent": sum(int(t.get("actual_total") or 0) for t in places)
        + sum(
            # Траты, записанные прямо на группу, тоже деньги поездки.
            int(g.get("actual_total") or 0)
            for g in trips
            if g.get("event_type") == "group" and _in_year(g.get("start_date"), year)
        ),
        "places": [
            {
                "name": t.get("name", ""),
                "emoji": t.get("emoji") or "📍",
                "trip": (by_id.get(t.get("parent_id")) or {}).get("name"),
                "start_date": str(_to_date(t.get("start_date")) or ""),
                "end_date": str(_to_date(t.get("end_date")) or ""),
                "spent": int(t.get("actual_total") or 0),
            }
            for t in places
        ],
    }

    # ─── Деньги ──────────────────────────────────────────────────────────
    spent = [e for e in expenses if _in_year(e.get("date"), year)]
    own_total = sum(int(e.get("amount") or 0) for e in spent)

    categories: dict[str, dict] = {}
    for e in spent:
        name = e.get("cat_name") or "Без категории"
        slot = categories.setdefault(name, {"name": name, "emoji": e.get("cat_emoji") or "💸", "amount": 0})
        slot["amount"] += int(e.get("amount") or 0)
    if travel["spent"]:
        categories.setdefault("Поездки", {"name": "Поездки", "emoji": "✈️", "amount": 0})
        categories["Поездки"]["amount"] += travel["spent"]

    merchants: dict[str, dict] = {}
    for e in spent:
        name = (e.get("merchant") or "").strip()
        if not name:
            continue
        slot = merchants.setdefault(name.lower(), {"name": name, "amount": 0, "count": 0})
        slot["amount"] += int(e.get("amount") or 0)
        slot["count"] += 1
    top_merchant = max(merchants.values(), key=lambda m: m["count"], default=None)

    monthly_money = _monthly(spent, lambda e: e.get("date"), lambda e: int(e.get("amount") or 0))
    biggest = max(range(12), key=lambda i: monthly_money[i]) if any(monthly_money) else None

    money = {
        "total": own_total + travel["spent"],
        "own_total": own_total,
        "trips_total": travel["spent"],
        "by_category": sorted(categories.values(), key=lambda c: c["amount"], reverse=True)[:6],
        "top_merchant": top_merchant,
        "biggest_month": None if biggest is None else {
            "month": biggest + 1,
            "name": MONTHS_RU[biggest],
            "amount": monthly_money[biggest],
        },
        "monthly": monthly_money,
    }

    return {
        "year": year,
        "cinema": cinema,
        "reading": reading,
        "travel": travel,
        "money": money,
        "title": _persona(cinema, reading, travel),
        "has_data": bool(seen or read or spent or places),
    }


def _persona(cinema: dict, reading: dict, travel: dict) -> str:
    """Шутливое звание года — первая карточка итогов."""
    total_screen = cinema["movies"] + cinema["shows"]
    top_genre = cinema["top_genres"][0]["name"].lower() if cinema["top_genres"] else ""

    if travel["count"] >= 4:
        return "Кочевник года"
    if total_screen >= 100:
        return "Киноман без тормозов"
    if reading["count"] >= 20:
        return "Книжный марафонец"
    if "ужас" in top_genre:
        return "Любитель пощекотать нервы"
    if "комедия" in top_genre:
        return "Ценитель хорошего смеха"
    if "драма" in top_genre:
        return "Человек глубоких чувств"
    if "фантаст" in top_genre:
        return "Исследователь других миров"
    if total_screen or reading["count"]:
        return "Год со вкусом"
    return "Всё только начинается"
