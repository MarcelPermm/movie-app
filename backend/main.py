import os
import asyncio
import httpx
from fastapi import FastAPI, HTTPException, UploadFile, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from typing import Optional
from dotenv import load_dotenv

import database
import recommender
import imdb_loader

load_dotenv()

TMDB_API_KEY      = os.getenv("TMDB_API_KEY")
TMDB_BASE         = "https://api.themoviedb.org/3"
GOOGLE_BOOKS_API_KEY = os.getenv("GOOGLE_BOOKS_API_KEY")
GOOGLE_BOOKS_BASE = "https://www.googleapis.com/books/v1"

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
    database.init_imdb_map_table()
    database.init_books_tables()
    database.init_tasks_table()
    database.init_lists_tables()
    database.init_notes_table()
    database.init_budget_tables()
    database.init_trips_tables()
    print("✅ База данных готова")
    if not TMDB_API_KEY:
        print("⚠️  TMDB_API_KEY не найден!")
    try:
        imdb_loader.init_imdb_tables()
        if imdb_loader.needs_update():
            print("📥 Запускаем загрузку IMDb ratings в фоне (~8MB)...")
            asyncio.create_task(imdb_loader.download_and_load())
        else:
            last = imdb_loader.get_last_update()
            ts = last.strftime('%d.%m.%Y') if last else "неизвестно"
            print(f"✅ IMDb данные актуальны (обновлено: {ts})")
    except Exception as e:
        print(f"⚠️  IMDb недоступен: {e} — продолжаем без IMDb рейтингов")


@app.get("/health")
async def health_check():
    """Пинг для поддержания Render + Neon живыми. Делает SELECT 1 к БД.
    При мёртвом соединении автоматически сбрасывает пул и переподключается."""
    try:
        conn = database._get_conn()  # внутри уже валидирует и переподключает при надобности
        cur = conn.cursor()
        cur.execute("SELECT 1")
        conn.close()
        return {"ok": True, "db": "alive"}
    except Exception as e:
        # Последняя попытка — полный сброс пула
        try:
            database._reset_pool()
            conn = database._get_conn()
            conn.cursor().execute("SELECT 1")
            conn.close()
            return {"ok": True, "db": "reconnected"}
        except Exception as e2:
            return {"ok": False, "error": str(e2)}


async def tmdb_get(path: str, **params) -> dict:
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{TMDB_BASE}{path}",
            params={"api_key": TMDB_API_KEY, "language": "ru-RU", **params},
            timeout=15,
        )
        r.raise_for_status()
        return r.json()


# ─── Google Books helpers ─────────────────────────────────────────────────────

async def books_get(path: str, **params) -> dict:
    async with httpx.AsyncClient() as client:
        p = {**params}
        if GOOGLE_BOOKS_API_KEY:
            p["key"] = GOOGLE_BOOKS_API_KEY
        r = await client.get(f"{GOOGLE_BOOKS_BASE}{path}", params=p, timeout=15)
        r.raise_for_status()
        return r.json()


def normalize_book(item: dict) -> dict:
    vi = item.get("volumeInfo", {})
    # cover: prefer https, zoom=2 for larger thumbnail
    cover = ""
    img = vi.get("imageLinks", {})
    raw = img.get("thumbnail") or img.get("smallThumbnail") or ""
    if raw:
        cover = raw.replace("http://", "https://")
        if "zoom=" not in cover:
            cover += "&zoom=2" if "?" in cover else "?zoom=2"
        else:
            cover = cover.replace("zoom=1", "zoom=2")
    return {
        "id":             item.get("id", ""),
        "title":          vi.get("title", "Без названия"),
        "author":         ", ".join(vi.get("authors") or []),
        "cover":          cover,
        "description":    vi.get("description", ""),
        "rating":         vi.get("averageRating"),
        "ratings_count":  vi.get("ratingsCount"),
        "page_count":     vi.get("pageCount"),
        "published_date": vi.get("publishedDate", ""),
        "genres":         vi.get("categories") or [],
        "language":       vi.get("language", ""),
        "publisher":      vi.get("publisher", ""),
    }


_books_cache: dict = {}
_BOOKS_TTL = 3600


# ─── Утилиты ──────────────────────────────────────────────────────────────────

async def enrich_with_imdb(items: list, media_type: str = "movie", fetch_unknown: bool = False) -> list:
    """Добавляет imdb_rating / imdb_vote_count к каждому фильму из кэша.
    Если fetch_unknown=True — дополнительно запрашивает external_ids у TMDB
    для новых фильмов (используется только для коротких списков ~20 штук).
    """
    if not items or not imdb_loader.has_imdb_data():
        return items

    tmdb_ids = [m["id"] for m in items]

    # 1. Известные маппинги из кэша
    known_map = database.get_imdb_mappings_batch(tmdb_ids, media_type)

    # 2. Загружаем external_ids для незнакомых (только для коротких списков)
    if fetch_unknown:
        unknown_ids = [mid for mid in tmdb_ids if mid not in known_map]
        if unknown_ids:
            prefix = "/tv" if media_type == "tv" else "/movie"

            async def _fetch_ext(mid: int):
                try:
                    data = await tmdb_get(f"{prefix}/{mid}/external_ids")
                    iid  = data.get("imdb_id")
                    if iid:
                        database.save_imdb_mapping(mid, iid, media_type)
                        return (mid, iid)
                except Exception:
                    pass
                return (mid, None)

            results = await asyncio.gather(*[_fetch_ext(mid) for mid in unknown_ids])
            for tmdb_id, imdb_id in results:
                if imdb_id:
                    known_map[tmdb_id] = imdb_id

    # 3. Батч-поиск рейтингов IMDb
    imdb_ids   = list(set(known_map.values()))
    imdb_stats = imdb_loader.get_imdb_stats_batch(imdb_ids)

    # 4. Добавляем поля к каждому фильму
    enriched = []
    for item in items:
        imdb_id = known_map.get(item["id"])
        if imdb_id and imdb_id in imdb_stats:
            stats = imdb_stats[imdb_id]
            item  = {**item,
                     "imdb_rating":     round(stats["rating"], 1),
                     "imdb_vote_count": stats["vote_count"]}
        enriched.append(item)
    return enriched


def normalize_tv(item: dict) -> dict:
    """Приводит поля сериала к единому формату с фильмом."""
    item.setdefault("title", item.get("name", ""))
    item.setdefault("release_date", item.get("first_air_date", ""))
    return item


# ─── Авторизация ──────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    username:     str
    display_name: str

class LoginRequest(BaseModel):
    username: str

@app.post("/auth/register")
async def register(req: RegisterRequest):
    username     = req.username.strip().lower()
    display_name = req.display_name.strip()
    if not username or not display_name:
        raise HTTPException(400, "Логин и имя не могут быть пустыми")
    user = database.create_user(username, display_name)
    if not user:
        raise HTTPException(409, "Такой логин уже занят")
    return user

@app.post("/auth/login")
async def login(req: LoginRequest):
    user = database.get_user_by_username(req.username.strip().lower())
    if not user:
        raise HTTPException(404, "Пользователь не найден")
    return user


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
async def search_movies(q: str, media_type: str = "movie", user_id: int = 1):
    if not q.strip():
        raise HTTPException(400, "Пустой запрос")
    path = "/search/tv" if media_type == "tv" else "/search/movie"
    data = await tmdb_get(path, query=q)
    items = data.get("results", [])[:10]
    if media_type == "tv":
        items = [normalize_tv(m) for m in items]
    watched_map   = database.get_watched_map(media_type, user_id)
    watchlist_ids = database.get_watchlist_ids(media_type, user_id)
    return [{**m,
             "is_watched":   m["id"] in watched_map,
             "user_rating":  watched_map.get(m["id"], {}).get("user_rating"),
             "is_watchlist": m["id"] in watchlist_ids} for m in items]


