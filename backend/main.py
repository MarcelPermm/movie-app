import os
import asyncio
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from dotenv import load_dotenv

import database
import recommender
import imdb_loader

load_dotenv()

TMDB_API_KEY = os.getenv("TMDB_API_KEY")
TMDB_BASE    = "https://api.themoviedb.org/3"

app = FastAPI(title="Movie Recommender API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

STUDIOS = [
    {"id": 2,    "name": "Walt Disney Pictures"},
    {"id": 3,    "name": "Pixar"},
    {"id": 420,  "name": "Marvel Studios"},
    {"id": 174,  "name": "Warner Bros."},
    {"id": 4,    "name": "Paramount Pictures"},
    {"id": 33,   "name": "Universal Pictures"},
    {"id": 5,    "name": "Columbia Pictures"},
    {"id": 21,   "name": "Metro-Goldwyn-Mayer"},
    {"id": 25,   "name": "20th Century Fox"},
    {"id": 923,  "name": "Legendary Pictures"},
    {"id": 7505, "name": "DC Studios"},
    {"id": 521,  "name": "DreamWorks Animation"},
    {"id": 6704, "name": "DreamWorks Pictures"},
    {"id": 1632, "name": "Lionsgate"},
    {"id": 315,  "name": "A24"},
    {"id": 9168, "name": "Bad Robot"},
]

TV_NETWORKS = [
    {"id": 213,  "name": "Netflix"},
    {"id": 49,   "name": "HBO"},
    {"id": 1024, "name": "Amazon Prime"},
    {"id": 2552, "name": "Apple TV+"},
    {"id": 453,  "name": "Hulu"},
    {"id": 2739, "name": "Disney+"},
    {"id": 67,   "name": "Showtime"},
    {"id": 88,   "name": "FX"},
    {"id": 174,  "name": "AMC"},
    {"id": 4,    "name": "BBC"},
    {"id": 6,    "name": "NBC"},
    {"id": 16,   "name": "CBS"},
    {"id": 2,    "name": "ABC"},
    {"id": 19,   "name": "FOX"},
    {"id": 43,   "name": "Cartoon Network"},
    {"id": 77,   "name": "Paramount+"},
]


@app.on_event("startup")
async def startup():
    database.init_db()
    imdb_loader.init_imdb_tables()
    print("✅ База данных готова")
    if not TMDB_API_KEY:
        print("⚠️  TMDB_API_KEY не найден!")
    # Загружаем IMDb данные в фоне (не блокируем старт)
    if imdb_loader.needs_update():
        print("📥 Запускаем загрузку IMDb данных в фоне...")
        asyncio.create_task(imdb_loader.download_and_load())
    else:
        print(f"✅ IMDb данные актуальны (обновлено: {imdb_loader.get_last_update().strftime('%d.%m.%Y')})")


async def tmdb_get(path: str, **params) -> dict:
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{TMDB_BASE}{path}",
            params={"api_key": TMDB_API_KEY, "language": "ru-RU", **params},
            timeout=15,
        )
        r.raise_for_status()
        return r.json()


# ─── Утилиты ──────────────────────────────────────────────────────────────────

def normalize_tv(item: dict) -> dict:
    """Приводит поля сериала к единому формату с фильмом."""
    item.setdefault("title", item.get("name", ""))
    item.setdefault("release_date", item.get("first_air_date", ""))
    return item


# ─── Жанры / студии ───────────────────────────────────────────────────────────

@app.get("/genres")
async def get_genres(media_type: str = "movie"):
    path = "/genre/tv/list" if media_type == "tv" else "/genre/movie/list"
    data = await tmdb_get(path)
    return data.get("genres", [])


@app.get("/studios")
async def get_studios(media_type: str = "movie"):
    return TV_NETWORKS if media_type == "tv" else STUDIOS


# ─── Поиск / популярные ───────────────────────────────────────────────────────

