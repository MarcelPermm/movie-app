/**
 * app.js — вся логика фронтенда.
 * 
 * Взаимодействует с нашим бэкендом (FastAPI на порту 8000).
 * Не используем никаких фреймворков — чистый JavaScript.
 */

const API = "http://127.0.0.1:8000";   // адрес нашего сервера
const TMDB_IMG = "https://image.tmdb.org/t/p/w500";  // базовый URL для постеров TMDB

// ─── Глобальное состояние ──────────────────────────────────────────────────
const state = {
  favorites: new Set(),    // Set с ID фильмов в избранном (для быстрой проверки)
  currentMovie: null,      // фильм, открытый в модальном окне
};

// ─── DOM-элементы ──────────────────────────────────────────────────────────
const $ = id => document.getElementById(id);
const moviesGrid  = $("movies-grid");
const favsGrid    = $("favorites-grid");
const recsGrid    = $("recs-grid");
const favCount    = $("fav-count");
const modalOverlay = $("modal-overlay");
const modalContent = $("modal-content");
const searchInput  = $("search-input");

// ─── Вкладки ───────────────────────────────────────────────────────────────
document.querySelectorAll(".nav-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    const tab = btn.dataset.tab;

    // Переключаем активную кнопку
    document.querySelectorAll(".nav-btn").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");

    // Переключаем активную вкладку
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    $(`tab-${tab}`).classList.add("active");

    // При переходе на избранное — обновляем список
    if (tab === "favorites") loadFavorites();
  });
});

// ─── Поиск ─────────────────────────────────────────────────────────────────
$("search-btn").addEventListener("click", doSearch);
searchInput.addEventListener("keydown", e => { if (e.key === "Enter") doSearch(); });

async function doSearch() {
  const query = searchInput.value.trim();
  if (!query) return;

  // Переходим на вкладку "Обзор"
  document.querySelector('[data-tab="discover"]').click();
  $("discover-title").textContent = `Результаты: «${query}»`;

  moviesGrid.innerHTML = '<div class="loader">Ищем…</div>';

  try {
    const movies = await apiFetch(`/search?q=${encodeURIComponent(query)}`);
    renderMovies(moviesGrid, movies, false);
  } catch (err) {
    moviesGrid.innerHTML = `<div class="empty-state"><span class="empty-icon">✕</span><p>Ошибка поиска</p></div>`;
  }
}

// ─── Загрузка популярных фильмов ───────────────────────────────────────────
async function loadPopular() {
  moviesGrid.innerHTML = '<div class="loader">Загружаем фильмы…</div>';
  try {
    const movies = await apiFetch("/popular");
    renderMovies(moviesGrid, movies, false);
  } catch (err) {
    moviesGrid.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Не удалось загрузить фильмы.<br>Проверь, запущен ли сервер.</p></div>`;
  }
}

// ─── Загрузка избранного ───────────────────────────────────────────────────
async function loadFavorites() {
  favsGrid.innerHTML = '<div class="loader">Загружаем…</div>';
  try {
    const favs = await apiFetch("/favorites");

    // Обновляем Set с ID и счётчик в шапке
    state.favorites = new Set(favs.map(m => m.movie_id));
    favCount.textContent = favs.length;

    if (favs.length === 0) {
      favsGrid.innerHTML = `<div class="empty-state"><span class="empty-icon">♡</span><p>Пока пусто. Добавь фильмы из «Обзора»</p></div>`;
      return;
    }

    // Адаптируем формат (в БД movie_id, в TMDB — id)
    const adapted = favs.map(m => ({ ...m, id: m.movie_id }));
    renderMovies(favsGrid, adapted, true);
  } catch (err) {
    favsGrid.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки избранного</p></div>`;
  }
}

// ─── Рекомендации ──────────────────────────────────────────────────────────
$("get-recs-btn").addEventListener("click", loadRecommendations);

async function loadRecommendations() {
  const btn = $("get-recs-btn");
  btn.disabled = true;
  btn.textContent = "Анализируем…";
  recsGrid.innerHTML = '<div class="loader">Подбираем фильмы для тебя…</div>';

  try {
    const recs = await apiFetch("/recommendations");
    renderMovies(recsGrid, recs, false, true); // true = показывать значок похожести
    toast("Рекомендации готовы!", "success");
  } catch (err) {
    const msg = err.detail || "Добавь хотя бы один фильм в избранное";
    recsGrid.innerHTML = `<div class="empty-state"><span class="empty-icon">✦</span><p>${msg}</p></div>`;
  } finally {
    btn.disabled = false;
    btn.textContent = "✦ Подобрать фильмы";
  }
}