# In-memory кэш популярного без user-specific полей.
# Раз в 10 мин обновляется фоном; обычно делает 1 TMDB + до 20 параллельных
# /external_ids для IMDb mapping — это самая дорогая часть homepage.
import time as _time
_popular_cache = {}   # {media_type: (timestamp, list[item_without_user_fields])}
_POPULAR_TTL = 600    # 10 минут


@app.get("/popular")
async def popular_movies(media_type: str = "movie", user_id: int = 1):
    now = _time.time()
    cached = _popular_cache.get(media_type)
    if cached and now - cached[0] < _POPULAR_TTL:
        items = cached[1]
    else:
        path = "/tv/popular" if media_type == "tv" else "/movie/popular"
        data = await tmdb_get(path)
        items = data.get("results", [])
        if media_type == "tv":
            items = [normalize_tv(m) for m in items]
        items = await enrich_with_imdb(items, media_type, fetch_unknown=True)
        _popular_cache[media_type] = (now, items)

    # User-specific аннотации добавляем на каждый запрос (это дёшево с пулом+индексами)
    watched_map   = database.get_watched_map(media_type, user_id)
    watchlist_ids = database.get_watchlist_ids(media_type, user_id)
    return [{**m,
             "is_watched":   m["id"] in watched_map,
             "user_rating":  watched_map.get(m["id"], {}).get("user_rating"),
             "is_watchlist": m["id"] in watchlist_ids} for m in items]


# ─── Детали фильма / сериала ──────────────────────────────────────────────────
# Кэш TMDB-части (не зависит от пользователя). user-specific (is_watched, оценка)
# добавляется на каждый запрос отдельно — это быстро (один DB-look-up).
_details_cache = {}    # {(movie_id, media_type): (timestamp, tmdb_only_dict)}
_DETAILS_TTL = 600     # 10 минут


async def _fetch_details_tmdb(movie_id: int, media_type: str) -> dict:
    """Возвращает кэшированный или свежезагруженный TMDB-блок деталей фильма."""
    cache_key = (movie_id, media_type)
    now = _time.time()
    cached = _details_cache.get(cache_key)
    if cached and now - cached[0] < _DETAILS_TTL:
        return cached[1]

    prefix = "/tv" if media_type == "tv" else "/movie"
    details, credits, ext_ids = await asyncio.gather(
        tmdb_get(f"{prefix}/{movie_id}"),
        tmdb_get(f"{prefix}/{movie_id}/credits"),
        tmdb_get(f"{prefix}/{movie_id}/external_ids"),
    )
    if media_type == "tv":
        normalize_tv(details)

    cast = [{"id": p["id"], "name": p["name"], "character": p.get("character", ""), "profile_path": p.get("profile_path")} for p in credits.get("cast", [])[:12]]
    director = director_id = None
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

    out = {**details, "cast": cast, "director": director, "director_id": director_id,
           "studios": studios, "countries": countries}

    if media_type == "tv":
        out["seasons_count"]  = details.get("number_of_seasons")
        out["episodes_count"] = details.get("number_of_episodes")

    imdb_id = ext_ids.get("imdb_id")
    if imdb_id:
        database.save_imdb_mapping(movie_id, imdb_id, media_type)
        if imdb_loader.has_imdb_data():
            imdb_stats = imdb_loader.get_imdb_stats_by_id(imdb_id)
            if imdb_stats:
                out["imdb_vote_count"] = int(imdb_stats["vote_count"])
                out["imdb_rating"]     = round(float(imdb_stats["rating"]), 1)

    _details_cache[cache_key] = (now, out)
    return out


@app.get("/movie/{movie_id}/details")
async def movie_details(movie_id: int, media_type: str = "movie", user_id: int = 1):
    out = dict(await _fetch_details_tmdb(movie_id, media_type))  # копия чтобы не мутировать кэш

    # User-specific аннотации добавляем на каждый запрос (дёшево с пулом+индексами)
    entry        = database.get_watched_entry(movie_id, media_type, user_id)
    watched_info = {"user_rating": entry["user_rating"], "review": entry["review"]} if entry else None
    out["is_watched"]   = entry is not None
    out["is_watchlist"] = database.is_watchlist(movie_id, media_type, user_id)
    out["watched_info"] = watched_info

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
async def studio_movies(studio_id: int, media_type: str = "movie", user_id: int = 1):
    path = "/discover/tv" if media_type == "tv" else "/discover/movie"
    data = await tmdb_get(path, with_companies=studio_id, sort_by="popularity.desc")
    items = data.get("results", [])[:20]
    if media_type == "tv":
        items = [normalize_tv(m) for m in items]
    watched_map   = database.get_watched_map(media_type, user_id)
    watchlist_ids = database.get_watchlist_ids(media_type, user_id)
    return [{**m,
             "is_watched":   m["id"] in watched_map,
             "is_watchlist": m["id"] in watchlist_ids} for m in items]


# ─── Похожие / трейлер ────────────────────────────────────────────────────────

@app.get("/similar/{movie_id}")
async def similar_movies(movie_id: int, media_type: str = "movie", user_id: int = 1):
    prefix = "/tv" if media_type == "tv" else "/movie"
    data = await tmdb_get(f"{prefix}/{movie_id}/recommendations")
    items = data.get("results", [])[:10]
    if media_type == "tv":
        items = [normalize_tv(m) for m in items]
    watched_map   = database.get_watched_map(media_type, user_id)
    watchlist_ids = database.get_watchlist_ids(media_type, user_id)
    return [{**m,
             "is_watched":   m["id"] in watched_map,
             "is_watchlist": m["id"] in watchlist_ids} for m in items]


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
async def watched_top_actors(limit: int = 30, user_id: int = 1):
    from collections import Counter
    all_watched = database.get_watched("movie", user_id) + database.get_watched("tv", user_id)
    actor_entries:     dict[str, list] = {}
    actor_movie_count: dict[str, int]  = {}
    actor_tv_count:    dict[str, int]  = {}
    for m in all_watched:
        mt = m.get("media_type", "movie")
        for name in (m.get("cast_names") or []):
            if name not in actor_entries:
                actor_entries[name]     = []
                actor_movie_count[name] = 0
                actor_tv_count[name]    = 0
            actor_entries[name].append({
                "movie_id":    m["movie_id"],
                "title":       m.get("title", ""),
                "user_rating": m.get("user_rating"),
                "poster_path": m.get("poster_path", ""),
                "media_type":  mt,
            })
            if mt == "tv":
                actor_tv_count[name]    += 1
            else:
                actor_movie_count[name] += 1

    sorted_actors = sorted(actor_entries.items(), key=lambda x: len(x[1]), reverse=True)[:limit]
    if not sorted_actors:
        return []
    fav_ids = {a["actor_id"] for a in database.get_favorite_actors(user_id)}
    search_results = await asyncio.gather(
        *[tmdb_get("/search/person", query=name) for name, _ in sorted_actors],
        return_exceptions=True,
    )
    actors = []
    for (name, movies_list), result in zip(sorted_actors, search_results):
        person_id = profile_path = None
        if not isinstance(result, Exception) and result.get("results"):
            p = result["results"][0]
            person_id    = p["id"]
            profile_path = p.get("profile_path")
        actors.append({
            "name":         name,
            "id":           person_id,
            "profile_path": profile_path,
            "movie_count":  actor_movie_count.get(name, 0),
            "tv_count":     actor_tv_count.get(name, 0),
            "is_favorite":  person_id in fav_ids if person_id else False,
            "movies":       sorted(movies_list, key=lambda x: x.get("user_rating") or 0, reverse=True),
        })
    return actors


