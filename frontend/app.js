const API       = typeof API_BASE_URL !== "undefined" ? API_BASE_URL : "http://127.0.0.1:8000";
const TMDB_IMG  = "https://image.tmdb.org/t/p/w500";
const TMDB_SM   = "https://image.tmdb.org/t/p/w185";
const TMDB_LOGO = "https://image.tmdb.org/t/p/w92";

const state = {
  mediaType:   "movie",   // "movie" | "tv"
  watched:     new Map(),
  watchlist:   new Set(),
  currentSort: "similarity",
  allRecs:     [],
  modalStack:  [],
  dismissed:   new Set(),
  favActors:   new Set(),  // actor_id (int)
  filterState: {
    genre:   { inc: new Set(), exc: new Set() },
    country: { inc: new Set(), exc: new Set() },
  },
  user: null,  // { id, username, display_name }
};

// Хелпер — добавляет media_type к fetch-параметрам
function mt(params = {}) {
  return { ...params, media_type: state.mediaType };
}
function mtq(base = "") {
  const sep = base.includes("?") ? "&" : "?";
  return `${base}${sep}media_type=${state.mediaType}`;
}

const COUNTRY_OPTIONS = [
  { value: "US", label: "🇺🇸 США" },
  { value: "GB", label: "🇬🇧 Великобритания" },
  { value: "FR", label: "🇫🇷 Франция" },
  { value: "DE", label: "🇩🇪 Германия" },
  { value: "IT", label: "🇮🇹 Италия" },
  { value: "JP", label: "🇯🇵 Япония" },
  { value: "KR", label: "🇰🇷 Южная Корея" },
  { value: "RU", label: "🇷🇺 Россия" },
  { value: "IN", label: "🇮🇳 Индия" },
  { value: "ES", label: "🇪🇸 Испания" },
  { value: "CN", label: "🇨🇳 Китай" },
  { value: "SE", label: "🇸🇪 Швеция" },
  { value: "AU", label: "🇦🇺 Австралия" },
  { value: "TR", label: "🇹🇷 Турция" },
];
const COUNTRY_LABELS = Object.fromEntries(COUNTRY_OPTIONS.map(o => [o.value, o.label.slice(3)]));

// Хранит текущие варианты для каждой панели
const mfItems = { genre: [], country: COUNTRY_OPTIONS };

const $ = id => document.getElementById(id);
const PAGE_SIZE = 50;

function fmtVotes(n) {
  if (n == null || n === undefined) return "—";
  const v = Number(n);
  if (Number.isNaN(v)) return "—";
  if (v >= 1_000_000) return `${(v / 1_000_000).toFixed(1).replace(/\.0$/, "")} млн`;
  if (v >= 1000) return `${Math.round(v / 1000)} тыс.`;
  return String(v);
}

/** Две строки: TMDB и при наличии IMDb (после рекомендаций / из деталей). */
function cardRatingsHTML(movie) {
  const tmdbRating = movie.vote_average != null ? Number(movie.vote_average).toFixed(1) : "—";
  const tmdbVotesL = fmtVotes(movie.vote_count);
  const imdbLine = movie.imdb_rating != null
    ? `<div class="rating-line imdb">IMDb ★${movie.imdb_rating} · ${fmtVotes(movie.imdb_vote_count)}</div>`
    : "";
  return `
    <div class="movie-ratings-detail">
      <div class="rating-line tmdb">TMDB ★${tmdbRating} · ${tmdbVotesL}</div>
      ${imdbLine}
    </div>
  `;
}

// ─── Вкладки ───────────────────────────────────────────────────────────────
document.querySelectorAll(".nav-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    const tab = btn.dataset.tab;
    document.querySelectorAll(".nav-btn").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    $(`tab-${tab}`).classList.add("active");
    if (tab === "watched")   loadWatched();
    if (tab === "watchlist") loadWatchlist();
    if (tab === "dismissed") loadDismissed();
    if (tab === "actors")    loadActors();
    if (tab === "suggest")   initSuggestTab();
    if (tab === "profile")   loadProfile();
    // Скрываем тултип рейтинговых баров при смене вкладки
    const bt = document.getElementById("bar-tooltip");
    if (bt) bt.classList.remove("visible");
  });
});

// ─── Переключатель режимов (фильмы / сериалы) ──────────────────────────────
document.querySelectorAll(".mode-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    const mode = btn.dataset.mode;
    if (mode === state.mediaType) return;
    document.querySelectorAll(".mode-btn").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    state.mediaType = mode;

    const isTV = mode === "tv";
    $("logo-text").textContent = isTV ? "SerialByMihaylov" : "FilmByMihaylov";
    $("search-input").placeholder = isTV ? "Найти сериал..." : "Найти фильм...";

    // Сбрасываем состояние
    state.allRecs = [];
    state.filterState.genre   = { inc: new Set(), exc: new Set() };
    state.filterState.country = { inc: new Set(), exc: new Set() };
    mfItems.genre = [];
    renderActiveTags();
    updateMfCount("genre");
    updateMfCount("country");
    $("sort-wrap").style.display = "none";
    $("recs-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">✦</span><p>Нажми кнопку выше, чтобы получить рекомендации</p></div>`;

    // Перезагружаем данные для нового режима
    reloadAllCounts();
    loadPopular();

    // Перегружаем жанры для нового режима
    apiFetch(`/genres?media_type=${mode}`).then(list => {
      if (list?.length) {
        mfItems.genre = list.map(g => ({ value: g.name, label: g.name }));
        buildMfPanel("genre");
      }
    }).catch(() => {});

    // Перезагружаем список студий/сетей для нового режима
    reloadStudios(mode);
  });
});

function reloadStudios(mediaType) {
  apiFetch(`/studios?media_type=${mediaType}`).then(list => {
    const sel = $("filter-studio");
    if (!sel) return;
    const label = mediaType === "tv" ? "Все сети" : "Все студии";
    sel.innerHTML = `<option value="0">${label}</option>`;
    list?.forEach(s => {
      const opt = document.createElement("option");
      opt.value = s.id; opt.textContent = s.name;
      sel.appendChild(opt);
    });
  }).catch(() => {});
}

async function reloadAllCounts() {
  try {
    const [watchedList, watchlistItems, dismissedList] = await Promise.all([
      apiFetch(mtq("/watched")),
      apiFetch(mtq("/watchlist")),
      apiFetch(mtq("/dismissed")),
    ]);
    state.watched   = new Map(watchedList.map(m => [m.movie_id, m.user_rating]));
    state.watchlist = new Set(watchlistItems.map(m => m.movie_id));
    state.dismissed = new Set(dismissedList.map(m => m.movie_id));
    $("watch-count").textContent     = watchedList.length;
    $("watchlist-count").textContent = watchlistItems.length;
    $("dismissed-count").textContent = dismissedList.length;
  } catch {}
}

// ─── Поиск ─────────────────────────────────────────────────────────────────
$("search-btn").addEventListener("click", doSearch);
$("search-input").addEventListener("keydown", e => { if (e.key === "Enter") doSearch(); });

async function doSearch() {
  const query = $("search-input").value.trim();
  if (!query) return;
  document.querySelector('[data-tab="discover"]').click();
  $("discover-title").textContent = `Результаты: «${query}»`;
  $("movies-grid").innerHTML = '<div class="loader">Ищем…</div>';
  try {
    const [movies, people] = await Promise.all([
      apiFetch(`/search?q=${encodeURIComponent(query)}&media_type=${state.mediaType}`),
      apiFetch(`/search/person?q=${encodeURIComponent(query)}`).catch(() => []),
    ]);
    renderSearchResults($("movies-grid"), movies, people);
  } catch {
    $("movies-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">✕</span><p>Ошибка поиска</p></div>`;
  }
}

function renderSearchResults(container, movies, people) {
  const hasPeople = people?.length > 0;
  const hasMovies = movies?.length > 0;

  if (!hasPeople && !hasMovies) {
    container.innerHTML = `<div class="empty-state"><span class="empty-icon">◌</span><p>Ничего не найдено</p></div>`;
    return;
  }

  container.style.display = "block";
  container.innerHTML = "";

  if (hasPeople) {
    const label = document.createElement("p");
    label.className = "search-section-label";
    label.textContent = "Актёры и режиссёры";
    container.appendChild(label);

    const row = document.createElement("div");
    row.className = "people-row";
    people.forEach(person => {
      const card = document.createElement("button");
      card.className = "person-search-card";
      const photo = person.profile_path ? `${TMDB_SM}${person.profile_path}` : null;
      const dept  = person.known_for_department === "Directing" ? "Режиссёр" : "Актёр/Актриса";
      card.innerHTML = `
        ${photo
          ? `<img class="person-search-photo" src="${photo}" alt="${person.name}" loading="lazy" />`
          : `<div class="person-no-photo-sm">👤</div>`}
        <div class="person-search-name">${person.name}</div>
        <div class="person-search-dept">${dept}</div>
      `;
      card.addEventListener("click", () => {
        state.modalStack = [];
        pushModal({ type: "person", data: { id: person.id } });
        $("modal-overlay").classList.add("open");
        document.body.style.overflow = "hidden";
        openPersonModal({ id: person.id });
      });
      row.appendChild(card);
    });
    container.appendChild(row);
  }

  if (hasMovies) {
    if (hasPeople) {
      const label = document.createElement("p");
      label.className = "search-section-label";
      label.style.marginTop = "4px";
      label.textContent = "Фильмы";
      container.appendChild(label);
    }
    const grid = document.createElement("div");
    grid.className = "movies-grid";
    container.appendChild(grid);
    renderMovies(grid, movies, "discover");
  }
}

