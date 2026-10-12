"""Тесты ленты новых серий и кэша карточек. Запуск: cd backend && python -m pytest tests"""

import asyncio
import os
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import main  # noqa: E402


def day(offset: int) -> str:
    return (date.today() + timedelta(days=offset)).isoformat()


def ep(eid, season, number, air):
    return {"id": eid, "season_number": season, "episode_number": number, "air_date": air, "name": f"Серия {number}"}


def run_upcoming(monkeypatch, shows, watchlist=(), progress=(), seen=()):
    """shows: {show_id: {"next": ..., "last": ...}} — ответы TMDB."""
    main._tv_air_cache.clear()

    async def fake_tmdb_get(path, **_):
        sid = int(path.rsplit("/", 1)[1])
        return {"name": f"Сериал {sid}", "poster_path": None, "backdrop_path": None,
                "next_episode_to_air": shows[sid].get("next"),
                "last_episode_to_air": shows[sid].get("last")}

    monkeypatch.setattr(main, "tmdb_get", fake_tmdb_get)
    monkeypatch.setattr(main.database, "get_watchlist", lambda *_: [{"movie_id": s} for s in watchlist])
    monkeypatch.setattr(main.database, "get_tv_progress", lambda *_: [{"show_id": s} for s in progress])
    monkeypatch.setattr(main.database, "get_watched_episode_keys", lambda *_: set(seen))
    return asyncio.run(main.tv_upcoming(user_id=1))


def test_next_episode_within_horizon_is_listed(monkeypatch):
    out = run_upcoming(monkeypatch, {1: {"next": ep(10, 3, 4, day(1))}}, watchlist=[1])
    assert [(e["show_id"], e["season"], e["episode"]) for e in out] == [(1, 3, 4)]
    assert out[0]["air_date"] == day(1)


def test_far_future_and_old_episodes_are_skipped(monkeypatch):
    out = run_upcoming(monkeypatch, {
        1: {"next": ep(10, 1, 2, day(120))},
        2: {"last": ep(20, 1, 1, day(-30))},
    }, watchlist=[1, 2])
    assert out == []


def test_fresh_episode_hidden_once_watched(monkeypatch):
    shows = {1: {"last": ep(10, 2, 5, day(-1))}}
    assert len(run_upcoming(monkeypatch, shows, progress=[1])) == 1
    assert run_upcoming(monkeypatch, shows, progress=[1], seen=[(1, 2, 5)]) == []


def test_sorted_by_date_and_watching_flag(monkeypatch):
    out = run_upcoming(monkeypatch, {
        1: {"next": ep(10, 1, 3, day(5))},
        2: {"next": ep(20, 1, 1, day(0))},
    }, watchlist=[1], progress=[2])
    assert [e["show_id"] for e in out] == [2, 1]
    assert out[0]["watching"] is True and out[1]["watching"] is False


def test_same_episode_not_duplicated(monkeypatch):
    same = ep(10, 1, 1, day(0))
    out = run_upcoming(monkeypatch, {1: {"next": same, "last": same}}, watchlist=[1])
    assert len(out) == 1


def test_details_cache_is_bounded(monkeypatch):
    main._details_cache.clear()

    async def fake_tmdb_get(path, **_):
        return {}

    monkeypatch.setattr(main, "tmdb_get", fake_tmdb_get)
    monkeypatch.setattr(main.database, "save_imdb_mapping", lambda *_: None)
    for movie_id in range(main._DETAILS_MAX + 25):
        asyncio.run(main._fetch_details_tmdb(movie_id, "movie"))
    assert len(main._details_cache) == main._DETAILS_MAX
    assert (0, "movie") not in main._details_cache
    assert (main._DETAILS_MAX + 24, "movie") in main._details_cache