@app.get("/person/{person_id}/watched-appearances")
async def person_watched_appearances(person_id: int, user_id: int = 1):
    movie_credits, tv_credits = await asyncio.gather(
        tmdb_get(f"/person/{person_id}/movie_credits"),
        tmdb_get(f"/person/{person_id}/tv_credits"),
    )
    watched_movie = {m["movie_id"]: m for m in database.get_watched("movie", user_id)}
    watched_tv    = {m["movie_id"]: m for m in database.get_watched("tv", user_id)}
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
    user_id:      int = 1


@app.get("/favorite-actors")
async def get_favorite_actors(user_id: int = 1):
    return database.get_favorite_actors(user_id)


@app.post("/favorite-actors")
async def add_favorite_actor(req: FavoriteActorRequest):
    database.add_favorite_actor(req.actor_id, req.actor_name, req.profile_path, req.user_id)
    return {"message": "Добавлен в избранные"}


@app.delete("/favorite-actors/{actor_id}")
async def remove_favorite_actor(actor_id: int, user_id: int = 1):
    database.remove_favorite_actor(actor_id, user_id)
    return {"message": "Убран из избранных"}


# ─── Просмотренное ────────────────────────────────────────────────────────────

@app.get("/watched")
async def get_watched(media_type: str = "movie", user_id: int = 1):
    items = database.get_watched(media_type, user_id)
    for m in items:
        m["id"] = m.get("movie_id")
    # fetch_unknown=False: используем только закэшированные маппинги, не идём в TMDB
    items = await enrich_with_imdb(items, media_type, fetch_unknown=False)
    return items


class WatchedRequest(BaseModel):
    movie_id:   int
    media_type: str = "movie"
    user_id:    int = 1

class RateRequest(BaseModel):
    movie_id:     int
    rating:       int
    media_type:   str = "movie"
    review:       Optional[str] = None
    user_id:      int = 1
    platform:     Optional[str] = None
    watched_date: Optional[str] = None


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
    }, req.media_type, req.user_id)
    if not added: raise HTTPException(409, "Уже в просмотренном")
    return {"message": f"«{details['title']}» добавлено в просмотренное"}


@app.post("/watched/rate")
async def rate_watched(req: RateRequest):
    if not 1 <= req.rating <= 10:
        raise HTTPException(400, "Оценка от 1 до 10")
    if not database.is_watched(req.movie_id, req.media_type, req.user_id):
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
            }, req.media_type, req.user_id)
        except Exception:
            raise HTTPException(404, "Не найдено")
    if not database.rate_watched(req.movie_id, req.rating, req.review, req.media_type, req.user_id,
                                  platform=req.platform, watched_date=req.watched_date):
        raise HTTPException(404, "Не найдено в просмотренном")
    return {"message": "Оценка сохранена"}


@app.delete("/watched/{movie_id}")
async def remove_watched(movie_id: int, media_type: str = "movie", user_id: int = 1):
    if not database.remove_watched(movie_id, media_type, user_id): raise HTTPException(404, "Не найден")
    return {"message": "Удалено"}


# ─── К просмотру ──────────────────────────────────────────────────────────────

@app.get("/watchlist")
async def get_watchlist(media_type: str = "movie", user_id: int = 1):
    items = database.get_watchlist(media_type, user_id)
    for m in items:
        m["id"] = m.get("movie_id")
    # fetch_unknown=False: используем только закэшированные маппинги, не идём в TMDB
    items = await enrich_with_imdb(items, media_type, fetch_unknown=False)
    return items


class MovieRequest(BaseModel):
    movie_id:   int
    media_type: str = "movie"
    user_id:    int = 1


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
    release_date = item.get("release_date") or item.get("first_air_date", "")
    release_year = int(release_date[:4]) if release_date and len(release_date) >= 4 else None
    prod_countries = item.get("production_countries", [])
    country = prod_countries[0]["iso_3166_1"] if prod_countries else None
    added = database.add_watchlist({
        "id": item["id"], "title": item["title"], "genres": genres,
        "overview": item.get("overview", ""), "poster_path": item.get("poster_path", ""),
        "vote_average": item.get("vote_average", 0.0),
        "release_year": release_year,
        "country": country,
    }, req.media_type, req.user_id)
    if not added: raise HTTPException(409, "Уже в списке")
    return {"message": f"«{item['title']}» добавлен"}


class WatchlistCategoryUpdate(BaseModel):
    category:   str
    media_type: str = "movie"
    user_id:    int = 1


@app.patch("/watchlist/{movie_id}/category")
async def update_watchlist_category(movie_id: int, req: WatchlistCategoryUpdate):
    if req.category not in {"must_see", "not_sure", "last_resort"}:
        raise HTTPException(400, "Недопустимая категория")
    updated = database.update_watchlist_category(movie_id, req.category, req.media_type, req.user_id)
    if not updated:
        raise HTTPException(404, "Не найден")
    return {"message": "Категория обновлена"}


@app.delete("/watchlist/{movie_id}")
async def remove_watchlist(movie_id: int, media_type: str = "movie", user_id: int = 1):
    if not database.remove_watchlist(movie_id, media_type, user_id): raise HTTPException(404, "Не найден")
    return {"message": "Удалено"}


# ─── Отклонённые ──────────────────────────────────────────────────────────────

@app.get("/dismissed")
async def get_dismissed(media_type: str = "movie", user_id: int = 1):
    return database.get_dismissed(media_type, user_id)


class DismissRequest(BaseModel):
    movie_id:   int
    media_type: str = "movie"
    user_id:    int = 1


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
        }, req.media_type, req.user_id)
    except Exception:
        database.dismiss_movie({"id": req.movie_id, "title": "", "genres": [], "cast_names": [], "country": None, "studio_names": []}, req.media_type, req.user_id)
    return {"message": "Скрыто"}


@app.delete("/dismissed/{movie_id}")
async def undismiss_movie(movie_id: int, media_type: str = "movie", user_id: int = 1):
    database.remove_dismissed(movie_id, media_type, user_id)
    return {"message": "Возвращено"}


# ─── Книги ────────────────────────────────────────────────────────────────────

class BookReadRequest(BaseModel):
    book_id: str
    user_id: int = 1

class BookRateRequest(BaseModel):
    book_id: str
    rating:  int
    review:  Optional[str] = None
    user_id: int = 1

class BookWishlistRequest(BaseModel):
    book_id: str
    user_id: int = 1


@app.get("/books/popular")
async def books_popular(user_id: int = 1):
    now = _time.time()
    cached = _books_cache.get("popular")
    if cached and now - cached[0] < _BOOKS_TTL:
        items = cached[1]
    else:
        queries = [
            "bestseller fiction novel",
            "award winning thriller",
            "classic literature must read",
        ]
        results = await asyncio.gather(
            *[books_get("/volumes", q=q, maxResults=20, orderBy="relevance") for q in queries],
            return_exceptions=True,
        )
        seen: set = set()
        items = []
        for res in results:
            if isinstance(res, Exception):
                continue
            for item in res.get("items", []):
                bid = item.get("id")
                if not bid or bid in seen:
                    continue
                b = normalize_book(item)
                vi = item.get("volumeInfo", {})
                if b["cover"] and (b["description"] or vi.get("description")):
                    seen.add(bid)
                    items.append(b)
        _books_cache["popular"] = (now, items)

    read_ids    = {r["book_id"] for r in database.get_books_read(user_id)}
    wish_ids    = {w["book_id"] for w in database.get_books_wishlist(user_id)}
    return [{**b, "is_read": b["id"] in read_ids, "is_wishlist": b["id"] in wish_ids} for b in items]