// ─── Популярные ────────────────────────────────────────────────────────────
async function loadPopular() {
  const label = state.mediaType === "tv" ? "сериалы" : "фильмы";
  $("movies-grid").innerHTML = `<div class="loader">Загружаем ${label}…</div>`;
  $("discover-title").textContent = state.mediaType === "tv" ? "Популярные сериалы" : "Популярные фильмы";
  try {
    const movies = await apiFetch(mtq("/popular"));
    renderMovies($("movies-grid"), movies, "discover");
  } catch {
    $("movies-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Не удалось загрузить. Проверь сервер.</p></div>`;
  }
}

// ─── Просмотренное ─────────────────────────────────────────────────────────
async function loadWatched(filterRating = null, filterTitle = "") {
  $("watched-grid").innerHTML = '<div class="loader">Загружаем…</div>';
  try {
    let items = await apiFetch(mtq("/watched"));
    state.watched = new Map(items.map(m => [m.movie_id, m.user_rating]));
    $("watch-count").textContent = items.length;

    // Фильтр по оценке
    if (filterRating !== null) {
      if (filterRating === 0) {
        items = items.filter(m => !m.user_rating);  // без оценки
      } else {
        items = items.filter(m => m.user_rating === filterRating);
      }
    }

    // Фильтр по названию
    if (filterTitle) {
      items = items.filter(m => m.title.toLowerCase().includes(filterTitle.toLowerCase()));
    }

    if (!items.length) {
      $("watched-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">🎬</span><p>Ничего не найдено</p></div>`;
      return;
    }
    renderMovies($("watched-grid"), items.map(m => ({...m, id: m.movie_id})), "watched");
  } catch {
    $("watched-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

// Фильтры в просмотренном
$("watched-search").addEventListener("input", debounce(() => {
  const rating = parseInt($("watched-rating-filter").value);
  loadWatched(isNaN(rating) ? null : rating, $("watched-search").value);
}, 300));

$("watched-rating-filter").addEventListener("change", () => {
  const rating = parseInt($("watched-rating-filter").value);
  loadWatched(isNaN(rating) ? null : rating, $("watched-search").value);
});

function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

// ─── К просмотру ───────────────────────────────────────────────────────────
async function loadWatchlist() {
  $("watchlist-grid").innerHTML = '<div class="loader">Загружаем…</div>';
  try {
    const items = await apiFetch(mtq("/watchlist"));
    state.watchlist = new Set(items.map(m => m.movie_id));
    $("watchlist-count").textContent = items.length;
    if (!items.length) {
      $("watchlist-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">🕐</span><p>Список пуст</p></div>`;
      return;
    }
    renderMovies($("watchlist-grid"), items.map(m => ({...m, id: m.movie_id})), "watchlist");
  } catch {
    $("watchlist-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

// ─── Рекомендации ──────────────────────────────────────────────────────────
$("get-recs-btn").addEventListener("click", loadRecommendations);

// Кнопка «Применить фильтры»
const applyFiltersBtn = document.getElementById("apply-filters-btn");
if (applyFiltersBtn) applyFiltersBtn.addEventListener("click", () => {
  if (state.allRecs.length > 0) applyFiltersAndRender();
});

// Студия — перезапрашивает пул
const studioSelectEl = document.getElementById("filter-studio");
if (studioSelectEl) studioSelectEl.addEventListener("change", () => {
  if (state.allRecs.length > 0) loadRecommendations();
});

// Сортировка — клиентская
document.querySelectorAll(".sort-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".sort-btn").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    state.currentSort = btn.dataset.sort;
    if (state.allRecs.length > 0) applyFiltersAndRender();
  });
});

// Открытие/закрытие мульти-фильтр панелей
["mf-genre-btn", "mf-country-btn"].forEach(btnId => {
  const btn = document.getElementById(btnId);
  if (!btn) return;
  const key = btnId === "mf-genre-btn" ? "genre" : "country";
  btn.addEventListener("click", e => {
    e.stopPropagation();
    const panel = $(`mf-${key}-panel`);
    if (!panel) return;
    const wasHidden = panel.hidden;
    document.querySelectorAll(".mf-panel").forEach(p => { p.hidden = true; });
    if (wasHidden) { panel.hidden = false; buildMfPanel(key); }
  });
});

document.addEventListener("click", e => {
  if (!e.target.closest(".mf-group")) {
    document.querySelectorAll(".mf-panel").forEach(p => { p.hidden = true; });
  }
});

function renderRecsPage(recs, showCount) {
  const grid = $("recs-grid");
  renderMovies(grid, recs.slice(0, showCount), "recommendations");
  const old = $("load-more-btn");
  if (old) old.remove();
  const remaining = recs.length - showCount;
  if (remaining > 0) {
    const btn = document.createElement("button");
    btn.id = "load-more-btn"; btn.className = "load-more-btn";
    btn.innerHTML = `<span class="page-btn-text">Следующие ${Math.min(remaining, PAGE_SIZE)} фильмов</span><span class="page-btn-sub">Осталось: ${remaining}</span>`;
    btn.addEventListener("click", () => renderRecsPage(recs, showCount + PAGE_SIZE));
    grid.appendChild(btn);
  }
}

async function loadRecommendations() {
  const btn      = $("get-recs-btn");
  btn.disabled   = true; btn.textContent = "Анализируем…";
  const studioId = $("filter-studio")?.value || "0";
  const incCountries = [...state.filterState.country.inc].join(",");
  const label = state.mediaType === "tv" ? "сериалы" : "фильмы";

  $("recs-grid").innerHTML = `<div class="loader">Подбираем ${label}…</div>`;

  try {
    const params = new URLSearchParams({ studio_id: studioId, media_type: state.mediaType });
    if (incCountries) params.set("country", incCountries);
    const recs   = await apiFetch(`/recommendations?${params}`);
    state.allRecs = recs;
    $("sort-wrap").style.display = "flex";
    if (!recs.length) {
      $("recs-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">◌</span><p>Ничего не найдено</p></div>`;
    } else {
      applyFiltersAndRender();
      toast(`Загружено ${recs.length} фильмов!`, "success");
    }
  } catch (err) {
    $("recs-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">✦</span><p>${err.detail || "Добавь хотя бы один фильм в просмотренное"}</p></div>`;
  } finally {
    btn.disabled = false; btn.textContent = "✦ Подобрать фильмы";
  }
}

function sortRecs(recs) {
  const sorted = [...recs];
  if (state.currentSort === "rating") {
    sorted.sort((a, b) => (b.vote_average || 0) - (a.vote_average || 0));
  } else if (state.currentSort === "popularity") {
    sorted.sort((a, b) => (b.popularity || 0) - (a.popularity || 0));
  } else if (state.currentSort === "recent") {
    sorted.sort((a, b) => (b.release_date || "0000").localeCompare(a.release_date || "0000"));
  }
  // similarity — оставляем оригинальный порядок от recommender
  return sorted;
}

// ─── Мульти-фильтр: функции ────────────────────────────────────────────────

function buildMfPanel(key) {
  const panel = $(`mf-${key}-panel`);
  if (!panel) return;
  const { inc, exc } = state.filterState[key];
  const items = mfItems[key];
  panel.innerHTML = "";

  if (!items.length) {
    panel.innerHTML = `<div style="padding:12px 8px;color:var(--text-dim);font-size:13px">Сначала загрузи рекомендации</div>`;
    return;
  }
  items.forEach(({ value, label }) => {
    const isInc = inc.has(value), isExc = exc.has(value);
    const row = document.createElement("div");
    row.className = "mf-item";
    row.innerHTML = `
      <button class="mf-inc${isInc ? " active" : ""}" title="Включить">✓</button>
      <button class="mf-exc${isExc ? " active" : ""}" title="Исключить">✕</button>
      <span class="mf-label">${label}</span>
    `;
    row.querySelector(".mf-inc").addEventListener("click", () => toggleMf(key, "inc", value));
    row.querySelector(".mf-exc").addEventListener("click", () => toggleMf(key, "exc", value));
    panel.appendChild(row);
  });
}

function toggleMf(key, mode, value) {
  const { inc, exc } = state.filterState[key];
  const primary   = mode === "inc" ? inc : exc;
  const secondary = mode === "inc" ? exc : inc;
  if (primary.has(value)) primary.delete(value);
  else { primary.add(value); secondary.delete(value); }
  buildMfPanel(key);
  updateMfCount(key);
  renderActiveTags();
}

function updateMfCount(key) {
  const { inc, exc } = state.filterState[key];
  const total = inc.size + exc.size;
  const countEl = $(`mf-${key}-count`);
  const btnEl   = $(`mf-${key}-btn`);
  if (countEl) { countEl.textContent = total; countEl.hidden = total === 0; }
  if (btnEl)   { btnEl.classList.toggle("has-active", total > 0); }
}

function renderActiveTags() {
  const container = $("active-filters");
  if (!container) return;
  container.innerHTML = "";

  const addTags = (key, mode, getLabel) => {
    for (const val of state.filterState[key][mode]) {
      const tag = document.createElement("span");
      tag.className = `af-tag ${mode}`;
      tag.innerHTML = `<span>${mode === "inc" ? "✓" : "✕"}</span> ${getLabel(val)} <span>×</span>`;
      tag.title = "Нажми чтобы убрать";
      tag.addEventListener("click", () => {
        state.filterState[key][mode].delete(val);
        updateMfCount(key);
        buildMfPanel(key);
        renderActiveTags();
      });
      container.appendChild(tag);
    }
  };
  addTags("genre",   "inc", v => v);
  addTags("genre",   "exc", v => v);
  addTags("country", "inc", v => COUNTRY_LABELS[v] || v);
  addTags("country", "exc", v => COUNTRY_LABELS[v] || v);
}

function updateGenrePanel(pool) {
  const genreSet = new Set();
  pool.forEach(m => (m.genres || []).forEach(g => { const n = g.name || g; if (n) genreSet.add(n); }));
  mfItems.genre = [...genreSet].sort().map(n => ({ value: n, label: n }));

  // Убираем выбранные жанры которых больше нет в пуле
  ["inc", "exc"].forEach(mode => {
    for (const v of state.filterState.genre[mode]) {
      if (!genreSet.has(v)) { state.filterState.genre[mode].delete(v); }
    }
  });
  updateMfCount("genre");
  renderActiveTags();

  const panel = $("mf-genre-panel");
  if (panel && !panel.hidden) buildMfPanel("genre");
}

function applyFiltersAndRender() {
  const yearFrom  = parseInt($("filter-year-from")?.value) || 0;
  const yearTo    = parseInt($("filter-year-to")?.value)   || 9999;
  const minRating = parseFloat($("filter-min-rating")?.value) || 0;
  const { genre, country } = state.filterState;

  let pool = sortRecs(state.allRecs);

  // Год
  if (yearFrom) pool = pool.filter(m => parseInt((m.release_date || "0000").slice(0, 4)) >= yearFrom);
  if (yearTo < 9999) pool = pool.filter(m => parseInt((m.release_date || "9999").slice(0, 4)) <= yearTo);

  // Рейтинг (IMDb если есть, иначе TMDB)
  if (minRating > 0) pool = pool.filter(m => {
    const r = m.imdb_rating ?? m.vote_average ?? 0;
    return Number(r) >= minRating;
  });

  // Жанр include/exclude
  if (genre.inc.size > 0) pool = pool.filter(m => (m.genres||[]).some(g => genre.inc.has(g.name||g)));
  if (genre.exc.size > 0) pool = pool.filter(m => !(m.genres||[]).some(g => genre.exc.has(g.name||g)));

  // Страна include/exclude — нормализуем origin_country в массив, фильтруем по OR
  const getCountries = m => {
    const oc = m.origin_country;
    if (Array.isArray(oc)) return oc;
    if (oc && typeof oc === "string") return [oc];
    return [];
  };
  if (country.inc.size > 0) pool = pool.filter(m => getCountries(m).some(c => country.inc.has(c)));
  if (country.exc.size > 0) pool = pool.filter(m => !getCountries(m).some(c => country.exc.has(c)));

  if (!pool.length) {
    $("recs-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">◌</span><p>Ничего не найдено с такими фильтрами</p></div>`;
    return;
  }
  renderRecsPage(pool, PAGE_SIZE);
}

// ─── Флаги стран ───────────────────────────────────────────────────────────
const COUNTRY_FLAGS = {
  US:"🇺🇸", GB:"🇬🇧", FR:"🇫🇷", DE:"🇩🇪", IT:"🇮🇹", JP:"🇯🇵",
  KR:"🇰🇷", RU:"🇷🇺", IN:"🇮🇳", ES:"🇪🇸", CN:"🇨🇳", SE:"🇸🇪",
  AU:"🇦🇺", TR:"🇹🇷", MX:"🇲🇽", BR:"🇧🇷", CA:"🇨🇦", DK:"🇩🇰",
  NO:"🇳🇴", FI:"🇫🇮", PL:"🇵🇱", NL:"🇳🇱", BE:"🇧🇪", PT:"🇵🇹",
  IR:"🇮🇷", TH:"🇹🇭", HK:"🇭🇰", TW:"🇹🇼", AR:"🇦🇷", ZA:"🇿🇦",
};
function getCountryFlag(code) {
  return COUNTRY_FLAGS[code] || "🌍";
}

// ─── Рендер карточек ───────────────────────────────────────────────────────
function renderMovies(container, movies, mode = "discover") {
  if (!movies?.length) {
    container.innerHTML = `<div class="empty-state"><span class="empty-icon">◌</span><p>Ничего не найдено</p></div>`;
    return;
  }
  container.innerHTML = "";

  movies.forEach((movie, index) => {
    const card     = document.createElement("div");
    card.className = "movie-card";
    card.style.animationDelay = `${Math.min(index, 20) * 40}ms`;

    const posterUrl   = movie.poster_path ? `${TMDB_IMG}${movie.poster_path}` : null;
    const year        = (movie.release_date || "").slice(0, 4) || "—";
    const movieId     = movie.id || movie.movie_id;
    const isWatched   = state.watched.has(movieId);
    const userRating  = state.watched.get(movieId) ?? movie.user_rating;
    const isWatch     = state.watchlist.has(movieId);
    const showDismiss = mode !== "watched" && mode !== "watchlist" && mode !== "dismissed";
    const showScore   = mode === "recommendations" && movie.similarity_score;
    const noRating    = mode === "watched" && !userRating;

    card.innerHTML = `
      ${showDismiss ? `<button class="dismiss-btn" title="Не интересно">✕</button>` : ""}
      ${showScore ? `<div class="similarity-badge">${Math.round(movie.similarity_score * 100)}%</div>` : ""}
      ${userRating ? `<div class="user-rating-badge">${userRating}</div>` : ""}
      ${noRating ? `<div class="no-rating-badge">не оценён</div>` : ""}
      ${posterUrl
        ? `<img class="movie-poster ${noRating ? "poster-unrated" : ""}" src="${posterUrl}" alt="${movie.title}" loading="lazy" />`
        : `<div class="no-poster"><span class="no-poster-icon">🎬</span>${movie.title}</div>`
      }
      <button class="watched-btn ${isWatched ? "is-watched" : ""}" title="${isWatched ? "Убрать из просмотренного" : "Отметить просмотренным"}">✓</button>
      <button class="watch-btn ${isWatch ? "is-watch" : ""}" title="${isWatch ? "Убрать из списка" : "К просмотру"}">🕐</button>
      <div class="movie-info">
        <div class="movie-title">${movie.title}</div>
        <div class="movie-meta">
          <span class="movie-year">${year}</span>
        </div>
        ${cardRatingsHTML(movie)}
        ${movie.origin_country?.[0] ? `<div class="movie-country">${getCountryFlag(movie.origin_country[0])} ${movie.origin_country[0]}</div>` : ""}
        ${userRating ? `<div class="my-rating-row">Моя оценка: <span class="my-rating-val">${userRating}/10</span></div>` : ""}
      </div>
    `;

    card.addEventListener("click", e => {
      if (e.target.closest(".watched-btn,.watch-btn,.dismiss-btn")) return;
      pushModal({ type: "movie", data: movie });
      openMovieModal(movie);
    });

    card.querySelector(".watched-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleWatched(movieId, card.querySelector(".watched-btn"), mode === "watched" ? container : null);
    });
    card.querySelector(".watch-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleWatchlist(movieId, card.querySelector(".watch-btn"), mode === "watchlist" ? container : null);
    });
    if (showDismiss) {
      card.querySelector(".dismiss-btn").addEventListener("click", e => {
        e.stopPropagation();
        dismissMovie(movieId, card, mode === "recommendations");
      });
    }
    container.appendChild(card);
  });
}

// ─── Стек модалок ──────────────────────────────────────────────────────────
function pushModal(entry) {
  entry.scrollTop = $("modal")?.scrollTop || 0;
  state.modalStack.push(entry);
  updateBackBtn();
}

function updateBackBtn() {
  $("modal-back-btn").style.display = state.modalStack.length > 1 ? "flex" : "none";
}

$("modal-back-btn").addEventListener("click", () => {
  state.modalStack.pop();
  const prev = state.modalStack[state.modalStack.length - 1];
  if (!prev) { closeModal(); return; }
  updateBackBtn();
  if (prev.type === "movie")  openMovieModal(prev.data, true);
  if (prev.type === "person") openPersonModal(prev.data, true);
  if (prev.type === "studio") openStudioModal(prev.data, true);
});

// ─── Модалка: фильм ────────────────────────────────────────────────────────
async function openMovieModal(movie, isBack = false) {
  if (!isBack) {
    $("modal-overlay").classList.add("open");
    document.body.style.overflow = "hidden";
  }
  $("similar-section").style.display = "none";
  $("modal-content").innerHTML = `<div style="height:400px;display:flex;align-items:center;justify-content:center;color:var(--text-dim)">Загружаем…</div>`;

  // Приоритет: явный _mediaType (из pushModal), потом media_type объекта, потом текущая вкладка
  const mediaType = movie._mediaType || movie.media_type || state.mediaType;

  try {
    const details = await apiFetch(`/movie/${movie.id || movie.movie_id}/details?media_type=${mediaType}`);
    renderMovieContent(details);
    if (isBack) $("modal").scrollTop = state.modalStack[state.modalStack.length - 1]?.scrollTop || 0;
  } catch {
    renderMovieContent(movie);
  }
}

function renderSeasonsHTML(movie) {
  const seasons = (movie.seasons || []).filter(s => s.season_number > 0);
  if (!seasons.length) return "";
  const rows = seasons.map(s => {
    const year = (s.air_date || "").slice(0, 4);
    const epCount = s.episode_count ? `${s.episode_count} эп` : "";
    const meta = [year, epCount].filter(Boolean).join(" · ");
    return `<div class="season-row" data-show-id="${movie.id || movie.movie_id}" data-season="${s.season_number}">
      <button class="season-toggle">
        <span class="season-name">${s.name || `Сезон ${s.season_number}`}</span>
        <span class="season-meta">${meta}</span>
        <span class="season-arrow">▸</span>
      </button>
      <div class="season-episodes" hidden></div>
    </div>`;
  }).join("");
  return `<div class="seasons-section"><h3 class="cast-title">Сезоны и серии</h3><div class="seasons-list">${rows}</div></div>`;
}

function bindSeasonsEvents(movieId) {
  document.querySelectorAll(".season-row").forEach(row => {
    const btn = row.querySelector(".season-toggle");
    const ep  = row.querySelector(".season-episodes");
    const arrow = row.querySelector(".season-arrow");
    btn.addEventListener("click", async () => {
      const isOpen = !ep.hidden;
      if (isOpen) {
        ep.hidden = true; arrow.textContent = "▸"; return;
      }
      ep.hidden = false; arrow.textContent = "▾";
      if (ep.dataset.loaded) return;
      ep.dataset.loaded = "1";
      ep.innerHTML = `<div class="ep-loading">Загружаем…</div>`;
      try {
        const showId = row.dataset.showId;
        const season = row.dataset.season;
        const episodes = await apiFetch(`/tv/${showId}/season/${season}`);
        if (!episodes?.length) { ep.innerHTML = `<div class="ep-loading">Серии не найдены</div>`; return; }
        ep.innerHTML = episodes.map(e => {
          const airDate = e.air_date ? formatDate(e.air_date) : "—";
          const runtime = e.runtime ? ` · ${e.runtime} мин` : "";
          const rating  = e.vote_average && e.vote_average > 0 ? ` · ★ ${Number(e.vote_average).toFixed(1)}` : "";
          return `<div class="episode-item">
            <span class="ep-num">E${String(e.episode_number).padStart(2, "0")}</span>
            <div class="ep-info">
              <div class="ep-name">${e.name || `Серия ${e.episode_number}`}</div>
              <div class="ep-meta">${airDate}${runtime}${rating}</div>
            </div>
          </div>`;
        }).join("");
      } catch {
        ep.innerHTML = `<div class="ep-loading">Ошибка загрузки</div>`;
      }
    });
  });
}

function formatDate(iso) {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  const months = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];
  return `${parseInt(d)} ${months[parseInt(m)-1]} ${y}`;
}

function renderMovieContent(movie) {
  const movieId     = movie.id || movie.movie_id;
  const isWatched   = state.watched.has(movieId) || movie.is_watched;
  const isWatch     = state.watchlist.has(movieId) || movie.is_watchlist;
  const userRating  = state.watched.get(movieId) ?? movie.watched_info?.user_rating;
  const review      = movie.watched_info?.review;
  const posterUrl   = movie.poster_path ? `${TMDB_IMG}${movie.poster_path}` : null;
  const backdropUrl = movie.backdrop_path ? `https://image.tmdb.org/t/p/w1280${movie.backdrop_path}` : posterUrl;
  const year        = (movie.release_date || "").slice(0, 4) || "—";
  const rating      = movie.vote_average != null ? Number(movie.vote_average).toFixed(1) : "—";
  const tmdbVotesL  = fmtVotes(movie.vote_count);
  const imdbStat    = movie.imdb_rating != null
    ? `<div class="modal-stat"><span class="modal-stat-label">IMDb</span><span class="modal-stat-value">★ ${movie.imdb_rating}<span class="stat-votes"> ${fmtVotes(movie.imdb_vote_count)}</span></span></div>`
    : "";
  const runtime = movie.seasons_count
    ? `${movie.seasons_count} сез · ${movie.episodes_count || "?"} эп`
    : movie.runtime ? `${movie.runtime} мин` : "";
  const genres  = (movie.genres || []).map(g => typeof g === "string" ? g : g.name).filter(Boolean);

  const studiosHTML = (movie.studios || []).map(s =>
    `<button class="studio-btn" data-studio-id="${s.id}" data-studio-name="${s.name}">` +
    (s.logo ? `<img class="studio-logo" src="${TMDB_LOGO}${s.logo}" alt="${s.name}" />` : `<span class="studio-name-text">${s.name}</span>`) +
    `</button>`
  ).join("");

  const castHTML = (movie.cast || []).map(p =>
    `<button class="cast-card" data-person-id="${p.id}">
      ${p.profile_path ? `<img class="cast-photo" src="${TMDB_SM}${p.profile_path}" alt="${p.name}" />` : `<div class="cast-photo cast-no-photo">👤</div>`}
      <div class="cast-name">${p.name}</div>
      <div class="cast-role">${p.character || ""}</div>
    </button>`
  ).join("");

  // Рейтинговые кнопки 1-10
  const ratingHTML = `
    <div class="rating-section">
      <div class="rating-label">Моя оценка</div>
      <div class="rating-btns" id="rating-btns">
        ${Array.from({length: 10}, (_, i) => {
          const n = i + 1;
          const cls = userRating === n ? "rating-btn active" : "rating-btn";
          const colorClass = n >= 8 ? "good" : n >= 6 ? "ok" : n >= 4 ? "meh" : "bad";
          return `<button class="${cls} ${colorClass}" data-rating="${n}">${n}</button>`;
        }).join("")}
      </div>
      <textarea class="review-input" id="review-input" placeholder="Написать отзыв (необязательно)…" rows="2">${review || ""}</textarea>
      <button class="save-rating-btn" id="save-rating-btn">Сохранить оценку</button>
    </div>
  `;

  $("modal-back-btn").style.display = state.modalStack.length > 1 ? "flex" : "none";

  $("modal-content").innerHTML = `
    <div class="modal-hero" id="modal-hero">
      ${backdropUrl ? `<img class="modal-backdrop" src="${backdropUrl}" alt="" />` : `<div style="height:280px;background:var(--border)"></div>`}
      <div class="modal-backdrop-overlay"></div>
      ${posterUrl ? `<div class="modal-poster-wrap"><img class="modal-poster" src="${posterUrl}" /></div>` : ""}
      <button class="trailer-play-btn" id="trailer-play-btn"><span class="trailer-play-icon">▶</span><span>Трейлер</span></button>
    </div>
    <div class="trailer-player" id="trailer-player" style="display:none">
      <iframe id="trailer-iframe" width="100%" height="380" frameborder="0"
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
      <button class="trailer-close-btn" id="trailer-close-btn">✕ Закрыть трейлер</button>
    </div>
    <div class="modal-body">
      <h2 class="modal-title">${movie.title}</h2>
      ${movie.original_title && movie.original_title !== movie.title ? `<div class="modal-original-title">${movie.original_title}</div>` : ""}
      ${genres.length ? `<div class="modal-tags">${genres.map(g => `<span class="modal-tag">${g}</span>`).join("")}</div>` : ""}
      <div class="modal-stats">
        <div class="modal-stat"><span class="modal-stat-label">TMDB</span><span class="modal-stat-value">★ ${rating}<span class="stat-votes"> ${tmdbVotesL}</span></span></div>
        ${imdbStat}
        <div class="modal-stat"><span class="modal-stat-label">Год</span><span class="modal-stat-value">${year}</span></div>
        ${runtime ? `<div class="modal-stat"><span class="modal-stat-label">Длительность</span><span class="modal-stat-value">${runtime}</span></div>` : ""}
        ${movie.director ? `<div class="modal-stat"><span class="modal-stat-label">Режиссёр</span><button class="director-btn" data-person-id="${movie.director_id}">${movie.director}</button></div>` : ""}
        ${movie.similarity_score ? `<div class="modal-stat"><span class="modal-stat-label">Совпадение</span><span class="modal-stat-value">${Math.round(movie.similarity_score * 100)}%</span></div>` : ""}
      </div>
      ${movie.overview ? `<p class="modal-overview">${movie.overview}</p>` : ""}
      ${studiosHTML ? `<div class="studios-row">${studiosHTML}</div>` : ""}
      <div class="modal-actions">
        <button class="modal-watched-btn ${isWatched ? "remove" : ""}" id="modal-watched-btn">${isWatched ? "✓ Просмотрено" : "✓ Отметить просмотренным"}</button>
        <button class="modal-watch-btn ${isWatch ? "remove" : ""}" id="modal-watch-btn">${isWatch ? "✕ Убрать из списка" : "🕐 К просмотру"}</button>
      </div>
      ${ratingHTML}
      ${castHTML ? `<div class="cast-section"><h3 class="cast-title">В ролях</h3><div class="cast-grid">${castHTML}</div></div>` : ""}
      ${state.mediaType === "tv" && movie.seasons?.length ? renderSeasonsHTML(movie) : ""}
    </div>
  `;

  // Сезоны
  if (state.mediaType === "tv") bindSeasonsEvents(movieId);

  // Трейлер
  $("trailer-play-btn").addEventListener("click", async () => {
    const btn = $("trailer-play-btn");
    btn.innerHTML = `<span>⏳</span><span>Загружаем…</span>`; btn.disabled = true;
    try {
      const data = await apiFetch(`/trailer/${movieId}?media_type=${state.mediaType}`);
      $("modal-hero").style.display = "none";
      $("trailer-player").style.display = "block";
      $("trailer-iframe").src = `https://www.youtube.com/embed/${data.key}?autoplay=1&rel=0`;
    } catch {
      toast("Трейлер не найден", "error");
      btn.innerHTML = `<span class="trailer-play-icon">▶</span><span>Трейлер</span>`; btn.disabled = false;
    }
  });
  $("trailer-close-btn").addEventListener("click", () => {
    $("trailer-iframe").src = "";
    $("trailer-player").style.display = "none";
    $("modal-hero").style.display = "block";
    $("trailer-play-btn").innerHTML = `<span class="trailer-play-icon">▶</span><span>Трейлер</span>`;
    $("trailer-play-btn").disabled = false;
  });

  // Просмотрено
  $("modal-watched-btn").addEventListener("click", async () => {
    await toggleWatched(movieId, $("modal-watched-btn"));
    const now = state.watched.has(movieId);
    $("modal-watched-btn").className = `modal-watched-btn ${now ? "remove" : ""}`;
    $("modal-watched-btn").textContent = now ? "✓ Просмотрено" : "✓ Отметить просмотренным";
  });

  // К просмотру
  $("modal-watch-btn").addEventListener("click", async () => {
    await toggleWatchlist(movieId, $("modal-watch-btn"));
    const now = state.watchlist.has(movieId);
    $("modal-watch-btn").className = `modal-watch-btn ${now ? "remove" : ""}`;
    $("modal-watch-btn").textContent = now ? "✕ Убрать из списка" : "🕐 К просмотру";
  });

  // Оценка: выбор кнопки
  let selectedRating = userRating || null;
  document.querySelectorAll(".rating-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".rating-btn").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      selectedRating = parseInt(btn.dataset.rating);
    });
  });

  // Сохранить оценку
  $("save-rating-btn").addEventListener("click", async () => {
    if (!selectedRating) { toast("Выбери оценку от 1 до 10", "error"); return; }
    const review = $("review-input").value.trim();
    try {
      await apiFetch("/watched/rate", {
        method: "POST",
        body: JSON.stringify({ movie_id: movieId, rating: selectedRating, review: review || null, media_type: state.mediaType }),
      });
      state.watched.set(movieId, selectedRating);
      $("watch-count").textContent = state.watched.size;
      toast(`Оценка ${selectedRating}/10 сохранена!`, "success");
      $("modal-watched-btn").className = "modal-watched-btn remove";
      $("modal-watched-btn").textContent = "✓ Просмотрено";
    } catch (err) {
      toast(err.detail || "Ошибка сохранения", "error");
    }
  });

  // Актёры
  document.querySelectorAll(".cast-card").forEach(btn => {
    btn.addEventListener("click", () => {
      pushModal({ type: "person", data: { id: parseInt(btn.dataset.personId) } });
      openPersonModal({ id: parseInt(btn.dataset.personId) });
    });
  });

  // Режиссёр
  document.querySelectorAll(".director-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      pushModal({ type: "person", data: { id: parseInt(btn.dataset.personId) } });
      openPersonModal({ id: parseInt(btn.dataset.personId) });
    });
  });

  // Студии
  document.querySelectorAll(".studio-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      const studio = { id: parseInt(btn.dataset.studioId), name: btn.dataset.studioName };
      pushModal({ type: "studio", data: studio });
      openStudioModal(studio);
    });
  });

  // Похожие фильмы
  const simSec  = $("similar-section");
  const simGrid = $("similar-grid");
  simSec.style.display = "block";
  simGrid.innerHTML = '<div class="loader">Загружаем похожие…</div>';
  apiFetch(`/similar/${movieId}?media_type=${state.mediaType}`).then(similar => {
    if (!similar?.length) { simSec.style.display = "none"; return; }
    renderMoviesInline(simGrid, similar);
  }).catch(() => simSec.style.display = "none");
}