@app.get("/search/person")
async def search_persons(q: str):
    if not q.strip():
        raise HTTPException(400, "Пустой запрос")
    data = await tmdb_get("/search/person", query=q)
    return data.get("results", [])[:8]


@app.get("/search")
async def search_movies(q: str, media_type: str = "movie"):
    if not q.strip():
        raise HTTPException(400, "Пустой запрос")
    path = "/search/tv" if media_type == "tv" else "/search/movie"
    data = await tmdb_get(path, query=q)
    items = data.get("results", [])[:10]
    if media_type == "tv":
        items = [normalize_tv(m) for m in items]
    return [{**m,
             "is_watched":   database.is_watched(m["id"], media_type),
             "user_rating":  database.get_watched_rating(m["id"], media_type),
             "is_watchlist": database.is_watchlist(m["id"], media_type)} for m in items]


@app.get("/popular")
async def popular_movies(media_type: str = "movie"):
    path = "/tv/popular" if media_type == "tv" else "/movie/popular"
    data = await tmdb_get(path)
    items = data.get("results", [])
    if media_type == "tv":
        items = [normalize_tv(m) for m in items]
    return [{**m,
             "is_watched":   database.is_watched(m["id"], media_type),
             "user_rating":  database.get_watched_rating(m["id"], media_type),
             "is_watchlist": database.is_watchlist(m["id"], media_type)} for m in items]


# ─── Детали фильма / сериала ──────────────────────────────────────────────────

@app.get("/movie/{movie_id}/details")
async def movie_details(movie_id: int, media_type: str = "movie"):
    prefix = "/tv" if media_type == "tv" else "/movie"
    details, credits = await asyncio.gather(
        tmdb_get(f"{prefix}/{movie_id}"),
        tmdb_get(f"{prefix}/{movie_id}/credits"),
    )
    if media_type == "tv":
        normalize_tv(details)

    cast = [{"id": p["id"], "name": p["name"], "character": p.get("character", ""), "profile_path": p.get("profile_path")} for p in credits.get("cast", [])[:12]]
    director = director_id = None
    # Для сериалов берём создателей вместо режиссёра
    if media_type == "tv":
        creators = details.get("created_by", [])
        if creators:
            director = creators[0].get("name")
            director_id = creators[0].get("id")
    else:
        for p in credits.get("crew", []):
            if p.get("job") == "Director":
                director = p["name"]; director_id = p["id"]; break

    studios  = [{"id": c["id"], "name": c["name"], "logo": c.get("logo_path")} for c in details.get("production_companies", [])]
    countries = [c["iso_3166_1"] for c in details.get("production_countries", [])]

    watched_info = None
    for w in database.get_watched(media_type):
        if w["movie_id"] == movie_id:
            watched_info = {"user_rating": w.get("user_rating"), "review": w.get("review")}
            break

    out = {**details, "cast": cast, "director": director, "director_id": director_id,
           "studios": studios, "countries": countries,
           "is_watched":   database.is_watched(movie_id, media_type),
           "is_watchlist": database.is_watchlist(movie_id, media_type),
           "watched_info": watched_info}

    if media_type == "tv":
        out["seasons_count"]  = details.get("number_of_seasons")
        out["episodes_count"] = details.get("number_of_episodes")

    if imdb_loader.has_imdb_data():
        rd   = details.get("release_date") or ""
        year = int(rd[:4]) if len(rd) >= 4 else None
        orig = details.get("original_title") or details.get("original_name") or ""
        ttl  = details.get("title") or details.get("name") or ""
        imdb_stats = imdb_loader.get_imdb_stats_for_movie(orig, ttl, year)
        if imdb_stats:
            out["imdb_vote_count"] = int(imdb_stats["vote_count"])
            out["imdb_rating"]     = round(float(imdb_stats["rating"]), 1)

    return out


# ─── Актёр / режиссёр ─────────────────────────────────────────────────────────