@app.get("/books/search")
async def books_search(q: str = "", user_id: int = 1):
    if not q.strip():
        raise HTTPException(400, "Пустой запрос")
    data = await books_get("/volumes", q=q, maxResults=20, printType="books", orderBy="relevance")
    items = [normalize_book(i) for i in data.get("items", [])]
    read_ids = {r["book_id"] for r in database.get_books_read(user_id)}
    wish_ids = {w["book_id"] for w in database.get_books_wishlist(user_id)}
    return [{**b, "is_read": b["id"] in read_ids, "is_wishlist": b["id"] in wish_ids} for b in items]


@app.get("/books/read")
async def get_books_read(user_id: int = 1):
    return database.get_books_read(user_id)


@app.post("/books/read")
async def add_book_read(req: BookReadRequest):
    try:
        data = await books_get(f"/volumes/{req.book_id}")
        book = normalize_book(data)
    except Exception:
        raise HTTPException(404, "Книга не найдена в Google Books")
    added = database.add_book_read(book, req.user_id)
    if not added:
        raise HTTPException(409, "Уже в прочитанных")
    return {"message": f"«{book['title']}» добавлена в прочитанные"}


@app.post("/books/read/rate")
async def rate_book(req: BookRateRequest):
    if not 1 <= req.rating <= 10:
        raise HTTPException(400, "Оценка от 1 до 10")
    # auto-add if not read yet
    if not database.is_book_read(req.book_id, req.user_id):
        try:
            data = await books_get(f"/volumes/{req.book_id}")
            book = normalize_book(data)
            database.add_book_read(book, req.user_id)
        except Exception:
            raise HTTPException(404, "Книга не найдена")
    if not database.rate_book(req.book_id, req.rating, req.review, req.user_id):
        raise HTTPException(404, "Не найдено в прочитанных")
    return {"message": "Оценка сохранена"}


@app.delete("/books/read/{book_id}")
async def remove_book_read(book_id: str, user_id: int = 1):
    if not database.remove_book_read(book_id, user_id):
        raise HTTPException(404, "Не найдено")
    return {"message": "Удалено"}


@app.get("/books/wishlist")
async def get_books_wishlist(user_id: int = 1):
    return database.get_books_wishlist(user_id)


@app.post("/books/wishlist")
async def add_book_wishlist(req: BookWishlistRequest):
    try:
        data = await books_get(f"/volumes/{req.book_id}")
        book = normalize_book(data)
    except Exception:
        raise HTTPException(404, "Книга не найдена в Google Books")
    added = database.add_book_wishlist(book, req.user_id)
    if not added:
        raise HTTPException(409, "Уже в списке")
    return {"message": f"«{book['title']}» добавлена в список"}


@app.delete("/books/wishlist/{book_id}")
async def remove_book_wishlist(book_id: str, user_id: int = 1):
    if not database.remove_book_wishlist(book_id, user_id):
        raise HTTPException(404, "Не найдено")
    return {"message": "Удалено"}


@app.get("/books/suggest")
async def books_suggest(query: str = "", user_id: int = 1):
    api_key = os.getenv("CEREBRAS_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI недоступен")

    import json, re
    from openai import AsyncOpenAI

    read_books = database.get_books_read(user_id)
    read_titles = [b["title"] for b in read_books if b.get("title")][:30]
    already_read = ", ".join(read_titles) if read_titles else "none"

    example = '[{"title": "The Name of the Wind", "author": "Patrick Rothfuss", "year": 2007, "reason": "Одна фраза"}]'

    if query.strip():
        prompt = f"""You are a strict book recommendation engine. Follow the user's request EXACTLY.

USER REQUEST: "{query}"

ALREADY READ (NEVER recommend): {already_read}

Recommend exactly 12 books strictly matching the USER REQUEST.
OUTPUT: ONLY a raw JSON array. Original English titles. reason in Russian, one short sentence.
Example: {example}"""
    else:
        author_counts = {}
        genre_counts = {}
        for b in read_books:
            if b.get("author"): author_counts[b["author"]] = author_counts.get(b["author"], 0) + 1
            for g in (b.get("genres") or []): genre_counts[g] = genre_counts.get(g, 0) + 1
        top_authors = [a for a,_ in sorted(author_counts.items(), key=lambda x: -x[1])[:5]]
        top_genres  = [g for g,_ in sorted(genre_counts.items(),  key=lambda x: -x[1])[:5]]

        prompt = f"""You are a book expert. Recommend books based on reading history.

Favorite authors: {", ".join(top_authors) if top_authors else "various"}
Favorite genres: {", ".join(top_genres) if top_genres else "various"}
ALREADY READ (DO NOT recommend): {already_read}

Recommend exactly 12 books the user hasn't read yet.
OUTPUT: ONLY a raw JSON array. Original English titles. reason in Russian.
Example: {example}"""

    client = AsyncOpenAI(api_key=api_key, base_url="https://api.cerebras.ai/v1")
    try:
        response = await client.chat.completions.create(
            model="gpt-oss-120b",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=2500,
            temperature=0.7 if query else 0.9,
        )
        raw = response.choices[0].message.content.strip()
        raw = re.sub(r'^```[a-z]*\s*', '', raw)
        raw = re.sub(r'\s*```$', '', raw).strip()
        match_json = re.search(r'\[.*\]', raw, re.DOTALL)
        if not match_json:
            raise HTTPException(503, "AI не вернул JSON")
        suggestions = json.loads(match_json.group())
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(503, f"Ошибка AI: {str(e)}")

    async def lookup(h, item):
        title = item.get("title", "").strip()
        author = item.get("author", "").strip()
        reason = item.get("reason", "")
        if not title: return None
        try:
            q = f"{title} {author}".strip()
            params = {"key": GOOGLE_BOOKS_API_KEY, "q": q, "maxResults": 3, "printType": "books"}
            r = await h.get(f"{GOOGLE_BOOKS_BASE}/volumes", params=params)
            items_data = r.json().get("items", [])
            if not items_data: return None
            book = normalize_book(items_data[0])
            book["ai_reason"] = reason
            read_ids = {b["book_id"] for b in database.get_books_read(user_id)}
            book["is_read"] = book["id"] in read_ids
            book["is_wishlist"] = database.is_book_wishlist(book["id"], user_id)
            return book
        except Exception:
            return None

    async with httpx.AsyncClient(timeout=30) as h:
        results = await asyncio.gather(*[lookup(h, s) for s in suggestions[:12]])
    books = [r for r in results if r]
    return {"books": books}


@app.get("/books/{book_id}/details")
async def book_details(book_id: str, user_id: int = 1):
    try:
        data = await books_get(f"/volumes/{book_id}")
        book = normalize_book(data)
    except Exception:
        raise HTTPException(404, "Книга не найдена")
    entry = database.get_book_read_entry(book_id, user_id)
    book["is_read"]      = entry is not None
    book["is_wishlist"]  = database.is_book_wishlist(book_id, user_id)
    book["user_rating"]  = entry["user_rating"] if entry else None
    book["review"]       = entry["review"] if entry else None
    return book