// ─── Модалка: актёр / режиссёр ─────────────────────────────────────────────
async function openPersonModal(person, isBack = false) {
  $("similar-section").style.display = "none";
  $("modal-content").innerHTML = `<div style="height:400px;display:flex;align-items:center;justify-content:center;color:var(--text-dim)">Загружаем…</div>`;
  try {
    const [personData, tvCredits, watchedApps] = await Promise.all([
      apiFetch(`/person/${person.id}/movies?media_type=movie`),
      apiFetch(`/person/${person.id}/movies?media_type=tv`),
      apiFetch(`/person/${person.id}/watched-appearances`).catch(() => []),
    ]);
    const movieCredits = personData;

    const photoUrl = personData.profile_path ? `${TMDB_IMG}${personData.profile_path}` : null;
    const bio      = personData.biography
      ? (personData.biography.length > 400 ? personData.biography.slice(0, 400) + "…" : personData.biography)
      : "";
    const dept     = personData.known_for_department === "Directing" ? "Режиссёр" : "Актёр";
    const isFav    = state.favActors.has(person.id);

    $("modal-content").innerHTML = `
      <div class="person-hero">
        <div class="person-hero-inner">
          ${photoUrl ? `<img class="person-photo" src="${photoUrl}" alt="${personData.name}" />` : `<div class="person-photo person-no-photo">👤</div>`}
          <div class="person-info">
            <div class="person-dept">${dept}</div>
            <h2 class="modal-title" style="margin-bottom:8px">${personData.name}</h2>
            ${personData.birthday ? `<div class="person-birth">Дата рождения: ${personData.birthday}</div>` : ""}
            ${bio ? `<p class="person-bio">${bio}</p>` : ""}
            <button class="person-fav-btn${isFav ? " is-fav" : ""}" id="person-fav-btn">
              ★ ${isFav ? "В избранных" : "В избранные"}
            </button>
          </div>
        </div>
      </div>
      <div class="person-tabs">
        <button class="person-tab-btn${watchedApps?.length ? " active" : ""}" data-ptab="ratings">
          Мои оценки${watchedApps?.length ? ` <span class="ptab-count">${watchedApps.length}</span>` : ""}
        </button>
        <button class="person-tab-btn${!watchedApps?.length ? " active" : ""}" data-ptab="movies">Фильмы</button>
        <button class="person-tab-btn" data-ptab="tv">Сериалы</button>
      </div>
      <div id="person-tab-content" class="person-tab-content"></div>
    `;

    // Данные для каждой вкладки
    const tabData = {
      ratings: watchedApps || [],
      movies:  movieCredits.movies || [],
      tv:      tvCredits.movies || [],
    };

    function showPersonTab(key) {
      document.querySelectorAll(".person-tab-btn").forEach(b => b.classList.toggle("active", b.dataset.ptab === key));
      const content = $("person-tab-content");
      if (key === "ratings") {
        renderPersonWatched(content, tabData.ratings);
      } else {
        content.innerHTML = `
          <div class="modal-body" style="padding-top:16px;padding-bottom:4px">
            <div class="modal-sort-bar" id="person-sort-bar-${key}"></div>
          </div>
          <div class="movies-grid person-movies-grid" id="person-movies-grid-${key}" style="padding:0 28px 28px"></div>
        `;
        renderMoviesInline($(`person-movies-grid-${key}`), tabData[key]);
        attachInlineSortBar(`person-sort-bar-${key}`, `person-movies-grid-${key}`, tabData[key]);
      }
    }

    document.querySelectorAll(".person-tab-btn").forEach(btn => {
      btn.addEventListener("click", () => showPersonTab(btn.dataset.ptab));
    });

    // Кнопка избранного
    $("person-fav-btn").addEventListener("click", async () => {
      const btn = $("person-fav-btn");
      await toggleFavActor(person.id, personData.name, personData.profile_path, { classList: { add: () => {}, remove: () => {}, toggle: () => {} } });
      const nowFav = state.favActors.has(person.id);
      btn.className = `person-fav-btn${nowFav ? " is-fav" : ""}`;
      btn.textContent = `★ ${nowFav ? "В избранных" : "В избранные"}`;
    });

    // Показываем первую вкладку
    showPersonTab(watchedApps?.length ? "ratings" : "movies");
    if (isBack) $("modal").scrollTop = state.modalStack[state.modalStack.length - 1]?.scrollTop || 0;
  } catch { toast("Не удалось загрузить информацию", "error"); }
}