@app.get("/person/{person_id}/movies")
async def person_movies(person_id: int, media_type: str = "movie"):
    credits_path = f"/person/{person_id}/tv_credits" if media_type == "tv" else f"/person/{person_id}/movie_credits"
    person, credits = await asyncio.gather(
        tmdb_get(f"/person/{person_id}"),
        tmdb_get(credits_path),
    )
    as_cast = credits.get("cast", [])
    as_crew = [m for m in credits.get("crew", []) if m.get("job") in ("Director", "Creator", "Executive Producer")]
    seen = set(); movies = []
    for m in sorted(as_cast + as_crew, key=lambda x: x.get("popularity", 0), reverse=True):
        if m["id"] not in seen and m.get("poster_path"):
            seen.add(m["id"])
            if media_type == "tv":
                normalize_tv(m)
            movies.append(m)
        if len(movies) >= 24: break
    return {"id": person["id"], "name": person["name"], "profile_path": person.get("profile_path"),
            "biography": person.get("biography", ""), "birthday": person.get("birthday"),
            "known_for_department": person.get("known_for_department", ""), "movies": movies}


# ─── Студия ───────────────────────────────────────────────────────────────────

@app.get("/studio/{studio_id}/movies")
async def studio_movies(studio_id: int, media_type: str = "movie"):
    path = "/discover/tv" if media_type == "tv" else "/discover/movie"
    data = await tmdb_get(path, with_companies=studio_id, sort_by="popularity.desc")
    items = data.get("results", [])[:20]
    if media_type == "tv":
        items = [normalize_tv(m) for m in items]
    return [{**m,
             "is_watched":   database.is_watched(m["id"], media_type),
             "is_watchlist": database.is_watchlist(m["id"], media_type)} for m in items]


# ─── Похожие / трейлер ────────────────────────────────────────────────────────

@app.get("/similar/{movie_id}")
async def similar_movies(movie_id: int, media_type: str = "movie"):
    prefix = "/tv" if media_type == "tv" else "/movie"
    data = await tmdb_get(f"{prefix}/{movie_id}/recommendations")
    items = data.get("results", [])[:10]
    if media_type == "tv":
        items = [normalize_tv(m) for m in items]
    return [{**m,
             "is_watched":   database.is_watched(m["id"], media_type),
             "is_watchlist": database.is_watchlist(m["id"], media_type)} for m in items]


@app.get("/trailer/{movie_id}")
async def get_trailer(movie_id: int, media_type: str = "movie"):
    prefix = "/tv" if media_type == "tv" else "/movie"
    data = await tmdb_get(f"{prefix}/{movie_id}/videos")
    def find(vids):
        for v in vids:
            if v.get("site") == "YouTube" and v.get("type") == "Trailer" and "official" in v.get("name","").lower(): return v.get("key")
        for v in vids:
            if v.get("site") == "YouTube" and v.get("type") == "Trailer": return v.get("key")
        for v in vids:
            if v.get("site") == "YouTube": return v.get("key")
        return None
    key = find(data.get("results", []))
    if not key:
        data_en = await tmdb_get(f"{prefix}/{movie_id}/videos", language="en-US")
        key = find(data_en.get("results", []))
    if not key: raise HTTPException(404, "Трейлер не найден")
    return {"key": key}


# ─── Серии сезона ─────────────────────────────────────────────────────────────

@app.get("/tv/{show_id}/season/{season_number}")
async def tv_season_episodes(show_id: int, season_number: int):
    data = await tmdb_get(f"/tv/{show_id}/season/{season_number}")
    return [
        {
            "episode_number": ep.get("episode_number"),
            "name":           ep.get("name", ""),
            "air_date":       ep.get("air_date", ""),
            "overview":       ep.get("overview", ""),
            "vote_average":   ep.get("vote_average"),
            "runtime":        ep.get("runtime"),
            "still_path":     ep.get("still_path"),
        }
        for ep in data.get("episodes", [])
    ]