@app.get("/books/{book_id}/similar")
async def book_similar(book_id: str):
    try:
        data  = await books_get(f"/volumes/{book_id}")
        vi    = data.get("volumeInfo", {})
        cats  = vi.get("categories") or []
        authors = vi.get("authors") or []
        q = cats[0] if cats else (authors[0] if authors else "")
        if not q:
            return []
        res = await books_get("/volumes", q=q, maxResults=12)
        items = [normalize_book(i) for i in res.get("items", []) if i.get("id") != book_id]
        return [b for b in items if b["cover"]][:8]
    except Exception:
        return []


# ─── Рекомендации ─────────────────────────────────────────────────────────────

@app.get("/recommendations")
async def get_recommendations(country: str = "", studio_id: int = 0, media_type: str = "movie", user_id: int = 1):
    watched = database.get_watched(media_type, user_id)
    if not watched:
        raise HTTPException(400, "Добавь хотя бы один фильм в просмотренное")

    dismissed     = database.get_dismissed(media_type, user_id)
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
    print(f"📦 До фильтра: {len(unique)} {label}")

    # ── Фильтр по TMDB vote_count — убираем ноунеймов ────────────────────────
    # IMDb рейтинг показывается в деталях фильма через /external_ids,
    # но для фильтрации 2000 кандидатов используем TMDB vote_count как прокси.
    min_tmdb = 50 if country_mode else 100
    unique = [m for m in unique if m.get("vote_count", 0) >= min_tmdb]
    print(f"📦 После фильтра: {len(unique)} {label} (TMDB vote_count >= {min_tmdb})")

    print(f"📦 Итого кандидатов: {len(unique)} фильмов")

    recs = recommender.get_recommendations(
        watched      = watched,
        candidates   = unique,
        dismissed    = dismissed,
        top_n        = 2000,
        dismissed_ids = dismissed_ids,
    )

    recs = await enrich_with_imdb(recs, media_type, fetch_unknown=False)
    return recs


# ─── Профиль / статистика ─────────────────────────────────────────────────────

@app.get("/profile/stats")
async def get_profile_stats(user_id: int = 1):
    from collections import Counter

    movies = database.get_watched("movie", user_id)
    tv     = database.get_watched("tv",    user_id)
    all_watched = movies + tv

    if not all_watched:
        return {"total": 0, "movies": 0, "tv": 0}

    def genre_name(g):
        if isinstance(g, str):  return g
        if isinstance(g, dict): return g.get("name", "")
        return ""

    # Рейтинги — раздельно по типу
    movie_rated = [m for m in movies if m.get("user_rating") is not None]
    tv_rated    = [m for m in tv     if m.get("user_rating") is not None]
    all_rated   = movie_rated + tv_rated
    avg_rating  = round(sum(m["user_rating"] for m in all_rated) / len(all_rated), 1) if all_rated else None

    rating_dist = {
        str(i): {
            "movie": sum(1 for m in movie_rated if m["user_rating"] == i),
            "tv":    sum(1 for m in tv_rated    if m["user_rating"] == i),
        } for i in range(1, 11)
    }

    # Жанры — раздельно по типу
    movie_genre_cnt = Counter(genre_name(g) for m in movies for g in (m.get("genres") or []) if genre_name(g))
    tv_genre_cnt    = Counter(genre_name(g) for m in tv     for g in (m.get("genres") or []) if genre_name(g))
    all_genre_names = set(list(movie_genre_cnt.keys()) + list(tv_genre_cnt.keys()))
    top_genres = sorted(
        [{"name": n,
          "movie_count": movie_genre_cnt.get(n, 0),
          "tv_count":    tv_genre_cnt.get(n, 0),
          "total":       movie_genre_cnt.get(n, 0) + tv_genre_cnt.get(n, 0)}
         for n in all_genre_names],
        key=lambda x: x["total"], reverse=True
    )[:8]

    # Режиссёры
    all_directors = [m["director"] for m in all_watched if m.get("director")]

    # Топ по оценке пользователя
    top_rated = sorted(
        [m for m in all_watched if m.get("user_rating") is not None],
        key=lambda x: x["user_rating"], reverse=True
    )[:6]

    # Monthly stats grouped by watched_date or added_at
    from datetime import datetime as dt
    monthly = {}
    for m in all_watched:
        raw = m.get("watched_date") or m.get("added_at")
        if raw:
            try:
                key = str(raw)[:7]  # "YYYY-MM"
                dt.strptime(key, "%Y-%m")
                if key not in monthly:
                    monthly[key] = {"movie": 0, "tv": 0}
                if m.get("media_type") == "tv":
                    monthly[key]["tv"] += 1
                else:
                    monthly[key]["movie"] += 1
            except Exception:
                pass

    # Platform stats
    platform_cnt = Counter(m.get("platform") for m in all_watched if m.get("platform"))

    return {
        "total":               len(all_watched),
        "movies":              len(movies),
        "tv":                  len(tv),
        "rated_count":         len(all_rated),
        "avg_rating":          avg_rating,
        "rating_distribution": rating_dist,
        "top_genres":          top_genres,
        "top_directors":       [{"name": n, "count": c} for n, c in Counter(all_directors).most_common(6)],
        "top_rated":           [{"title": m["title"], "rating": m["user_rating"], "poster": m.get("poster_path")} for m in top_rated],
        "monthly_stats":       monthly,
        "platform_stats":      dict(platform_cnt.most_common()),
    }


@app.get("/profile/analyze")
async def analyze_profile(user_id: int = 1):
    api_key = os.getenv("CEREBRAS_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI анализ временно недоступен")

    from collections import Counter
    from openai import AsyncOpenAI

    movies = database.get_watched("movie", user_id)
    tv     = database.get_watched("tv",    user_id)
    all_watched = movies + tv

    if len(all_watched) < 3:
        raise HTTPException(status_code=400, detail="Отметь хотя бы 3 фильма, чтобы получить анализ")

    # Собираем данные для промпта
    all_rated = [m for m in all_watched if m.get("user_rating") is not None]
    avg_rating = round(sum(m["user_rating"] for m in all_rated) / len(all_rated), 1) if all_rated else None

    def genre_name(g):
        if isinstance(g, str):  return g
        if isinstance(g, dict): return g.get("name", "")
        return ""

    genre_cnt = Counter(genre_name(g) for m in all_watched for g in (m.get("genres") or []) if genre_name(g))
    top_genres = [f"{name} ({cnt})" for name, cnt in genre_cnt.most_common(6)]

    director_cnt = Counter(m["director"] for m in all_watched if m.get("director"))
    top_directors = [f"{name} ({cnt})" for name, cnt in director_cnt.most_common(4)]

    top_rated_titles = [
        f"{m['title']} — {m['user_rating']}/10"
        for m in sorted(all_rated, key=lambda x: x["user_rating"], reverse=True)[:8]
    ]
    low_rated_titles = [
        f"{m['title']} — {m['user_rating']}/10"
        for m in sorted(all_rated, key=lambda x: x["user_rating"])[:4]
        if m["user_rating"] <= 5
    ]

    prompt = f"""Ты мой друг-киноман, который знает всё о кино. Посмотри что я смотрел и расскажи мне о моём вкусе — как другу, неформально, на "ты". Без воды и канцелярщины.

Вот что я смотрел:
- Фильмов: {len(movies)}, сериалов: {len(tv)}
- Оценил {len(all_rated)} из {len(all_watched)}, средняя оценка: {avg_rating or "пока нет"}
- Жанры которые чаще всего смотрю: {", ".join(top_genres) if top_genres else "разные"}
- Режиссёры: {", ".join(top_directors) if top_directors else "разные"}
- Что поставил высокие оценки: {", ".join(top_rated_titles) if top_rated_titles else "пока нет"}
- Что не понравилось: {", ".join(low_rated_titles) if low_rated_titles else "ничего"}

Напиши 3 коротких абзаца на русском:
1. Какой у меня вкус — что я люблю, в чём моя фишка
2. Что интересного ты заметил в моих оценках — может какая-то закономерность
3. Что конкретно посоветуешь посмотреть — 2-3 названия с коротким объяснением почему

Пиши как живой человек, с характером. Можно с лёгкой иронией если уместно."""

    client = AsyncOpenAI(
        api_key=api_key,
        base_url="https://api.cerebras.ai/v1"
    )

    try:
        response = await client.chat.completions.create(
            model="gpt-oss-120b",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=600,
            temperature=0.8,
        )
        analysis = response.choices[0].message.content.strip()
        return {"analysis": analysis}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Ошибка AI: {str(e)}")