function renderPersonWatched(container, items) {
  if (!items?.length) {
    container.innerHTML = `<div class="empty-state" style="height:140px"><p>Нет просмотренных фильмов с этим актёром</p></div>`;
    return;
  }
  container.innerHTML = `<div class="my-ratings-list">${items.map(m => {
    const posterUrl = m.poster_path ? `${TMDB_SM}${m.poster_path}` : null;
    const year = (m.release_date || "").slice(0, 4) || "—";
    const ratingBadge = m.user_rating
      ? `<div class="my-rating-badge">${m.user_rating}</div>`
      : `<div class="my-rating-badge no-rating">—</div>`;
    const typeLabel = m.media_type === "tv" ? "сериал" : "фильм";
    return `<div class="my-rating-item" data-id="${m.id}" data-type="${m.media_type}">
      ${posterUrl ? `<img class="my-rating-poster" src="${posterUrl}" alt="${m.title}" />` : `<div class="my-rating-poster my-rating-no-poster">🎬</div>`}
      <div class="my-rating-info">
        <div class="my-rating-title">${m.title || m.name || "—"}</div>
        <div class="my-rating-meta">${year} · ${typeLabel}</div>
      </div>
      ${ratingBadge}
    </div>`;
  }).join("")}</div>`;

  container.querySelectorAll(".my-rating-item").forEach(el => {
    el.addEventListener("click", () => {
      const id   = parseInt(el.dataset.id);
      const type = el.dataset.type;
      pushModal({ type: "movie", data: { id, _mediaType: type } });
      const prev = state.mediaType;
      state.mediaType = type;
      openMovieModal({ id }).finally(() => { state.mediaType = prev; });
    });
  });
}