# ─── Любимые актёры ──────────────────────────────────────────────────────────

@app.get("/watched/top-actors")
async def watched_top_actors(limit: int = 30):
    from collections import Counter
    all_watched = database.get_watched("movie") + database.get_watched("tv")
    actor_entries: dict[str, list] = {}
    for m in all_watched:
        for name in (m.get("cast_names") or []):
            if name not in actor_entries:
                actor_entries[name] = []
            actor_entries[name].append({
                "movie_id":   m["movie_id"],
                "title":      m.get("title", ""),
                "user_rating": m.get("user_rating"),
                "poster_path": m.get("poster_path", ""),
                "media_type":  m.get("media_type", "movie"),
            })
    sorted_actors = sorted(actor_entries.items(), key=lambda x: len(x[1]), reverse=True)[:limit]
    if not sorted_actors:
        return []
    fav_ids = {a["actor_id"] for a in database.get_favorite_actors()}
    search_results = await asyncio.gather(
        *[tmdb_get("/search/person", query=name) for name, _ in sorted_actors],
        return_exceptions=True,
    )
    actors = []
    for (name, movies), result in zip(sorted_actors, search_results):
        person_id = profile_path = None
        if not isinstance(result, Exception) and result.get("results"):
            p = result["results"][0]
            person_id    = p["id"]
            profile_path = p.get("profile_path")
        actors.append({
            "name":         name,
            "id":           person_id,
            "profile_path": profile_path,
            "movie_count":  len(movies),
            "is_favorite":  person_id in fav_ids if person_id else False,
            "movies":       sorted(movies, key=lambda x: x.get("user_rating") or 0, reverse=True),
        })
    return actors


@app.get("/person/{person_id}/watched-appearances")
async def person_watched_appearances(person_id: int):
    movie_credits, tv_credits = await asyncio.gather(
        tmdb_get(f"/person/{person_id}/movie_credits"),
        tmdb_get(f"/person/{person_id}/tv_credits"),
    )
    watched_movie = {m["movie_id"]: m for m in database.get_watched("movie")}
    watched_tv    = {m["movie_id"]: m for m in database.get_watched("tv")}
    seen: set[int] = set()
    results = []
    for item in movie_credits.get("cast", []) + movie_credits.get("crew", []):
        if item["id"] in watched_movie and item["id"] not in seen:
            seen.add(item["id"])
            w = watched_movie[item["id"]]
            results.append({**item, "media_type": "movie", "user_rating": w.get("user_rating")})
    for item in tv_credits.get("cast", []) + tv_credits.get("crew", []):
        if item["id"] in watched_tv and item["id"] not in seen:
            seen.add(item["id"])
            w = watched_tv[item["id"]]
            normalize_tv(item)
            results.append({**item, "media_type": "tv", "user_rating": w.get("user_rating")})
    return sorted(results, key=lambda x: x.get("user_rating") or 0, reverse=True)


class FavoriteActorRequest(BaseModel):
    actor_id:     int
    actor_name:   str
    profile_path: Optional[str] = None


@app.get("/favorite-actors")
async def get_favorite_actors():
    return database.get_favorite_actors()


@app.post("/favorite-actors")
async def add_favorite_actor(req: FavoriteActorRequest):
    database.add_favorite_actor(req.actor_id, req.actor_name, req.profile_path)
    return {"message": "Добавлен в избранные"}


@app.delete("/favorite-actors/{actor_id}")
async def remove_favorite_actor(actor_id: int):
    database.remove_favorite_actor(actor_id)
    return {"message": "Убран из избранных"}


# ─── Просмотренное ────────────────────────────────────────────────────────────

@app.get("/watched")
async def get_watched(media_type: str = "movie"):
    return database.get_watched(media_type)


class WatchedRequest(BaseModel):
    movie_id:   int
    media_type: str = "movie"