@app.get("/ai/suggest")
async def ai_suggest(user_id: int = 1, query: str = ""):
    api_key = os.getenv("CEREBRAS_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI недоступен")

    from collections import Counter
    from openai import AsyncOpenAI
    import json, re

    movies  = database.get_watched("movie", user_id)
    tv      = database.get_watched("tv",    user_id)
    all_watched = movies + tv

    # Если пользователь написал запрос — пускаем независимо от истории
    # (AI может рекомендовать по описанию). Без запроса — нужны хотя бы 3
    # просмотренных, иначе анализировать вкус не из чего.
    if not query.strip() and len(all_watched) < 3:
        raise HTTPException(status_code=400, detail="Отметь хотя бы 3 фильма или опиши что хочешь посмотреть в поле ниже")

    watched_ids = {m.get("movie_id") or m.get("id") for m in all_watched}

    def genre_name(g):
        if isinstance(g, str):  return g
        if isinstance(g, dict): return g.get("name", "")
        return ""

    all_rated   = [m for m in all_watched if m.get("user_rating") is not None]
    avg_rating  = round(sum(m["user_rating"] for m in all_rated) / len(all_rated), 1) if all_rated else None
    genre_cnt   = Counter(genre_name(g) for m in all_watched for g in (m.get("genres") or []) if genre_name(g))
    top_genres  = [name for name, _ in genre_cnt.most_common(5)]
    top_titles  = [m["title"] for m in sorted(all_rated, key=lambda x: x["user_rating"], reverse=True)[:8]]
    # Все просмотренные названия — AI должен их исключить
    all_watched_titles = [m["title"] for m in all_watched if m.get("title")]

    example = '[{"title": "The Dark Knight", "year": 2008, "type": "movie", "reason": "Одна фраза"}, {"title": "Breaking Bad", "year": 2008, "type": "tv", "reason": "Одна фраза"}]'

    already_seen = ", ".join(all_watched_titles[:40]) if all_watched_titles else "none"

    if query:
        # ВАЖНО: когда есть текстовый запрос — игнорируем вкус пользователя.
        # Запрос диктует жанр/год/настроение. Историю используем ТОЛЬКО для исключения
        # уже просмотренного. Это убирает галлюцинации типа "ужастик с 2015" → "Veronica Mars 2004".
        prompt = f"""You are a strict movie recommendation engine. Follow the user's request EXACTLY.

USER REQUEST: "{query}"

You MUST obey every constraint in the request:
- If a GENRE is mentioned (horror, comedy, thriller, etc.) — recommend ONLY that genre
- If a YEAR or year range is mentioned (e.g. "since 2015", "from the 90s") — recommend ONLY titles in that range
- If "popular", "highly rated", "blockbuster" is mentioned — recommend only well-known/successful titles
- If a country/language is mentioned — match it
- If a duration/mood is mentioned — match it
- Ignore the user's general taste — match the request literally

ALREADY WATCHED (NEVER recommend any of these): {already_seen}

Recommend exactly 15 titles strictly matching the USER REQUEST.

OUTPUT RULES:
- ONLY a raw JSON array, no markdown, no code blocks, no explanation
- ORIGINAL English titles (as on IMDb/TMDB), NOT translated
- Each item MUST satisfy the user request
- Provide the correct year and type ("movie" or "tv")
- reason in Russian, one short sentence explaining WHY it matches the request

Example output:
{example}"""
    else:
        prompt = f"""You are a movie expert. Recommend movies or TV shows based on user taste.

User taste:
- Favorite genres: {", ".join(top_genres) if top_genres else "various"}
- Highly rated: {", ".join(top_titles) if top_titles else "none yet"}
- Average rating: {avg_rating or "unknown"}

ALREADY WATCHED (DO NOT recommend these): {already_seen}

Recommend exactly 15 movies or TV shows the user has NOT seen yet and would enjoy based on their taste.

IMPORTANT RULES:
- Output ONLY a raw JSON array, no markdown, no code blocks, no explanation
- Use the ORIGINAL English title (as it appears on IMDb/TMDB), not translated
- Only recommend titles that definitely exist on IMDb/TMDB
- Do NOT recommend anything from the "ALREADY WATCHED" list
- reason must be in Russian, one short sentence

Example output:
{example}"""

    ai_client = AsyncOpenAI(api_key=api_key, base_url="https://api.cerebras.ai/v1")

    try:
        # При запросе — низкая температура для строгого следования ограничениям.
        # Без запроса — выше для разнообразия рекомендаций.
        temp = 0.4 if query else 0.8
        response = await ai_client.chat.completions.create(
            model="gpt-oss-120b",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=2500,
            temperature=temp,
        )
        raw = response.choices[0].message.content.strip()

        # Убираем markdown code blocks
        raw = re.sub(r'^```[a-z]*\s*', '', raw)
        raw = re.sub(r'\s*```$', '', raw)
        raw = raw.strip()

        json_match = re.search(r'\[.*\]', raw, re.DOTALL)
        if not json_match:
            raise HTTPException(status_code=503, detail=f"AI не вернул JSON. Ответ: {raw[:300]}")
        suggestions = json.loads(json_match.group())
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Ошибка AI: {str(e)}")

    # Нормализация названия для сравнения (убираем артикли, lowercase)
    def norm_title(t: str) -> str:
        t = t.lower().strip()
        for prefix in ("the ", "a ", "an "):
            if t.startswith(prefix):
                t = t[len(prefix):]
        return t

    # Набор нормализованных названий просмотренного — для предварительной фильтрации
    watched_titles_norm = {norm_title(m["title"]) for m in all_watched if m.get("title")}

    # Убираем из предложений AI всё что уже смотрели (по названию, не только по TMDB ID)
    suggestions_filtered = [
        s for s in suggestions
        if norm_title(s.get("title", "")) not in watched_titles_norm
    ]

    # Если AI всё равно дал мало нового — используем всё что есть
    candidates = suggestions_filtered if len(suggestions_filtered) >= 6 else suggestions

    # Ищем все фильмы параллельно через /search/multi (ищет и фильмы и сериалы сразу)
    async def tmdb_lookup(h, item):
        title  = item.get("title", "").strip()
        year   = item.get("year")
        reason = item.get("reason", "")
        if not title:
            return None
        try:
            # /search/multi — обходит проблему угадывания типа (movie vs tv)
            params = {"api_key": TMDB_API_KEY, "query": title, "language": "ru-RU"}
            if year:
                params["year"] = year
            r = await h.get(f"{TMDB_BASE}/search/multi", params=params)
            items = [x for x in r.json().get("results", []) if x.get("media_type") in ("movie", "tv")]

            # Попытка 2: без года
            if not items and year:
                params.pop("year", None)
                r = await h.get(f"{TMDB_BASE}/search/multi", params=params)
                items = [x for x in r.json().get("results", []) if x.get("media_type") in ("movie", "tv")]

            # Попытка 3: без language
            if not items:
                r = await h.get(f"{TMDB_BASE}/search/multi", params={"api_key": TMDB_API_KEY, "query": title})
                items = [x for x in r.json().get("results", []) if x.get("media_type") in ("movie", "tv")]

            if not items:
                return None

            m          = items[0]
            tmdb_id    = m["id"]
            media_type = m.get("media_type", "movie")

            if tmdb_id in watched_ids:
                return None

            name_key = "name" if media_type == "tv" else "title"
            date_key = "first_air_date" if media_type == "tv" else "release_date"

            # Если вернулось не кириллическое название — тянем русский перевод
            ru_title = m.get(name_key) or title
            if not any('Ѐ' <= c <= 'ӿ' for c in ru_title):
                try:
                    det = await h.get(
                        f"{TMDB_BASE}/{media_type}/{tmdb_id}",
                        params={"api_key": TMDB_API_KEY, "language": "ru-RU"}
                    )
                    ru_title = det.json().get(name_key) or ru_title
                except Exception:
                    pass

            return {
                "id":          tmdb_id,
                "title":       ru_title,
                "poster_path": m.get("poster_path"),
                "vote_average": m.get("vote_average"),
                date_key:      m.get(date_key, ""),
                "media_type":  media_type,
                "ai_reason":   reason,
            }
        except Exception as e:
            print(f"[tmdb_lookup] '{title}': {e}")
            return None

    async with httpx.AsyncClient(timeout=60) as h:
        found = await asyncio.gather(*[tmdb_lookup(h, item) for item in candidates[:15]])
    results = [r for r in found if r is not None][:12]