// ─── Модалка: студия ───────────────────────────────────────────────────────
async function openStudioModal(studio, isBack = false) {
  $("similar-section").style.display = "none";
  $("modal-content").innerHTML = `<div style="height:400px;display:flex;align-items:center;justify-content:center;color:var(--text-dim)">Загружаем фильмы ${studio.name}…</div>`;
  try {
    const movies = await apiFetch(`/studio/${studio.id}/movies?media_type=${state.mediaType}`);
    $("modal-content").innerHTML = `
      <div class="modal-body" style="padding-top:32px">
        <h2 class="modal-title">${studio.name}</h2>
        <p class="section-sub" style="margin-bottom:12px">Популярные фильмы студии</p>
        <div class="modal-sort-bar" id="studio-sort-bar"></div>
        <div class="movies-grid person-movies-grid" id="studio-movies-grid"></div>
      </div>
    `;
    renderMoviesInline($("studio-movies-grid"), movies);
    attachInlineSortBar("studio-sort-bar", "studio-movies-grid", movies);
    if (isBack) $("modal").scrollTop = state.modalStack[state.modalStack.length - 1]?.scrollTop || 0;
  } catch { toast("Не удалось загрузить фильмы студии", "error"); }
}

// ─── Сортировка внутри модалки ─────────────────────────────────────────────

function sortMoviesInline(movies, sort) {
  const arr = [...movies];
  if (sort === "rating")   return arr.sort((a, b) => (b.vote_average || 0) - (a.vote_average || 0));
  if (sort === "recent")   return arr.sort((a, b) => (b.release_date || "0000").localeCompare(a.release_date || "0000"));
  if (sort === "oldest")   return arr.sort((a, b) => (a.release_date || "9999").localeCompare(b.release_date || "9999"));
  return arr; // popularity — оригинальный порядок от TMDB
}

function attachInlineSortBar(barId, gridId, movies) {
  const bar = $(barId);
  if (!bar) return;
  const sorts = [
    { key: "popularity", label: "По популярности" },
    { key: "rating",     label: "По оценке" },
    { key: "recent",     label: "Новые" },
    { key: "oldest",     label: "Старые" },
  ];
  sorts.forEach((s, i) => {
    const btn = document.createElement("button");
    btn.className = i === 0 ? "sort-btn active" : "sort-btn";
    btn.textContent = s.label;
    btn.addEventListener("click", () => {
      bar.querySelectorAll(".sort-btn").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      renderMoviesInline($(gridId), sortMoviesInline(movies, s.key));
    });
    bar.appendChild(btn);
  });
}

// ─── Рендер фильмов внутри модалки ────────────────────────────────────────
function renderMoviesInline(container, movies) {
  if (!movies?.length) {
    container.innerHTML = `<div class="empty-state" style="height:120px"><p>Ничего не найдено</p></div>`;
    return;
  }
  container.innerHTML = "";
  movies.forEach((movie, i) => {
    const card     = document.createElement("div");
    card.className = "movie-card";
    card.style.animationDelay = `${Math.min(i, 10) * 40}ms`;
    const posterUrl  = movie.poster_path ? `${TMDB_IMG}${movie.poster_path}` : null;
    const year       = (movie.release_date || "").slice(0, 4) || "—";
    const movieId    = movie.id || movie.movie_id;
    const isWatched  = state.watched.has(movieId);
    const userRating = state.watched.get(movieId);
    const isWatch    = state.watchlist.has(movieId);

    card.innerHTML = `
      ${userRating ? `<div class="user-rating-badge">${userRating}</div>` : ""}
      ${posterUrl ? `<img class="movie-poster" src="${posterUrl}" alt="${movie.title}" loading="lazy" />` : `<div class="no-poster"><span class="no-poster-icon">🎬</span>${movie.title}</div>`}
      <button class="watched-btn ${isWatched ? "is-watched" : ""}">✓</button>
      <button class="watch-btn ${isWatch ? "is-watch" : ""}">🕐</button>
      <div class="movie-info">
        <div class="movie-title">${movie.title}</div>
        <div class="movie-meta"><span class="movie-year">${year}</span></div>
        ${cardRatingsHTML(movie)}
      </div>
    `;
    const itemMediaType = movie.media_type || state.mediaType;

    card.addEventListener("click", e => {
      if (e.target.closest(".watched-btn,.watch-btn")) return;
      // Сохраняем media_type в объекте для корректного открытия (сериал vs фильм)
      const movieWithType = { ...movie, _mediaType: itemMediaType };
      pushModal({ type: "movie", data: movieWithType });
      openMovieModal(movieWithType);
    });
    card.querySelector(".watched-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleWatched(movieId, card.querySelector(".watched-btn"), null, itemMediaType);
    });
    card.querySelector(".watch-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleWatchlist(movieId, card.querySelector(".watch-btn"), null, itemMediaType);
    });
    container.appendChild(card);
  });
}

