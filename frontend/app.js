const API       = typeof API_BASE_URL !== "undefined" ? API_BASE_URL : "http://127.0.0.1:8000";
const TMDB_IMG  = "https://image.tmdb.org/t/p/w500";   // полноразмерный — для модалок и hero
const TMDB_CARD = "https://image.tmdb.org/t/p/w342";   // средний — для карточек и постеров в гриде
const TMDB_SM   = "https://image.tmdb.org/t/p/w185";   // мелкий — для скролл-карточек на главной
const TMDB_LOGO = "https://image.tmdb.org/t/p/w92";

const state = {
  // Глобальный mediaType больше не управляется тоггом в шапке.
  // Используется как fallback для модалок (когда нет _mediaType в данных).
  mediaType:   "movie",
  // Локальные режимы для каждой "личной" вкладки
  watchedMode:   "movie",
  watchlistMode: "movie",
  dismissedMode: "movie",
  recsMode:      "movie",
  booksMode:     "discover",
  appMode:       "cinema",   // "cinema" | "books"
  activeBooksTab: "discover",
  booksRead:     new Set(),
  booksWishlist: new Set(),
  watchlistCat:  "all",   // "all" | "must_see" | "not_sure" | "last_resort"
  diaryView:     "grid",  // "grid" | "timeline"
  // Combined множества — содержат обе типа сразу (фильмы И сериалы)
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
  // Кэш списков по типу — заполняется в init() и инвалидируется при мутациях.
  // Позволяет переключать Movies/TV внутри вкладки мгновенно (без round-trip).
  cache: {
    watched:   { movie: null, tv: null },
    watchlist: { movie: null, tv: null },
    dismissed: { movie: null, tv: null },
    // Кэш главной страницы — возврат на вкладку Обзор мгновенный.
    // TTL 60с: после возвращаем кэш и параллельно обновляем в фоне.
    homepage:  { ts: 0, movies: null, tv: null, recs: null, recsTv: null },
    booksPopular:      null,
    booksReadData:     null,
    booksWishlistData: null,
  },
  user: null,  // { id, username, display_name }
};

// ─── Переключатель режима (Кино / Книги) ───────────────────────────────────

function switchAppMode(mode) {
  state.appMode = mode;
  try { localStorage.setItem("appMode", mode); } catch {}

  const isCinema = mode === "cinema";
  $("cinema-nav").style.display  = isCinema ? "" : "none";
  $("books-nav").style.display   = isCinema ? "none" : "";
  document.querySelectorAll(".mode-btn").forEach(b => b.classList.toggle("active", b.dataset.mode === mode));

  // Hide all tabs
  document.querySelectorAll(".tab").forEach(t => {
    t.classList.remove("active");
    t.style.display = "none";
  });

  if (isCinema) {
    // Restore last active cinema tab or default to discover
    const cinemaTab = $("tab-discover");
    cinemaTab.classList.add("active");
    cinemaTab.style.display = "";
    $("search-input").placeholder = "Найти фильм, сериал…";
    $("home-content").style.display = "";
    $("search-content").style.display = "none";
  } else {
    // Open books mode
    $("search-input").placeholder = "Найти книгу, автора…";
    openBooksTab(state.activeBooksTab || "discover");
  }
}

function openBooksTab(tabName) {
  state.activeBooksTab = tabName;

  // Hide all books tabs
  document.querySelectorAll(".books-tab").forEach(t => {
    t.classList.remove("active");
    t.style.display = "none";
  });

  // Update nav active state
  document.querySelectorAll(".books-nav-btn").forEach(b => {
    b.classList.toggle("active", b.dataset.booksTab === tabName);
  });

  // Show target tab
  const section = $(`tab-books-${tabName}`);
  if (section) {
    section.classList.add("active");
    section.style.display = "";
  }

  // Load content
  if (tabName === "discover")  loadBooksDiscover();
  else if (tabName === "diary")    loadBooksReadView();
  else if (tabName === "wishlist") loadBooksWishlistView();
  else if (tabName === "suggest")  initBooksSuggest();
  else if (tabName === "profile")  loadBooksProfile();
}

// ─── Переключатель оформления ──────────────────────────────────────────────
// Две темы: "cinema" (тёмная по умолчанию) и "mono" (бумажная редакторская).
// Тоггл живёт в шапке. Предпочтение сохраняется в localStorage.

function applyTheme(theme) {
  document.body.classList.toggle("theme-mono", theme === "mono");
  document.querySelectorAll(".theme-btn").forEach(b => {
    b.classList.toggle("active", b.dataset.theme === theme);
  });
  try { localStorage.setItem("film_theme", theme); } catch {}
  // Перерендериваем активную вкладку т.к. layout кардинально другой
  if (document.getElementById("tab-discover")?.classList.contains("active") && typeof loadHomepage === "function") {
    loadHomepage();
  }
  if (document.getElementById("tab-profile")?.classList.contains("active") && typeof loadProfile === "function") {
    loadProfile();
  }
}

(function initTheme() {
  // Восстанавливаем сохранённую тему сразу при загрузке, до рендера
  let saved = "cinema";
  try { saved = localStorage.getItem("film_theme") || "cinema"; } catch {}
  if (saved === "mono") document.body.classList.add("theme-mono");
})();

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".theme-btn").forEach(btn => {
    btn.addEventListener("click", () => applyTheme(btn.dataset.theme));
  });
  // Синхронизируем активную кнопку с сохранённой темой (на случай если она была "mono")
  let saved = "cinema";
  try { saved = localStorage.getItem("film_theme") || "cinema"; } catch {}
  document.querySelectorAll(".theme-btn").forEach(b => {
    b.classList.toggle("active", b.dataset.theme === saved);
  });
});