class RateRequest(BaseModel):
    movie_id:   int
    rating:     int
    media_type: str = "movie"
    review:     Optional[str] = None


@app.post("/watched")
async def add_watched(req: WatchedRequest):
    prefix = "/tv" if req.media_type == "tv" else "/movie"
    try:
        details, credits = await asyncio.gather(
            tmdb_get(f"{prefix}/{req.movie_id}"),
            tmdb_get(f"{prefix}/{req.movie_id}/credits"),
        )
    except httpx.HTTPError:
        raise HTTPException(404, "Не найдено")
    if req.media_type == "tv":
        normalize_tv(details)
    genres     = [g["name"] for g in details.get("genres", [])]
    director   = next((p["name"] for p in credits.get("crew", []) if p.get("job") == "Director"), None)
    if req.media_type == "tv" and not director:
        creators = details.get("created_by", [])
        director = creators[0].get("name") if creators else None
    cast_names = [p["name"] for p in credits.get("cast", [])[:5]]
    added = database.add_watched({
        "id": details["id"], "title": details["title"], "genres": genres,
        "overview": details.get("overview", ""), "poster_path": details.get("poster_path", ""),
        "vote_average": details.get("vote_average", 0.0),
        "director": director, "cast_names": cast_names,
    }, req.media_type)
    if not added: raise HTTPException(409, "Уже в просмотренном")
    return {"message": f"«{details['title']}» добавлено в просмотренное"}


@app.post("/watched/rate")
async def rate_watched(req: RateRequest):
    if not 1 <= req.rating <= 10:
        raise HTTPException(400, "Оценка от 1 до 10")
    if not database.is_watched(req.movie_id, req.media_type):
        prefix = "/tv" if req.media_type == "tv" else "/movie"
        try:
            details, credits = await asyncio.gather(
                tmdb_get(f"{prefix}/{req.movie_id}"),
                tmdb_get(f"{prefix}/{req.movie_id}/credits"),
            )
            if req.media_type == "tv":
                normalize_tv(details)
            genres     = [g["name"] for g in details.get("genres", [])]
            director   = next((p["name"] for p in credits.get("crew", []) if p.get("job") == "Director"), None)
            cast_names = [p["name"] for p in credits.get("cast", [])[:5]]
            database.add_watched({
                "id": details["id"], "title": details["title"], "genres": genres,
                "overview": details.get("overview", ""), "poster_path": details.get("poster_path", ""),
                "vote_average": details.get("vote_average", 0.0),
                "director": director, "cast_names": cast_names,
            }, req.media_type)
        except Exception:
            raise HTTPException(404, "Не найдено")
    if not database.rate_watched(req.movie_id, req.rating, req.review, req.media_type):
        raise HTTPException(404, "Не найдено в просмотренном")
    return {"message": "Оценка сохранена"}


@app.delete("/watched/{movie_id}")
async def remove_watched(movie_id: int, media_type: str = "movie"):
    if not database.remove_watched(movie_id, media_type): raise HTTPException(404, "Не найден")
    return {"message": "Удалено"}


# ─── К просмотру ──────────────────────────────────────────────────────────────

@app.get("/watchlist")
async def get_watchlist(media_type: str = "movie"):
    return database.get_watchlist(media_type)


class MovieRequest(BaseModel):
    movie_id:   int
    media_type: str = "movie"


@app.post("/watchlist")
async def add_watchlist(req: MovieRequest):
    prefix = "/tv" if req.media_type == "tv" else "/movie"
    try:
        item = await tmdb_get(f"{prefix}/{req.movie_id}")
    except httpx.HTTPError:
        raise HTTPException(404, "Не найден")
    if req.media_type == "tv":
        normalize_tv(item)
    genres = [g["name"] for g in item.get("genres", [])]
    added = database.add_watchlist({
        "id": item["id"], "title": item["title"], "genres": genres,
        "overview": item.get("overview", ""), "poster_path": item.get("poster_path", ""),
        "vote_average": item.get("vote_average", 0.0),
    }, req.media_type)
    if not added: raise HTTPException(409, "Уже в списке")
    return {"message": f"«{item['title']}» добавлен"}


