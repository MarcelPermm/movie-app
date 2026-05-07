"""
recommender.py — алгоритм рекомендаций фильмов.

Как работает Content-Based Filtering:
1. Каждый фильм описывается текстом: жанры + описание
2. TF-IDF превращает текст в числовой вектор
   (TF = как часто слово встречается в фильме,
    IDF = насколько редкое это слово среди всех фильмов)
3. Cosine Similarity измеряет угол между векторами двух фильмов
   (чем меньше угол = чем ближе к 1.0 = тем похожее фильмы)
4. Мы суммируем сходство кандидата с каждым фильмом из избранного
   и сортируем по убыванию
"""

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np


def build_feature_text(movie: dict) -> str:
    """
    Собирает из данных фильма одну строку для анализа.
    Чем больше информации — тем точнее рекомендации.
    """
    genres = " ".join(movie.get("genres", []))

    # Повторяем жанры 3 раза, чтобы они весили больше, чем описание
    parts = [genres, genres, genres, movie.get("overview", "")]
    return " ".join(p for p in parts if p)  # убираем пустые части


def get_recommendations(
    favorites: list[dict],
    candidates: list[dict],
    top_n: int = 10,
) -> list[dict]:
    """
    Возвращает топ-N рекомендованных фильмов.

    favorites  — фильмы из избранного пользователя
    candidates — пул фильмов для подбора (популярные/новые из TMDB)
    top_n      — сколько рекомендаций вернуть
    """
    if not favorites:
        # Нет избранного — не можем ничего рекомендовать
        return []

    # ID фильмов из избранного — их не надо рекомендовать повторно
    favorite_ids = {m["movie_id"] for m in favorites}

    # Отфильтровываем кандидатов: убираем уже избранные
    new_candidates = [m for m in candidates if m["id"] not in favorite_ids]

    if not new_candidates:
        return []

    # --- Шаг 1: Строим текстовые описания для всех фильмов ---
    fav_texts = [build_feature_text({
        "genres": m["genres"],
        "overview": m.get("overview", ""),
    }) for m in favorites]

    cand_texts = [build_feature_text({
        "genres": [g["name"] for g in m.get("genres", [])],
        "overview": m.get("overview", ""),
    }) for m in new_candidates]

    all_texts = fav_texts + cand_texts

    # --- Шаг 2: TF-IDF превращает тексты в матрицу чисел ---
    # stop_words='english' убирает незначимые слова (the, a, is, ...)
    vectorizer = TfidfVectorizer(stop_words="english", min_df=1)
    try:
        tfidf_matrix = vectorizer.fit_transform(all_texts)
    except ValueError:
        # Если тексты пустые — возвращаем кандидатов по рейтингу
        return sorted(new_candidates, key=lambda m: m.get("vote_average", 0), reverse=True)[:top_n]

    fav_matrix  = tfidf_matrix[:len(favorites)]   # строки для избранного
    cand_matrix = tfidf_matrix[len(favorites):]    # строки для кандидатов

    # --- Шаг 3: Cosine Similarity между каждым кандидатом и избранным ---
    # similarity_matrix[i][j] = похожесть кандидата i на избранный фильм j
    similarity_matrix = cosine_similarity(cand_matrix, fav_matrix)

    # Итоговый скор = среднее сходство кандидата со всем избранным
    scores = similarity_matrix.mean(axis=1)

    # --- Шаг 4: Сортируем кандидатов по скору ---
    ranked_indices = np.argsort(scores)[::-1]  # от большего к меньшему

    recommendations = []
    for idx in ranked_indices[:top_n]:
        movie = new_candidates[idx].copy()
        movie["similarity_score"] = round(float(scores[idx]), 3)
        recommendations.append(movie)

    return recommendations