// Хелпер — добавляет media_type к URL. По умолчанию берёт state.mediaType,
// но можно передать явный тип (для per-tab переключателей).
function mt(params = {}, mediaType = null) {
  return { ...params, media_type: mediaType || state.mediaType };
}
function mtq(base = "", mediaType = null) {
  const type = mediaType || state.mediaType;
  const sep = base.includes("?") ? "&" : "?";
  return `${base}${sep}media_type=${type}`;
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
const CUR_YEAR  = new Date().getFullYear();

// ─── Ползунок года с обезьянкой ────────────────────────────────────────────
function initYearSlider(containerId, onChange) {
  const MIN_Y = 1960, MAX_Y = CUR_YEAR;
  const container = document.getElementById(containerId);
  if (!container) return null;

  container.innerHTML = `
    <div class="ys-wrap">
      <div class="ys-display">
        <span class="ys-from-val">${MIN_Y}</span>
        <span class="ys-dash"> — </span>
        <span class="ys-to-val">${MAX_Y}</span>
      </div>
      <div class="ys-area">
        <div class="ys-monkey" id="${containerId}-mk">🐒</div>
        <div class="ys-track-bg"></div>
        <div class="ys-track-fill" id="${containerId}-fill"></div>
        <input type="range" class="ys-input ys-from" id="${containerId}-from"
               min="${MIN_Y}" max="${MAX_Y}" value="${MIN_Y}" step="1" />
        <input type="range" class="ys-input ys-to"   id="${containerId}-to"
               min="${MIN_Y}" max="${MAX_Y}" value="${MAX_Y}" step="1" />
      </div>
    </div>`;

  const fromInput = container.querySelector('.ys-from');
  const toInput   = container.querySelector('.ys-to');
  const fromVal   = container.querySelector('.ys-from-val');
  const toVal     = container.querySelector('.ys-to-val');
  const fill      = container.querySelector('.ys-track-fill');
  const monkey    = container.querySelector('.ys-monkey');
  let hideTimer   = null;

  function pct(val) { return (val - MIN_Y) / (MAX_Y - MIN_Y) * 100; }

  function updateUI(activeHandle) {
    const from = parseInt(fromInput.value);
    const to   = parseInt(toInput.value);
    fromVal.textContent = from === MIN_Y ? MIN_Y : from;
    toVal.textContent   = to   === MAX_Y ? MAX_Y : to;
    const fp = pct(from), tp = pct(to);
    fill.style.left  = fp + '%';
    fill.style.width = (tp - fp) + '%';
    if (activeHandle !== undefined) {
      const mp = activeHandle === 'from' ? fp : tp;
      monkey.style.left = `calc(${mp}% - 14px)`;
      monkey.classList.add('visible');
      clearTimeout(hideTimer);
    }
    onChange(from, to);
  }

  fromInput.addEventListener('input', () => {
    if (parseInt(fromInput.value) > parseInt(toInput.value))
      fromInput.value = toInput.value;
    updateUI('from');
  });
  toInput.addEventListener('input', () => {
    if (parseInt(toInput.value) < parseInt(fromInput.value))
      toInput.value = fromInput.value;
    updateUI('to');
  });

  [fromInput, toInput].forEach((inp, i) => {
    const handle = i === 0 ? 'from' : 'to';
    inp.addEventListener('mousedown',  () => { clearTimeout(hideTimer); updateUI(handle); });
    inp.addEventListener('touchstart', () => { clearTimeout(hideTimer); updateUI(handle); }, { passive: true });
    inp.addEventListener('mouseup',    () => { hideTimer = setTimeout(() => monkey.classList.remove('visible'), 700); });
    inp.addEventListener('touchend',   () => { hideTimer = setTimeout(() => monkey.classList.remove('visible'), 700); });
  });

  updateUI();

  return {
    getFrom: () => parseInt(fromInput.value),
    getTo:   () => parseInt(toInput.value),
    isDefault: () => parseInt(fromInput.value) === MIN_Y && parseInt(toInput.value) === MAX_Y,
  };
}

// Глобальные ссылки на слайдеры (инициализируются после DOMContentLoaded)
const sliders = {};

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
document.querySelectorAll(".nav-btn[data-tab]").forEach(btn => {
  btn.addEventListener("click", () => {
    const tab = btn.dataset.tab;
    document.querySelectorAll(".nav-btn[data-tab]").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    document.querySelectorAll(".tab").forEach(t => { t.classList.remove("active"); t.style.display = "none"; });
    const tabEl = $(`tab-${tab}`);
    if (tabEl) { tabEl.classList.add("active"); tabEl.style.display = ""; }
    if (tab === "discover")  { $("home-content").style.display = ""; $("search-content").style.display = "none"; }
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

// ─── Локальные переключатели типа во вкладках ──────────────────────────────
// Каждая из 4 вкладок (watched / watchlist / dismissed / recs) имеет свой pill-toggle.
document.querySelectorAll(".tab-mode-toggle").forEach(toggle => {
  const key = toggle.dataset.toggle;  // "watched" | "watchlist" | "dismissed" | "recs"
  toggle.querySelectorAll(".tab-mode-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      const mode = btn.dataset.mode;
      const stateKey = `${key}Mode`;
      if (state[stateKey] === mode) return;
      state[stateKey] = mode;
      toggle.querySelectorAll(".tab-mode-btn").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");

      // Перезагружаем соответствующую вкладку
      if (key === "watched")   loadWatched();
      if (key === "watchlist") loadWatchlist();
      if (key === "dismissed") loadDismissed();
      if (key === "recs") {
        // Для рекомендаций обновляем подпись, сбрасываем пул и перезагружаем фильтры жанров
        const subEl = $("recs-sub");
        if (subEl) subEl.textContent = mode === "tv"
          ? "Подобрано на основе твоих оценок · до 2000 сериалов"
          : "Подобрано на основе твоих оценок · до 2000 фильмов";
        state.allRecs = [];
        state.filterState.genre   = { inc: new Set(), exc: new Set() };
        state.filterState.country = { inc: new Set(), exc: new Set() };
        mfItems.genre = [];
        renderActiveTags();
        updateMfCount("genre");
        updateMfCount("country");
        $("sort-wrap").style.display = "none";
        $("recs-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">✦</span><p>Нажми кнопку выше, чтобы получить рекомендации</p></div>`;
        // Перегружаем жанры и студии под новый тип
        apiFetch(`/genres?media_type=${mode}`).then(list => {
          if (list?.length) {
            mfItems.genre = list.map(g => ({ value: g.name, label: g.name }));
            buildMfPanel("genre");
          }
        }).catch(() => {});
        reloadStudios(mode);
      }
    });
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
    // Загружаем оба типа параллельно (6 запросов) и объединяем в общие сеты.
    // Это нужно чтобы кнопки "Просмотрено / Позже / Скрыто" на карточках работали
    // одинаково независимо от того, какой тип сейчас выбран на вкладке.
    const [
      watchedMv, watchedTv,
      watchlistMv, watchlistTv,
      dismissedMv, dismissedTv,
    ] = await Promise.all([
      apiFetch(mtq("/watched",   "movie")),
      apiFetch(mtq("/watched",   "tv")),
      apiFetch(mtq("/watchlist", "movie")),
      apiFetch(mtq("/watchlist", "tv")),
      apiFetch(mtq("/dismissed", "movie")),
      apiFetch(mtq("/dismissed", "tv")),
    ]);
    const allWatched   = [...watchedMv, ...watchedTv];
    const allWatchlist = [...watchlistMv, ...watchlistTv];
    const allDismissed = [...dismissedMv, ...dismissedTv];
    state.watched   = new Map(allWatched.map(m => [m.movie_id, m.user_rating]));
    state.watchlist = new Set(allWatchlist.map(m => m.movie_id));
    state.dismissed = new Set(allDismissed.map(m => m.movie_id));
    // Кэшируем результаты для мгновенного переключения movie/tv во вкладках
    state.cache.watched.movie   = watchedMv;
    state.cache.watched.tv      = watchedTv;
    state.cache.watchlist.movie = watchlistMv;
    state.cache.watchlist.tv    = watchlistTv;
    state.cache.dismissed.movie = dismissedMv;
    state.cache.dismissed.tv    = dismissedTv;
    $("watch-count").textContent     = allWatched.length;
    $("watchlist-count").textContent = allWatchlist.length;
    $("dismissed-count").textContent = allDismissed.length;
  } catch {}
}

// ─── Поиск ─────────────────────────────────────────────────────────────────
$("search-btn").addEventListener("click", doSearch);
$("search-input").addEventListener("keydown", e => {
  if (e.key === "Enter") doSearch();
  if (e.key === "Escape") {
    e.currentTarget.value = "";
    $("home-content").style.display = "";
    $("search-content").style.display = "none";
    e.currentTarget.blur();
  }
});

async function doSearch() {
  const query = $("search-input").value.trim();
  if (state.appMode === "books") {
    searchBooks(query);
    return;
  }
  if (!query) {
    // Если запрос пустой — возвращаемся на главную
    $("home-content").style.display = "";
    $("search-content").style.display = "none";
    return;
  }
  document.querySelector('[data-tab="discover"]').click();
  // Показываем поиск, скрываем главную
  $("home-content").style.display = "none";
  $("search-content").style.display = "";
  $("discover-title").textContent = `Результаты: «${query}»`;
  $("movies-grid").innerHTML = '<div class="loader">Ищем…</div>';
  try {
    // Параллельный поиск фильмов И сериалов, плюс актёры
    const [movieResults, tvResults, people] = await Promise.all([
      apiFetch(`/search?q=${encodeURIComponent(query)}&media_type=movie`).catch(() => []),
      apiFetch(`/search?q=${encodeURIComponent(query)}&media_type=tv`).catch(() => []),
      apiFetch(`/search/person?q=${encodeURIComponent(query)}`).catch(() => []),
    ]);
    // Помечаем каждый результат своим media_type
    const movies = [
      ...(movieResults || []).map(m => ({ ...m, media_type: "movie" })),
      ...(tvResults    || []).map(m => ({ ...m, media_type: "tv"    })),
    ];
    // Сортировка по популярности (если есть), иначе по vote_count
    movies.sort((a, b) => (b.popularity || b.vote_count || 0) - (a.popularity || a.vote_count || 0));
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

// ─── Главная страница ──────────────────────────────────────────────────────
const HOMEPAGE_TTL = 60_000;   // 60s — после возвращаем кэш + обновляем в фоне

function renderHomepageData(movies, tvShows, recs) {
  // Отфильтровываем то что пользователь убрал в "Неинтересное"
  const notDismissed = m => !state.dismissed.has(m.id);
  const m  = (movies  || []).filter(notDismissed);
  const tv = (tvShows || []).filter(notDismissed);
  const r  = (recs    || []).filter(notDismissed);

  // Hero — теперь карусель из 5 фильмов
  state.heroSlides = m.slice(0, 5);
  state.heroIdx    = 0;
  if (state.heroSlides.length) renderHero(state.heroSlides[0]);
  else $("home-hero").innerHTML = "";
  renderScrollRow("scroll-movies", m, "movie");
  renderScrollRow("scroll-tv",     tv, "tv");
  attachScrollArrows("movies");
  attachScrollArrows("tv");
  if (r.length) {
    $("home-row-recs").style.display = "";
    renderScrollRow("scroll-recs", r.slice(0, 20), "movie");
    attachScrollArrows("recs");
  } else {
    $("home-row-recs").style.display = "none";
  }
}

async function loadHomepage() {
  $("search-content").style.display = "none";
  const isMono = document.body.classList.contains("theme-mono");

  if (isMono) {
    $("home-content").style.display = "none";
    $("home-content-mono").style.display = "";
  } else {
    $("home-content").style.display = "";
    $("home-content-mono").style.display = "none";
  }

  const hp = state.cache.homepage;
  const fresh = (Date.now() - hp.ts) < HOMEPAGE_TTL;

  // ─── MONO путь ──────────────────────────────────────────────────────────
  if (isMono) {
    if (fresh && hp.movies && hp.tv) {
      renderMonoHomepage(hp.movies, hp.tv, hp.recs, hp.recsTv);
      return;
    }
    if (hp.movies && hp.tv) {
      renderMonoHomepage(hp.movies, hp.tv, hp.recs, hp.recsTv);
    } else {
      $("home-content-mono").innerHTML = `<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ ИНДЕКС</div></div>`;
    }
    try {
      const [movies, tvShows] = await Promise.all([
        apiFetch("/popular?media_type=movie"),
        apiFetch("/popular?media_type=tv"),
      ]);
      hp.movies = movies; hp.tv = tvShows; hp.ts = Date.now();
      renderMonoHomepage(movies, tvShows, hp.recs, hp.recsTv);

      // Лениво грузим рекомендации обоих типов параллельно
      if (state.watched.size > 0) {
        const recPromises = [
          apiFetch("/recommendations?media_type=movie").catch(() => null),
          apiFetch("/recommendations?media_type=tv").catch(() => null),
        ];
        Promise.all(recPromises).then(([recs, recsTv]) => {
          if (recs)   hp.recs   = recs;
          if (recsTv) hp.recsTv = recsTv;
          renderMonoHomepage(hp.movies, hp.tv, hp.recs, hp.recsTv);
        });
      }
    } catch {
      if (!hp.movies) $("home-content-mono").innerHTML = `<div class="empty-state"><p>Не удалось загрузить</p></div>`;
    }
    return;
  }

  // ─── CINEMA путь (оригинальный) ─────────────────────────────────────────

  // ─── Если есть свежий кэш — рендерим мгновенно и не дёргаем сеть ─────────
  if (fresh && hp.movies && hp.tv) {
    renderHomepageData(hp.movies, hp.tv, hp.recs);
    return;
  }

  // ─── Если кэш есть но протух — показываем его пока грузим свежее ─────────
  if (hp.movies && hp.tv) {
    renderHomepageData(hp.movies, hp.tv, hp.recs);
    // продолжаем — обновим в фоне ниже
  } else {
    // Полностью пусто — показываем фан-loader прямо в hero (вместо blocking-splash)
    const heroLoader = `
      <div class="hero-loader-wrap">
        <div class="fun-loader" style="min-height:380px">
          <div class="fun-piano">
            <div class="fun-monkey">🐵</div>
            <div class="fun-shadow"></div>
            <div class="fun-dots"><span></span><span></span><span></span></div>
          </div>
          <div class="fun-text">СОБИРАЕМ ТВОЮ БИБЛИОТЕКУ</div>
        </div>
      </div>`;
    $("home-hero").innerHTML = heroLoader;
    $("scroll-movies").innerHTML = "";
    $("scroll-tv").innerHTML     = "";
  }

  try {
    // Параллельно: popular movies + tv. Recs стартует одновременно, но рендерится отдельно
    // чтобы не блокировать первые два ряда (recs может тянуться ~5-10 сек).
    const [movies, tvShows] = await Promise.all([
      apiFetch("/popular?media_type=movie"),
      apiFetch("/popular?media_type=tv"),
    ]);
    hp.movies = movies;
    hp.tv     = tvShows;
    hp.ts     = Date.now();

    // Используем единый рендер чтобы state.heroSlides обязательно установился
    renderHomepageData(movies, tvShows, hp.recs);

    // Lazy: рекомендации в фоне, не блокируют popular ряды
    if (state.watched.size > 0) {
      $("home-row-recs").style.display = "";
      $("scroll-recs").innerHTML = `<div class="loader" style="padding:40px 20px">Подбираем для тебя…</div>`;
      apiFetch("/recommendations?media_type=movie").then(recs => {
        hp.recs = recs;
        if (recs?.length) {
          renderScrollRow("scroll-recs", recs.slice(0, 20), "movie");
          attachScrollArrows("recs");
        } else {
          $("home-row-recs").style.display = "none";
        }
      }).catch(() => {
        $("home-row-recs").style.display = "none";
      });
    } else {
      $("home-row-recs").style.display = "none";
    }
  } catch {
    if (!hp.movies) {  // только если не было кэша
      $("home-hero").innerHTML = `<div class="empty-state" style="height:380px;display:flex;flex-direction:column;align-items:center;justify-content:center"><div class="empty-monkey"><div class="em-icon">🙈</div><div class="em-shadow"></div></div><p>Не удалось загрузить — попробуй обновить</p></div>`;
      $("scroll-movies").innerHTML = "";
      $("scroll-tv").innerHTML     = "";
    }
  }
}

// ─── Главная: MONO редакторский индекс ──────────────────────────────────────
// ─── Главная: MONO редакторский индекс ─────────────────────────────────────
// Layout: гигантский заголовок + 4 секции (Popular Movies, Popular TV, Recs Movies, Recs TV).
// Каждая секция = большая горизонтальная карусель из 5 хедер-карточек с backdrop+описанием+рейтингом.
// Между секциями popular — сетка квадратных карточек с дополнительными фильмами/сериалами.
function renderMonoHomepage(movies, tvShows, recs, recsTv) {
  const wrap = $("home-content-mono");
  if (!wrap) return;

  // Фильтр отклонённых: убираем всё что пользователь скрыл
  const notDismissed = m => !state.dismissed.has(m.id);
  const moviesArr = (movies  || []).filter(notDismissed).map(m => ({...m, media_type: "movie"}));
  const tvArr     = (tvShows || []).filter(notDismissed).map(m => ({...m, media_type: "tv"}));
  recs    = (recs   || []).filter(notDismissed);
  recsTv  = (recsTv || []).filter(notDismissed);

  // Дата/время для шапки
  const now  = new Date();
  const hh   = String(now.getHours()).padStart(2, "0");
  const mm   = String(now.getMinutes()).padStart(2, "0");
  const date = now.toLocaleDateString("ru-RU", { day: "2-digit", month: "short" }).toUpperCase();

  // ─── Шаблон БОЛЬШОЙ карточки в карусели (5 шт) ─────────────────────────
  const bigCardHTML = (m, idx, total) => {
    const backdrop = m.backdrop_path
      ? `https://image.tmdb.org/t/p/w1280${m.backdrop_path}`
      : (m.poster_path ? `${TMDB_IMG}${m.poster_path}` : null);
    const title    = (m.title || m.name || "").toUpperCase();
    const year     = (m.release_date || m.first_air_date || "").slice(0, 4) || "—";
    const rating   = m.vote_average ? Number(m.vote_average).toFixed(1) : "—";
    const genres   = (m.genres || []).slice(0, 3).map(g => (typeof g === "string" ? g : g.name)).filter(Boolean).join(" · ").toUpperCase();
    const overview = m.overview ? (m.overview.length > 280 ? m.overview.slice(0, 280) + "…" : m.overview) : "";
    const isWatched   = state.watched.has(m.id);
    const isWatchlist = state.watchlist.has(m.id);
    const num    = String(idx + 1).padStart(2, "0");
    const total2 = String(total).padStart(2, "0");
    return `
      <article class="mono-feat-card" data-id="${m.id}" data-type="${m.media_type}">
        ${backdrop ? `<div class="mono-feat-bg" style="background-image:url('${backdrop}')"></div>` : `<div class="mono-feat-bg mono-feat-bg-empty"></div>`}
        <div class="mono-feat-overlay"></div>
        <div class="mono-feat-grid">
          <div class="mono-feat-num">Nº ${num}/${total2}</div>
          <div class="mono-feat-info">
            <div class="mono-feat-genres">${genres || "—"}</div>
            <h3 class="mono-feat-title">${title}</h3>
            <div class="mono-feat-meta">
              <span class="mono-feat-rating">★ ${rating}</span>
              <span class="mono-feat-sep">/</span>
              <span>${year}</span>
              <span class="mono-feat-sep">/</span>
              <span>${m.media_type === "tv" ? "СЕРИАЛ" : "ФИЛЬМ"}</span>
            </div>
            ${overview ? `<p class="mono-feat-overview">${overview}</p>` : ""}
            <div class="mono-feat-actions">
              <button class="mono-feat-btn primary" data-act="open">ОТКРЫТЬ →</button>
              <button class="mono-feat-btn ${isWatched ? "active" : ""}" data-act="watched">${isWatched ? "✓ ПРОСМОТРЕНО" : "✓ ОТМЕТИТЬ"}</button>
              <button class="mono-feat-btn ${isWatchlist ? "active-blue" : ""}" data-act="watchlist">${isWatchlist ? "🕐 В СПИСКЕ" : "🕐 ПОЗЖЕ"}</button>
              <button class="mono-feat-btn dismiss" data-act="dismiss" title="Не интересно">✕</button>
            </div>
          </div>
        </div>
      </article>`;
  };

  // ─── Шаблон квадратной карточки для сеток ──────────────────────────────
  const squareCardHTML = (m, idx) => {
    const poster = m.poster_path ? `${TMDB_CARD}${m.poster_path}` : null;
    const year   = (m.release_date || m.first_air_date || "").slice(2, 4);
    const rating = m.vote_average ? Number(m.vote_average).toFixed(1) : "—";
    const imdb   = m.imdb_rating ? Number(m.imdb_rating).toFixed(1) : null;
    const num    = String(idx + 1).padStart(3, "0");
    const isWatched   = state.watched.has(m.id);
    const isWatchlist = state.watchlist.has(m.id);
    const typeBadge = m.media_type === "tv" ? "TV" : "FILM";
    return `
      <article class="mono-card" data-id="${m.id}" data-type="${m.media_type}">
        <div class="mono-poster" ${poster ? `style="background-image:url('${poster}')"` : ""}>
          <div class="mono-poster-top">
            <span class="mono-num">Nº ${num}</span>
            <span class="mono-type">${typeBadge}</span>
          </div>
          <div class="mono-poster-bot">
            <span class="mono-poster-title">${(m.title || m.name || "").toUpperCase()}</span>
          </div>
          <div class="mono-card-actions">
            <button class="mono-act watched ${isWatched ? "active" : ""}" data-act="watched" title="Просмотрено">✓</button>
            <button class="mono-act watchlist ${isWatchlist ? "active" : ""}" data-act="watchlist" title="Позже">🕐</button>
            <button class="mono-act dismiss" data-act="dismiss" title="Не интересно">✕</button>
          </div>
        </div>
        <div class="mono-meta">
          <span class="mono-year">'${year}</span>
          <span class="mono-rating">★ ${rating}${imdb ? ` <span class="mono-imdb">· IMDb ${imdb}</span>` : ""}</span>
        </div>
      </article>`;
  };

  // ─── Шаблон секции с каруселью ─────────────────────────────────────────
  const sectionHTML = (num, title, subtitle, items, sectionKey) => {
    if (!items || items.length === 0) return "";
    const top5 = items.slice(0, 5);
    return `
      <section class="mono-section" data-section="${sectionKey}">
        <div class="mono-sec-head">
          <div class="mono-sec-num">${num}</div>
          <div class="mono-sec-titles">
            <h2 class="mono-sec-title">${title}</h2>
            <p class="mono-sec-sub">${subtitle}</p>
          </div>
          <div class="mono-sec-nav">
            <button class="mono-carousel-arrow" data-dir="-1">‹</button>
            <button class="mono-carousel-arrow" data-dir="1">›</button>
          </div>
        </div>
        <div class="mono-carousel" data-section="${sectionKey}">
          ${top5.map((m, i) => bigCardHTML(m, i, top5.length)).join("")}
        </div>
      </section>`;
  };

  // ─── Шаблон сетки квадратиков ──────────────────────────────────────────
  const gridSectionHTML = (num, title, subtitle, items, sectionKey) => {
    if (!items || items.length === 0) return "";
    // Берём с 6-го (5 первых уже в карусели). Ровно 15 = 3 ряда по 5, без сирот.
    const gridItems = items.slice(5, 20);
    if (!gridItems.length) return "";
    return `
      <section class="mono-section mono-section-grid" data-section="${sectionKey}-grid">
        <div class="mono-sec-head">
          <div class="mono-sec-num">${num}</div>
          <div class="mono-sec-titles">
            <h2 class="mono-sec-title">${title}</h2>
            <p class="mono-sec-sub">${subtitle}</p>
          </div>
        </div>
        <div class="mono-grid">${gridItems.map(squareCardHTML).join("")}</div>
      </section>`;
  };

  // ─── Финальная HTML-сборка ─────────────────────────────────────────────
  wrap.innerHTML = `
    <header class="mono-page-head">
      <div class="mono-eyebrow">INDEX Nº 47 · ${date} · ${hh}:${mm}</div>
      <h1 class="mono-hero-title">ЧТО СМОТРИШЬ<br/><span>СЕГОДНЯ?</span></h1>
      <div class="mono-stamp">NOW SHOWING</div>
      <div class="mono-page-stats">
        <div class="mono-pstat"><span class="mono-pstat-v">${moviesArr.length}</span><span class="mono-pstat-l">фильмов</span></div>
        <div class="mono-pstat"><span class="mono-pstat-v">${tvArr.length}</span><span class="mono-pstat-l">сериалов</span></div>
        <div class="mono-pstat"><span class="mono-pstat-v">${state.watched.size}</span><span class="mono-pstat-l">просмотрено</span></div>
        <div class="mono-pstat"><span class="mono-pstat-v">${state.watchlist.size}</span><span class="mono-pstat-l">в списке</span></div>
      </div>
    </header>

    ${sectionHTML("01", "ПОПУЛЯРНЫЕ ФИЛЬМЫ", "Топ-5 этой недели по версии TMDB", moviesArr, "pop-movies")}
    ${gridSectionHTML("02", "ФИЛЬМЫ — БОЛЬШЕ", "Что ещё смотрят прямо сейчас", moviesArr, "pop-movies")}
    ${sectionHTML("03", "ПОПУЛЯРНЫЕ СЕРИАЛЫ", "Топ-5 сериалов недели", tvArr, "pop-tv")}
    ${gridSectionHTML("04", "СЕРИАЛЫ — БОЛЬШЕ", "Расширенный индекс сериалов", tvArr, "pop-tv")}
    ${recs?.length ? sectionHTML("05", "✦ ДЛЯ ТЕБЯ · ФИЛЬМЫ", "Подобрано на основе твоих оценок", recs, "rec-movies") : ""}
    ${recsTv?.length ? sectionHTML("06", "✦ ДЛЯ ТЕБЯ · СЕРИАЛЫ", "Сериалы которые могут понравиться", recsTv, "rec-tv") : ""}
    ${(!recs?.length && state.watched.size > 0) ? `
      <section class="mono-section mono-recs-loading">
        <div class="mono-sec-head">
          <div class="mono-sec-num">05</div>
          <div class="mono-sec-titles">
            <h2 class="mono-sec-title">✦ ДЛЯ ТЕБЯ</h2>
            <p class="mono-sec-sub">Подбираем рекомендации…</p>
          </div>
        </div>
        <div class="mono-loader">АНАЛИЗИРУЕМ ТВОЮ ИСТОРИЮ…</div>
      </section>` : ""}

    <footer class="mono-page-foot">
      <span>END OF INDEX Nº 47</span>
      <span>FILMBYMIHAYLOV · ${new Date().getFullYear()}</span>
      <span>← / →  NAVIGATE · CLICK CARD TO OPEN</span>
    </footer>
  `;

  // ── Биндинги ─────────────────────────────────────────────────────────
  const allMaps = {
    "pop-movies": moviesArr,
    "pop-tv":     tvArr,
    "rec-movies": recs    || [],
    "rec-tv":     recsTv  || [],
  };

  // Большие карточки в каруселях
  wrap.querySelectorAll(".mono-feat-card").forEach(card => {
    const id   = parseInt(card.dataset.id);
    const type = card.dataset.type;
    const findInAll = () => {
      for (const arr of Object.values(allMaps)) {
        const found = arr.find(m => m.id === id);
        if (found) return found;
      }
      return null;
    };
    const movie = findInAll();

    card.addEventListener("click", e => {
      if (e.target.closest(".mono-feat-actions")) return;
      if (!movie) return;
      pushModal({ type: "movie", data: { ...movie, _mediaType: type } });
      openMovieModal({ ...movie, _mediaType: type });
    });
    card.querySelectorAll(".mono-feat-btn").forEach(btn => {
      btn.addEventListener("click", e => {
        e.stopPropagation();
        const act = btn.dataset.act;
        if (act === "open" && movie) {
          pushModal({ type: "movie", data: { ...movie, _mediaType: type } });
          openMovieModal({ ...movie, _mediaType: type });
        }
        if (act === "watched") {
          toggleWatched(id, btn, null, type);
          const now = btn.classList.toggle("active");
          btn.textContent = now ? "✓ ПРОСМОТРЕНО" : "✓ ОТМЕТИТЬ";
        }
        if (act === "watchlist") {
          toggleWatchlist(id, btn, null, type);
          const now = btn.classList.toggle("active-blue");
          btn.textContent = now ? "🕐 В СПИСКЕ" : "🕐 ПОЗЖЕ";
        }
        if (act === "dismiss") {
          dismissMovie(id, card, true, type);
        }
      });
    });
  });

  // Квадратные карточки
  wrap.querySelectorAll(".mono-card").forEach(card => {
    const id   = parseInt(card.dataset.id);
    const type = card.dataset.type;
    const movie = (type === "tv" ? tvArr : moviesArr).find(m => m.id === id);
    if (!movie) return;
    card.addEventListener("click", e => {
      if (e.target.closest(".mono-card-actions")) return;
      pushModal({ type: "movie", data: { ...movie, _mediaType: type } });
      openMovieModal({ ...movie, _mediaType: type });
    });
    card.querySelectorAll(".mono-act").forEach(btn => {
      btn.addEventListener("click", e => {
        e.stopPropagation();
        const act = btn.dataset.act;
        if (act === "watched") {
          toggleWatched(id, btn, null, type);
          btn.classList.toggle("active");
        }
        if (act === "watchlist") {
          toggleWatchlist(id, btn, null, type);
          btn.classList.toggle("active");
        }
        if (act === "dismiss") {
          dismissMovie(id, card, true, type);
        }
      });
    });
  });

  // Стрелки навигации в каруселях
  wrap.querySelectorAll(".mono-sec-head").forEach(head => {
    const section = head.closest(".mono-section");
    if (!section) return;
    const carousel = section.querySelector(".mono-carousel");
    if (!carousel) return;
    head.querySelectorAll(".mono-carousel-arrow").forEach(arr => {
      arr.addEventListener("click", () => {
        const dir = parseInt(arr.dataset.dir) || 1;
        carousel.scrollBy({ left: dir * (carousel.clientWidth * 0.85), behavior: "smooth" });
      });
    });
  });
}

function renderHero(movie) {
  const backdropUrl = movie.backdrop_path
    ? `https://image.tmdb.org/t/p/original${movie.backdrop_path}`
    : null;
  const posterUrl = movie.poster_path ? `${TMDB_CARD}${movie.poster_path}` : null;
  const year      = (movie.release_date || movie.first_air_date || "").slice(0, 4) || "";
  const rating    = movie.vote_average ? `★ ${Number(movie.vote_average).toFixed(1)}` : "";
  const overview  = movie.overview
    ? (movie.overview.length > 200 ? movie.overview.slice(0, 200) + "…" : movie.overview)
    : "";
  const isWatched  = state.watched.has(movie.id);
  const isWatchlist = state.watchlist.has(movie.id);

  // Карусель: если есть state.heroSlides, рендерим точки и стрелки
  const total = (state.heroSlides || []).length;
  const idx   = state.heroIdx || 0;
  const dotsHTML = total > 1
    ? `<div class="hero-dots">${state.heroSlides.map((_, i) => `<button class="hero-dot ${i === idx ? "active" : ""}" data-idx="${i}"></button>`).join("")}</div>`
    : "";
  const arrowsHTML = total > 1
    ? `<button class="hero-nav-arrow left" id="hero-prev" title="Предыдущий">‹</button>
       <button class="hero-nav-arrow right" id="hero-next" title="Следующий">›</button>`
    : "";

  $("home-hero").innerHTML = `
    ${backdropUrl ? `<div class="hero-backdrop" style="background-image:url('${backdropUrl}')"></div>` : `<div class="hero-backdrop" style="background:var(--card-bg)"></div>`}
    <div class="hero-gradient"></div>
    ${arrowsHTML}
    <div class="hero-content">
      ${posterUrl ? `
        <div class="hero-poster-wrap">
          <img class="hero-poster" src="${posterUrl}" alt="${movie.title}" loading="eager" />
        </div>` : ""}
      <div class="hero-info">
        <div class="hero-meta">
          ${year ? `<span class="hero-meta-item">${year}</span>` : ""}
          ${rating ? `<span class="hero-meta-item hero-rating">${rating}</span>` : ""}
          ${total > 1 ? `<span class="hero-meta-item hero-counter">${String(idx + 1).padStart(2, "0")} / ${String(total).padStart(2, "0")}</span>` : ""}
        </div>
        <div class="hero-title">${movie.title}</div>
        ${overview ? `<div class="hero-overview">${overview}</div>` : ""}
        <div class="hero-actions">
          <button class="hero-btn hero-btn-primary" id="hero-open-btn">Подробнее</button>
          <button class="hero-btn hero-btn-watched ${isWatched ? "active" : ""}" id="hero-watched-btn">
            ${isWatched ? "✓ Просмотрено" : "✓ Отметить"}
          </button>
          <button class="hero-btn hero-btn-watchlist ${isWatchlist ? "active" : ""}" id="hero-watchlist-btn">
            ${isWatchlist ? "🕐 В списке" : "🕐 Позже"}
          </button>
        </div>
      </div>
    </div>
    ${dotsHTML}
  `;

  // Биндинг навигации карусели
  const cycleTo = (newIdx) => {
    if (!state.heroSlides || !state.heroSlides.length) return;
    state.heroIdx = ((newIdx % total) + total) % total;
    renderHero(state.heroSlides[state.heroIdx]);
  };
  $("hero-prev")?.addEventListener("click", e => { e.stopPropagation(); cycleTo(idx - 1); });
  $("hero-next")?.addEventListener("click", e => { e.stopPropagation(); cycleTo(idx + 1); });
  document.querySelectorAll(".hero-dot").forEach(d => {
    d.addEventListener("click", e => { e.stopPropagation(); cycleTo(parseInt(d.dataset.idx)); });
  });

  $("hero-open-btn").addEventListener("click", () => {
    pushModal({ type: "movie", data: { ...movie, _mediaType: "movie" } });
    openMovieModal({ ...movie, _mediaType: "movie" });
  });
  $("hero-watched-btn").addEventListener("click", e => {
    toggleWatched(movie.id, e.currentTarget, null, "movie");
    const active = e.currentTarget.classList.toggle("active");
    e.currentTarget.textContent = active ? "✓ Просмотрено" : "✓ Отметить";
  });
  $("hero-watchlist-btn").addEventListener("click", e => {
    toggleWatchlist(movie.id, e.currentTarget, null, "movie");
    const active = e.currentTarget.classList.toggle("active");
    e.currentTarget.textContent = active ? "🕐 В списке" : "🕐 Позже";
  });
}

function renderScrollRow(rowId, movies, mediaType) {
  const row = $(rowId);
  if (!row) return;
  if (!movies?.length) {
    row.innerHTML = `<div class="empty-state" style="padding:20px">Нет данных</div>`;
    return;
  }
  row.innerHTML = "";
  movies.slice(0, 30).forEach(movie => {
    const posterUrl  = movie.poster_path ? `${TMDB_SM}${movie.poster_path}` : null;
    const year       = (movie.release_date || movie.first_air_date || "").slice(0, 4) || "";
    const rating     = movie.vote_average ? Number(movie.vote_average).toFixed(1) : null;
    const isWatched  = state.watched.has(movie.id);
    const isWatchlist = state.watchlist.has(movie.id);

    const card = document.createElement("div");
    card.className = "scroll-card";
    card.innerHTML = `
      <div class="scroll-card-poster-wrap">
        ${posterUrl
          ? `<img class="scroll-card-poster" src="${posterUrl}" alt="${movie.title}" loading="lazy" />`
          : `<div class="scroll-card-no-poster">✦</div>`}
        <div class="scroll-card-overlay">
          <button class="scroll-card-action watch ${isWatched ? "is-watched" : ""}" data-action="watched" title="Просмотрено">✓</button>
          <button class="scroll-card-action list ${isWatchlist ? "is-watch" : ""}" data-action="watchlist" title="Смотреть позже">🕐</button>
          <button class="scroll-card-action dismiss" data-action="dismiss" title="Не интересно">✕</button>
        </div>
        ${rating ? `<div class="scroll-card-rating">★ ${rating}</div>` : ""}
      </div>
      <div class="scroll-card-title">${movie.title}</div>
      ${year ? `<div class="scroll-card-year">${year}</div>` : ""}
    `;

    card.addEventListener("click", e => {
      if (e.target.closest(".scroll-card-action")) return;
      pushModal({ type: "movie", data: { ...movie, _mediaType: mediaType } });
      openMovieModal({ ...movie, _mediaType: mediaType });
    });
    card.querySelector('[data-action="watched"]').addEventListener("click", e => {
      e.stopPropagation();
      toggleWatched(movie.id, e.currentTarget, null, mediaType);
      e.currentTarget.classList.toggle("is-watched");
    });
    card.querySelector('[data-action="dismiss"]').addEventListener("click", e => {
      e.stopPropagation();
      dismissMovie(movie.id, card, true, mediaType);
    });
    card.querySelector('[data-action="watchlist"]').addEventListener("click", e => {
      e.stopPropagation();
      toggleWatchlist(movie.id, e.currentTarget, null, mediaType);
      e.currentTarget.classList.toggle("is-watch");
    });

    row.appendChild(card);
  });
}

function attachScrollArrows(key) {
  const row   = $(`scroll-${key}`);
  const left  = $(`arrow-${key}-left`);
  const right = $(`arrow-${key}-right`);
  if (!row || !left || !right) return;

  const scroll = dir => {
    row.scrollBy({ left: dir * 600, behavior: "smooth" });
  };
  left.onclick  = () => scroll(-1);
  right.onclick = () => scroll(1);
}

function showAllMovies() {
  $("home-content").style.display = "none";
  $("search-content").style.display = "";
  $("discover-title").textContent = "Популярные фильмы";
  $("movies-grid").innerHTML = '<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ</div></div>';
  apiFetch("/popular?media_type=movie").then(movies => {
    renderMovies($("movies-grid"), movies, "discover");
  }).catch(() => {
    $("movies-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Не удалось загрузить</p></div>`;
  });
}

function showAllTV() {
  $("home-content").style.display = "none";
  $("search-content").style.display = "";
  $("discover-title").textContent = "Популярные сериалы";
  $("movies-grid").innerHTML = '<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ</div></div>';
  apiFetch("/popular?media_type=tv").then(shows => {
    renderMovies($("movies-grid"), shows, "discover");
  }).catch(() => {
    $("movies-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Не удалось загрузить</p></div>`;
  });
}

// ─── Популярные (устарело, оставлено для совместимости) ────────────────────
async function loadPopular() {
  loadHomepage();
}

// ─── Кино Дневник ──────────────────────────────────────────────────────────
async function loadWatched() {
  const mode = state.watchedMode;
  const subEl = $("watched-sub");
  if (subEl) subEl.textContent = mode === "tv"
    ? "История сериалов"
    : "История фильмов";
  let items;
  const cached = state.cache.watched[mode];
  if (cached) {
    items = cached;
    apiFetch(mtq("/watched", mode)).then(fresh => {
      state.cache.watched[mode] = fresh;
    }).catch(() => {});
  } else {
    const diaryC = $("diary-container") || $("watched-grid");
    diaryC.innerHTML = '<div class="movies-grid" id="watched-grid"><div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ</div></div></div>';
    try {
      items = await apiFetch(mtq("/watched", mode));
      state.cache.watched[mode] = items;
    } catch {
      diaryC.innerHTML = `<div class="movies-grid" id="watched-grid"><div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div></div>`;
      return;
    }
  }
  try {
    applyDiaryFilters(items);
  } catch {
    const diaryC2 = $("diary-container") || $("watched-grid");
    diaryC2.innerHTML = `<div class="movies-grid" id="watched-grid"><div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div></div>`;
  }
}

function applyDiaryFilters(rawItems) {
  const filterRatingVal = $("watched-rating-filter")?.value || "";
  const filterRating    = filterRatingVal === "" ? null : parseInt(filterRatingVal);
  const filterTitle     = $("watched-search")?.value || "";
  const activePlatBtn   = document.querySelector("#diary-plat-filter .plat-filter-btn.active");
  const filterPlatform  = activePlatBtn?.dataset.val || "";
  const filterPlatCustom = ($("plat-filter-custom")?.value || "").trim().toLowerCase();

  // Mini stats
  const statsEl = $("diary-mini-stats");
  if (statsEl && rawItems.length) {
    const thisYear = new Date().getFullYear();
    const thisYearCount = rawItems.filter(m => {
      const d = m.watched_date || (m.added_at ? String(m.added_at).slice(0, 4) : "");
      return String(d).slice(0, 4) === String(thisYear);
    }).length;
    const rated = rawItems.filter(m => m.user_rating).length;
    const avgRating = rated ? (rawItems.filter(m => m.user_rating).reduce((a, m) => a + m.user_rating, 0) / rated).toFixed(1) : null;
    statsEl.innerHTML = `
      <div class="diary-stat"><span class="diary-stat-val">${rawItems.length}</span><span class="diary-stat-lbl">всего</span></div>
      <div class="diary-stat"><span class="diary-stat-val">${thisYearCount}</span><span class="diary-stat-lbl">в ${thisYear}</span></div>
      ${avgRating ? `<div class="diary-stat"><span class="diary-stat-val">★ ${avgRating}</span><span class="diary-stat-lbl">средняя</span></div>` : ""}
      <div class="diary-stat"><span class="diary-stat-val">${rated}</span><span class="diary-stat-lbl">оценено</span></div>
    `;
  }

  let items = rawItems.map(m => ({ ...m, id: m.movie_id || m.id }));

  if (filterRating !== null) {
    items = filterRating === 0
      ? items.filter(m => !m.user_rating)
      : items.filter(m => m.user_rating === filterRating);
  }
  if (filterTitle) items = items.filter(m => m.title.toLowerCase().includes(filterTitle.toLowerCase()));
  if (filterPlatform === "cinema") {
    items = items.filter(m => m.platform === "cinema");
  } else if (filterPlatform === "home") {
    items = items.filter(m => m.platform === "home");
  } else if (filterPlatform === "other") {
    if (filterPlatCustom) {
      items = items.filter(m => m.platform && m.platform.toLowerCase().includes(filterPlatCustom));
    } else {
      items = items.filter(m => m.platform && m.platform !== "cinema" && m.platform !== "home");
    }
  }

  const container = $("diary-container");
  if (!items.length) {
    container.innerHTML = `<div class="movies-grid" id="watched-grid"><div class="empty-state"><span class="empty-icon">🎬</span><p>Ничего не найдено</p></div></div>`;
    return;
  }

  if (state.diaryView === "timeline") {
    renderDiaryTimeline(container, items);
  } else {
    container.innerHTML = `<div class="movies-grid" id="watched-grid"></div>`;
    renderMovies($("watched-grid"), items, "watched");
  }
}

function renderDiaryTimeline(container, items) {
  const MONTHS_RU = ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"];
  // Group by month
  const groups = new Map();
  items.forEach(m => {
    const raw = m.watched_date || m.added_at;
    let key = "Без даты";
    if (raw) {
      const s = String(raw).slice(0, 7);
      try {
        const [y, mo] = s.split("-");
        key = `${MONTHS_RU[parseInt(mo) - 1]} ${y}`;
      } catch {}
    }
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(m);
  });

  container.innerHTML = "";
  groups.forEach((groupItems, label) => {
    const section = document.createElement("div");
    section.className = "diary-month-section";
    section.innerHTML = `
      <div class="diary-month-header">
        <span class="diary-month-label">${label}</span>
        <span class="diary-month-count">${groupItems.length}</span>
      </div>
    `;
    const grid = document.createElement("div");
    grid.className = "movies-grid";
    renderMovies(grid, groupItems, "watched");
    section.appendChild(grid);
    container.appendChild(section);
  });
}

// Diary view toggle
$("diary-view-grid")?.addEventListener("click", () => {
  state.diaryView = "grid";
  $("diary-view-grid")?.classList.add("active");
  $("diary-view-timeline")?.classList.remove("active");
  const cached = state.cache.watched[state.watchedMode];
  if (cached) applyDiaryFilters(cached);
});
$("diary-view-timeline")?.addEventListener("click", () => {
  state.diaryView = "timeline";
  $("diary-view-timeline")?.classList.add("active");
  $("diary-view-grid")?.classList.remove("active");
  const cached = state.cache.watched[state.watchedMode];
  if (cached) applyDiaryFilters(cached);
});

// Фильтры в дневнике
$("watched-search").addEventListener("input", debounce(() => {
  const cached = state.cache.watched[state.watchedMode];
  if (cached) applyDiaryFilters(cached);
}, 300));

$("watched-rating-filter").addEventListener("change", () => {
  const cached = state.cache.watched[state.watchedMode];
  if (cached) applyDiaryFilters(cached);
});


function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

// ─── К просмотру ───────────────────────────────────────────────────────────
async function loadWatchlist() {
  const mode = state.watchlistMode;
  const subEl = $("watchlist-sub");
  if (subEl) subEl.textContent = mode === "tv"
    ? "Сериалы которые хочешь посмотреть позже"
    : "Фильмы которые хочешь посмотреть позже";
  let items;
  const cached = state.cache.watchlist[mode];
  if (cached) {
    items = cached;
    apiFetch(mtq("/watchlist", mode)).then(fresh => {
      state.cache.watchlist[mode] = fresh;
    }).catch(() => {});
  } else {
    $("watchlist-grid").innerHTML = '<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ</div></div>';
    try {
      items = await apiFetch(mtq("/watchlist", mode));
      state.cache.watchlist[mode] = items;
    } catch {
      $("watchlist-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
      return;
    }
  }
  try {
    applyWatchlistFilters(items);
  } catch {
    $("watchlist-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

function applyWatchlistFilters(rawItems) {
  const cat     = state.watchlistCat;
  const search  = ($("wl-search")?.value || "").toLowerCase();
  const genre   = $("wl-genre")?.value || "";
  const country = $("wl-country")?.value || "";
  const wlYearFrom = sliders.wl?.getFrom() ?? 0;
  const wlYearTo   = sliders.wl?.isDefault() ? 9999 : (sliders.wl?.getTo() ?? 9999);

  // Счётчики по категориям
  const counts = { all: 0, must_see: 0, not_sure: 0, last_resort: 0 };
  rawItems.forEach(m => {
    counts.all++;
    const c = m.category || "not_sure";
    if (counts[c] !== undefined) counts[c]++;
  });
  const countIds = { all: "wl-count-all", must_see: "wl-count-must", not_sure: "wl-count-notsure", last_resort: "wl-count-last" };
  Object.entries(countIds).forEach(([k, id]) => { const el = $(id); if (el) el.textContent = counts[k]; });

  // Заполняем жанры в select один раз
  const genreSelect = $("wl-genre");
  if (genreSelect && genreSelect.options.length <= 1) {
    const allGenres = [...new Set(rawItems.flatMap(m => (m.genres || []).map(g => typeof g === "string" ? g : g.name)))].sort();
    allGenres.forEach(g => { const o = document.createElement("option"); o.value = g; o.textContent = g; genreSelect.appendChild(o); });
  }

  let items = rawItems.map(m => ({ ...m, id: m.movie_id || m.id }));

  // Фильтр по категории
  if (cat !== "all") items = items.filter(m => (m.category || "not_sure") === cat);

  // Поиск
  if (search) items = items.filter(m => m.title.toLowerCase().includes(search));

  // Жанр
  if (genre) items = items.filter(m => (m.genres || []).some(g => (typeof g === "string" ? g : g.name) === genre));

  // Год (слайдер)
  if (!sliders.wl?.isDefault()) {
    items = items.filter(m => {
      const y = m.release_year || parseInt((m.release_date || "").slice(0, 4)) || 0;
      return y >= wlYearFrom && y <= wlYearTo;
    });
  }

  // Страна
  if (country) items = items.filter(m => m.country === country);

  const grid = $("watchlist-grid");
  if (!items.length) {
    grid.innerHTML = `<div class="empty-state"><span class="empty-icon">🕐</span><p>${cat !== "all" ? "В этой категории пусто" : "Список пуст"}</p></div>`;
    return;
  }
  renderWatchlistCards(grid, items);
}

function renderWatchlistCards(container, movies) {
  container.innerHTML = "";
  const mode = state.watchlistMode;
  movies.forEach((movie, index) => {
    const card = document.createElement("div");
    card.className = "movie-card";
    card.style.animationDelay = `${Math.min(index, 20) * 40}ms`;
    const posterUrl  = movie.poster_path ? `${TMDB_CARD}${movie.poster_path}` : null;
    const year       = movie.release_year || (movie.release_date || "").slice(0, 4) || "—";
    const movieId    = movie.id || movie.movie_id;
    const isWatched  = state.watched.has(movieId);
    const userRating = state.watched.get(movieId) ?? movie.user_rating;
    const cat        = movie.category || "not_sure";
    const catLabels  = { must_see: "🔥 Must See", not_sure: "🤔 Не знаю", last_resort: "😴 На крайний" };
    const catClass   = { must_see: "must-see", not_sure: "not-sure", last_resort: "last-resort" };

    card.innerHTML = `
      ${userRating ? `<div class="user-rating-badge">${userRating}</div>` : ""}
      ${posterUrl
        ? `<img class="movie-poster" src="${posterUrl}" alt="${movie.title}" loading="lazy" />`
        : `<div class="no-poster"><span class="no-poster-icon">🎬</span>${movie.title}</div>`}
      <button class="watched-btn ${isWatched ? "is-watched" : ""}" title="${isWatched ? "Убрать из просмотренного" : "Отметить просмотренным"}">✓</button>
      <button class="watch-btn is-watch" title="Убрать из списка">🕐</button>
      <div class="movie-info">
        <div class="wl-cat-chip ${catClass[cat]}" data-movie-id="${movieId}">
          <div class="wl-cat-default">
            <span class="wl-cat-label">${catLabels[cat]}</span>
            <span class="wl-cat-arrow">▾</span>
          </div>
          <div class="wl-cat-picker">
            <button class="wl-pick-btn ${cat === 'must_see'    ? 'active' : ''}" data-cat="must_see">🔥</button>
            <button class="wl-pick-btn ${cat === 'not_sure'    ? 'active' : ''}" data-cat="not_sure">🤔</button>
            <button class="wl-pick-btn ${cat === 'last_resort' ? 'active' : ''}" data-cat="last_resort">😴</button>
          </div>
        </div>
        <div class="movie-title">${movie.title}</div>
        <div class="movie-meta"><span class="movie-year">${year}</span></div>
        ${cardRatingsHTML(movie)}
      </div>
    `;

    const cardMediaType = movie.media_type || mode;

    card.addEventListener("click", e => {
      if (e.target.closest(".watched-btn,.watch-btn,.wl-cat-chip")) return;
      pushModal({ type: "movie", data: { ...movie, _mediaType: cardMediaType } });
      openMovieModal({ ...movie, _mediaType: cardMediaType });
    });

    card.querySelector(".watched-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleWatched(movieId, card.querySelector(".watched-btn"), null, cardMediaType);
    });

    card.querySelector(".watch-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleWatchlist(movieId, card.querySelector(".watch-btn"), container, cardMediaType);
    });

    // Category chip — открывает inline-пикер на месте, без дропдауна
    const chip = card.querySelector(".wl-cat-chip");
    chip.querySelector(".wl-cat-default").addEventListener("click", e => {
      e.stopPropagation();
      document.querySelectorAll(".wl-cat-chip.picking").forEach(c => { if (c !== chip) c.classList.remove("picking"); });
      chip.classList.toggle("picking");
    });
    chip.querySelector(".wl-cat-picker").addEventListener("click", e => {
      e.stopPropagation();
      const btn = e.target.closest(".wl-pick-btn");
      if (!btn) return;
      chip.classList.remove("picking");
      setWatchlistCategory(movieId, btn.dataset.cat, cardMediaType, chip, catLabels, catClass);
    });

    container.appendChild(card);
  });

  document.addEventListener("click", () => {
    document.querySelectorAll(".wl-cat-chip.picking").forEach(c => c.classList.remove("picking"));
  }, { once: true });
}

function updateWatchlistCounts(rawItems) {
  if (!rawItems) return;
  const counts = { all: 0, must_see: 0, not_sure: 0, last_resort: 0 };
  rawItems.forEach(m => { counts.all++; const c = m.category || "not_sure"; if (counts[c] !== undefined) counts[c]++; });
  const ids = { all: "wl-count-all", must_see: "wl-count-must", not_sure: "wl-count-notsure", last_resort: "wl-count-last" };
  Object.entries(ids).forEach(([k, id]) => { const el = $(id); if (el) el.textContent = counts[k]; });
}

async function setWatchlistCategory(movieId, category, mediaType, chip, catLabels, catClass) {
  const mode = state.watchlistMode;
  const item = state.cache.watchlist[mode]?.find(m => (m.movie_id || m.id) === movieId);
  const oldCategory = item?.category || "not_sure";
  if (oldCategory === category) return;

  // Оптимистичный апдейт — мгновенно, без ожидания сети
  chip.className = `wl-cat-chip ${catClass[category]}`;
  chip.querySelector(".wl-cat-label").textContent = catLabels[category];
  chip.querySelectorAll(".wl-pick-btn").forEach(b => b.classList.toggle("active", b.dataset.cat === category));
  if (item) item.category = category;
  updateWatchlistCounts(state.cache.watchlist[mode]);

  // Если просматриваем конкретную категорию и карточка туда уже не входит — плавно убираем
  if (state.watchlistCat !== "all" && state.watchlistCat !== category) {
    const card = chip.closest(".movie-card");
    if (card) {
      card.style.transition = "opacity 0.25s, transform 0.25s";
      card.style.opacity = "0";
      card.style.transform = "scale(0.94)";
      setTimeout(() => card.remove(), 260);
    }
  }

  try {
    await apiFetch(`/watchlist/${movieId}/category`, {
      method: "PATCH",
      body: JSON.stringify({ category, media_type: mediaType, user_id: state.user?.id || 1 }),
    });
  } catch {
    // Откат при ошибке
    chip.className = `wl-cat-chip ${catClass[oldCategory]}`;
    chip.querySelector(".wl-cat-label").textContent = catLabels[oldCategory];
    chip.querySelectorAll(".wl-pick-btn").forEach(b => b.classList.toggle("active", b.dataset.cat === oldCategory));
    if (item) item.category = oldCategory;
    updateWatchlistCounts(state.cache.watchlist[mode]);
    const cached = state.cache.watchlist[mode];
    if (cached) applyWatchlistFilters(cached);
    toast("Ошибка обновления категории", "error");
  }
}

// Watchlist category tab clicks
document.querySelectorAll(".wl-cat-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".wl-cat-btn").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    state.watchlistCat = btn.dataset.cat;
    const cached = state.cache.watchlist[state.watchlistMode];
    if (cached) applyWatchlistFilters(cached);
  });
});

// Watchlist filters
["wl-search", "wl-genre", "wl-country"].forEach(id => {
  const el = document.getElementById(id);
  if (!el) return;
  const handler = () => {
    const cached = state.cache.watchlist[state.watchlistMode];
    if (cached) applyWatchlistFilters(cached);
  };
  el.addEventListener(id === "wl-search" ? "input" : "change", id === "wl-search" ? debounce(handler, 250) : handler);
});

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
  const mode     = state.recsMode;
  const studioId = $("filter-studio")?.value || "0";
  const incCountries = [...state.filterState.country.inc].join(",");
  const label = mode === "tv" ? "сериалы" : "фильмы";

  $("recs-grid").innerHTML = `<div class="loader">Подбираем ${label}…</div>`;

  try {
    const params = new URLSearchParams({ studio_id: studioId, media_type: mode });
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

// Есть ли активные фильтры — определяет, включать ли Mono mode
function hasActiveFilters() {
  const yearFrom  = sliders.rec?.getFrom() ?? 0;
  const yearTo    = sliders.rec?.getTo()   ?? 9999;
  const minRating = parseFloat($("filter-min-rating")?.value) || 0;
  const studioId  = parseInt($("filter-studio")?.value) || 0;
  const { genre, country } = state.filterState;
  return (
    yearFrom > 0 || yearTo > 0 || minRating > 0 || studioId > 0 ||
    genre.inc.size > 0 || genre.exc.size > 0 ||
    country.inc.size > 0 || country.exc.size > 0
  );
}

function applyFiltersAndRender() {
  const yearFrom  = sliders.rec?.getFrom() ?? 0;
  const yearTo    = sliders.rec?.isDefault() ? 9999 : (sliders.rec?.getTo() ?? 9999);
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

    const posterUrl   = movie.poster_path ? `${TMDB_CARD}${movie.poster_path}` : null;
    const year        = (movie.release_date || "").slice(0, 4) || "—";
    const movieId     = movie.id || movie.movie_id;
    const isWatched   = state.watched.has(movieId);
    const userRating  = state.watched.get(movieId) ?? movie.user_rating;
    const isWatch     = state.watchlist.has(movieId);
    const showDismiss = mode !== "watched" && mode !== "watchlist" && mode !== "dismissed";
    const showScore   = mode === "recommendations" && movie.similarity_score;
    const noRating    = mode === "watched" && !userRating;

    const PLATFORM_LABELS = { cinema: "🎦 Кино", home: "🏠 Дома" };
    const platformBadge = mode === "watched" && movie.platform
      ? `<div class="platform-badge">${PLATFORM_LABELS[movie.platform] || movie.platform}</div>`
      : "";
    card.innerHTML = `
      ${showDismiss ? `<button class="dismiss-btn" title="Не интересно">✕</button>` : ""}
      ${showScore ? `<div class="similarity-badge">${Math.round(movie.similarity_score * 100)}%</div>` : ""}
      ${userRating ? `<div class="user-rating-badge">${userRating}</div>` : ""}
      ${noRating ? `<div class="no-rating-badge">не оценён</div>` : ""}
      ${platformBadge}
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

    // Определяем тип карточки: из movie или из контекста вкладки
    const cardMediaType =
      movie.media_type ||
      (mode === "watched"         ? state.watchedMode
      : mode === "watchlist"       ? state.watchlistMode
      : mode === "dismissed"       ? state.dismissedMode
      : mode === "recommendations" ? state.recsMode
      : "movie");

    card.addEventListener("click", e => {
      if (e.target.closest(".watched-btn,.watch-btn,.dismiss-btn")) return;
      pushModal({ type: "movie", data: { ...movie, _mediaType: cardMediaType } });
      openMovieModal({ ...movie, _mediaType: cardMediaType });
    });

    card.querySelector(".watched-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleWatched(movieId, card.querySelector(".watched-btn"), mode === "watched" ? container : null, cardMediaType);
    });
    card.querySelector(".watch-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleWatchlist(movieId, card.querySelector(".watch-btn"), mode === "watchlist" ? container : null, cardMediaType);
    });
    if (showDismiss) {
      card.querySelector(".dismiss-btn").addEventListener("click", e => {
        e.stopPropagation();
        dismissMovie(movieId, card, mode === "recommendations", cardMediaType);
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
    const movieId = movie.id || movie.movie_id;
    const cacheKey = `${movieId}-${mediaType}`;
    let details = state._detailsCache?.get(cacheKey);
    if (!details) {
      details = await apiFetch(`/movie/${movieId}/details?media_type=${mediaType}`);
      if (!state._detailsCache) state._detailsCache = new Map();
      state._detailsCache.set(cacheKey, details);
    }
    details.media_type = details.media_type || mediaType;
    renderMovieContent(details);
    if (isBack) $("modal").scrollTop = state.modalStack[state.modalStack.length - 1]?.scrollTop || 0;
  } catch {
    movie.media_type = movie.media_type || mediaType;
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
  const mediaType   = movie.media_type || "movie";  // тип конкретно этой модалки
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
  const watchedPlatform = movie.platform || "";
  const watchedDate = movie.watched_date ? String(movie.watched_date).slice(0, 10) : "";
  const isOther   = watchedPlatform && watchedPlatform !== "cinema" && watchedPlatform !== "home";
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
      <div class="rating-meta-row">
        <div class="platform-picker" id="platform-picker">
          <button class="plat-btn ${watchedPlatform === "cinema" ? "active" : ""}" data-val="cinema">🎦 В кино</button>
          <button class="plat-btn ${watchedPlatform === "home"   ? "active" : ""}" data-val="home">🏠 Дома</button>
          <button class="plat-btn ${isOther ? "active" : ""}" data-val="other">✏️ Другое</button>
        </div>
        <input type="text" class="plat-other-input" id="plat-other-input"
               placeholder="Netflix, у друга, самолёт…"
               value="${isOther ? watchedPlatform : ""}"
               style="display:${isOther ? "block" : "none"}" />
        <input type="date" class="rating-date-input" id="rating-date" value="${watchedDate}" max="${new Date().toISOString().slice(0,10)}" />
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
      ${mediaType === "tv" && movie.seasons?.length ? renderSeasonsHTML(movie) : ""}
    </div>
  `;

  // Сезоны
  if (mediaType === "tv") bindSeasonsEvents(movieId);

  // Трейлер
  $("trailer-play-btn").addEventListener("click", async () => {
    const btn = $("trailer-play-btn");
    btn.innerHTML = `<span>⏳</span><span>Загружаем…</span>`; btn.disabled = true;
    try {
      const data = await apiFetch(`/trailer/${movieId}?media_type=${mediaType}`);
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
    await toggleWatched(movieId, $("modal-watched-btn"), null, mediaType);
    const now = state.watched.has(movieId);
    $("modal-watched-btn").className = `modal-watched-btn ${now ? "remove" : ""}`;
    $("modal-watched-btn").textContent = now ? "✓ Просмотрено" : "✓ Отметить просмотренным";
  });

  // К просмотру
  $("modal-watch-btn").addEventListener("click", async () => {
    await toggleWatchlist(movieId, $("modal-watch-btn"), null, mediaType);
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

  // Платформа: 3 кнопки + текстовое поле
  document.querySelectorAll("#platform-picker .plat-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll("#platform-picker .plat-btn").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      const inp = $("plat-other-input");
      if (inp) inp.style.display = btn.dataset.val === "other" ? "block" : "none";
    });
  });

  // Сохранить оценку
  $("save-rating-btn").addEventListener("click", async () => {
    if (!selectedRating) { toast("Выбери оценку от 1 до 10", "error"); return; }
    const review  = $("review-input").value.trim();
    const activePlatBtn = document.querySelector("#platform-picker .plat-btn.active");
    const platVal       = activePlatBtn?.dataset.val;
    const platform      = platVal === "other"
      ? ($("plat-other-input")?.value.trim() || null)
      : (platVal || null);
    const watchedDate = $("rating-date")?.value || null;
    try {
      await apiFetch("/watched/rate", {
        method: "POST",
        body: JSON.stringify({ movie_id: movieId, rating: selectedRating, review: review || null, media_type: mediaType, platform: platform || null, watched_date: watchedDate || null }),
      });
      state.watched.set(movieId, selectedRating);
      state.cache.watched[mediaType] = null;  // инвалидируем кэш дневника
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
      const studio = { id: parseInt(btn.dataset.studioId), name: btn.dataset.studioName, _mediaType: mediaType };
      pushModal({ type: "studio", data: studio });
      openStudioModal(studio);
    });
  });

  // Похожие фильмы
  const simSec  = $("similar-section");
  const simGrid = $("similar-grid");
  simSec.style.display = "block";
  simGrid.innerHTML = '<div class="loader">Загружаем похожие…</div>';
  apiFetch(`/similar/${movieId}?media_type=${mediaType}`).then(similar => {
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
      openMovieModal({ id, _mediaType: type });
    });
  });
}

// ─── Модалка: студия ───────────────────────────────────────────────────────
async function openStudioModal(studio, isBack = false) {
  $("similar-section").style.display = "none";
  $("modal-content").innerHTML = `<div style="height:400px;display:flex;align-items:center;justify-content:center;color:var(--text-dim)">Загружаем фильмы ${studio.name}…</div>`;
  try {
    const studioMediaType = studio._mediaType || "movie";
    const movies = await apiFetch(`/studio/${studio.id}/movies?media_type=${studioMediaType}`);
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
    const posterUrl  = movie.poster_path ? `${TMDB_CARD}${movie.poster_path}` : null;
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
      state.cache.watched[mt] = null;  // инвалидируем кэш
      btn.classList.remove("is-watched");
      toast("Убрано из просмотренного");
      if (containerToRefresh) animateRemove(btn.closest(".movie-card"), () => loadWatched());
    } else {
      await apiFetch("/watched", { method: "POST", body: JSON.stringify({ movie_id: movieId, media_type: mt }) });
      state.watched.set(movieId, null);
      state.cache.watched[mt] = null;  // инвалидируем кэш
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
      state.cache.watchlist[mt] = null;  // инвалидируем кэш
      toast("Удалено из списка");
      if (containerToRefresh) animateRemove(btn.closest(".movie-card"), () => loadWatchlist());
    } else {
      await apiFetch("/watchlist", { method: "POST", body: JSON.stringify({ movie_id: movieId, media_type: mt }) });
      state.watchlist.add(movieId); btn.classList.add("is-watch");
      state.cache.watchlist[mt] = null;  // инвалидируем кэш
      toast("Добавлено в список 🕐", "success");
    }
    $("watchlist-count").textContent = state.watchlist.size;
  } catch (err) { toast(err.detail || "Ошибка", "error"); }
}

// ─── Отклонить ─────────────────────────────────────────────────────────────
async function dismissMovie(movieId, card, removeFromList = false, mediaType = "movie") {
  try {
    await apiFetch("/dismiss", { method: "POST", body: JSON.stringify({ movie_id: movieId, media_type: mediaType }) });
    if (state.dismissed) state.dismissed.add(movieId);
    state.cache.dismissed[mediaType] = null;  // инвалидируем кэш
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
    // Параллельно: обе типа списков + студии/жанры по дефолтному типу (movie) для recs
    const [
      watchedMv, watchedTv,
      watchlistMv, watchlistTv,
      dismissedMv, dismissedTv,
      studios, genreList, favActorList,
    ] = await Promise.all([
      apiFetch(mtq("/watched",   "movie")),
      apiFetch(mtq("/watched",   "tv")),
      apiFetch(mtq("/watchlist", "movie")),
      apiFetch(mtq("/watchlist", "tv")),
      apiFetch(mtq("/dismissed", "movie")),
      apiFetch(mtq("/dismissed", "tv")),
      apiFetch(mtq("/studios",   state.recsMode)),
      apiFetch(mtq("/genres",    state.recsMode)).catch(() => []),
      apiFetch("/favorite-actors").catch(() => []),
    ]);
    const allWatched   = [...watchedMv,   ...watchedTv];
    const allWatchlist = [...watchlistMv, ...watchlistTv];
    const allDismissed = [...dismissedMv, ...dismissedTv];
    state.favActors = new Set((favActorList || []).map(a => a.actor_id));
    state.watched   = new Map(allWatched.map(m => [m.movie_id, m.user_rating]));
    state.watchlist = new Set(allWatchlist.map(m => m.movie_id));
    state.dismissed = new Set(allDismissed.map(m => m.movie_id));
    // Заполняем кэш для мгновенного переключения типа во вкладках
    state.cache.watched.movie   = watchedMv;
    state.cache.watched.tv      = watchedTv;
    state.cache.watchlist.movie = watchlistMv;
    state.cache.watchlist.tv    = watchlistTv;
    state.cache.dismissed.movie = dismissedMv;
    state.cache.dismissed.tv    = dismissedTv;
    $("watch-count").textContent     = allWatched.length;
    $("watchlist-count").textContent = allWatchlist.length;
    const dc = document.getElementById("dismissed-count");
    if (dc) dc.textContent = allDismissed.length;

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
  loadHomepage();
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
    init().then(() => { if (state.appMode === "books") setTimeout(() => switchAppMode("books"), 100); });
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
    init().then(() => { if (state.appMode === "books") setTimeout(() => switchAppMode("books"), 100); });
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
  state.cache = {
    watched:   { movie: null, tv: null },
    watchlist: { movie: null, tv: null },
    dismissed: { movie: null, tv: null },
    homepage:  { ts: 0, movies: null, tv: null, recs: null, recsTv: null },
  };
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

  // ── Инициализация ползунков года ──────────────────────────────────────
  sliders.rec = initYearSlider("rec-year-slider", (from, to) => {
    if (state.allRecs.length > 0) applyFiltersAndRender();
  });

  sliders.wl = initYearSlider("wl-year-slider", () => {
    const cached = state.cache.watchlist[state.watchlistMode];
    if (cached) applyWatchlistFilters(cached);
  });

  // ── Платформа-фильтр в дневнике ───────────────────────────────────────
  document.querySelectorAll("#diary-plat-filter .plat-filter-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll("#diary-plat-filter .plat-filter-btn").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      const customInput = $("plat-filter-custom");
      if (customInput) {
        customInput.style.display = btn.dataset.val === "other" ? "inline-block" : "none";
        if (btn.dataset.val !== "other") customInput.value = "";
      }
      const cached = state.cache.watched[state.watchedMode];
      if (cached) applyDiaryFilters(cached);
    });
  });

  $("plat-filter-custom")?.addEventListener("input", debounce(() => {
    const cached = state.cache.watched[state.watchedMode];
    if (cached) applyDiaryFilters(cached);
  }, 300));

  // ── Переключатель режима и книжная навигация ──────────────────────────────
  document.querySelectorAll(".mode-btn").forEach(btn => {
    btn.addEventListener("click", () => switchAppMode(btn.dataset.mode));
  });

  document.querySelectorAll(".books-nav-btn").forEach(btn => {
    btn.addEventListener("click", () => openBooksTab(btn.dataset.booksTab));
  });

  const booksSearchInput = $("books-search-input");
  if (booksSearchInput) {
    booksSearchInput.addEventListener("input", debounce(e => {
      searchBooks(e.target.value.trim());
    }, 400));
  }

  $("books-suggest-btn")?.addEventListener("click", loadBooksSuggest);
});

// ─── Запуск ────────────────────────────────────────────────────────────────
(function startup() {
  // Восстанавливаем сохранённый режим (кино/книги)
  const savedMode = localStorage.getItem("appMode") || "cinema";
  if (savedMode === "books") {
    state.appMode = "books";
  }

  const saved = localStorage.getItem("film_user");
  if (saved) {
    try {
      const user = JSON.parse(saved);
      setUser(user);
      init().then(() => {
        if (state.appMode === "books") {
          setTimeout(() => switchAppMode("books"), 100);
        }
      });
      return;
    } catch {}
  }
  // Нет сохранённого пользователя — показываем авторизацию
  $("auth-overlay").classList.add("visible");
})();

// ─── Актёры ────────────────────────────────────────────────────────────────

async function loadActors() {
  const grid = $("actors-grid");
  grid.innerHTML = '<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ИЩЕМ АКТЁРОВ</div></div>';
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
  const photoUrl  = actor.profile_path ? `${TMDB_CARD}${actor.profile_path}` : null;
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
  const mode = state.dismissedMode;
  let items;
  const cached = state.cache.dismissed[mode];
  if (cached) {
    items = cached;
    apiFetch(mtq("/dismissed", mode)).then(fresh => {
      state.cache.dismissed[mode] = fresh;
    }).catch(() => {});
  } else {
    $("dismissed-grid").innerHTML = '<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ</div></div>';
    try {
      items = await apiFetch(mtq("/dismissed", mode));
      state.cache.dismissed[mode] = items;
    } catch {
      $("dismissed-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
      return;
    }
  }
  try {
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
  grid.innerHTML = `
    <div class="ai-thinker">
      <div class="ai-thinker-stage">
        <div class="ai-thought">💭</div>
        <div class="ai-spark">✦</div>
        <div class="ai-monkey">🙊</div>
        <div class="ai-shadow"></div>
      </div>
      <div class="ai-thinker-text">ОБЕЗЬЯНКА ДУМАЕТ<span class="ai-thinker-dots">...</span></div>
    </div>`;

  try {
    const url = query
      ? `/ai/suggest?query=${encodeURIComponent(query)}`
      : "/ai/suggest";
    const data = await apiFetch(url);
    const movies = data.movies || [];
    if (!movies.length) {
      const aiTitles = (data.debug_ai || []).map(x => x.title).join(", ");
      hint.textContent = aiTitles
        ? `AI предложил: ${aiTitles} — но TMDB не нашёл эти фильмы`
        : "AI не вернул рекомендации, попробуй ещё раз";
      grid.innerHTML = `<div class="empty-state"><span class="empty-icon">✦</span><p>Ничего не нашлось в базе TMDB. Попробуй ещё раз — AI иногда предлагает разное</p></div>`;
      return;
    }
    hint.textContent = `Нашёл ${movies.length} ${movies.length === 1 ? "рекомендацию" : movies.length < 5 ? "рекомендации" : "рекомендаций"} специально для тебя`;

    grid.innerHTML = "";
    movies.forEach((movie, i) => {
      const card = document.createElement("div");
      card.className = "movie-card";
      card.style.animationDelay = `${i * 60}ms`;
      const posterUrl  = movie.poster_path ? `${TMDB_CARD}${movie.poster_path}` : null;
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
  wrap.innerHTML = '<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">СОБИРАЕМ ПРОФИЛЬ</div></div>';
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
  // В Mono теме — отдельный рендерер с другим layout
  if (document.body.classList.contains("theme-mono")) {
    return renderProfileMono(s, actorsData);
  }
  const wrap = $("profile-content");
  const user = state.user || { display_name: "Пользователь" };
  const initial = user.display_name?.[0]?.toUpperCase() || "?";
  const actors = Array.isArray(actorsData) ? actorsData : (actorsData?.actors || []);

  if (!s.total) {
    wrap.innerHTML = `
      <div class="profile-wrap">
        <div class="profile-banner">
          <div class="profile-banner-overlay"></div>
          <div class="profile-banner-content">
            <div class="profile-avatar">${initial}</div>
            <div class="profile-banner-info">
              <div class="profile-name">${user.display_name}</div>
              <div class="profile-sub">Участник FilmByMihaylov</div>
            </div>
          </div>
        </div>
        <div class="empty-state" style="margin-top:40px"><span class="empty-icon">🎬</span><p>Отметь фильмы просмотренными, чтобы увидеть статистику</p></div>
      </div>`;
    return;
  }

  // Постеры для баннера
  const bannerPosters = s.top_rated.slice(0, 6).map(m =>
    m.poster
      ? `<div class="profile-banner-poster" style="background-image:url('${TMDB_SM}${m.poster}')"></div>`
      : ""
  ).join("");

  // Рейтинговый чарт
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
        <div class="rating-bar-stack" style="height:${Math.max(pct, total ? 4 : 0)}%">
          <div class="rating-bar tv"    style="height:${tvPct}%"></div>
          <div class="rating-bar movie" style="height:${moviePct}%"></div>
        </div>
        <div class="rating-bar-num">${num}</div>
      </div>`;
  }).join("");

  // Жанры
  const maxGenre = Math.max(...s.top_genres.map(g => g.total || 0), 1);
  const genresHTML = s.top_genres.map(g => {
    const total    = g.total || 0;
    const mc       = g.movie_count || 0;
    const tc       = g.tv_count    || 0;
    const barPct   = Math.round(total / maxGenre * 100);
    const moviePct = total ? Math.round(mc / total * 100) : 50;
    const tvPct    = 100 - moviePct;
    const mcLabel  = mc ? `<span class="genre-bar-count-movie">🎬 ${mc}</span>` : "";
    const tcLabel  = tc ? `<span class="genre-bar-count-tv">📺 ${tc}</span>` : "";
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

  // Актёры
  const actorsHTML = actors.map(a => {
    const img = a.profile_path
      ? `<img class="profile-actor-photo" src="https://image.tmdb.org/t/p/w185${a.profile_path}" loading="lazy" />`
      : `<div class="profile-actor-no-photo">👤</div>`;
    const movieBadge = a.movie_count ? `<span class="badge-movie">🎬 ${a.movie_count}</span>` : "";
    const tvBadge    = a.tv_count    ? `<span class="badge-tv">📺 ${a.tv_count}</span>` : "";
    return `
    <div class="profile-actor-item" data-actor-id="${a.id || ""}">
      ${img}
      <div class="profile-actor-info">
        <div class="profile-actor-name">${a.name}</div>
        <div class="profile-actor-badges">${movieBadge}${tvBadge}</div>
      </div>
    </div>`;
  }).join("");

  // Режиссёры с порядковым номером
  const directorsHTML = s.top_directors.map((d, i) => `
    <div class="profile-list-item">
      <span class="profile-list-rank">${i + 1}</span>
      <span class="profile-list-name">${d.name}</span>
      <span class="profile-list-badge">${d.count}</span>
    </div>`).join("");

  // Топ фильмы — горизонтальный скролл с постерами
  const topRatedHTML = s.top_rated.map(m => `
    <div class="profile-top-movie">
      <div class="profile-top-poster-wrap">
        ${m.poster
          ? `<img class="profile-top-poster" src="${TMDB_SM}${m.poster}" loading="lazy" />`
          : `<div class="profile-top-no-poster">🎬</div>`}
        <div class="profile-top-rating">★ ${m.rating}</div>
      </div>
    </div>`).join("");

  const legendHTML = `
    <div class="profile-legend">
      <span class="legend-dot movie"></span><span class="legend-lbl">Фильмы</span>
      <span class="legend-dot tv"></span><span class="legend-lbl">Сериалы</span>
    </div>`;

  wrap.innerHTML = `
    <div class="profile-wrap">

      <div class="profile-banner">
        <div class="profile-banner-bg">${bannerPosters}</div>
        <div class="profile-banner-overlay"></div>
        <div class="profile-banner-content">
          <div class="profile-avatar">${initial}</div>
          <div class="profile-banner-info">
            <div class="profile-name">${user.display_name}</div>
            <div class="profile-sub">Участник FilmByMihaylov</div>
          </div>
        </div>
      </div>

      <div class="profile-stats">
        <div class="profile-stat">
          <div class="profile-stat-val">${s.movies}</div>
          <div class="profile-stat-lbl">Фильмов</div>
        </div>
        <div class="profile-stat-divider"></div>
        <div class="profile-stat">
          <div class="profile-stat-val">${s.tv}</div>
          <div class="profile-stat-lbl">Сериалов</div>
        </div>
        <div class="profile-stat-divider"></div>
        <div class="profile-stat">
          <div class="profile-stat-val">${s.avg_rating ?? "—"}</div>
          <div class="profile-stat-lbl">Средняя оценка</div>
        </div>
        <div class="profile-stat-divider"></div>
        <div class="profile-stat">
          <div class="profile-stat-val">${s.rated_count}</div>
          <div class="profile-stat-lbl">Оценено</div>
        </div>
      </div>

      <div class="profile-grid">

        ${s.rated_count ? `
        <div class="profile-card">
          <div class="profile-card-title">Оценки ${legendHTML}</div>
          ${s.avg_rating ? `
          <div class="profile-avg-badge">
            <div class="profile-avg-val">${s.avg_rating}</div>
            <div class="profile-avg-sub">средняя оценка</div>
          </div>` : ""}
          <div class="rating-bars">
            <div class="rating-bars-grid">
              <div class="rating-grid-line"></div>
              <div class="rating-grid-line"></div>
              <div class="rating-grid-line"></div>
            </div>
            ${ratingBarsHTML}
          </div>
        </div>` : ""}

        ${s.top_genres.length ? `
        <div class="profile-card">
          <div class="profile-card-title">Жанры ${legendHTML}</div>
          <div class="genre-bars">${genresHTML}</div>
        </div>` : ""}

        ${actors.length ? `
        <div class="profile-card profile-card-full">
          <div class="profile-card-title">Часто встречаемые актёры</div>
          <div class="profile-actors-list" id="profile-actors-list">${actorsHTML}</div>
        </div>` : ""}

        ${s.top_rated.length ? `
        <div class="profile-card profile-card-full">
          <div class="profile-card-title">Лучшие по твоей оценке</div>
          <div class="profile-top-scroll">${topRatedHTML}</div>
        </div>` : ""}

        ${s.top_directors.length ? `
        <div class="profile-card">
          <div class="profile-card-title">Режиссёры</div>
          <div class="profile-list">${directorsHTML}</div>
        </div>` : ""}

        ${buildMonthlyChartHTML(s)}

        ${buildPlatformStatsHTML(s)}

        <div class="profile-card ${s.top_directors.length ? "" : "profile-card-full"}">
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
        ${tc ? `<div class="bar-tooltip-tv">📺 Сериалы: <b>${tc}</b></div>` : ""}
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

  // Клики по актёрам
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

// ─── Год в кино: monthly chart ───────────────────────────────────────────────
function buildMonthlyChartHTML(s) {
  const monthly = s.monthly_stats;
  if (!monthly || !Object.keys(monthly).length) return "";

  const sorted = Object.entries(monthly).sort(([a], [b]) => a.localeCompare(b));
  if (sorted.length < 2) return "";

  const MONTHS_RU = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];
  const maxVal = Math.max(...sorted.map(([, v]) => (v.movie || 0) + (v.tv || 0)), 1);

  // Last 12 months only
  const recent = sorted.slice(-12);

  const barsHTML = recent.map(([key, v]) => {
    const [yr, mo] = key.split("-");
    const total  = (v.movie || 0) + (v.tv || 0);
    const pct    = Math.round(total / maxVal * 100);
    const mPct   = total ? Math.round((v.movie || 0) / total * 100) : 50;
    const tPct   = 100 - mPct;
    return `
      <div class="mc-bar-wrap" title="${MONTHS_RU[parseInt(mo)-1]} ${yr}: ${total} шт">
        ${total ? `<div class="mc-bar-cnt">${total}</div>` : ""}
        <div class="mc-bar-stack" style="height:${Math.max(pct, total ? 6 : 0)}%">
          <div class="mc-bar tv"    style="height:${tPct}%"></div>
          <div class="mc-bar movie" style="height:${mPct}%"></div>
        </div>
        <div class="mc-bar-lbl">${MONTHS_RU[parseInt(mo)-1]}</div>
      </div>`;
  }).join("");

  const thisYear = new Date().getFullYear();
  const yearTotal = sorted.filter(([k]) => k.startsWith(String(thisYear))).reduce((a, [, v]) => a + (v.movie || 0) + (v.tv || 0), 0);

  return `
    <div class="profile-card profile-card-full">
      <div class="profile-card-title">Год в кино <span class="profile-card-sub">${thisYear} — ${yearTotal} просмотров</span></div>
      <div class="monthly-chart">${barsHTML}</div>
    </div>`;
}

// ─── Статистика платформ ─────────────────────────────────────────────────────
function buildPlatformStatsHTML(s) {
  const platforms = s.platform_stats;
  if (!platforms || !Object.keys(platforms).length) return "";
  const LABELS = { cinema: "🎦 В кино", netflix: "Netflix", kinopoisk: "Кинопоиск", prime: "Prime Video", appletv: "Apple TV+", disney: "Disney+", hbo: "HBO Max", home: "🏠 Дома", other: "Другое" };
  const total = Object.values(platforms).reduce((a, b) => a + b, 0);
  const rows = Object.entries(platforms).map(([key, cnt]) => {
    const pct = Math.round(cnt / total * 100);
    return `
      <div class="platform-row">
        <div class="platform-row-label">${LABELS[key] || key}</div>
        <div class="platform-row-bar-wrap">
          <div class="platform-row-bar" style="width:${pct}%"></div>
        </div>
        <div class="platform-row-cnt">${cnt}</div>
      </div>`;
  }).join("");

  return `
    <div class="profile-card">
      <div class="profile-card-title">Где смотрел</div>
      <div class="platform-stats">${rows}</div>
    </div>`;
}

// ─── MONO профиль: редакторская верстка ─────────────────────────────────────
function renderProfileMono(s, actorsData) {
  const wrap = $("profile-content");
  const user = state.user || { display_name: "Пользователь", username: "user" };
  const actors = Array.isArray(actorsData) ? actorsData : (actorsData?.actors || []);

  if (!s || !s.total) {
    wrap.innerHTML = `
      <div class="mono-profile">
        <div class="mono-profile-head">
          <div class="mono-prof-name-block">
            <div class="mono-prof-eyebrow">PROFILE · MEMBER SINCE 2025</div>
            <h1 class="mono-prof-name">${(user.display_name || "ПОЛЬЗОВАТЕЛЬ").toUpperCase()}</h1>
            <div class="mono-prof-handle">@${user.username || "user"}</div>
          </div>
        </div>
        <div class="empty-state" style="padding:60px 0"><p style="font-family:'Fraunces',serif;font-style:italic;font-size:18px">Отметь хотя бы один фильм просмотренным, чтобы появилась статистика.</p></div>
      </div>`;
    return;
  }

  // ── Подготовка данных ─────────────────────────────────────────────────
  // Donut: movie vs tv
  const totalWatched = s.movies + s.tv;
  const moviePct = Math.round((s.movies / Math.max(totalWatched, 1)) * 100);
  const tvPct    = 100 - moviePct;
  // SVG donut
  const R = 60, C = 2 * Math.PI * R;
  const movieLen = (moviePct / 100) * C;
  const tvLen    = C - movieLen;

  // Гистограмма рейтингов
  const maxRC = Math.max(
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
    const pct = Math.round((total / maxRC) * 100);
    const moviePctBar = total ? Math.round((mc / total) * 100) : 50;
    const tvPctBar    = 100 - moviePctBar;
    return `
      <div class="mono-rb" title="Оценка ${num}: фильмов ${mc}, сериалов ${tc}">
        ${total ? `<div class="mono-rb-cnt">${total}</div>` : ""}
        <div class="mono-rb-stack" style="height:${Math.max(pct, total ? 3 : 0)}%">
          <div class="mono-rb-bar tv"    style="height:${tvPctBar}%"></div>
          <div class="mono-rb-bar movie" style="height:${moviePctBar}%"></div>
        </div>
        <div class="mono-rb-num">${num}</div>
      </div>`;
  }).join("");

  // Жанры
  const maxGenre = Math.max(...s.top_genres.map(g => g.total || 0), 1);
  const genresHTML = s.top_genres.slice(0, 8).map(g => {
    const total   = g.total || 0;
    const mc      = g.movie_count || 0;
    const tc      = g.tv_count || 0;
    const barPct  = (total / maxGenre) * 100;
    const mp = total ? (mc / total) * 100 : 50;
    const tp = 100 - mp;
    return `
      <div class="mono-genre-row">
        <div class="mono-genre-label">
          <span class="mono-genre-name">${g.name}</span>
          <span class="mono-genre-cnt">${mc ? `<span class="m">🎬${mc}</span>` : ""} ${tc ? `<span class="t">📺${tc}</span>` : ""}</span>
        </div>
        <div class="mono-genre-track">
          <div class="mono-genre-fill movie" style="width:${barPct * mp / 100}%"></div>
          <div class="mono-genre-fill tv"    style="width:${barPct * tp / 100}%"></div>
        </div>
      </div>`;
  }).join("");

  // Топ актёры
  const actorsHTML = actors.slice(0, 8).map(a => {
    const img = a.profile_path
      ? `<img class="mono-actor-photo" src="https://image.tmdb.org/t/p/w185${a.profile_path}" loading="lazy" />`
      : `<div class="mono-actor-nophoto"></div>`;
    return `
      <div class="mono-actor" data-actor-id="${a.id || ""}">
        ${img}
        <div class="mono-actor-info">
          <div class="mono-actor-name">${a.name}</div>
          <div class="mono-actor-meta">${a.movie_count || 0}🎬 · ${a.tv_count || 0}📺</div>
        </div>
      </div>`;
  }).join("");

  // Режиссёры
  const directorsHTML = s.top_directors.slice(0, 7).map((d, i) => `
    <div class="mono-director">
      <span class="mono-dir-rank">${String(i + 1).padStart(2, "0")}</span>
      <span class="mono-dir-name">${d.name}</span>
      <span class="mono-dir-cnt">${d.count} ${d.count === 1 ? "ФИЛЬМ" : d.count < 5 ? "ФИЛЬМА" : "ФИЛЬМОВ"}</span>
    </div>`).join("");

  // Топ фильмы
  const topRatedHTML = s.top_rated.slice(0, 10).map(m => `
    <div class="mono-top-item">
      <div class="mono-top-poster" ${m.poster ? `style="background-image:url('${TMDB_CARD}${m.poster}')"` : ""}>
        <span class="rt">★ ${m.rating}</span>
      </div>
    </div>`).join("");

  // ── HTML сборка ────────────────────────────────────────────────────────
  wrap.innerHTML = `
    <div class="mono-profile">

      <header class="mono-profile-head">
        <div class="mono-prof-name-block">
          <div class="mono-prof-eyebrow">PROFILE · INDEX Nº 47</div>
          <h1 class="mono-prof-name">${(user.display_name || "").toUpperCase()}</h1>
          <div class="mono-prof-handle">@${user.username || "user"} · ${totalWatched} ПРОСМОТРЕНО · ${s.rated_count} ОЦЕНОК</div>
        </div>
        <div class="mono-prof-bigstats">
          <div class="mono-prof-bigstat">
            <div class="mono-prof-bigstat-v red">${s.movies}</div>
            <div class="mono-prof-bigstat-l">фильмов</div>
          </div>
          <div class="mono-prof-bigstat">
            <div class="mono-prof-bigstat-v">${s.tv}</div>
            <div class="mono-prof-bigstat-l">сериалов</div>
          </div>
          <div class="mono-prof-bigstat">
            <div class="mono-prof-bigstat-v red">${s.avg_rating ?? "—"}</div>
            <div class="mono-prof-bigstat-l">средняя</div>
          </div>
          <div class="mono-prof-bigstat">
            <div class="mono-prof-bigstat-v">${s.rated_count}</div>
            <div class="mono-prof-bigstat-l">оценено</div>
          </div>
        </div>
      </header>

      <div class="mono-profile-body">

        <!-- LEFT COLUMN: оценки + жанры -->
        <div class="mono-prof-col left">

          ${s.rated_count ? `
          <div class="mono-prof-block">
            <div class="mono-prof-block-head">
              <span>РАСПРЕДЕЛЕНИЕ ОЦЕНОК</span>
              <span class="ed">${s.rated_count} оценок</span>
            </div>
            <div class="mono-avg-row">
              <div class="mono-avg-num">${s.avg_rating ?? "—"}</div>
              <div class="mono-avg-info">
                Средняя оценка по всем твоим фильмам и сериалам.<br/>
                <b>Топ-оценка: 10/10</b> у самых любимых, <b>1/10</b> у разочарований.
              </div>
            </div>
            <div class="mono-rating-chart">${ratingBarsHTML}</div>
            <div class="mono-rating-legend">
              <span><span class="dot movie"></span>ФИЛЬМЫ</span>
              <span><span class="dot tv"></span>СЕРИАЛЫ</span>
            </div>
          </div>` : ""}

          ${s.top_genres.length ? `
          <div class="mono-prof-block">
            <div class="mono-prof-block-head">
              <span>ЛЮБИМЫЕ ЖАНРЫ</span>
              <span class="ed">по частоте просмотров</span>
            </div>
            <div class="mono-genres">${genresHTML}</div>
          </div>` : ""}

        </div>

        <!-- RIGHT COLUMN: donut + актёры + режиссёры + топ -->
        <div class="mono-prof-col right">

          <div class="mono-prof-block">
            <div class="mono-prof-block-head">
              <span>СООТНОШЕНИЕ ТИПА</span>
              <span class="ed">movie · tv</span>
            </div>
            <div class="mono-donut-row">
              <div class="mono-donut">
                <svg viewBox="0 0 140 140">
                  <circle cx="70" cy="70" r="${R}" fill="none" stroke="var(--mono-paper-3)" stroke-width="22"/>
                  <circle cx="70" cy="70" r="${R}" fill="none" stroke="var(--mono-red)" stroke-width="22"
                    stroke-dasharray="${movieLen} ${C}" stroke-dashoffset="0" />
                  <circle cx="70" cy="70" r="${R}" fill="none" stroke="var(--mono-ink)" stroke-width="22"
                    stroke-dasharray="${tvLen} ${C}" stroke-dashoffset="${-movieLen}" />
                </svg>
                <div class="mono-donut-center">
                  <div class="mono-donut-pct">${totalWatched}</div>
                  <div class="mono-donut-lbl">всего</div>
                </div>
              </div>
              <div class="mono-donut-legend">
                <div class="mono-donut-li">
                  <span class="mono-donut-li-name"><span class="sq" style="background:var(--mono-red)"></span>ФИЛЬМЫ</span>
                  <span class="mono-donut-li-val">${s.movies} · ${moviePct}%</span>
                </div>
                <div class="mono-donut-li">
                  <span class="mono-donut-li-name"><span class="sq" style="background:var(--mono-ink)"></span>СЕРИАЛЫ</span>
                  <span class="mono-donut-li-val">${s.tv} · ${tvPct}%</span>
                </div>
              </div>
            </div>
          </div>

          ${actors.length ? `
          <div class="mono-prof-block">
            <div class="mono-prof-block-head">
              <span>ЧАСТО ВСТРЕЧАЕМЫЕ АКТЁРЫ</span>
              <span class="ed">в твоей библиотеке</span>
            </div>
            <div class="mono-actors">${actorsHTML}</div>
          </div>` : ""}

          ${s.top_directors.length ? `
          <div class="mono-prof-block">
            <div class="mono-prof-block-head">
              <span>РЕЖИССЁРЫ</span>
              <span class="ed">кого ты любишь</span>
            </div>
            <div class="mono-directors">${directorsHTML}</div>
          </div>` : ""}

          ${s.top_rated.length ? `
          <div class="mono-prof-block">
            <div class="mono-prof-block-head">
              <span>ВЫСШИЕ ОЦЕНКИ</span>
              <span class="ed">твоя личная коллекция</span>
            </div>
            <div class="mono-top-strip">${topRatedHTML}</div>
          </div>` : ""}

        </div>

        <!-- AI блок: на всю ширину под колонками -->
        <div class="mono-ai-block">
          <div class="mono-prof-block-head">
            <span>✦ AI · АНАЛИЗ ВКУСА</span>
            <span class="ed">Cerebras Llama · по твоей истории</span>
          </div>
          <button class="mono-ai-btn" id="claude-analyze-btn" onclick="analyzeWithClaude()">
            ПРОАНАЛИЗИРОВАТЬ МОЙ ВКУС →
          </button>
          <div class="mono-ai-result" id="claude-result" style="display:none"></div>
        </div>

      </div>
    </div>
  `;

  // ── Биндинги: клики по актёрам ───────────────────────────────────────
  wrap.querySelectorAll(".mono-actor[data-actor-id]").forEach(el => {
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
    const posterUrl = movie.poster_path ? `${TMDB_CARD}${movie.poster_path}` : null;

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
        const dismissedType = movie.media_type || state.dismissedMode;
        await apiFetch(`/dismissed/${movie.movie_id}?media_type=${dismissedType}`, { method: "DELETE" });
        state.cache.dismissed[dismissedType] = null;  // инвалидируем кэш
        animateRemove(card, () => loadDismissed());
        const word = dismissedType === "tv" ? "Сериал" : "Фильм";
        toast(`${word} возвращён в рекомендации`, "success");
      } catch { toast("Ошибка", "error"); }
    });

    grid.appendChild(card);
  });
}

// ─── Книги ─────────────────────────────────────────────────────────────────

async function loadBooksDiscover() {
  const grid = $("books-popular-grid");
  const query = $("books-search-input")?.value?.trim();
  if (query) {
    await searchBooks(query);
  } else {
    await loadBooksPopular();
  }
}

function initBooksSuggest() {
  // Nothing to load initially, just show the form
}

async function loadBooksSuggest() {
  const query = $("books-suggest-input")?.value?.trim() || "";
  const grid = $("books-suggest-grid");
  grid.innerHTML = `<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ДУМАЕМ…</div></div>`;
  try {
    const result = await apiFetch(`/books/suggest?query=${encodeURIComponent(query)}`);
    if (!result?.books?.length) {
      grid.innerHTML = `<div class="empty-state"><span class="empty-icon">📚</span><p>Не удалось подобрать — попробуй уточнить запрос</p></div>`;
      return;
    }
    renderBookCards(grid, result.books);
  } catch(err) {
    grid.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>${err?.detail || "Ошибка загрузки"}</p></div>`;
  }
}

async function loadBooksProfile() {
  const content = $("books-profile-content");
  try {
    const [readBooks, wishlistBooks] = await Promise.all([
      apiFetch("/books/read"),
      apiFetch("/books/wishlist"),
    ]);
    const rated = readBooks.filter(b => b.user_rating);
    const avgRating = rated.length ? (rated.reduce((s, b) => s + b.user_rating, 0) / rated.length).toFixed(1) : null;
    const thisYear = new Date().getFullYear();
    const readThisYear = readBooks.filter(b => (b.added_at || "").startsWith(thisYear)).length;

    // Genre stats
    const genreCounts = {};
    readBooks.forEach(b => {
      (b.genres || []).forEach(g => { genreCounts[g] = (genreCounts[g] || 0) + 1; });
    });
    const topGenres = Object.entries(genreCounts).sort((a,b) => b[1]-a[1]).slice(0,5);

    // Author stats
    const authorCounts = {};
    readBooks.forEach(b => {
      if (b.author) authorCounts[b.author] = (authorCounts[b.author] || 0) + 1;
    });
    const topAuthors = Object.entries(authorCounts).sort((a,b) => b[1]-a[1]).slice(0,5);

    const topRated = [...readBooks].filter(b => b.user_rating).sort((a,b) => b.user_rating - a.user_rating).slice(0,4);

    content.innerHTML = `
      <div class="profile-grid">
        <div class="profile-card">
          <div class="profile-card-title">Статистика</div>
          <div class="profile-stats-row">
            <div class="profile-stat"><div class="stat-num">${readBooks.length}</div><div class="stat-label">Прочитано</div></div>
            <div class="profile-stat"><div class="stat-num">${wishlistBooks.length}</div><div class="stat-label">Хочу прочитать</div></div>
            <div class="profile-stat"><div class="stat-num">${readThisYear}</div><div class="stat-label">В ${thisYear} году</div></div>
            ${avgRating ? `<div class="profile-stat"><div class="stat-num">${avgRating}</div><div class="stat-label">Средняя оценка</div></div>` : ""}
          </div>
        </div>
        ${topGenres.length ? `
        <div class="profile-card">
          <div class="profile-card-title">Любимые жанры</div>
          <div class="top-genres-list">
            ${topGenres.map(([g, c]) => `<div class="genre-bar-row"><span class="genre-bar-label">${g}</span><span class="genre-bar-count">${c}</span></div>`).join("")}
          </div>
        </div>` : ""}
        ${topAuthors.length ? `
        <div class="profile-card">
          <div class="profile-card-title">Любимые авторы</div>
          <div class="top-genres-list">
            ${topAuthors.map(([a, c]) => `<div class="genre-bar-row"><span class="genre-bar-label">${a}</span><span class="genre-bar-count">${c}</span></div>`).join("")}
          </div>
        </div>` : ""}
        ${topRated.length ? `
        <div class="profile-card">
          <div class="profile-card-title">Лучшие книги</div>
          <div class="top-rated-list">
            ${topRated.map(b => `
              <div class="top-rated-item">
                ${b.cover ? `<img class="top-rated-poster" src="${b.cover}" />` : `<div class="top-rated-no-poster">📖</div>`}
                <div class="top-rated-info">
                  <div class="top-rated-title">${b.title}</div>
                  <div class="top-rated-rating">${b.user_rating}/10</div>
                </div>
              </div>`).join("")}
          </div>
        </div>` : ""}
      </div>
    `;
  } catch {
    content.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

async function loadBooksPopular() {
  if (state.cache.booksPopular) {
    renderBookCards($("books-popular-grid"), state.cache.booksPopular);
    return;
  }
  $("books-popular-grid").innerHTML = `<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ КНИГИ</div></div>`;
  try {
    const books = await apiFetch("/books/popular");
    state.cache.booksPopular = books;
    renderBookCards($("books-popular-grid"), books);
  } catch {
    $("books-popular-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

async function searchBooks(q) {
  if (!q.trim()) { loadBooksPopular(); return; }
  $("books-popular-grid").innerHTML = `<div class="loader">Ищем «${q}»…</div>`;
  try {
    const books = await apiFetch(`/books/search?q=${encodeURIComponent(q)}`);
    renderBookCards($("books-popular-grid"), books);
  } catch {
    $("books-popular-grid").innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ничего не найдено</p></div>`;
  }
}

function renderBookCards(container, books) {
  container.innerHTML = "";
  if (!books?.length) {
    container.innerHTML = `<div class="empty-state"><span class="empty-icon">📚</span><p>Ничего не найдено</p></div>`;
    return;
  }
  books.forEach((book, index) => {
    const card = document.createElement("div");
    card.className = "movie-card book-card";
    card.style.animationDelay = `${Math.min(index, 20) * 40}ms`;
    const year = (book.published_date || book.publishedDate || "").slice(0, 4) || "—";
    const isRead     = state.booksRead.has(book.id) || book.is_read;
    const isWishlist = state.booksWishlist.has(book.id) || book.is_wishlist;
    const userRating = book.user_rating;
    const googleRating = book.rating ? `⭐ ${Number(book.rating).toFixed(1)}` : "";

    card.innerHTML = `
      ${userRating ? `<div class="user-rating-badge">${userRating}</div>` : ""}
      ${book.cover
        ? `<img class="movie-poster" src="${book.cover}" alt="${book.title}" loading="lazy" />`
        : `<div class="no-poster"><span class="no-poster-icon">📖</span>${book.title}</div>`}
      <button class="watched-btn book-read-btn ${isRead ? "is-watched" : ""}" title="${isRead ? "Убрать из прочитанного" : "Отметить прочитанной"}">✓</button>
      <button class="watch-btn book-wish-btn ${isWishlist ? "is-watch" : ""}" title="${isWishlist ? "Убрать из списка" : "Хочу прочитать"}">🔖</button>
      <div class="movie-info">
        <div class="movie-title">${book.title}</div>
        <div class="movie-meta">
          <span class="book-author">${book.author || "—"}</span>
          <span class="movie-year">${year}</span>
        </div>
        ${googleRating ? `<div class="book-grating">${googleRating} <span class="imdb-votes">${book.ratings_count ? `· ${(book.ratings_count/1000).toFixed(0)}K` : ""}</span></div>` : ""}
      </div>
    `;

    card.addEventListener("click", e => {
      if (e.target.closest(".book-read-btn,.book-wish-btn")) return;
      openBookModal(book);
    });

    card.querySelector(".book-read-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleBookRead(book.id, card.querySelector(".book-read-btn"), book, card);
    });
    card.querySelector(".book-wish-btn").addEventListener("click", e => {
      e.stopPropagation();
      toggleBookWishlist(book.id, card.querySelector(".book-wish-btn"), book);
    });

    container.appendChild(card);
  });
}

async function toggleBookRead(bookId, btn, book, card) {
  const isRead = state.booksRead.has(bookId);
  if (isRead) {
    state.booksRead.delete(bookId);
    btn.classList.remove("is-watched");
    state.cache.booksReadData = null;
    updateBooksCount();
    try { await apiFetch(`/books/read/${bookId}`, { method: "DELETE" }); }
    catch { state.booksRead.add(bookId); btn.classList.add("is-watched"); }
  } else {
    state.booksRead.add(bookId);
    btn.classList.add("is-watched");
    state.cache.booksReadData = null;
    updateBooksCount();
    try {
      await apiFetch("/books/read", { method: "POST", body: JSON.stringify({ book_id: bookId }) });
      toast(`«${book.title}» прочитана`, "success");
    } catch(err) {
      if (err?.detail && err.detail.includes("Уже")) return;
      state.booksRead.delete(bookId); btn.classList.remove("is-watched"); updateBooksCount();
    }
  }
}

async function toggleBookWishlist(bookId, btn, book) {
  const isWish = state.booksWishlist.has(bookId);
  if (isWish) {
    state.booksWishlist.delete(bookId);
    btn.classList.remove("is-watch");
    state.cache.booksWishlistData = null;
    try { await apiFetch(`/books/wishlist/${bookId}`, { method: "DELETE" }); }
    catch { state.booksWishlist.add(bookId); btn.classList.add("is-watch"); }
  } else {
    state.booksWishlist.add(bookId);
    btn.classList.add("is-watch");
    state.cache.booksWishlistData = null;
    try {
      await apiFetch("/books/wishlist", { method: "POST", body: JSON.stringify({ book_id: bookId }) });
      toast(`«${book.title}» добавлена в список`, "success");
    } catch(err) {
      if (err?.detail && err.detail.includes("Уже")) return;
      state.booksWishlist.delete(bookId); btn.classList.remove("is-watch");
    }
  }
}

function updateBooksCount() {
  const el  = $("books-read-count");
  if (el)  el.textContent  = state.booksRead.size;
  const we = $("books-wishlist-count");
  if (we)  we.textContent  = state.booksWishlist.size;
}

async function loadBooksReadView() {
  const grid = $("books-read-grid");
  if (state.cache.booksReadData) { renderBookCards(grid, state.cache.booksReadData); return; }
  grid.innerHTML = `<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ</div></div>`;
  try {
    const books = await apiFetch("/books/read");
    state.cache.booksReadData = books;
    state.booksRead = new Set(books.map(b => b.book_id));
    updateBooksCount();
    if (!books.length) {
      grid.innerHTML = `<div class="empty-state"><span class="empty-icon">📖</span><p>Ещё не добавил прочитанных книг</p></div>`;
      return;
    }
    renderBookCards(grid, books.map(b => ({ ...b, id: b.book_id })));
  } catch {
    grid.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

async function loadBooksWishlistView() {
  const grid = $("books-wishlist-grid");
  if (state.cache.booksWishlistData) { renderBookCards(grid, state.cache.booksWishlistData); return; }
  grid.innerHTML = `<div class="fun-loader"><div class="fun-piano"><div class="fun-monkey">🐵</div><div class="fun-shadow"></div><div class="fun-dots"><span></span><span></span><span></span></div></div><div class="fun-text">ЗАГРУЖАЕМ</div></div>`;
  try {
    const books = await apiFetch("/books/wishlist");
    state.cache.booksWishlistData = books;
    state.booksWishlist = new Set(books.map(b => b.book_id));
    updateBooksCount();
    if (!books.length) {
      grid.innerHTML = `<div class="empty-state"><span class="empty-icon">📚</span><p>Список пуст</p></div>`;
      return;
    }
    renderBookCards(grid, books.map(b => ({ ...b, id: b.book_id })));
  } catch {
    grid.innerHTML = `<div class="empty-state"><span class="empty-icon">⚠</span><p>Ошибка загрузки</p></div>`;
  }
}

async function openBookModal(book) {
  $("modal-overlay").classList.add("open");
  document.body.style.overflow = "hidden";
  $("similar-section").style.display = "none";
  $("modal-content").innerHTML = `<div style="height:400px;display:flex;align-items:center;justify-content:center;color:var(--text-dim)">Загружаем…</div>`;
  try {
    const details = await apiFetch(`/books/${book.id}/details`);
    renderBookModalContent(details);
    apiFetch(`/books/${book.id}/similar`).then(similar => {
      if (!similar?.length) return;
      $("similar-section").style.display = "";
      $("similar-section").querySelector(".similar-title").textContent = "Похожие книги";
      const sg = $("similar-grid");
      sg.innerHTML = "";
      similar.slice(0, 8).forEach(b => {
        const div = document.createElement("div");
        div.className = "similar-card";
        div.innerHTML = `
          ${b.cover ? `<img class="similar-poster" src="${b.cover}" loading="lazy"/>` : `<div class="similar-no-poster">📖</div>`}
          <div class="similar-title-text">${b.title}</div>
          <div class="similar-year">${b.author || ""}</div>`;
        div.addEventListener("click", () => openBookModal(b));
        sg.appendChild(div);
      });
    }).catch(() => {});
  } catch {
    renderBookModalContent(book);
  }
}

function renderBookModalContent(book) {
  const year = (book.published_date || "").slice(0, 4) || "—";
  const isRead     = state.booksRead.has(book.id) || book.is_read;
  const isWishlist = state.booksWishlist.has(book.id) || book.is_wishlist;
  const googleRating = book.rating ? `⭐ ${Number(book.rating).toFixed(1)} / 5` : "";
  const genres = (book.genres || []).slice(0, 4).join(", ");

  $("modal-content").innerHTML = `
    <div class="modal-body">
      <div class="modal-poster-col">
        ${book.cover
          ? `<img class="modal-poster" src="${book.cover.replace('zoom=2','zoom=3')}" alt="${book.title}" />`
          : `<div class="modal-no-poster">📖</div>`}
      </div>
      <div class="modal-info-col">
        <h2 class="modal-title">${book.title}</h2>
        ${book.author ? `<button class="modal-director book-author-link" data-author="${book.author.replace(/"/g,'&quot;')}">✍️ ${book.author}</button>` : ""}
        <div class="modal-meta-row">
          ${year !== "—" ? `<span class="modal-year">${year}</span>` : ""}
          ${book.page_count ? `<span class="modal-runtime">${book.page_count} стр.</span>` : ""}
          ${book.publisher ? `<span class="modal-country">${book.publisher}</span>` : ""}
        </div>
        ${googleRating ? `<div class="modal-ratings-row"><span class="imdb-badge">Google Books</span><span class="imdb-rating">${googleRating}</span>${book.ratings_count ? `<span class="imdb-votes">${(book.ratings_count/1000).toFixed(1)}K оценок</span>` : ""}</div>` : ""}
        ${genres ? `<div class="modal-genres">${genres.split(", ").map(g => `<span class="genre-tag">${g}</span>`).join("")}</div>` : ""}
        ${book.description ? `<p class="modal-overview">${book.description.slice(0, 600)}${book.description.length > 600 ? "…" : ""}</p>` : ""}
        <div class="modal-actions" style="margin-top:16px;display:flex;gap:8px;flex-wrap:wrap;">
          <button class="modal-book-read-btn ${isRead ? "is-watched active-btn" : ""}" data-id="${book.id}">
            ${isRead ? "✓ Прочитана" : "✓ Прочитал"}
          </button>
          <button class="modal-book-wish-btn ${isWishlist ? "is-watch active-btn" : ""}" data-id="${book.id}">
            ${isWishlist ? "🔖 В списке" : "🔖 Хочу прочитать"}
          </button>
        </div>
        ${isRead ? renderBookRatingHTML(book) : ""}
      </div>
    </div>
  `;

  $("modal-content").querySelector(".modal-book-read-btn").addEventListener("click", async function() {
    const wasRead = state.booksRead.has(book.id) || book.is_read;
    await toggleBookRead(book.id, { classList: { add: () => {}, remove: () => {}, contains: () => wasRead } }, book, null);
    openBookModal({ ...book, is_read: !wasRead });
  });
  $("modal-content").querySelector(".modal-book-wish-btn").addEventListener("click", async function() {
    const wasWish = state.booksWishlist.has(book.id) || book.is_wishlist;
    await toggleBookWishlist(book.id, { classList: { add: () => {}, remove: () => {}, contains: () => wasWish } }, book);
    openBookModal({ ...book, is_wishlist: !wasWish });
  });

  const authorLink = $("modal-content").querySelector(".book-author-link");
  if (authorLink) {
    authorLink.addEventListener("click", () => {
      closeModal();
      openBooksTab("discover");
      const inp = $("books-search-input");
      if (inp) { inp.value = book.author; searchBooks(book.author); }
    });
  }

  $("modal-content").querySelectorAll(".rating-btn").forEach(btn => {
    btn.addEventListener("click", async () => {
      const rating = parseInt(btn.dataset.r);
      try {
        await apiFetch("/books/read/rate", { method: "POST", body: JSON.stringify({ book_id: book.id, rating }) });
        state.cache.booksReadData = null;
        openBookModal({ ...book, is_read: true, user_rating: rating });
        toast("Оценка сохранена", "success");
      } catch {}
    });
  });
}

function renderBookRatingHTML(book) {
  const cur = book.user_rating;
  const btns = Array.from({length: 10}, (_, i) => i + 1).map(r =>
    `<button class="rating-btn ${cur === r ? "active" : ""}" data-r="${r}">${r}</button>`
  ).join("");
  return `<div class="rating-row" style="margin-top:12px"><span class="rating-label">Твоя оценка:</span><div class="rating-btns">${btns}</div></div>`;
}