# ─── Тетрадь: Задачи ──────────────────────────────────────────────────────────

class TaskCreate(BaseModel):
    title: str
    date: str
    time_str: Optional[str] = None
    tag: Optional[str] = None
    priority: Optional[str] = "normal"
    recurrence: Optional[str] = None   # null | 'daily' | 'weekly:0,2,4'

class TaskUpdate(BaseModel):
    title: Optional[str] = None
    status: Optional[str] = None
    cancel_reason: Optional[str] = None
    time_str: Optional[str] = None
    tag: Optional[str] = None
    date: Optional[str] = None
    recurrence: Optional[str] = None

@app.get("/tasks")
async def get_tasks(date: str, user_id: int = 1):
    return database.get_tasks(user_id, date)

@app.get("/tasks/week")
async def get_tasks_week(date_from: str, date_to: str, user_id: int = 1):
    return database.get_tasks_range(user_id, date_from, date_to)

@app.post("/tasks")
async def create_task(req: TaskCreate, user_id: int = 1):
    return database.add_task(
        user_id, req.title, req.date,
        req.time_str, req.tag, req.priority, req.recurrence
    )

@app.patch("/tasks/{task_id}")
async def patch_task(task_id: int, req: TaskUpdate, user_id: int = 1):
    fields = {k: v for k, v in req.dict().items() if v is not None}
    try:
        return database.update_task(task_id, user_id, **fields)
    except ValueError:
        raise HTTPException(404, "Задача не найдена")

@app.delete("/tasks/{task_id}")
async def remove_task(task_id: int, user_id: int = 1):
    database.delete_task(task_id, user_id)
    return {"ok": True}

@app.post("/tasks/{task_id}/complete")
async def complete_task(task_id: int, date: str, user_id: int = 1):
    database.add_task_completion(task_id, date)
    return {"ok": True}

@app.delete("/tasks/{task_id}/complete")
async def uncomplete_task(task_id: int, date: str, user_id: int = 1):
    database.remove_task_completion(task_id, date)
    return {"ok": True}


# ─── Тетрадь: Списки ──────────────────────────────────────────────────────────

class ListCreate(BaseModel):
    name: str
    emoji: str = "📋"

class ListItemCreate(BaseModel):
    title: str

@app.get("/notebook/lists")
async def get_lists(user_id: int = 1):
    return database.get_lists(user_id)

@app.post("/notebook/lists")
async def create_list(req: ListCreate, user_id: int = 1):
    return database.add_list(user_id, req.name, req.emoji)

@app.delete("/notebook/lists/{list_id}")
async def delete_list(list_id: int, user_id: int = 1):
    database.delete_list(list_id, user_id)
    return {"ok": True}

@app.get("/notebook/lists/{list_id}/items")
async def get_list_items(list_id: int, user_id: int = 1):
    return database.get_list_items(list_id, user_id)

@app.post("/notebook/lists/{list_id}/items")
async def add_list_item(list_id: int, req: ListItemCreate, user_id: int = 1):
    return database.add_list_item(list_id, user_id, req.title)

@app.patch("/notebook/list-items/{item_id}")
async def toggle_item(item_id: int, done: bool, user_id: int = 1):
    return database.toggle_list_item(item_id, user_id, done)

@app.delete("/notebook/list-items/{item_id}")
async def delete_list_item(item_id: int, user_id: int = 1):
    database.delete_list_item(item_id, user_id)
    return {"ok": True}


# ─── Тетрадь: Заметки ─────────────────────────────────────────────────────────

class NoteCreate(BaseModel):
    body: str = ""
    title: str = ""
    color: str = "yellow"

class NoteUpdate(BaseModel):
    body: Optional[str] = None
    title: Optional[str] = None
    color: Optional[str] = None

@app.get("/notebook/notes")
async def get_notes(user_id: int = 1):
    return database.get_notes(user_id)

@app.post("/notebook/notes")
async def create_note(req: NoteCreate, user_id: int = 1):
    return database.add_note(user_id, req.body, req.title, req.color)

@app.patch("/notebook/notes/{note_id}")
async def update_note(note_id: int, req: NoteUpdate, user_id: int = 1):
    fields = {k: v for k, v in req.dict().items() if v is not None}
    return database.update_note(note_id, user_id, **fields)

@app.delete("/notebook/notes/{note_id}")
async def delete_note(note_id: int, user_id: int = 1):
    database.delete_note(note_id, user_id)
    return {"ok": True}


# ─── Тетрадь: Бюджет ──────────────────────────────────────────────────────────

class BudgetCategoryCreate(BaseModel):
    name: str
    emoji: str = "💰"
    plan_monthly: int = 0

class BudgetCategoryUpdate(BaseModel):
    name: Optional[str] = None
    emoji: Optional[str] = None
    plan_monthly: Optional[int] = None

class BudgetExpenseCreate(BaseModel):
    date: str
    amount: int
    category_id: Optional[int] = None
    note: Optional[str] = None
    merchant: Optional[str] = None

@app.get("/budget/categories")
async def get_budget_categories(user_id: int = 1):
    return database.get_budget_categories(user_id)

@app.post("/budget/categories")
async def create_budget_category(req: BudgetCategoryCreate, user_id: int = 1):
    return database.add_budget_category(user_id, req.name, req.emoji, req.plan_monthly)