// ─── Закрыть модалку ──────────────────────────────────────────────────────
function closeModal() {
  const iframe = $("trailer-iframe");
  if (iframe) iframe.src = "";
  $("modal-overlay").classList.remove("open");
  document.body.style.overflow = "";
  state.modalStack = [];
  updateBackBtn();
}

$("modal-close").addEventListener("click", closeModal);
$("modal-overlay").addEventListener("click", e => { if (e.target === $("modal-overlay")) closeModal(); });
document.addEventListener("keydown", e => { if (e.key === "Escape") closeModal(); });

// ─── Просмотрено ───────────────────────────────────────────────────────────
async function toggleWatched(movieId, btn, containerToRefresh = null, mediaType = null) {
  const mt = mediaType || state.mediaType;
  const isWatched = state.watched.has(movieId);
  try {
    if (isWatched) {
      await apiFetch(`/watched/${movieId}?media_type=${mt}`, { method: "DELETE" });
      state.watched.delete(movieId);
      btn.classList.remove("is-watched");
      toast("Убрано из просмотренного");
      if (containerToRefresh) animateRemove(btn.closest(".movie-card"), () => loadWatched());
    } else {
      await apiFetch("/watched", { method: "POST", body: JSON.stringify({ movie_id: movieId, media_type: mt }) });
      state.watched.set(movieId, null);
      btn.classList.add("is-watched");
      toast("Добавлено в просмотренное ✓", "success");
    }
    $("watch-count").textContent = state.watched.size;
  } catch (err) { toast(err.detail || "Ошибка", "error"); }
}

// ─── К просмотру ───────────────────────────────────────────────────────────
async function toggleWatchlist(movieId, btn, containerToRefresh = null, mediaType = null) {
  const mt = mediaType || state.mediaType;
  const isWatch = state.watchlist.has(movieId);
  try {
    if (isWatch) {
      await apiFetch(`/watchlist/${movieId}?media_type=${mt}`, { method: "DELETE" });
      state.watchlist.delete(movieId); btn.classList.remove("is-watch");
      toast("Удалено из списка");
      if (containerToRefresh) animateRemove(btn.closest(".movie-card"), () => loadWatchlist());
    } else {
      await apiFetch("/watchlist", { method: "POST", body: JSON.stringify({ movie_id: movieId, media_type: mt }) });
      state.watchlist.add(movieId); btn.classList.add("is-watch");
      toast("Добавлено в список 🕐", "success");
    }
    $("watchlist-count").textContent = state.watchlist.size;
  } catch (err) { toast(err.detail || "Ошибка", "error"); }
}

// ─── Отклонить ─────────────────────────────────────────────────────────────
async function dismissMovie(movieId, card, removeFromList = false) {
  try {
    await apiFetch("/dismiss", { method: "POST", body: JSON.stringify({ movie_id: movieId, media_type: state.mediaType }) });
    if (state.dismissed) state.dismissed.add(movieId);
    if (removeFromList) {
      state.allRecs = state.allRecs.filter(m => m.id !== movieId);
      animateRemove(card);
    } else {
      const btn = card.querySelector(".dismiss-btn");
      if (btn) { btn.classList.add("is-dismissed"); btn.title = "Уже в неинтересных"; }
    }
    toast("Добавлено в неинтересные");
    const dc = document.getElementById("dismissed-count");
    if (dc) dc.textContent = parseInt(dc.textContent || "0") + 1;
  } catch (err) {
    console.error(err);
    toast("Ошибка при отклонении", "error");
  }
}

function animateRemove(card, callback) {
  card.style.transition = "all 0.3s ease";
  card.style.transform  = "scale(0)"; card.style.opacity = "0";
  setTimeout(() => { card.remove(); if (callback) callback(); }, 300);
}

// ─── HTTP ───────────────────────────────────────────────────────────────────
function getUID() {
  return state.user?.id ?? 1;
}

async function apiFetch(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...options.headers };

  // Inject user_id into URL query string
  const uid = getUID();
  let fullPath = path;
  if (!fullPath.includes("user_id=")) {
    const sep = fullPath.includes("?") ? "&" : "?";
    fullPath = `${fullPath}${sep}user_id=${uid}`;
  }

  // Inject user_id into POST/PUT/PATCH JSON body
  let finalOptions = options;
  if (options.body) {
    try {
      const bodyObj = JSON.parse(options.body);
      if (bodyObj.user_id === undefined) bodyObj.user_id = uid;
      finalOptions = { ...options, body: JSON.stringify(bodyObj) };
    } catch {}
  }

  const response = await fetch(`${API}${fullPath}`, { ...finalOptions, headers });
  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw err;
  }
  if (response.status === 204) return null;
  return response.json();
}

// ─── Тосты ─────────────────────────────────────────────────────────────────
function toast(message, type = "") {
  const el = document.createElement("div");
  el.className = `toast ${type}`; el.textContent = message;
  $("toast-container").appendChild(el);
  requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add("show")));
  setTimeout(() => { el.classList.remove("show"); setTimeout(() => el.remove(), 400); }, 3000);
}

// ─── Инициализация ─────────────────────────────────────────────────────────
async function init() {
  try {
    const [watchedList, watchlistItems, studios, dismissedList, genreList, favActorList] = await Promise.all([
      apiFetch(mtq("/watched")), apiFetch(mtq("/watchlist")),
      apiFetch(mtq("/studios")), apiFetch(mtq("/dismissed")),
      apiFetch(mtq("/genres")).catch(() => []),
      apiFetch("/favorite-actors").catch(() => []),
    ]);
    state.favActors = new Set((favActorList || []).map(a => a.actor_id));
    state.dismissed = new Set(dismissedList.map(m => m.movie_id));
    const dc = document.getElementById("dismissed-count");
    if (dc) dc.textContent = dismissedList.length;
    state.watched   = new Map(watchedList.map(m => [m.movie_id, m.user_rating]));
    state.watchlist = new Set(watchlistItems.map(m => m.movie_id));
    $("watch-count").textContent     = watchedList.length;
    $("watchlist-count").textContent = watchlistItems.length;

    const studioSelect = $("filter-studio");
    studios?.forEach(s => {
      const opt = document.createElement("option");
      opt.value = s.id; opt.textContent = s.name;
      studioSelect.appendChild(opt);
    });

    if (genreList?.length) {
      mfItems.genre = genreList.map(g => ({ value: g.name, label: g.name }));
    }
  } catch {}

  // Инициализируем панели фильтров (статические списки)
  buildMfPanel("country");
  buildMfPanel("genre");
  loadPopular();
}

// ─── Аутентификация ────────────────────────────────────────────────────────

function switchAuthTab(tab) {
  const isLogin = tab === "login";
  $("auth-tab-login").classList.toggle("active", isLogin);
  $("auth-tab-register").classList.toggle("active", !isLogin);
  $("auth-login-form").style.display    = isLogin ? "" : "none";
  $("auth-register-form").style.display = isLogin ? "none" : "";
  $("auth-login-error").textContent = "";
  $("auth-reg-error").textContent   = "";
}