// ─── Рендер карточек фильмов ───────────────────────────────────────────────
/**
 * @param {HTMLElement} container  — куда рендерить
 * @param {Array}       movies     — массив фильмов
 * @param {boolean}     isFavView  — режим избранного (показываем кнопку удаления)
 * @param {boolean}     showScore  — показывать значок похожести
 */
function renderMovies(container, movies, isFavView = false, showScore = false) {
  if (!movies || movies.length === 0) {
    container.innerHTML = `<div class="empty-state"><span class="empty-icon">◌</span><p>Ничего не найдено</p></div>`;
    return;
  }

  container.innerHTML = "";

  movies.forEach((movie, index) => {
    const card = document.createElement("div");
    card.className = "movie-card";
    card.style.animationDelay = `${index * 40}ms`;  // эффект появления по очереди

    const posterUrl = movie.poster_path
      ? `${TMDB_IMG}${movie.poster_path}`
      : null;

    const year = (movie.release_date || "").slice(0, 4) || "—";
    const rating = movie.vote_average ? movie.vote_average.toFixed(1) : "—";

    // ID фильма: в ответах БД это movie_id, в ответах TMDB — id
    const movieId = movie.id || movie.movie_id;
    const isFav = state.favorites.has(movieId);

    const scoreHTML = showScore && movie.similarity_score
      ? `<div class="similarity-badge">${Math.round(movie.similarity_score * 100)}% совпадение</div>`
      : "";

    card.innerHTML = `
      ${scoreHTML}
      ${posterUrl
        ? `<img class="movie-poster" src="${posterUrl}" alt="${movie.title}" loading="lazy" />`
        : `<div class="no-poster"><span class="no-poster-icon">🎬</span>${movie.title}</div>`
      }
      <button class="fav-btn ${isFav ? "is-fav" : ""}" data-id="${movieId}" title="${isFav ? "Убрать из избранного" : "В избранное"}">
        ${isFav ? "♥" : "♡"}
      </button>
      <div class="movie-info">
        <div class="movie-title">${movie.title}</div>
        <div class="movie-meta">
          <span class="movie-year">${year}</span>
          <span class="movie-rating">★ ${rating}</span>
        </div>
      </div>
    `;

    // Клик по карточке → открываем модальное окно
    card.addEventListener("click", e => {
      // Не открываем модалку при клике по кнопке избранного
      if (e.target.closest(".fav-btn")) return;
      openModal(movie);
    });

    // Кнопка избранного
    card.querySelector(".fav-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleFavorite(movieId, card.querySelector(".fav-btn"), isFavView ? container : null);
    });

    container.appendChild(card);
  });
}

// ─── Переключение избранного ───────────────────────────────────────────────
async function toggleFavorite(movieId, btn, containerToRefresh = null) {
  const isFav = state.favorites.has(movieId);

  try {
    if (isFav) {
      // Удаляем из избранного
      await apiFetch(`/favorites/${movieId}`, { method: "DELETE" });
      state.favorites.delete(movieId);
      btn.classList.remove("is-fav");
      btn.textContent = "♡";
      btn.title = "В избранное";
      toast("Удалено из избранного");

      // Если мы на вкладке избранного — убираем карточку
      if (containerToRefresh) {
        const card = btn.closest(".movie-card");
        card.style.transform = "scale(0)";
        card.style.opacity = "0";
        card.style.transition = "all 0.3s ease";
        setTimeout(() => { card.remove(); loadFavorites(); }, 300);
      }
    } else {
      // Добавляем в избранное
      await apiFetch("/favorites", {
        method: "POST",
        body: JSON.stringify({ movie_id: movieId }),
      });
      state.favorites.add(movieId);
      btn.classList.add("is-fav");
      btn.textContent = "♥";
      btn.title = "Убрать из избранного";
      toast("Добавлено в избранное ♥", "success");
    }

    // Обновляем счётчик в шапке
    favCount.textContent = state.favorites.size;
  } catch (err) {
    toast(err.detail || "Ошибка. Попробуй ещё раз.", "error");
  }
}