@app.delete("/watchlist/{movie_id}")
async def remove_watchlist(movie_id: int, media_type: str = "movie"):
    if not database.remove_watchlist(movie_id, media_type): raise HTTPException(404, "Не найден")
    return {"message": "Удалено"}


# ─── Отклонённые ──────────────────────────────────────────────────────────────

@app.get("/dismissed")
async def get_dismissed(media_type: str = "movie"):
    return database.get_dismissed(media_type)


class DismissRequest(BaseModel):
    movie_id:   int
    media_type: str = "movie"


@app.post("/dismiss")
async def dismiss_movie(req: DismissRequest):
    prefix = "/tv" if req.media_type == "tv" else "/movie"
    try:
        details, credits = await asyncio.gather(
            tmdb_get(f"{prefix}/{req.movie_id}"),
            tmdb_get(f"{prefix}/{req.movie_id}/credits"),
        )
        if req.media_type == "tv":
            normalize_tv(details)
        cast_names   = [p["name"] for p in credits.get("cast", [])[:3]]
        country      = details.get("production_countries", [{}])[0].get("iso_3166_1") if details.get("production_countries") else None
        studio_names = [c["name"] for c in details.get("production_companies", [])[:3]]
        database.dismiss_movie({
            "id":           details["id"],
            "title":        details.get("title", ""),
            "genres":       [g["name"] for g in details.get("genres", [])],
            "cast_names":   cast_names,
            "country":      country,
            "studio_names": studio_names,
        }, req.media_type)
    except Exception:
        database.dismiss_movie({"id": req.movie_id, "title": "", "genres": [], "cast_names": [], "country": None, "studio_names": []}, req.media_type)
    return {"message": "Скрыто"}


@app.delete("/dismissed/{movie_id}")
async def undismiss_movie(movie_id: int, media_type: str = "movie"):
    database.remove_dismissed(movie_id, media_type)
    return {"message": "Возвращено"}


# ─── Рекомендации ─────────────────────────────────────────────────────────────

