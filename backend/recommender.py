"""
recommender.py — улучшенный алгоритм с учётом отклонённых фильмов.

Логика скоринга:
1. TF-IDF сходство × вес оценки пользователя
2. Жанровые предпочтения (буст/штраф по средней оценке жанра)
3. Бонус за любимых режиссёров и актёров (+0.2 / +0.1)
4. Штраф за нелюбимые жанры (средний вес < -0.3)
5. Штраф за отклонённые фильмы: актёры (-0.4), страна (-0.3), студия (-0.2)
6. Разнообразие: 70% топ + 30% случайные
"""

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np
import random

RATING_WEIGHTS = {
    10: 1.3, 9: 1.2, 8: 1.1, 7: 0.9, 6: 0.7,
    5: -0.1, 4: -0.3, 3: -0.5, 2: -0.8, 1: -1.0,
    None: 0.2,
}


def build_feature_text(movie: dict) -> str:
    genres   = " ".join(movie.get("genres", []))
    director = movie.get("director", "") or ""
    cast     = " ".join((movie.get("cast_names") or [])[:3])
    parts    = [genres, genres, genres, movie.get("overview", ""), director, cast]
    return " ".join(p for p in parts if p)


def compute_genre_stats(watched: list[dict]) -> tuple[dict, set]:
    genre_ratings = {}
    for m in watched:
        weight = RATING_WEIGHTS.get(m.get("user_rating"), 0.2)
        for g in m.get("genres", []):
            name = g if isinstance(g, str) else g.get("name", "")
            if name:
                genre_ratings.setdefault(name, []).append(weight)
    genre_scores = {g: sum(ws) / len(ws) for g, ws in genre_ratings.items()}
    penalized_genres = {g for g, s in genre_scores.items() if s < -0.3}
    return genre_scores, penalized_genres


def compute_person_bonuses(watched: list[dict]) -> tuple[set, set]:
    fav_directors = set()
    fav_actors    = set()
    for m in watched:
        if (m.get("user_rating") or 0) >= 8:
            if m.get("director"):
                fav_directors.add(m["director"])
            for a in (m.get("cast_names") or [])[:3]:
                fav_actors.add(a)
    return fav_directors, fav_actors


def compute_dismissed_penalties(dismissed: list[dict]) -> tuple[set, set, set]:
    """
    Возвращает:
    - bad_actors:   актёры из отклонённых фильмов
    - bad_countries: страны из отклонённых фильмов
    - bad_studios:  студии из отклонённых фильмов
    """
    bad_actors    = set()
    bad_countries = set()
    bad_studios   = set()
    for m in dismissed:
        for a in (m.get("cast_names") or [])[:3]:
            bad_actors.add(a)
        if m.get("country"):
            bad_countries.add(m["country"])
        for s in (m.get("studio_names") or []):
            bad_studios.add(s)
    return bad_actors, bad_countries, bad_studios


def get_recommendations(
    watched: list[dict],
    candidates: list[dict],
    dismissed: list[dict] = None,
    top_n: int = 2000,
    dismissed_ids: set = None,
) -> list[dict]:

    if not watched:
        return []

    if dismissed_ids is None:
        dismissed_ids = set()
    if dismissed is None:
        dismissed = []

    watched_ids = {m["movie_id"] for m in watched}

    new_candidates = [
        m for m in candidates
        if m["id"] not in watched_ids and m["id"] not in dismissed_ids
    ]
    if not new_candidates:
        return []

    # ── Предвычисления ────────────────────────────────────────────────────────
    genre_scores, penalized_genres       = compute_genre_stats(watched)
    fav_directors, fav_actors            = compute_person_bonuses(watched)
    bad_actors, bad_countries, bad_studios = compute_dismissed_penalties(dismissed)

    # ── TF-IDF ────────────────────────────────────────────────────────────────
    watched_texts = [build_feature_text({
        "genres":     [g if isinstance(g, str) else g.get("name", "") for g in m.get("genres", [])],
        "overview":   m.get("overview", ""),
        "director":   m.get("director", ""),
        "cast_names": m.get("cast_names", []),
    }) for m in watched]

    cand_texts = [build_feature_text({
        "genres":   [g["name"] for g in m.get("genres", []) if isinstance(g, dict)],
        "overview": m.get("overview", ""),
    }) for m in new_candidates]

    all_texts = watched_texts + cand_texts
    vectorizer = TfidfVectorizer(stop_words="english", min_df=1)
    try:
        tfidf_matrix = vectorizer.fit_transform(all_texts)
    except ValueError:
        return sorted(new_candidates, key=lambda m: m.get("vote_average", 0), reverse=True)[:top_n]

    watched_matrix = tfidf_matrix[:len(watched)]
    cand_matrix    = tfidf_matrix[len(watched):]

    sim_matrix = cosine_similarity(cand_matrix, watched_matrix)
    weights    = np.array([RATING_WEIGHTS.get(m.get("user_rating"), 0.2) for m in watched])
    scores     = sim_matrix.dot(weights) / max(len(watched), 1)

    # ── Применяем бонусы и штрафы ─────────────────────────────────────────────
    for i, movie in enumerate(new_candidates):
        movie_genres   = [g["name"] for g in movie.get("genres", []) if isinstance(g, dict)]
        movie_cast     = (movie.get("cast_names") or [])[:3]
        movie_country  = movie.get("country", "")
        movie_studios  = movie.get("studio_names") or []

        # Жанровый буст (идея 1)
        for g in movie_genres:
            if g in genre_scores:
                scores[i] += genre_scores[g] * 0.15

        # Штраф за нелюбимые жанры (идея 5)
        for g in movie_genres:
            if g in penalized_genres:
                scores[i] -= 0.25

        # Бонус за любимых режиссёра/актёров (идея 4)
        if movie.get("director") and movie["director"] in fav_directors:
            scores[i] += 0.2
        for actor in movie_cast:
            if actor in fav_actors:
                scores[i] += 0.1

        # Штраф за актёров из отклонённых (самый сильный)
        for actor in movie_cast:
            if actor in bad_actors:
                scores[i] -= 0.4

        # Штраф за страну из отклонённых
        if movie_country and movie_country in bad_countries:
            scores[i] -= 0.3

        # Штраф за студию из отклонённых
        for studio in movie_studios:
            if studio in bad_studios:
                scores[i] -= 0.2

    # ── Разнообразие 70/30 (идея 3) ───────────────────────────────────────────
    ranked     = np.argsort(scores)[::-1]
    top_count  = max(1, int(top_n * 0.7))
    rand_count = top_n - top_count

    top_indices    = list(ranked[:top_count])
    pool_indices   = list(ranked[top_count:])
    random_indices = random.sample(pool_indices, min(rand_count, len(pool_indices)))

    result = []
    for idx in top_indices + random_indices:
        m = new_candidates[idx].copy()
        m["similarity_score"] = round(float(scores[idx]), 3)
        result.append(m)

    return result