// ─── Модальное окно ────────────────────────────────────────────────────────
function openModal(movie) {
  state.currentMovie = movie;
  const movieId = movie.id || movie.movie_id;
  const isFav = state.favorites.has(movieId);

  const posterUrl  = movie.poster_path ? `${TMDB_IMG}${movie.poster_path}` : null;
  const backdropUrl = movie.backdrop_path ? `https://image.tmdb.org/t/p/w1280${movie.backdrop_path}` : posterUrl;
  const year    = (movie.release_date || "").slice(0, 4) || "—";
  const rating  = movie.vote_average ? movie.vote_average.toFixed(1) : "—";

  // Жанры могут быть в разных форматах
  let genres = [];
  if (Array.isArray(movie.genres)) {
    genres = movie.genres.map(g => typeof g === "string" ? g : g.name);
  }

  const tagsHTML = genres.map(g => `<span class="modal-tag">${g}</span>`).join("");

  modalContent.innerHTML = `
    <div class="modal-hero">
      ${backdropUrl
        ? `<img class="modal-backdrop" src="${backdropUrl}" alt="" />`
        : `<div style="height:280px; background: var(--border);"></div>`
      }
      <div class="modal-backdrop-overlay"></div>
      ${posterUrl
        ? `<div class="modal-poster-wrap"><img class="modal-poster" src="${posterUrl}" alt="${movie.title}" /></div>`
        : ""
      }
    </div>
    <div class="modal-body">
      <h2 class="modal-title">${movie.title}</h2>
      ${tagsHTML ? `<div class="modal-tags">${tagsHTML}</div>` : ""}
      <div class="modal-stats">
        <div class="modal-stat">
          <span class="modal-stat-label">Рейтинг</span>
          <span class="modal-stat-value">★ ${rating}</span>
        </div>
        <div class="modal-stat">
          <span class="modal-stat-label">Год</span>
          <span class="modal-stat-value">${year}</span>
        </div>
        ${movie.similarity_score ? `
        <div class="modal-stat">
          <span class="modal-stat-label">Похожесть</span>
          <span class="modal-stat-value">${Math.round(movie.similarity_score * 100)}%</span>
        </div>` : ""}
      </div>
      ${movie.overview ? `<p class="modal-overview">${movie.overview}</p>` : ""}
      <div class="modal-actions">
        <button class="modal-fav-btn ${isFav ? "remove" : ""}" id="modal-fav-btn">
          ${isFav ? "✕ Убрать из избранного" : "♡ В избранное"}
        </button>
      </div>
    </div>
  `;

  // Кнопка избранного внутри модалки
  $("modal-fav-btn").addEventListener("click", async () => {
    await toggleFavorite(movieId, $("modal-fav-btn"));
    const isNowFav = state.favorites.has(movieId);
    $("modal-fav-btn").className = `modal-fav-btn ${isNowFav ? "remove" : ""}`;
    $("modal-fav-btn").textContent = isNowFav ? "✕ Убрать из избранного" : "♡ В избранное";
  });

  modalOverlay.classList.add("open");
  document.body.style.overflow = "hidden";
}

function closeModal() {
  modalOverlay.classList.remove("open");
  document.body.style.overflow = "";
}

$("modal-close").addEventListener("click", closeModal);
modalOverlay.addEventListener("click", e => { if (e.target === modalOverlay) closeModal(); });
document.addEventListener("keydown", e => { if (e.key === "Escape") closeModal(); });

// ─── Вспомогательная функция: HTTP-запросы к API ───────────────────────────
async function apiFetch(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...options.headers };
  const response = await fetch(`${API}${path}`, { ...options, headers });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw err;
  }

  // DELETE может вернуть пустое тело
  if (response.status === 204) return null;
  return response.json();
}

// ─── Тост-уведомления ─────────────────────────────────────────────────────
function toast(message, type = "") {
  const el = document.createElement("div");
  el.className = `toast ${type}`;
  el.textContent = message;
  $("toast-container").appendChild(el);

  // Анимация появления
  requestAnimationFrame(() => { requestAnimationFrame(() => el.classList.add("show")); });

  // Автоскрытие через 3 секунды
  setTimeout(() => {
    el.classList.remove("show");
    setTimeout(() => el.remove(), 400);
  }, 3000);
}

// ─── Инициализация ─────────────────────────────────────────────────────────
async function init() {
  // Загружаем избранное, чтобы знать какие фильмы уже добавлены
  try {
    const favs = await apiFetch("/favorites");
    state.favorites = new Set(favs.map(m => m.movie_id));
    favCount.textContent = favs.length;
  } catch (e) {
    console.warn("Не удалось загрузить избранное:", e);
  }

  // Загружаем популярные фильмы
  loadPopular();
}

init();