async function authFetch(path, body) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 70_000); // 70 сек — ждём холодный старт Render
  try {
    const resp = await fetch(`${API}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: ctrl.signal,
    });
    clearTimeout(timer);
    return resp;
  } catch (err) {
    clearTimeout(timer);
    if (err.name === "AbortError") throw new Error("timeout");
    throw err;
  }
}

async function authLogin() {
  const username = $("auth-username-input").value.trim();
  const errEl    = $("auth-login-error");
  const btn      = document.querySelector("#auth-login-form .auth-btn");
  errEl.textContent = "";
  if (!username) { errEl.textContent = "Введи логин"; return; }

  btn.disabled = true;
  btn.textContent = "Подключаемся…";
  errEl.textContent = "⏳ Сервер просыпается, подожди до 60 сек…";

  try {
    const resp = await authFetch("/auth/login", { username });
    if (!resp.ok) {
      const e = await resp.json().catch(() => ({}));
      errEl.textContent = e.detail || "Пользователь не найден";
      return;
    }
    const user = await resp.json();
    setUser(user);
    $("auth-overlay").classList.remove("visible");
    toast(`Привет, ${user.display_name}! 👋`, "success");
    init();
  } catch (err) {
    errEl.textContent = err.message === "timeout"
      ? "Сервер не отвечает (>60 сек). Попробуй ещё раз."
      : "Не удалось подключиться к серверу";
  } finally {
    btn.disabled = false;
    btn.textContent = "Войти";
  }
}

async function authRegister() {
  const username = $("auth-reg-username").value.trim();
  const display  = $("auth-reg-display").value.trim();
  const errEl    = $("auth-reg-error");
  const btn      = document.querySelector("#auth-register-form .auth-btn");
  errEl.textContent = "";
  if (!username) { errEl.textContent = "Введи логин"; return; }
  if (!display)  { errEl.textContent = "Введи своё имя"; return; }

  btn.disabled = true;
  btn.textContent = "Подключаемся…";
  errEl.textContent = "⏳ Сервер просыпается, подожди до 60 сек…";

  try {
    const resp = await authFetch("/auth/register", { username, display_name: display });
    if (!resp.ok) {
      const e = await resp.json().catch(() => ({}));
      errEl.textContent = e.detail || "Ошибка регистрации";
      return;
    }
    const user = await resp.json();
    setUser(user);
    $("auth-overlay").classList.remove("visible");
    toast(`Добро пожаловать, ${user.display_name}! 🎬`, "success");
    init();
  } catch (err) {
    errEl.textContent = err.message === "timeout"
      ? "Сервер не отвечает (>60 сек). Попробуй ещё раз."
      : "Не удалось подключиться к серверу";
  } finally {
    btn.disabled = false;
    btn.textContent = "Зарегистрироваться";
  }
}

function setUser(user) {
  state.user = user;
  localStorage.setItem("film_user", JSON.stringify(user));
  const badge = $("user-badge");
  if (badge) {
    badge.classList.add("visible");
    $("user-name").textContent = user.display_name;
  }
}

function authLogout() {
  state.user      = null;
  state.watched   = new Map();
  state.watchlist = new Set();
  state.dismissed = new Set();
  state.favActors = new Set();
  localStorage.removeItem("film_user");
  const badge = $("user-badge");
  if (badge) badge.classList.remove("visible");
  $("watch-count").textContent     = "0";
  $("watchlist-count").textContent = "0";
  $("dismissed-count").textContent = "0";
  $("auth-username-input").value   = "";
  $("auth-login-error").textContent = "";
  switchAuthTab("login");
  $("auth-overlay").classList.add("visible");
}

// Enter в полях авторизации
document.addEventListener("DOMContentLoaded", () => {
  $("auth-username-input")?.addEventListener("keydown", e => { if (e.key === "Enter") authLogin(); });
  $("auth-reg-username")?.addEventListener("keydown",   e => { if (e.key === "Enter") authRegister(); });
  $("auth-reg-display")?.addEventListener("keydown",    e => { if (e.key === "Enter") authRegister(); });
});

// ─── Запуск ────────────────────────────────────────────────────────────────
(function startup() {
  const saved = localStorage.getItem("film_user");
  if (saved) {
    try {
      const user = JSON.parse(saved);
      setUser(user);
      init();
      return;
    } catch {}
  }
  // Нет сохранённого пользователя — показываем авторизацию
  $("auth-overlay").classList.add("visible");
})();

// ─── Актёры ────────────────────────────────────────────────────────────────

async function loadActors() {
  const grid = $("actors-grid");
  grid.innerHTML = '<div class="loader">Ищем твоих любимых актёров…</div>';
  try {
    const actors = await apiFetch("/watched/top-actors");
    if (!actors?.length) {
      grid.innerHTML = `<div class="empty-state"><span class="empty-icon">🎭</span><p>Отметь фильмы просмотренными, чтобы увидеть любимых актёров</p></div>`;
      return;
    }
    renderActors(actors);
  } catch {
    grid.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

function renderActors(actors) {
  const grid = $("actors-grid");
  grid.innerHTML = "";

  const favs    = actors.filter(a => a.id && state.favActors.has(a.id));
  const regular = actors.filter(a => !(a.id && state.favActors.has(a.id)));

  if (favs.length) {
    const label = document.createElement("div");
    label.className = "actors-section-label";
    label.textContent = "★ Избранные";
    grid.appendChild(label);
    favs.forEach(a => grid.appendChild(buildActorCard(a)));

    const label2 = document.createElement("div");
    label2.className = "actors-section-label";
    label2.textContent = "Все актёры";
    grid.appendChild(label2);
  }
  regular.forEach(a => grid.appendChild(buildActorCard(a)));
}

function buildActorCard(actor) {
  const card = document.createElement("div");
  card.className = "actor-card";
  const photoUrl  = actor.profile_path ? `${TMDB_IMG}${actor.profile_path}` : null;
  const isFav     = actor.id && state.favActors.has(actor.id);
  const countWord = actor.movie_count === 1 ? "фильм" : actor.movie_count < 5 ? "фильма" : "фильмов";

  card.innerHTML = `
    ${photoUrl
      ? `<img class="actor-photo" src="${photoUrl}" alt="${actor.name}" loading="lazy" />`
      : `<div class="actor-photo actor-no-photo">👤</div>`}
    ${actor.id ? `<button class="actor-fav-btn${isFav ? " is-fav" : ""}" title="${isFav ? "Убрать из избранных" : "В избранные"}">★</button>` : ""}
    <div class="actor-info">
      <div class="actor-name">${actor.name}</div>
      <div class="actor-count">${actor.movie_count} ${countWord}</div>
    </div>
  `;

  if (actor.id) {
    card.querySelector(".actor-fav-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleFavActor(actor.id, actor.name, actor.profile_path, e.currentTarget);
    });
    card.addEventListener("click", () => {
      state.modalStack = [];
      pushModal({ type: "person", data: { id: actor.id, _watchedMovies: actor.movies } });
      $("modal-overlay").classList.add("open");
      document.body.style.overflow = "hidden";
      openPersonModal({ id: actor.id, _watchedMovies: actor.movies });
    });
  }
  return card;
}

async function toggleFavActor(actorId, actorName, profilePath, cardBtn = null) {
  const isFav = state.favActors.has(actorId);
  try {
    if (isFav) {
      await apiFetch(`/favorite-actors/${actorId}`, { method: "DELETE" });
      state.favActors.delete(actorId);
      if (cardBtn) { cardBtn.classList.remove("is-fav"); cardBtn.title = "В избранные"; }
      toast(`${actorName} убран из избранных`, "success");
    } else {
      await apiFetch("/favorite-actors", {
        method: "POST",
        body: JSON.stringify({ actor_id: actorId, actor_name: actorName, profile_path: profilePath }),
      });
      state.favActors.add(actorId);
      if (cardBtn) { cardBtn.classList.add("is-fav"); cardBtn.title = "Убрать из избранных"; }
      toast(`${actorName} добавлен в избранные`, "success");
    }
    // Обновляем сетку только если вкладка актёров активна
    if ($("tab-actors")?.classList.contains("active")) {
      const currentActors = await apiFetch("/watched/top-actors");
      renderActors(currentActors);
    }
  } catch {
    toast("Ошибка", "error");
  }
}

// ─── Отклонённые фильмы ────────────────────────────────────────────────────

async function loadDismissed() {
  $("dismissed-grid").innerHTML = '<div class="loader">Загружаем…</div>';
  try {
    const items = await apiFetch(mtq("/dismissed"));
    $("dismissed-count").textContent = items.length;
    if (!items.length) {
      $("dismissed-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">✕</span><p>Нет отклонённых фильмов</p></div>`;
      return;
    }
    renderDismissed(items);
  } catch {
    $("dismissed-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

// ─── AI: Посоветуй фильм ───────────────────────────────────────────────────

function initSuggestTab() {
  // Ничего не грузим автоматически — ждём клика
}

async function loadSuggest() {
  const btn   = $("suggest-ask-btn");
  const hint  = $("suggest-hint");
  const grid  = $("suggest-grid");
  const query = ($("suggest-input")?.value || "").trim();

  btn.disabled = true;
  btn.textContent = "✦ Думаю…";
  hint.textContent = query
    ? "AI читает твой запрос, обычно 5–10 секунд…"
    : "AI анализирует твою историю просмотров, обычно 5–10 секунд…";
  grid.innerHTML = '<div class="loader">Подбираем для тебя…</div>';

  try {
    const url = query
      ? `/ai/suggest?query=${encodeURIComponent(query)}`
      : "/ai/suggest";
    const data = await apiFetch(url);
    const movies = data.movies || [];
    hint.textContent = movies.length
      ? `Нашёл ${movies.length} рекомендаций специально для тебя`
      : "Не удалось подобрать — попробуй позже";

    if (!movies.length) {
      grid.innerHTML = `<div class="empty-state"><span class="empty-icon">✦</span><p>Ничего не нашлось, попробуй ещё раз</p></div>`;
      return;
    }

    grid.innerHTML = "";
    movies.forEach((movie, i) => {
      const card = document.createElement("div");
      card.className = "movie-card";
      card.style.animationDelay = `${i * 60}ms`;
      const posterUrl  = movie.poster_path ? `${TMDB_IMG}${movie.poster_path}` : null;
      const year       = (movie.release_date || movie.first_air_date || "").slice(0, 4) || "—";
      const movieId    = movie.id;
      const isWatched  = state.watched.has(movieId);
      const isWatch    = state.watchlist.has(movieId);
      const mt         = movie.media_type || "movie";

      card.innerHTML = `
        ${posterUrl
          ? `<img class="movie-poster" src="${posterUrl}" alt="${movie.title}" loading="lazy" />`
          : `<div class="no-poster"><span class="no-poster-icon">✦</span>${movie.title}</div>`}
        <button class="watched-btn ${isWatched ? "is-watched" : ""}">✓</button>
        <button class="watch-btn ${isWatch ? "is-watch" : ""}">🕐</button>
        <div class="movie-info">
          <div class="movie-title">${movie.title}</div>
          <div class="movie-meta"><span class="movie-year">${year}</span></div>
          ${movie.vote_average ? `<div class="movie-ratings"><span class="rating-badge tmdb-badge">★ ${movie.vote_average.toFixed(1)}</span></div>` : ""}
          ${movie.ai_reason ? `<div class="suggest-reason">✦ ${movie.ai_reason}</div>` : ""}
        </div>
      `;

      card.addEventListener("click", e => {
        if (e.target.closest(".watched-btn,.watch-btn")) return;
        pushModal({ type: "movie", data: { ...movie, _mediaType: mt } });
        openMovieModal({ ...movie, _mediaType: mt });
      });
      card.querySelector(".watched-btn").addEventListener("click", e => {
        e.stopPropagation();
        toggleWatched(movieId, card.querySelector(".watched-btn"), null, mt);
      });
      card.querySelector(".watch-btn").addEventListener("click", e => {
        e.stopPropagation();
        toggleWatchlist(movieId, card.querySelector(".watch-btn"), null, mt);
      });

      grid.appendChild(card);
    });
  } catch (err) {
    hint.textContent = "";
    grid.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>${err?.detail || "Ошибка AI, попробуй позже"}</p></div>`;
  } finally {
    btn.disabled = false;
    btn.textContent = "✦ Подобрать ещё раз";
  }
}

// ─── Профиль ───────────────────────────────────────────────────────────────

async function loadProfile() {
  const wrap = $("profile-content");
  wrap.innerHTML = '<div class="loader">Загружаем профиль…</div>';
  try {
    const [s, actorsData] = await Promise.all([
      apiFetch("/profile/stats"),
      apiFetch("/watched/top-actors?limit=10")
    ]);
    renderProfile(s, actorsData);
  } catch {
    wrap.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки профиля</p></div>`;
  }
}

function renderProfile(s, actorsData) {
  const wrap = $("profile-content");
  const user = state.user || { display_name: "Пользователь" };
  const initial = user.display_name?.[0]?.toUpperCase() || "?";
  const actors = actorsData?.actors || [];

  if (!s.total) {
    wrap.innerHTML = `
      <div class="profile-wrap">
        <div class="profile-header">
          <div class="profile-avatar">${initial}</div>
          <div class="profile-info">
            <div class="profile-name">${user.display_name}</div>
            <div class="profile-sub">Ещё нет просмотренных фильмов</div>
          </div>
        </div>
        <div class="empty-state"><span class="empty-icon">🎬</span><p>Отметь фильмы просмотренными, чтобы увидеть статистику</p></div>
      </div>`;
    return;
  }

  // Рейтинговый чарт — стэк movie+tv
  const maxRatingCount = Math.max(
    ...Array.from({length: 10}, (_, i) => {
      const d = s.rating_distribution[String(i + 1)] || {};
      return (d.movie || 0) + (d.tv || 0);
    }), 1
  );
  const ratingBarsHTML = Array.from({length: 10}, (_, i) => {
    const num = i + 1;
    const d   = s.rating_distribution[String(num)] || {};
    const mc  = d.movie || 0;
    const tc  = d.tv    || 0;
    const total = mc + tc;
    const pct = Math.round((total / maxRatingCount) * 100);
    const moviePct = total ? Math.round((mc / total) * 100) : 50;
    const tvPct    = 100 - moviePct;
    return `
      <div class="rating-bar-wrap" data-mc="${mc}" data-tc="${tc}" data-num="${num}">
        ${total ? `<div class="rating-bar-cnt">${total}</div>` : ""}
        <div class="rating-bar-stack" style="height:${Math.max(pct, total ? 3 : 0)}%">
          <div class="rating-bar tv"    style="height:${tvPct}%"></div>
          <div class="rating-bar movie" style="height:${moviePct}%"></div>
        </div>
        <div class="rating-bar-num">${num}</div>
      </div>`;
  }).join("");

  // Жанры — split movie/tv с раздельными счётчиками
  const maxGenre = Math.max(...s.top_genres.map(g => g.total || 0), 1);
  const genresHTML = s.top_genres.map(g => {
    const total   = g.total || 0;
    const mc      = g.movie_count || 0;
    const tc      = g.tv_count    || 0;
    const barPct  = Math.round(total / maxGenre * 100);
    const moviePct = total ? Math.round(mc / total * 100) : 50;
    const tvPct    = 100 - moviePct;
    const mcLabel  = mc ? `<span class="genre-bar-count-movie">🎬 ${mc}</span>` : "";
    const tcLabel  = tc ? `<span class="genre-bar-count-tv">📺 ${tc}</span>`    : "";
    return `
    <div class="genre-bar-row">
      <div class="genre-bar-label">
        <span>${g.name}</span>
        <span class="genre-bar-counts">${mcLabel}${tcLabel}</span>
      </div>
      <div class="genre-bar-track">
        <div class="genre-bar-fill movie" style="width:${barPct * moviePct / 100}%"></div>
        <div class="genre-bar-fill tv"    style="width:${barPct * tvPct    / 100}%"></div>
      </div>
    </div>`;
  }).join("");

  // Актёры с бейджами — из top-actors
  const actorsHTML = actors.map(a => {
    const img = a.profile_path
      ? `<img class="profile-actor-photo" src="https://image.tmdb.org/t/p/w92${a.profile_path}" loading="lazy" />`
      : `<div class="profile-actor-no-photo">👤</div>`;
    const movieBadge = a.movie_count ? `<span class="badge-movie">🎬 ${a.movie_count}</span>` : "";
    const tvBadge    = a.tv_count    ? `<span class="badge-tv">📺 ${a.tv_count}</span>`    : "";
    return `
    <div class="profile-actor-item" data-actor-id="${a.id || ""}">
      ${img}
      <div class="profile-actor-info">
        <div class="profile-actor-name">${a.name}</div>
        <div class="profile-actor-badges">${movieBadge}${tvBadge}</div>
      </div>
    </div>`;
  }).join("");

  // Режиссёры
  const directorsHTML = s.top_directors.map(d => `
    <div class="profile-list-item">
      <span class="profile-list-name">🎬 ${d.name}</span>
      <span class="profile-list-badge">${d.count}</span>
    </div>`).join("");

  // Топ фильмы
  const topRatedHTML = s.top_rated.map(m => `
    <div class="profile-top-movie">
      ${m.poster
        ? `<img class="profile-top-poster" src="${TMDB_IMG}${m.poster}" loading="lazy" />`
        : `<div class="profile-top-no-poster">🎬</div>`}
      <div class="profile-top-rating">★ ${m.rating}</div>
    </div>`).join("");

  const legendHTML = `
    <div class="profile-legend">
      <span class="legend-dot movie"></span><span class="legend-lbl">Фильмы</span>
      <span class="legend-dot tv"></span><span class="legend-lbl">Сериалы</span>
    </div>`;

  wrap.innerHTML = `
    <div class="profile-wrap">

      <div class="profile-header">
        <div class="profile-avatar">${initial}</div>
        <div class="profile-info">
          <div class="profile-name">${user.display_name}</div>
          <div class="profile-sub">Участник FilmByMihaylov</div>
        </div>
        <div class="profile-nums">
          <div class="profile-num">
            <span class="profile-num-val">${s.movies}</span>
            <span class="profile-num-lbl">Фильмов</span>
          </div>
          <div class="profile-num">
            <span class="profile-num-val">${s.tv}</span>
            <span class="profile-num-lbl">Сериалов</span>
          </div>
          <div class="profile-num">
            <span class="profile-num-val">${s.avg_rating ?? "—"}</span>
            <span class="profile-num-lbl">Средняя оценка</span>
          </div>
          <div class="profile-num">
            <span class="profile-num-val">${s.rated_count}</span>
            <span class="profile-num-lbl">Оценено</span>
          </div>
        </div>
      </div>

      <div class="profile-grid">

        ${s.rated_count ? `
        <div class="profile-card">
          <div class="profile-card-title">Распределение оценок ${legendHTML}</div>
          <div class="rating-bars">${ratingBarsHTML}</div>
        </div>` : ""}

        ${s.top_genres.length ? `
        <div class="profile-card">
          <div class="profile-card-title">Любимые жанры ${legendHTML}</div>
          <div class="genre-bars">${genresHTML}</div>
        </div>` : ""}

        ${actors.length ? `
        <div class="profile-card">
          <div class="profile-card-title">Часто встречаемые актёры</div>
          <div class="profile-actors-list" id="profile-actors-list">${actorsHTML}</div>
        </div>` : ""}

        ${s.top_directors.length ? `
        <div class="profile-card">
          <div class="profile-card-title">Режиссёры</div>
          <div class="profile-list">${directorsHTML}</div>
        </div>` : ""}

        ${s.top_rated.length ? `
        <div class="profile-card profile-card-full">
          <div class="profile-card-title">Лучшие по твоей оценке</div>
          <div class="profile-top-movies">${topRatedHTML}</div>
        </div>` : ""}

        <div class="profile-card profile-card-full">
          <div class="profile-card-title">Анализ вкуса — AI</div>
          <button class="claude-btn" id="claude-analyze-btn" onclick="analyzeWithClaude()">
            ✦ Проанализировать мой вкус
          </button>
          <div class="claude-result" id="claude-result" style="display:none"></div>
        </div>

      </div>
    </div>`;

  // Тултип для рейтинговых баров
  let barTooltip = document.getElementById("bar-tooltip");
  if (!barTooltip) {
    barTooltip = document.createElement("div");
    barTooltip.className = "bar-tooltip";
    barTooltip.id = "bar-tooltip";
    document.body.appendChild(barTooltip);
  }
  document.querySelectorAll(".rating-bar-wrap[data-num]").forEach(el => {
    el.addEventListener("mouseenter", () => {
      const mc    = parseInt(el.dataset.mc) || 0;
      const tc    = parseInt(el.dataset.tc) || 0;
      const total = mc + tc;
      const num   = el.dataset.num;
      if (!total) return;
      barTooltip.innerHTML = `
        <div class="bar-tooltip-num">Оценка ${num}</div>
        ${mc ? `<div class="bar-tooltip-movie">🎬 Фильмы: <b>${mc}</b></div>` : ""}
        ${tc ? `<div class="bar-tooltip-tv">📺 Сериалы: <b>${tc}</b></div>`   : ""}
        <div class="bar-tooltip-total">Итого: ${total}</div>`;
      barTooltip.classList.add("visible");
    });
    el.addEventListener("mousemove", e => {
      barTooltip.style.left = `${e.clientX + 14}px`;
      barTooltip.style.top  = `${e.clientY - 10}px`;
    });
    el.addEventListener("mouseleave", () => {
      barTooltip.classList.remove("visible");
    });
  });

  // Клики по актёрам — открываем персональный модал
  document.querySelectorAll(".profile-actor-item[data-actor-id]").forEach(el => {
    const actorId = parseInt(el.dataset.actorId);
    if (!actorId) return;
    el.addEventListener("click", () => {
      state.modalStack = [];
      pushModal({ type: "person", data: { id: actorId } });
      $("modal-overlay").classList.add("open");
      document.body.style.overflow = "hidden";
      openPersonModal({ id: actorId });
    });
  });
}

async function analyzeWithClaude() {
  const btn = $("claude-analyze-btn");
  const res = $("claude-result");
  btn.disabled = true;
  btn.textContent = "Анализируем…";
  res.style.display = "none";
  try {
    const data = await apiFetch("/profile/analyze");
    res.textContent = data.analysis;
    res.style.display = "block";
  } catch (err) {
    res.textContent = err?.detail || "Функция временно недоступна";
    res.style.display = "block";
  } finally {
    btn.disabled = false;
    btn.textContent = "✦ Проанализировать мой вкус";
  }
}

function renderDismissed(items) {
  const grid = $("dismissed-grid");
  grid.innerHTML = "";
  items.forEach((movie, index) => {
    const card     = document.createElement("div");
    card.className = "movie-card dismissed-card";
    card.style.animationDelay = `${Math.min(index, 20) * 40}ms`;
    const posterUrl = movie.poster_path ? `${TMDB_IMG}${movie.poster_path}` : null;

    card.innerHTML = `
      <div class="dismissed-overlay">✕</div>
      ${posterUrl
        ? `<img class="movie-poster" src="${posterUrl}" alt="${movie.title}" loading="lazy" />`
        : `<div class="no-poster"><span class="no-poster-icon">🎬</span>${movie.title}</div>`
      }
      <button class="restore-btn" title="Вернуть в рекомендации">↩</button>
      <div class="movie-info">
        <div class="movie-title">${movie.title || "Неизвестный фильм"}</div>
        <div class="dismissed-meta">
          ${movie.cast_names?.length ? `<span>👤 ${movie.cast_names.slice(0,2).join(", ")}</span>` : ""}
          ${movie.origin_country ? `<span>🌍 ${movie.origin_country}</span>` : ""}
        </div>
      </div>
    `;

    card.querySelector(".restore-btn").addEventListener("click", async e => {
      e.stopPropagation();
      try {
        await apiFetch(`/dismissed/${movie.movie_id}?media_type=${state.mediaType}`, { method: "DELETE" });
        animateRemove(card, () => loadDismissed());
        const word = state.mediaType === "tv" ? "Сериал" : "Фильм";
        toast(`${word} возвращён в рекомендации`, "success");
      } catch { toast("Ошибка", "error"); }
    });

    grid.appendChild(card);
  });
}