"""
main.py — главный файл сервера на FastAPI.

FastAPI автоматически создаёт документацию по всем маршрутам.
После запуска открой: http://127.0.0.1:8000/docs
"""

import os
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

import database
import recommender

# Загружаем переменные из файла .env (там лежит TMDB_API_KEY)
load_dotenv()

TMDB_API_KEY = os.getenv("TMDB_API_KEY")
TMDB_BASE    = "https://api.themoviedb.org/3"

app = FastAPI(title="Movie Recommender API")

# CORS — разрешаем фронтенду (другой порт) обращаться к серверу
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Запуск / инициализация ---

@app.on_event("startup")
async def startup():
    """Вызывается один раз при старте сервера."""
    database.init_db()
    print("✅ База данных готова")
    if not TMDB_API_KEY:
        print("⚠️  TMDB_API_KEY не найден! Создай файл backend/.env")


# --- Вспомогательные функции для запросов к TMDB ---

async def tmdb_get(path: str, **params) -> dict:
    """Делает GET-запрос к TMDB API и возвращает JSON."""
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"{TMDB_BASE}{path}",
            params={"api_key": TMDB_API_KEY, "language": "ru-RU", **params},
            timeout=10,
        )
        response.raise_for_status()
        return response.json()


async def get_movie_details(movie_id: int) -> dict:
    """Получает полные данные фильма включая жанры."""
    return await tmdb_get(f"/movie/{movie_id}")


# --- Маршруты API ---

@app.get("/search")
async def search_movies(q: str):
    """
    Поиск фильмов по названию.
    Пример: GET /search?q=Матрица
    """
    if not q.strip():
        raise HTTPException(400, "Поисковый запрос не может быть пустым")

    data = await tmdb_get("/search/movie", query=q)
    movies = data.get("results", [])[:10]  # берём первые 10 результатов

    # Добавляем флаг: находится ли фильм уже в избранном
    return [
        {**m, "is_favorite": database.is_favorite(m["id"])}
        for m in movies
    ]


@app.get("/popular")
async def popular_movies():
    """
    Возвращает популярные фильмы с TMDB.
    Используется как начальный экран и пул для рекомендаций.
    """
    data = await tmdb_get("/movie/popular")
    movies = data.get("results", [])
    return [
        {**m, "is_favorite": database.is_favorite(m["id"])}
        for m in movies
    ]


@app.get("/favorites")
async def get_favorites():
    """Возвращает список избранных фильмов пользователя."""
    return database.get_favorites()


class FavoriteRequest(BaseModel):
    movie_id: int


@app.post("/favorites")
async def add_favorite(req: FavoriteRequest):
    """
    Добавляет фильм в избранное.
    Тело запроса: { "movie_id": 123 }
    """
    # Получаем полные данные фильма с TMDB
    try:
        movie = await get_movie_details(req.movie_id)
    except httpx.HTTPError:
        raise HTTPException(404, "Фильм не найден в TMDB")

    # Преобразуем жанры: [{"id": 28, "name": "Action"}] → ["Action"]
    genres = [g["name"] for g in movie.get("genres", [])]

    added = database.add_favorite({
        "id":           movie["id"],
        "title":        movie["title"],
        "genres":       genres,
        "overview":     movie.get("overview", ""),
        "poster_path":  movie.get("poster_path", ""),
        "vote_average": movie.get("vote_average", 0.0),
    })

    if not added:
        raise HTTPException(409, "Фильм уже в избранном")

    return {"message": f"«{movie['title']}» добавлен в избранное"}


@app.delete("/favorites/{movie_id}")
async def remove_favorite(movie_id: int):
    """Удаляет фильм из избранного."""
    removed = database.remove_favorite(movie_id)
    if not removed:
        raise HTTPException(404, "Фильм не найден в избранном")
    return {"message": "Фильм удалён из избранного"}


@app.get("/recommendations")
async def get_recommendations():
    """
    Главная функция: подбирает фильмы на основе избранного.
    Алгоритм: Content-Based Filtering (TF-IDF + Cosine Similarity).
    """
    favorites = database.get_favorites()

    if not favorites:
        raise HTTPException(400, "Добавь хотя бы один фильм в избранное")

    # Берём популярные фильмы как пул кандидатов (страницы 1-3)
    candidates = []
    for page in range(1, 4):
        data = await tmdb_get("/movie/popular", page=page)
        candidates.extend(data.get("results", []))

    # Запрашиваем жанры для каждого кандидата (они нужны алгоритму)
    # Для скорости — берём жанры из general list, не из детального запроса
    genre_data = await tmdb_get("/genre/movie/list")
    genre_map = {g["id"]: g["name"] for g in genre_data["genres"]}

    for movie in candidates:
        movie["genres"] = [
            {"name": genre_map[gid]}
            for gid in movie.get("genre_ids", [])
            if gid in genre_map
        ]

    recs = recommender.get_recommendations(favorites, candidates, top_n=12)
    return recs


@app.get("/")
async def root():
    return {"message": "Movie Recommender API работает! Документация: /docs"}