@app.get("/recommendations")
async def get_recommendations(country: str = "", studio_id: int = 0, media_type: str = "movie"):
    watched = database.get_watched(media_type)
    if not watched:
        raise HTTPException(400, "Добавь хотя бы один фильм в просмотренное")

    dismissed     = database.get_dismissed(media_type)
    dismissed_ids = {m["movie_id"] for m in dismissed}

    is_tv = media_type == "tv"
    discover_path = "/discover/tv" if is_tv else "/discover/movie"

    # ── Строим большой пул кандидатов (~2000 единиц) ──────────────────────────
    genre_map_data = await tmdb_get("/genre/tv/list" if is_tv else "/genre/movie/list")
    genre_map      = {g["id"]: g["name"] for g in genre_map_data["genres"]}

    from collections import Counter
    from datetime import date, timedelta

    tasks = []

    # country может быть "JP" или "JP,KR,RU" — список через запятую
    country_list = [c.strip().upper() for c in country.split(",") if c.strip()] if country else []
    country_mode = bool(country_list or studio_id)

    MIN_VOTES_TMDB  = 20
    MIN_VOTES_GENRE = 20
    MIN_VOTES_ACTOR = 20

    LOW_VOTE_COUNTRIES = {"RU", "TR"}
    if country_list and all(c in LOW_VOTE_COUNTRIES for c in country_list):
        IMDB_MIN_VOTES = 400
    elif country_mode:
        IMDB_MIN_VOTES = 1000
    else:
        IMDB_MIN_VOTES = 4000

    if studio_id:
        studio_base = {"with_networks": studio_id} if is_tv else {"with_companies": studio_id}
    else:
        studio_base = {}

    # ── Вычисляем топ жанры ────────────────────────────────────────────────
    genre_counts = Counter()
    for m in watched:
        weight = m.get("user_rating") or 5
        if weight >= 7:
            for g in m.get("genres", []):
                name = g if isinstance(g, str) else g.get("name", "")
                if name: genre_counts[name] += weight
    top_genres = [name for name, _ in genre_counts.most_common(5)]
    genre_name_to_id = {v: k for k, v in genre_map.items()}

    # ── Вычисляем топ актёры ───────────────────────────────────────────────
    actor_scores = Counter()
    for m in watched:
        weight = m.get("user_rating") or 0
        if weight >= 8:
            for a in (m.get("cast_names") or [])[:3]:
                actor_scores[a] += weight
    top_actors = [name for name, _ in actor_scores.most_common(5)]

    actor_search_tasks = [tmdb_get("/search/person", query=name) for name in top_actors]
    actor_results_raw = await asyncio.gather(*actor_search_tasks, return_exceptions=True)
    actor_ids = []
    for result in actor_results_raw:
        if isinstance(result, Exception): continue
        persons = result.get("results", [])
        if persons:
            actor_ids.append(persons[0]["id"])

    # ── Строим задачи для одного base-фильтра ─────────────────────────────
    recent_date_key = "first_air_date.gte" if is_tv else "primary_release_date.gte"
    recent_sort     = "first_air_date.desc" if is_tv else "primary_release_date.desc"
    rec_prefix      = "/tv" if is_tv else "/movie"
    on_air_path     = "/tv/on_the_air" if is_tv else "/movie/now_playing"

    def build_tasks(base, pp, pt, pr, pg, pa, global_mode=False):
        t = []
        if global_mode:
            top_w = sorted(
                [m for m in watched if (m.get("user_rating") or 0) >= 7],
                key=lambda m: m.get("user_rating") or 0, reverse=True
            )[:10]
            t += [tmdb_get(f"{rec_prefix}/{m['movie_id']}/recommendations", page=p)
                  for m in top_w for p in range(1, 4)]
            t += [tmdb_get(on_air_path, page=p) for p in range(1, pr + 1)]
        else:
            six_months_ago = (date.today() - timedelta(days=180)).strftime("%Y-%m-%d")
            t += [tmdb_get(discover_path, page=p,
                           sort_by=recent_sort,
                           **{recent_date_key: six_months_ago},
                           **base)
                  for p in range(1, pr + 1)]

        t += [tmdb_get(discover_path, page=p,
                       sort_by="popularity.desc",
                       **{"vote_count.gte": MIN_VOTES_TMDB}, **base)
              for p in range(1, pp + 1)]
        t += [tmdb_get(discover_path, page=p,
                       sort_by="vote_average.desc",
                       **{"vote_count.gte": MIN_VOTES_TMDB}, **base)
              for p in range(1, pt + 1)]

        for gname in top_genres:
            gid = genre_name_to_id.get(gname)
            if gid:
                t += [tmdb_get(discover_path, page=p,
                               with_genres=gid, sort_by="popularity.desc",
                               **{"vote_count.gte": MIN_VOTES_GENRE}, **base)
                      for p in range(1, pg + 1)]
        for pid in actor_ids:
            t += [tmdb_get(discover_path, page=p,
                           with_cast=pid, sort_by="popularity.desc",
                           **{"vote_count.gte": MIN_VOTES_ACTOR}, **base)
                  for p in range(1, pa + 1)]
        return t

    if not country_list:
        # ── Глобальный режим: полный пул ──────────────────────────────────
        tasks += build_tasks(studio_base, pp=30, pt=15, pr=5, pg=5, pa=4, global_mode=True)
    else:
        # ── Режим стран: для каждой страны — пропорционально уменьшенный пул
        n  = len(country_list)
        pp = max(5, 30 // n)
        pt = max(3, 15 // n)
        pr = max(2, 5  // n)
        pg = max(2, 5  // n)
        pa = max(2, 4  // n)
        print(f"🌍 Страны: {country_list}, страниц на страну: popular={pp} top={pt} recent={pr}")
        for sel_country in country_list:
            country_base = {"with_origin_country": sel_country, **studio_base}
            tasks += build_tasks(country_base, pp=pp, pt=pt, pr=pr, pg=pg, pa=pa)

    # ── Выполняем все запросы параллельно ─────────────────────────────────────
    results = await asyncio.gather(*tasks, return_exceptions=True)

    candidates = []
    for r in results:
        if isinstance(r, Exception): continue
        candidates.extend(r.get("results", []))

    # Убираем дубли
    seen   = set()
    unique = []
    for m in candidates:
        if m["id"] not in seen:
            seen.add(m["id"])
            unique.append(m)

    # Язык → страна (fallback когда TMDB не возвращает origin_country)
    _LANG_COUNTRY = {
        "en": "US", "ja": "JP", "ko": "KR", "zh": "CN", "fr": "FR",
        "de": "DE", "it": "IT", "es": "ES", "ru": "RU", "pt": "BR",
        "hi": "IN", "sv": "SE", "tr": "TR", "da": "DK", "no": "NO",
        "fi": "FI", "pl": "PL", "nl": "NL", "th": "TH", "ar": "EG",
    }

    # Добавляем жанры, нормализуем TV-поля и заполняем origin_country
    for movie in unique:
        movie["genres"] = [{"name": genre_map[gid]} for gid in movie.get("genre_ids", []) if gid in genre_map]
        if is_tv:
            normalize_tv(movie)
        if not movie.get("origin_country"):
            lang = movie.get("original_language", "")
            if lang in _LANG_COUNTRY:
                movie["origin_country"] = [_LANG_COUNTRY[lang]]

    label = "сериалов" if is_tv else "фильмов"
    print(f"📦 До IMDb фильтра: {len(unique)} {label}")

    # ── IMDb фильтр — убираем ноунеймов ───────────────────────────────────────
    if imdb_loader.has_imdb_data():
        min_votes = IMDB_MIN_VOTES

        filtered = []

        for movie in unique:
            title    = (movie.get("title") or "").strip()
            original = (movie.get("original_title") or movie.get("original_name") or "").strip()
            year     = int(movie.get("release_date", "0000")[:4]) if movie.get("release_date") else None
            imdb_stats = imdb_loader.get_imdb_stats_for_movie(original, title, year)

            if imdb_stats:
                # Нашли в IMDb — фильтруем по IMDb голосам
                if imdb_stats["vote_count"] >= min_votes:
                    movie["imdb_vote_count"] = int(imdb_stats["vote_count"])
                    movie["imdb_rating"]     = round(float(imdb_stats["rating"]), 1)
                    filtered.append(movie)
            else:
                # Не нашли в IMDb — фильтруем по TMDB голосам (порог выше, чем начальный)
                if movie.get("vote_count", 0) >= 100:
                    filtered.append(movie)

        unique = filtered
        print(f"📦 После IMDb фильтра: {len(unique)} фильмов (порог IMDb: {min_votes}, TMDB fallback: 100)")
    else:
        print("⚠️  IMDb данные ещё загружаются, используем TMDB vote_count")
        unique = [m for m in unique if m.get("vote_count", 0) >= 100]
        print(f"📦 После TMDB фильтра: {len(unique)} фильмов")

    print(f"📦 Итого кандидатов: {len(unique)} фильмов")

    recs = recommender.get_recommendations(
        watched      = watched,
        candidates   = unique,
        dismissed    = dismissed,
        top_n        = 2000,
        dismissed_ids = dismissed_ids,
    )

    return recs


@app.get("/")
async def root():
    return {"message": "Movie Recommender API работает!"}