@app.patch("/budget/categories/{cat_id}")
async def update_budget_category(cat_id: int, req: BudgetCategoryUpdate, user_id: int = 1):
    return database.update_budget_category(cat_id, user_id, req.name, req.emoji, req.plan_monthly)

@app.delete("/budget/categories/{cat_id}")
async def delete_budget_category(cat_id: int, user_id: int = 1):
    database.delete_budget_category(cat_id, user_id)
    return {"ok": True}

@app.get("/budget/expenses")
async def get_budget_expenses(year: int, month: int, user_id: int = 1):
    return database.get_budget_expenses(user_id, year, month)

@app.get("/budget/merchants")
async def get_budget_merchants(user_id: int = 1):
    return database.get_merchant_suggestions(user_id)

@app.post("/budget/expenses")
async def create_budget_expense(req: BudgetExpenseCreate, user_id: int = 1):
    return database.add_budget_expense(
        user_id, req.date, req.amount, req.category_id, req.note, req.merchant
    )

@app.patch("/budget/expenses/{exp_id}")
async def update_budget_expense(exp_id: int, req: dict = Body(...), user_id: int = 1):
    return database.update_budget_expense(
        exp_id, user_id,
        amount=req.get("amount"),
        note=req.get("note"),
        category_id=req.get("category_id"),
        merchant=req.get("merchant"),
    )

@app.delete("/budget/expenses/month")
async def delete_budget_expenses_month(year: int, month: int, user_id: int = 1):
    deleted = database.delete_budget_expenses_month(user_id, year, month)
    return {"deleted": deleted}

@app.delete("/budget/expenses/all")
async def delete_budget_expenses_all(user_id: int = 1):
    deleted = database.delete_budget_expenses_all(user_id)
    return {"deleted": deleted}

@app.delete("/budget/expenses/{exp_id}")
async def delete_budget_expense(exp_id: int, user_id: int = 1):
    database.delete_budget_expense(exp_id, user_id)
    return {"ok": True}


@app.post("/budget/parse-statement")
async def parse_statement(file: UploadFile):
    """Принимает PDF-выписку, возвращает список распознанных транзакций."""
    from statement_parser import parse_ozon_pdf
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(400, "Нужен PDF-файл")
    data = await file.read()
    try:
        transactions = parse_ozon_pdf(data)
    except Exception as e:
        raise HTTPException(500, f"Ошибка парсинга: {e}")
    return {"transactions": transactions, "count": len(transactions)}


@app.post("/budget/import")
async def import_expenses(req: dict, user_id: int = 1):
    """Сохраняет подтверждённые транзакции из выписки в budget_expenses."""
    items = req.get("transactions", [])
    saved = 0
    for t in items:
        try:
            # Ищем категорию по имени или создаём «Из выписки»
            cats = database.get_budget_categories(user_id)
            cat_id = None
            cat_name = t.get("category", "Другое")
            cat_emoji = t.get("emoji", "💰")
            for c in cats:
                if c["name"] == cat_name:
                    cat_id = c["id"]
                    break
            if cat_id is None:
                new_cat = database.add_budget_category(user_id, cat_name, cat_emoji, 0)
                cat_id = new_cat["id"]
            database.add_budget_expense(
                user_id,
                t["date"],
                int(t["amount"]),
                cat_id,
                t.get("description", ""),
                t.get("merchant", ""),
            )
            saved += 1
        except Exception:
            continue
    return {"saved": saved}


# ─── Тетрадь: Поездки ─────────────────────────────────────────────────────────

class TripCreate(BaseModel):
    name: str
    emoji: str = "✈️"
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    planned_total: int = 0
    event_type: str = "trip"
    subtitle: str = ""

class TripExpenseCreate(BaseModel):
    date: str
    amount: int = 0
    planned_amount: Optional[int] = None
    category: str = ""
    note: str = ""
    emoji: str = ""
    city: str = ""

@app.get("/trips")
async def get_trips(user_id: int = 1):
    return database.get_trips(user_id)

@app.get("/budget/events")
async def get_budget_events(year: int, month: int, user_id: int = 1):
    """Поездки и события пересекающиеся с указанным месяцем."""
    return database.get_trips_for_month(user_id, year, month)

@app.post("/trips")
async def create_trip(req: TripCreate, user_id: int = 1):
    return database.add_trip(
        user_id, req.name, req.emoji, req.start_date, req.end_date,
        req.planned_total, req.event_type, req.subtitle
    )

@app.get("/trips/{trip_id}/day-notes")
async def get_day_notes(trip_id: int, user_id: int = 1):
    return database.get_trip_day_notes(trip_id)

@app.post("/trips/{trip_id}/day-notes")
async def upsert_day_note(trip_id: int, req: dict = Body(...), user_id: int = 1):
    return database.upsert_trip_day_note(trip_id, req["date"], req.get("note",""), req.get("title",""))

@app.delete("/trips/{trip_id}")
async def delete_trip(trip_id: int, user_id: int = 1):
    database.delete_trip(trip_id, user_id)
    return {"ok": True}

@app.post("/trips/group")
async def group_trips(body: dict, user_id: int = 1):
    """Объединяет две поездки в группу (или добавляет в существующую)."""
    trip_a = int(body["trip_a"])
    trip_b = int(body["trip_b"])
    name   = body.get("name")
    emoji  = body.get("emoji", "📁")
    return database.group_trips(trip_a, trip_b, user_id, name, emoji)

@app.post("/trips/{trip_id}/ungroup")
async def ungroup_trip(trip_id: int, user_id: int = 1):
    """Убирает поездку из группы."""
    database.ungroup_trip(trip_id, user_id)
    return {"ok": True}

@app.patch("/trips/{trip_id}")
async def patch_trip(trip_id: int, body: dict, user_id: int = 1):
    """Обновляет название/emoji/subtitle группы или поездки."""
    conn = database._get_conn()
    try:
        cur = conn.cursor()
        fields, vals = [], []
        for f in ("name", "emoji", "subtitle", "planned_total"):
            if f in body:
                fields.append(f"{f}=%s"); vals.append(body[f])
        if not fields:
            return {"ok": True}
        vals += [trip_id, user_id]
        cur.execute(f"UPDATE trips SET {', '.join(fields)} WHERE id=%s AND user_id=%s", vals)
        conn.commit()
    finally:
        conn.close()
    return {"ok": True}

@app.get("/trips/{trip_id}/expenses")
async def get_trip_expenses(trip_id: int, user_id: int = 1):
    return database.get_trip_expenses(trip_id, user_id)

@app.post("/trips/{trip_id}/expenses")
async def add_trip_expense(trip_id: int, req: TripExpenseCreate, user_id: int = 1):
    return database.add_trip_expense(
        trip_id, user_id, req.date, req.amount,
        req.planned_amount, req.category, req.note, req.emoji, req.city
    )

@app.patch("/trip-expenses/{exp_id}/amount")
async def set_trip_expense_amount(exp_id: int, amount: int, user_id: int = 1):
    return database.update_trip_expense_amount(exp_id, user_id, amount)

@app.delete("/trip-expenses/{exp_id}")
async def delete_trip_expense(exp_id: int, user_id: int = 1):
    database.delete_trip_expense(exp_id, user_id)
    return {"ok": True}

# ─── Раздача фронтенда ───────────────────────────────────────────────────────
# Должно быть ПОСЛЕ всех API-роутов, чтобы не перехватывать /api/* запросы
import pathlib
_frontend = pathlib.Path(__file__).parent.parent / "frontend"
if _frontend.exists():
    app.mount("/", StaticFiles(directory=str(_frontend), html=True), name="frontend")
