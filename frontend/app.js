// Локально → http://127.0.0.1:8000, на проде (Render) → тот же домен (относительные URL)
const API = typeof API_BASE_URL !== "undefined"
  ? API_BASE_URL
  : (location.hostname === "127.0.0.1" || location.hostname === "localhost")
    ? "http://127.0.0.1:8000"
    : "";
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
  appMode:       "cinema",   // "cinema" | "books" | "notebook"
  activeBooksTab: "discover",
  activeNotebookTab: "today",
  notebookDate: new Date().toISOString().slice(0, 10),
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

  $("cinema-nav").style.display   = mode === "cinema"   ? "" : "none";
  $("books-nav").style.display    = mode === "books"    ? "" : "none";
  document.querySelectorAll(".mode-btn").forEach(b => b.classList.toggle("active", b.dataset.mode === mode));

  // Hide all tabs
  document.querySelectorAll(".tab").forEach(t => {
    t.classList.remove("active");
    t.style.display = "none";
  });

  if (mode === "cinema") {
    const cinemaTab = $("tab-discover");
    cinemaTab.classList.add("active");
    cinemaTab.style.display = "";
    $("search-input").placeholder = "Найти фильм, сериал…";
    $("home-content").style.display = "";
    $("search-content").style.display = "none";
  } else if (mode === "books") {
    $("search-input").placeholder = "Найти книгу, автора…";
    openBooksTab(state.activeBooksTab || "discover");
  } else if (mode === "notebook") {
    const nb = $("tab-notebook");
    nb.classList.add("active");
    nb.style.display = "";
    openNotebookTab(state.activeNotebookTab || "today");
  } else if (mode === "games") {
    const gTab = $("tab-games");
    gTab.classList.add("active");
    gTab.style.display = "";
    initGamesMode();
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
  const password = $("auth-password-input")?.value || "";
  const errEl    = $("auth-login-error");
  const btn      = document.querySelector("#auth-login-form .auth-btn");
  errEl.textContent = "";
  if (!username) { errEl.textContent = "Введи логин"; return; }

  btn.disabled = true;
  btn.textContent = "Подключаемся…";
  errEl.textContent = "⏳ Сервер просыпается, подожди до 60 сек…";

  try {
    const resp = await authFetch("/auth/login", { username, password });
    if (!resp.ok) {
      const e = await resp.json().catch(() => ({}));
      errEl.textContent = e.detail || "Пользователь не найден";
      return;
    }
    const user = await resp.json();
    setUser(user);
    $("auth-overlay").classList.remove("visible");
    toast(`Привет, ${user.display_name}! 👋`, "success");
    init().then(() => { if (state.appMode === "books" || state.appMode === "notebook") setTimeout(() => switchAppMode(state.appMode), 100); });
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
  const password = $("auth-reg-password")?.value || "";
  const errEl    = $("auth-reg-error");
  const btn      = document.querySelector("#auth-register-form .auth-btn");
  errEl.textContent = "";
  if (!username) { errEl.textContent = "Введи логин"; return; }
  if (!display)  { errEl.textContent = "Введи своё имя"; return; }
  if (!password || password.length < 4) { errEl.textContent = "Пароль должен быть не короче 4 символов"; return; }

  btn.disabled = true;
  btn.textContent = "Подключаемся…";
  errEl.textContent = "⏳ Сервер просыпается, подожди до 60 сек…";

  try {
    const resp = await authFetch("/auth/register", { username, display_name: display, password });
    if (!resp.ok) {
      const e = await resp.json().catch(() => ({}));
      errEl.textContent = e.detail || "Ошибка регистрации";
      return;
    }
    const user = await resp.json();
    setUser(user);
    $("auth-overlay").classList.remove("visible");
    toast(`Добро пожаловать, ${user.display_name}! 🎬`, "success");
    init().then(() => { if (state.appMode === "books" || state.appMode === "notebook") setTimeout(() => switchAppMode(state.appMode), 100); });
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
  // Восстанавливаем сохранённый режим (кино/книги/тетрадь/игры)
  const savedMode = localStorage.getItem("appMode") || "cinema";
  if (["books", "notebook", "games"].includes(savedMode)) {
    state.appMode = savedMode;
  }

  const saved = localStorage.getItem("film_user");
  if (saved) {
    try {
      const user = JSON.parse(saved);
      setUser(user);
      init().then(() => {
        if (["books", "notebook", "games"].includes(state.appMode)) {
          setTimeout(() => switchAppMode(state.appMode), 100);
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
      if (inp) { inp.value = book.author; searchBooks(`inauthor:"${book.author}"`); }
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


// ════════════════════════════════════════════════════════════════
//  ТЕТРАДЬ
// ════════════════════════════════════════════════════════════════

function openNotebookTab(tab) {
  state.activeNotebookTab = tab;
  document.querySelectorAll(".ntab-panel").forEach(p => p.style.display = "none");
  document.querySelectorAll(".spine-tab").forEach(b => b.classList.toggle("active", b.dataset.ntab === tab));
  const panel = $(`ntab-${tab}`);
  if (panel) panel.style.display = "";
  if (tab === "today") loadNotebookToday();
}

async function loadNotebookToday() {
  const today   = state.notebookDate;
  const dateObj = new Date(today + "T00:00:00");
  const realToday = new Date().toISOString().slice(0, 10);

  // ── Day-bar ───────────────────────────────────────────────────────
  const jan1     = new Date(dateObj.getFullYear(), 0, 1);
  const dayOfYear = Math.round((dateObj - jan1) / 86400000) + 1;
  const isLeap   = y => (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  const totalDays = isLeap(dateObj.getFullYear()) ? 366 : 365;
  const tmpD = new Date(Date.UTC(dateObj.getFullYear(), dateObj.getMonth(), dateObj.getDate()));
  const dow  = tmpD.getUTCDay() || 7;
  tmpD.setUTCDate(tmpD.getUTCDate() + 4 - dow);
  const ys   = new Date(Date.UTC(tmpD.getUTCFullYear(), 0, 1));
  const weekNum = Math.ceil((((tmpD - ys) / 86400000) + 1) / 7);

  const DAY_FULL  = ["воскресенье","понедельник","вторник","среда","четверг","пятница","суббота"];
  const MONTHS_GEN = ["января","февраля","марта","апреля","мая","июня","июля","августа","сентября","октября","ноября","декабря"];

  const lb = $("nb-daybar-left");
  const cb = $("nb-daybar-center");
  const rb = $("nb-daybar-right");
  if (lb) lb.textContent = `ДЕНЬ ${dayOfYear} ИЗ ${totalDays}`;
  if (cb) cb.textContent = `${DAY_FULL[dateObj.getDay()]}, ${dateObj.getDate()} ${MONTHS_GEN[dateObj.getMonth()]}`;
  if (rb) rb.textContent = `НЕДЕЛЯ ${weekNum}`;

  // ── Title (меняется если не сегодня) ─────────────────────────────
  const titleEl = $("nb-title-today");
  if (titleEl) {
    if (today === realToday) {
      titleEl.textContent = "Сегодня";
    } else {
      const mo = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];
      titleEl.textContent = `${dateObj.getDate()} ${mo[dateObj.getMonth()]}`;
    }
  }

  const listEl = $("task-list-today");
  if (!listEl) return;
  listEl.innerHTML = `<div class="nb-loading">загружаем…</div>`;

  // ── Yesterday ─────────────────────────────────────────────────────
  const ydObj = new Date(dateObj);
  ydObj.setDate(ydObj.getDate() - 1);
  const ydStr = ydObj.toISOString().slice(0, 10);

  try {
    const [tasks, weekTasks, ydTasks] = await Promise.all([
      apiFetch(`/tasks?date=${today}`),
      loadWeekTasks(today),
      apiFetch(`/tasks?date=${ydStr}`).catch(() => []),
    ]);
    renderTodayTasks(tasks);
    renderWeekGrid(weekTasks, today);
    renderYesterday(ydTasks);
    initAddTaskBtn();
  } catch {
    listEl.innerHTML = `<div style="color:var(--nb-red);font-size:13px;padding:8px 0">Ошибка загрузки</div>`;
  }
}

function renderYesterday(tasks) {
  const listEl   = $("task-list-yesterday");
  const badgesEl = $("nb-yesterday-badges");
  if (!listEl) return;

  const isDoneTask = t => t.recurrence
    ? (t.done_today === true || t.done_today === "true")
    : t.status === "done";
  const isCancelTask = t => !t.recurrence && t.status === "cancel";

  const done   = tasks.filter(isDoneTask).length;
  const cancel = tasks.filter(isCancelTask).length;
  const total  = tasks.length;

  if (badgesEl) {
    badgesEl.innerHTML = total
      ? `<span class="nb-yday-badge nb-yday-done">${done}/${total} сделано</span>${cancel ? `<span class="nb-yday-badge nb-yday-cancel">${cancel} отменено</span>` : ""}`
      : "";
  }

  listEl.innerHTML = "";
  tasks.slice(0, 6).forEach(t => {
    const done   = isDoneTask(t);
    const cancel = isCancelTask(t);
    const div = document.createElement("div");
    div.className = `task-item-sm ${done ? "st-done" : cancel ? "st-cancel" : "st-todo"}`;
    div.innerHTML = `
      <span class="task-sm-cb">${done ? "✓" : cancel ? "✗" : ""}</span>
      <div class="task-sm-body">
        <span class="task-sm-title">${t.title}</span>
        ${t.time_str ? `<span class="task-sm-time">${t.time_str}</span>` : ""}
        ${t.tag      ? `<span class="task-sm-tag">#${t.tag}</span>`     : ""}
        ${cancel && t.cancel_reason ? `<div class="task-sm-reason">причина: ${t.cancel_reason}</div>` : ""}
      </div>`;
    listEl.appendChild(div);
  });

  if (!tasks.length) {
    listEl.innerHTML = `<div class="nb-empty-hint">вчера не было задач</div>`;
  }
}

function renderTodayTasks(tasks) {
  const listEl = $("task-list-today");
  listEl.innerHTML = "";
  tasks.forEach(t => listEl.appendChild(buildTaskEl(t)));
  updateTodayMeta(tasks);
}

function updateTodayMeta(tasks) {
  const done   = tasks.filter(t => t.recurrence ? (t.done_today === true || t.done_today === "true") : t.status === "done").length;
  const cancel = tasks.filter(t => !t.recurrence && t.status === "cancel").length;
  const total  = tasks.length;
  const pct    = total > 0 ? Math.round((done / total) * 100) : 0;

  const metaEl  = $("nb-today-meta");
  const countEl = $("nb-task-count");

  if (metaEl) metaEl.textContent = total
    ? `◐ ${pct}% выполнено${cancel ? ` · ${cancel} отменена` : ""}`
    : "◐ нет задач на сегодня";

  if (countEl) countEl.textContent = total > 0
    ? `${total} задач, ${done}✓${cancel ? `, ${cancel}✗` : ""}`
    : "";
}

function formatRecurrence(r) {
  if (!r || r === "daily") return "каждый день";
  if (r.startsWith("weekly:")) {
    const names = ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"];
    return r.split(":")[1].split(",").map(d => names[+d] || d).join(", ");
  }
  return r;
}

function buildTaskEl(task) {
  const isRecurring  = !!task.recurrence;
  const isDoneToday  = task.done_today === true || task.done_today === "true";
  const effectiveStatus = isRecurring ? (isDoneToday ? "done" : "todo") : task.status;

  const div = document.createElement("div");
  div.className = `task-item status-${effectiveStatus}`;
  div.dataset.id = task.id;

  const cancelBlock = (!isRecurring && task.status === "cancel")
    ? `<div class="task-cancel-block">
         <span class="cancel-label">ПРИЧИНА:</span>
         ${task.cancel_reason
           ? `<span class="cancel-reason-text">${task.cancel_reason}</span>`
           : `<input class="cancel-input" placeholder="почему отменил…" />`}
       </div>`
    : "";

  const recurBadge = isRecurring
    ? `<span class="task-recur-badge">🔄 ${formatRecurrence(task.recurrence)}</span>`
    : "";

  div.innerHTML = `
    <button class="task-cb" title="Изменить статус"></button>
    <div class="task-body">
      <div class="task-title">${task.title}</div>
      <div class="task-meta">
        ${task.time_str ? `<span class="task-time">${task.time_str}</span>` : ""}
        ${task.tag ? `<span class="task-tag">#${task.tag}</span>` : ""}
        ${recurBadge}
      </div>
      ${cancelBlock}
    </div>
    <button class="task-delete-btn" title="Удалить">×</button>`;

  div.querySelector(".task-cb").addEventListener("click", () => {
    if (isRecurring) toggleRecurringTask(task, div, isDoneToday);
    else cycleTaskStatus(task, div);
  });

  // Двойной клик по названию → инлайн-редактирование
  div.querySelector(".task-title").addEventListener("dblclick", () => {
    const titleEl = div.querySelector(".task-title");
    const oldVal  = task.title;
    const inp = document.createElement("input");
    inp.className = "task-edit-input";
    inp.value = oldVal;
    titleEl.replaceWith(inp);
    inp.focus(); inp.select();
    const save = async () => {
      const newTitle = inp.value.trim() || oldVal;
      const span = document.createElement("span");
      span.className = "task-title";
      span.textContent = newTitle;
      inp.replaceWith(span);
      span.addEventListener("dblclick", arguments.callee); // re-bind (handled by rebuild)
      if (newTitle !== oldVal) {
        try {
          await apiFetch(`/tasks/${task.id}`, { method: "PATCH", body: JSON.stringify({ title: newTitle }) });
          task.title = newTitle;
          // Перестроим элемент чтобы dblclick снова работал
          const newEl = buildTaskEl(task);
          div.replaceWith(newEl);
          syncMetaFromDOM();
        } catch { span.textContent = oldVal; }
      }
    };
    inp.addEventListener("blur", save);
    inp.addEventListener("keydown", e => {
      if (e.key === "Enter")  { e.preventDefault(); inp.blur(); }
      if (e.key === "Escape") { inp.value = oldVal; inp.blur(); }
    });
  });

  const cancelInput = div.querySelector(".cancel-input");
  if (cancelInput) bindCancelInput(cancelInput, task);

  div.querySelector(".task-delete-btn").addEventListener("click", async () => {
    div.style.opacity = "0.3";
    try {
      await apiFetch(`/tasks/${task.id}`, { method: "DELETE" });
      div.remove();
      syncMetaFromDOM();
    } catch { div.style.opacity = "1"; }
  });

  return div;
}

async function toggleRecurringTask(task, div, wasDone) {
  const date = state.notebookDate;
  try {
    if (wasDone) {
      await apiFetch(`/tasks/${task.id}/complete?date=${date}`, { method: "DELETE" });
      task.done_today = false;
      div.className = "task-item status-todo";
    } else {
      await apiFetch(`/tasks/${task.id}/complete?date=${date}`, { method: "POST" });
      task.done_today = true;
      div.className = "task-item status-done";
    }
    syncMetaFromDOM();
  } catch {}
}

function bindCancelInput(inp, task) {
  const save = async () => {
    const reason = inp.value.trim();
    if (!reason) return;
    try {
      await apiFetch(`/tasks/${task.id}`, { method: "PATCH", body: JSON.stringify({ cancel_reason: reason }) });
      task.cancel_reason = reason;
      const span = document.createElement("span");
      span.className = "cancel-reason-text";
      span.textContent = reason;
      inp.replaceWith(span);
    } catch {}
  };
  inp.addEventListener("blur", save);
  inp.addEventListener("keydown", e => { if (e.key === "Enter") inp.blur(); });
  setTimeout(() => inp.focus(), 60);
}

async function cycleTaskStatus(task, div) {
  const order = ["todo", "done", "cancel"];
  const next  = order[(order.indexOf(task.status) + 1) % 3];
  const prev  = task.status;

  task.status = next;
  div.className = `task-item status-${next}`;

  const body = div.querySelector(".task-body");
  if (next === "cancel") {
    if (!body.querySelector(".task-cancel-block")) {
      const block = document.createElement("div");
      block.className = "task-cancel-block";
      block.innerHTML = `<span class="cancel-label">ПРИЧИНА:</span><input class="cancel-input" placeholder="почему отменил…" />`;
      body.appendChild(block);
      bindCancelInput(block.querySelector(".cancel-input"), task);
    }
  } else {
    const cb = body.querySelector(".task-cancel-block");
    if (cb) cb.remove();
    task.cancel_reason = null;
  }

  try {
    await apiFetch(`/tasks/${task.id}`, {
      method: "PATCH",
      body: JSON.stringify({ status: next, ...(next !== "cancel" ? { cancel_reason: null } : {}) }),
    });
    syncMetaFromDOM();
  } catch {
    task.status = prev;
    div.className = `task-item status-${prev}`;
  }
}

function syncMetaFromDOM() {
  const items = Array.from(($("task-list-today") || { querySelectorAll: () => [] })
    .querySelectorAll(".task-item"))
    .map(el => ({
      status: el.className.includes("status-done") ? "done"
            : el.className.includes("status-cancel") ? "cancel" : "todo",
    }));
  updateTodayMeta(items);
}

async function loadWeekTasks(todayStr) {
  const d   = new Date(todayStr + "T00:00:00");
  const day = d.getDay();
  const mon = new Date(d);
  mon.setDate(d.getDate() - (day === 0 ? 6 : day - 1));
  const sun = new Date(mon);
  sun.setDate(mon.getDate() + 6);
  const fmt = dt => dt.toISOString().slice(0, 10);
  return apiFetch(`/tasks/week?date_from=${fmt(mon)}&date_to=${fmt(sun)}`);
}

function renderWeekGrid(tasks, todayStr) {
  const grid = $("nb-week-grid");
  if (!grid) return;
  const d   = new Date(todayStr + "T00:00:00");
  const day = d.getDay();
  const mon = new Date(d);
  mon.setDate(d.getDate() - (day === 0 ? 6 : day - 1));
  const DAY_SHORT = ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"];
  grid.innerHTML = "";

  for (let i = 0; i < 7; i++) {
    const dt  = new Date(mon); dt.setDate(mon.getDate() + i);
    const ds  = dt.toISOString().slice(0, 10);
    const isT = ds === todayStr;
    const dayTasks = tasks.filter(t => String(t.date).slice(0, 10) === ds).slice(0, 5);

    const col = document.createElement("div");
    col.className = `week-col${isT ? " week-col-today" : ""}`;
    col.innerHTML = `
      <div class="week-col-head">
        <div class="week-col-name">${DAY_SHORT[i]}</div>
        <div class="week-col-num">${dt.getDate()}</div>
      </div>
      <div class="week-col-tasks">
        ${dayTasks.length
          ? dayTasks.map(t => `<div class="week-col-task wct-${t.status || "todo"}">· ${t.title}</div>`).join("")
          : `<div class="week-col-empty">—</div>`}
      </div>`;
    grid.appendChild(col);
  }
}

function initAddTaskBtn() {
  const btn = $("task-add-btn");
  if (!btn || btn._nbInit) return;
  btn._nbInit = true;
  btn.addEventListener("click", () => {
    btn.style.display = "none";
    const DAY_NAMES = ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"];
    const form = document.createElement("div");
    form.className = "task-add-form";
    form.innerHTML = `
      <input class="task-add-input" placeholder="Новая задача…" />
      <div class="task-recur-opts" style="display:none">
        <button type="button" class="task-recur-btn active" data-recur="">Один раз</button>
        <button type="button" class="task-recur-btn" data-recur="daily">Каждый день</button>
        <button type="button" class="task-recur-btn" data-recur="weekly">По дням</button>
        <div class="task-recur-days" style="display:none">
          ${DAY_NAMES.map((n, i) => `<button type="button" class="task-day-btn" data-dow="${i}">${n}</button>`).join("")}
        </div>
      </div>`;
    btn.parentNode.insertBefore(form, btn.nextSibling);
    const inp      = form.querySelector(".task-add-input");
    const recurOpts = form.querySelector(".task-recur-opts");
    const recurBtns = form.querySelectorAll(".task-recur-btn");
    const daysDiv   = form.querySelector(".task-recur-days");
    const dayBtns   = form.querySelectorAll(".task-day-btn");
    inp.focus();

    let selectedRecur = "";
    const selectedDays = new Set();

    inp.addEventListener("input", () => {
      recurOpts.style.display = inp.value.trim() ? "" : "none";
    });
    recurBtns.forEach(b => b.addEventListener("click", () => {
      recurBtns.forEach(x => x.classList.remove("active"));
      b.classList.add("active");
      selectedRecur = b.dataset.recur;
      daysDiv.style.display = selectedRecur === "weekly" ? "" : "none";
    }));
    dayBtns.forEach(b => b.addEventListener("click", () => {
      const dow = b.dataset.dow;
      if (selectedDays.has(dow)) { selectedDays.delete(dow); b.classList.remove("active"); }
      else { selectedDays.add(dow); b.classList.add("active"); }
    }));

    const submit = async () => {
      const title = inp.value.trim();
      form.remove();
      btn.style.display = "";
      if (!title) return;
      let recurrence = null;
      if (selectedRecur === "daily") recurrence = "daily";
      else if (selectedRecur === "weekly" && selectedDays.size > 0)
        recurrence = `weekly:${[...selectedDays].sort().join(",")}`;
      try {
        const task = await apiFetch("/tasks", {
          method: "POST",
          body: JSON.stringify({ title, date: state.notebookDate, recurrence }),
        });
        $("task-list-today").appendChild(buildTaskEl(task));
        syncMetaFromDOM();
        toast(`Задача добавлена`, "success");
      } catch { toast("Ошибка при сохранении", "error"); }
    };

    inp.addEventListener("keydown", e => {
      if (e.key === "Enter") submit();  // Enter всегда сохраняет
      if (e.key === "Escape") { form.remove(); btn.style.display = ""; }
    });
  });
}

// — Spine tab clicks —
document.querySelectorAll(".spine-tab").forEach(btn => {
  btn.addEventListener("click", () => openNotebookTab(btn.dataset.ntab));
});

// — Кнопки удаления расходов бюджета (статические элементы, вешаем сразу) —
document.addEventListener("click", async e => {
  if (e.target.id === "budget-clear-month") {
    const { year, month } = budgetState;
    const MONTHS = ["","янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];
    if (!confirm(`Удалить все расходы за ${MONTHS[month]} ${year}?`)) return;
    try {
      const res = await apiFetch(`/budget/expenses/month?year=${year}&month=${month}`, { method: "DELETE" });
      loadBudget();
      _showBudgetToast(`🗑️ Удалено ${res.deleted} операций`);
    } catch (err) {
      _showBudgetToast("Ошибка: " + (err?.detail || err?.message || "сервер недоступен"));
    }
  }
  if (e.target.id === "budget-clear-all") {
    if (!confirm("Удалить ВСЕ расходы за всё время?\nЭто действие нельзя отменить.")) return;
    try {
      const res = await apiFetch("/budget/expenses/all", { method: "DELETE" });
      loadBudget();
      _showBudgetToast(`🗑️ Удалено ${res.deleted} операций`);
    } catch (err) {
      _showBudgetToast("Ошибка: " + (err?.detail || err?.message || "сервер недоступен"));
    }
  }
});

// ─── openNotebookTab: вызывает нужный загрузчик ──────────────────────────────
const _nbLoaders = {
  today:    () => loadNotebookToday(),
  calendar: () => loadCalendar(),
  budget:   () => loadBudget(),
  trips:    () => loadTrips(),
  lists:    () => loadLists(),
  notes:    () => loadNotes(),
};
// Переопределяем openNotebookTab чтобы вызывать лоадер
const _openNotebookTabBase = openNotebookTab;
openNotebookTab = function(tab) {
  state.activeNotebookTab = tab;
  document.querySelectorAll(".ntab-panel").forEach(p => p.style.display = "none");
  document.querySelectorAll(".spine-tab").forEach(b => b.classList.toggle("active", b.dataset.ntab === tab));
  const panel = $(`ntab-${tab}`);
  if (panel) panel.style.display = "";
  if (_nbLoaders[tab]) _nbLoaders[tab]();
};


// ════════════════════════════════════════════════════════════════
//  НЕДЕЛЯ — кликабельные дни
// ════════════════════════════════════════════════════════════════

function renderWeekGridClickable(tasks, todayStr) {
  const grid = $("nb-week-grid");
  if (!grid) return;
  const realToday = new Date().toISOString().slice(0, 10);
  const d   = new Date(todayStr + "T00:00:00");
  const day = d.getDay();
  const mon = new Date(d);
  mon.setDate(d.getDate() - (day === 0 ? 6 : day - 1));
  const dayNames = ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"];
  grid.innerHTML = "";
  for (let i = 0; i < 7; i++) {
    const dt  = new Date(mon);
    dt.setDate(mon.getDate() + i);
    const ds  = dt.toISOString().slice(0, 10);
    const isT = ds === realToday;
    const isSel = ds === state.notebookDate;
    const dayTasks = tasks.filter(t => String(t.date).slice(0,10) === ds).slice(0, 3);
    const row = document.createElement("div");
    row.className = `week-day-row${isSel ? " is-selected" : ""}`;
    row.dataset.date = ds;
    row.innerHTML = `
      <div class="week-day-num ${isT ? "is-today" : ""}">${dt.getDate()}</div>
      <div class="week-day-name">${dayNames[i]}</div>
      <div class="week-day-tasks">
        ${dayTasks.length
          ? dayTasks.map(t => `<div class="week-task-dot ${t.status}">${t.title}</div>`).join("")
          : `<div class="week-task-dot" style="opacity:.3">—</div>`}
      </div>`;
    row.addEventListener("click", () => switchNotebookDay(ds));
    grid.appendChild(row);
  }
}

async function switchNotebookDay(dateStr) {
  state.notebookDate = dateStr;
  const realToday = new Date().toISOString().slice(0, 10);
  const isToday = dateStr === realToday;

  // Обновляем заголовок
  const titleEl = document.querySelector(".nb-page-today .nb-title");
  if (titleEl) {
    if (isToday) {
      titleEl.textContent = "Сегодня";
    } else {
      const dt = new Date(dateStr + "T00:00:00");
      const months = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];
      titleEl.textContent = `${dt.getDate()} ${months[dt.getMonth()]}`;
    }
  }

  // Подсвечиваем выбранный день в гриде
  document.querySelectorAll(".week-day-row").forEach(r => {
    r.classList.toggle("is-selected", r.dataset.date === dateStr);
  });

  // Загружаем задачи
  const listEl = $("task-list-today");
  if (listEl) listEl.innerHTML = `<div style="padding:8px 0;font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3)">загружаем…</div>`;
  try {
    const tasks = await apiFetch(`/tasks?date=${dateStr}`);
    renderTodayTasks(tasks);
    // Обновляем subtitle
    const days   = ["воскресенье","понедельник","вторник","среда","четверг","пятница","суббота"];
    const months = ["января","февраля","марта","апреля","мая","июня","июля","августа","сентября","октября","ноября","декабря"];
    const dt = new Date(dateStr + "T00:00:00");
    const subtEl = $("nb-today-subtitle");
    if (subtEl) subtEl.textContent = `${days[dt.getDay()]}, ${dt.getDate()} ${months[dt.getMonth()]}`;
  } catch {}
  initAddTaskBtn();
}

// Патчим loadNotebookToday чтобы использовать clickable grid
const _loadNotebookTodayOrig = loadNotebookToday;
loadNotebookToday = async function() {
  const today = state.notebookDate;
  const dateObj = new Date(today + "T00:00:00");
  const days    = ["воскресенье","понедельник","вторник","среда","четверг","пятница","суббота"];
  const months  = ["января","февраля","марта","апреля","мая","июня","июля","августа","сентября","октября","ноября","декабря"];
  const subtitleEl = $("nb-today-subtitle");
  if (subtitleEl) subtitleEl.textContent = `${days[dateObj.getDay()]}, ${dateObj.getDate()} ${months[dateObj.getMonth()]}`;
  const realToday = new Date().toISOString().slice(0, 10);
  const titleEl = document.querySelector(".nb-page-today .nb-title");
  if (titleEl) titleEl.textContent = today === realToday ? "Сегодня" : (() => { const mo=["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"]; return `${dateObj.getDate()} ${mo[dateObj.getMonth()]}`; })();
  const listEl = $("task-list-today");
  if (!listEl) return;
  listEl.innerHTML = `<div style="padding:8px 0;font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3)">загружаем…</div>`;
  try {
    const tasks = await apiFetch(`/tasks?date=${today}`);
    renderTodayTasks(tasks);
    renderWeekView();
    initWeekNav();
    initGoals();
    loadGoals();
    initAddTaskBtn();
  } catch {
    listEl.innerHTML = `<div style="color:var(--nb-red);font-size:13px;padding:8px 0">Ошибка загрузки</div>`;
  }
};

// ════════════════════════════════════════════════════════════════
//  НЕДЕЛЯ — прокрутка по неделям
// ════════════════════════════════════════════════════════════════
let _weekOffset = 0;

function _weekMonday(offset) {
  const base = new Date(new Date().toISOString().slice(0, 10) + "T00:00:00");
  base.setDate(base.getDate() + offset * 7);
  const day = base.getDay();
  const mon = new Date(base);
  mon.setDate(base.getDate() - (day === 0 ? 6 : day - 1));
  return mon;
}

async function renderWeekView() {
  const mon = _weekMonday(_weekOffset);
  const sun = new Date(mon); sun.setDate(mon.getDate() + 6);
  const fmt = dt => dt.toISOString().slice(0, 10);
  const mo = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];
  const title = $("nb-week-title");
  if (title) {
    title.textContent = _weekOffset === 0
      ? "Эта неделя"
      : `${mon.getDate()} ${mo[mon.getMonth()]} – ${sun.getDate()} ${mo[sun.getMonth()]}`;
  }
  const todayBtn = $("nb-week-today");
  if (todayBtn) todayBtn.style.visibility = _weekOffset === 0 ? "hidden" : "visible";
  let tasks = [];
  try { tasks = await apiFetch(`/tasks/week?date_from=${fmt(mon)}&date_to=${fmt(sun)}`); } catch {}
  renderWeekGridForMonday(tasks, mon);
}

function renderWeekGridForMonday(tasks, mon) {
  const grid = $("nb-week-grid");
  if (!grid) return;
  const realToday = new Date().toISOString().slice(0, 10);
  const dayNames = ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"];
  grid.innerHTML = "";
  for (let i = 0; i < 7; i++) {
    const dt = new Date(mon); dt.setDate(mon.getDate() + i);
    const ds = dt.toISOString().slice(0, 10);
    const isT = ds === realToday;
    const isSel = ds === state.notebookDate;
    const dayTasks = tasks.filter(t => String(t.date).slice(0, 10) === ds).slice(0, 3);
    const row = document.createElement("div");
    row.className = `week-day-row${isSel ? " is-selected" : ""}`;
    row.dataset.date = ds;
    row.innerHTML = `
      <div class="week-day-num ${isT ? "is-today" : ""}">${dt.getDate()}</div>
      <div class="week-day-name">${dayNames[i]}</div>
      <div class="week-day-tasks">
        ${dayTasks.length
          ? dayTasks.map(t => `<div class="week-task-dot ${t.status}">${t.title}</div>`).join("")
          : `<div class="week-task-dot" style="opacity:.3">—</div>`}
      </div>`;
    row.addEventListener("click", () => switchNotebookDay(ds));
    grid.appendChild(row);
  }
}

function initWeekNav() {
  const prev = $("nb-week-prev"), next = $("nb-week-next"), tdy = $("nb-week-today");
  if (prev && !prev._init) { prev._init = true; prev.addEventListener("click", () => { _weekOffset--; renderWeekView(); }); }
  if (next && !next._init) { next._init = true; next.addEventListener("click", () => { _weekOffset++; renderWeekView(); }); }
  if (tdy  && !tdy._init)  { tdy._init  = true; tdy.addEventListener("click",  () => { _weekOffset = 0; renderWeekView(); }); }
}

// ════════════════════════════════════════════════════════════════
//  ЦЕЛИ на месяц / год
// ════════════════════════════════════════════════════════════════
let _goalPeriod = "month";

function _goalKey() {
  const d = new Date();
  const y = d.getFullYear();
  return _goalPeriod === "month" ? `${y}-${String(d.getMonth() + 1).padStart(2, "0")}` : `${y}`;
}

async function loadGoals() {
  const list = $("nb-goals-list");
  if (!list) return;
  const periodEl = $("nb-goals-period");
  if (periodEl) {
    const d = new Date();
    const mo = ["январь","февраль","март","апрель","май","июнь","июль","август","сентябрь","октябрь","ноябрь","декабрь"];
    periodEl.textContent = _goalPeriod === "month" ? `${mo[d.getMonth()]} ${d.getFullYear()}` : `${d.getFullYear()} год`;
  }
  let goals = [];
  try { goals = await apiFetch(`/goals?period=${_goalPeriod}&period_key=${_goalKey()}`); } catch {}
  renderGoals(goals);
}

function renderGoals(goals) {
  const list = $("nb-goals-list");
  if (!list) return;
  list.innerHTML = "";
  if (!goals.length) {
    list.innerHTML = `<div class="nb-goals-empty">пока нет целей — добавь ниже ↓</div>`;
    return;
  }
  const done = goals.filter(g => g.done).length;
  for (const g of goals) {
    const row = document.createElement("div");
    row.className = `nb-goal-row${g.done ? " is-done" : ""}`;
    row.innerHTML = `
      <button class="nb-goal-check">${g.done ? "✓" : ""}</button>
      <span class="nb-goal-text">${g.text}</span>
      <button class="nb-goal-del">×</button>`;
    row.querySelector(".nb-goal-check").addEventListener("click", async () => {
      try { await apiFetch(`/goals/${g.id}`, { method: "PATCH", body: JSON.stringify({ done: !g.done }) }); loadGoals(); } catch {}
    });
    row.querySelector(".nb-goal-del").addEventListener("click", async () => {
      try { await apiFetch(`/goals/${g.id}`, { method: "DELETE" }); loadGoals(); } catch {}
    });
    list.appendChild(row);
  }
  // прогресс
  const periodEl = $("nb-goals-period");
  if (periodEl && goals.length) {
    periodEl.dataset.progress = `${done}/${goals.length}`;
    let badge = periodEl.querySelector(".nb-goals-badge");
    if (!badge) { badge = document.createElement("span"); badge.className = "nb-goals-badge"; periodEl.appendChild(badge); }
    badge.textContent = ` · ${done}/${goals.length}`;
  }
}

function initGoals() {
  document.querySelectorAll(".nb-goal-tab").forEach(tab => {
    if (tab._init) return; tab._init = true;
    tab.addEventListener("click", () => {
      document.querySelectorAll(".nb-goal-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      _goalPeriod = tab.dataset.period;
      loadGoals();
    });
  });
  const addBtn = $("nb-goal-add");
  if (addBtn && !addBtn._init) {
    addBtn._init = true;
    addBtn.addEventListener("click", () => {
      addBtn.style.display = "none";
      const form = document.createElement("div");
      form.className = "nb-goal-add-form";
      form.innerHTML = `<input class="nb-goal-input" placeholder="${_goalPeriod === "month" ? "Цель на месяц…" : "Цель на год…"}" />`;
      addBtn.parentNode.insertBefore(form, addBtn);
      const inp = form.querySelector(".nb-goal-input");
      inp.focus();
      const submit = async () => {
        const text = inp.value.trim();
        form.remove(); addBtn.style.display = "";
        if (!text) return;
        try {
          await apiFetch("/goals", { method: "POST", body: JSON.stringify({ period: _goalPeriod, period_key: _goalKey(), text }) });
          loadGoals();
        } catch {}
      };
      inp.addEventListener("keydown", e => {
        if (e.key === "Enter") submit();
        if (e.key === "Escape") { form.remove(); addBtn.style.display = ""; }
      });
    });
  }
}


// ════════════════════════════════════════════════════════════════
//  КАЛЕНДАРЬ
// ════════════════════════════════════════════════════════════════

const calState = { year: new Date().getFullYear(), month: new Date().getMonth() };

async function loadCalendar() {
  renderCalendarHeader();
  const { year, month } = calState;
  const first = new Date(year, month, 1);
  const last  = new Date(year, month + 1, 0);
  const fmt   = d => d.toISOString().slice(0, 10);
  try {
    const [tasks, trips] = await Promise.all([
      apiFetch(`/tasks/week?date_from=${fmt(first)}&date_to=${fmt(last)}`),
      apiFetch("/trips"),
    ]);
    renderCalendarGrid(tasks, trips);
  } catch { renderCalendarGrid([], []); }
}

function renderCalendarHeader() {
  const { year, month } = calState;
  const months = ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"];
  const lbl = $("cal-month-label");
  if (lbl) lbl.textContent = `${months[month]} ${year}`;
}

function renderCalendarGrid(tasks, trips = []) {
  const grid = $("cal-grid");
  if (!grid) return;
  grid.innerHTML = "";
  const { year, month } = calState;
  const today = new Date().toISOString().slice(0, 10);
  const first = new Date(year, month, 1);
  let startDay = first.getDay();
  startDay = startDay === 0 ? 6 : startDay - 1;
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const daysInPrev  = new Date(year, month, 0).getDate();

  const cells = [];
  for (let i = startDay - 1; i >= 0; i--) cells.push({ d: daysInPrev - i, m: month - 1, y: year, other: true });
  for (let d = 1; d <= daysInMonth; d++) cells.push({ d, m: month, y: year, other: false });
  while (cells.length % 7 !== 0) { cells.push({ d: cells.length - daysInMonth - startDay + 1, m: month + 1, y: year, other: true }); }

  cells.forEach(({ d, m: mo, y, other }) => {
    const dt  = new Date(y, mo, d);
    const ds  = dt.toISOString().slice(0, 10);
    const dayTasks = tasks.filter(t => String(t.date).slice(0,10) === ds);

    // Поездки этого дня
    const dayTrips = trips.filter(tr => {
      const start = tr.start_date ? String(tr.start_date).slice(0,10) : null;
      const end   = tr.end_date   ? String(tr.end_date).slice(0,10)   : start;
      return start && ds >= start && ds <= (end || start);
    });

    const cell = document.createElement("div");
    cell.className = `cal-cell${other ? " cal-other-month" : ""}${ds === today ? " cal-today" : ""}`;
    const dots = dayTasks.map(t => `<div class="cal-dot ${t.status}"></div>`).join("");

    // Полосы поездок
    const tripBars = dayTrips.map(tr => {
      const start   = String(tr.start_date).slice(0,10);
      const end     = tr.end_date ? String(tr.end_date).slice(0,10) : start;
      const isStart = ds === start;
      const isEnd   = ds === end;
      const label   = isStart ? `${tr.emoji} ${tr.name}` : "";
      return `<div class="cal-trip-bar ${isStart?"trip-start":""}${isEnd?" trip-end":""}" title="${tr.name}" style="background:var(--honey)">${label}</div>`;
    }).join("");

    cell.innerHTML = `<div class="cal-day-num">${d}</div><div class="cal-dots">${dots}</div>${tripBars}`;
    cell.addEventListener("click", () => {
      document.querySelectorAll(".cal-cell").forEach(c => c.classList.remove("cal-selected"));
      cell.classList.add("cal-selected");
      loadCalendarDayDetail(ds, dayTasks, dayTrips);
    });
    grid.appendChild(cell);
  });
}

async function loadCalendarDayDetail(dateStr, cachedTasks, dayTrips = []) {
  const detail = $("cal-day-detail");
  if (!detail) return;
  const dt = new Date(dateStr + "T00:00:00");
  const days   = ["воскресенье","понедельник","вторник","среда","четверг","пятница","суббота"];
  const months = ["января","февраля","марта","апреля","мая","июня","июля","августа","сентября","октября","ноября","декабря"];
  const tripsHtml = dayTrips.map(tr =>
    `<div class="cal-detail-trip"><span>${tr.emoji}</span> <span>${tr.name}</span>${tr.start_date ? `<span class="cal-detail-trip-dates">${String(tr.start_date).slice(0,10)}${tr.end_date?" → "+String(tr.end_date).slice(0,10):""}</span>` : ""}</div>`
  ).join("");
  detail.innerHTML = `
    <div class="cal-day-detail-title">${dt.getDate()} ${months[dt.getMonth()]}</div>
    <div class="cal-day-detail-sub">${days[dt.getDay()]}</div>
    ${tripsHtml ? `<div class="cal-detail-trips">${tripsHtml}</div>` : ""}
    <div class="nb-ruled-area" style="padding-right:8px;margin-top:${tripsHtml?8:0}px">
      <div class="task-list" id="cal-task-list"></div>
      <button class="task-add-btn" id="cal-add-task-btn"><span class="task-add-line">+ задача…</span></button>
    </div>`;
  try {
    const tasks = cachedTasks && cachedTasks.length >= 0 ? cachedTasks : await apiFetch(`/tasks?date=${dateStr}`);
    const listEl = $("cal-task-list");
    listEl.innerHTML = "";
    tasks.forEach(t => listEl.appendChild(buildTaskEl(t)));
    if (!tasks.length) listEl.innerHTML = `<div style="padding:8px 0;font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3)">нет задач</div>`;
  } catch {}
  // Add task button for calendar day
  const addBtn = $("cal-add-task-btn");
  if (addBtn) {
    addBtn.addEventListener("click", () => {
      addBtn.style.display = "none";
      const form = document.createElement("div");
      form.className = "task-add-form";
      form.innerHTML = `<input class="task-add-input" placeholder="Новая задача…" />`;
      addBtn.parentNode.insertBefore(form, addBtn.nextSibling);
      const inp = form.querySelector("input");
      inp.focus();
      const submit = async () => {
        const title = inp.value.trim();
        form.remove(); addBtn.style.display = "";
        if (!title) return;
        try {
          const task = await apiFetch("/tasks", { method: "POST", body: JSON.stringify({ title, date: dateStr }) });
          $("cal-task-list").appendChild(buildTaskEl(task));
        } catch {}
      };
      inp.addEventListener("keydown", e => { if (e.key === "Enter") submit(); if (e.key === "Escape") { form.remove(); addBtn.style.display = ""; } });
      inp.addEventListener("blur", () => setTimeout(() => { if (form.parentNode) { form.remove(); addBtn.style.display = ""; } }, 180));
    });
  }
}

// Calendar nav buttons (bind after DOM ready via delegation)
document.addEventListener("click", e => {
  if (e.target.id === "cal-prev") { calState.month--; if (calState.month < 0) { calState.month = 11; calState.year--; } loadCalendar(); }
  if (e.target.id === "cal-next") { calState.month++; if (calState.month > 11) { calState.month = 0; calState.year++; } loadCalendar(); }
});


// ════════════════════════════════════════════════════════════════
//  БЮДЖЕТ
// ════════════════════════════════════════════════════════════════

const CATEGORY_PRESETS = [
  // Базовые / регулярные
  { emoji: "🏠",  name: "Ипотека / Аренда" },
  { emoji: "💡",  name: "ЖКХ" },
  { emoji: "📶",  name: "Интернет" },
  { emoji: "📱",  name: "Связь / Телефон" },
  { emoji: "🚗",  name: "Авто / Бензин" },
  { emoji: "🛒",  name: "Продукты" },
  { emoji: "☕",  name: "Кофе" },
  { emoji: "🍽️", name: "Кафе / Ресторан" },
  { emoji: "🚕",  name: "Такси / Транспорт" },
  // Здоровье и спорт
  { emoji: "💊",  name: "Аптека / Здоровье" },
  { emoji: "🏋️", name: "Спорт / Фитнес" },
  // Развлечения
  { emoji: "🎬",  name: "Кино / Театр" },
  { emoji: "🎮",  name: "Подписки / Игры" },
  { emoji: "🍺",  name: "Алкоголь / Бар" },
  { emoji: "🎢",  name: "Развлечения" },
  // Прочее
  { emoji: "👗",  name: "Одежда / Шопинг" },
  { emoji: "🎁",  name: "Подарки" },
  { emoji: "✈️",  name: "Путешествия" },
  { emoji: "🏨",  name: "Жильё в поездке" },
  { emoji: "🐾",  name: "Животные" },
  { emoji: "📚",  name: "Образование / Книги" },
  { emoji: "💰",  name: "Другое" },
];

const budgetState = { year: new Date().getFullYear(), month: new Date().getMonth() + 1 };

async function loadBudget() {
  renderBudgetHeader();
  const { year, month } = budgetState;
  try {
    const [cats, expenses, events] = await Promise.all([
      apiFetch("/budget/categories"),
      apiFetch(`/budget/expenses?year=${year}&month=${month}`),
      apiFetch(`/budget/events?year=${year}&month=${month}`).catch(() => []),
    ]);
    renderBudgetSummary(cats, expenses, events);
    renderBudgetAccordion(cats, expenses);
    renderBudgetEvents(events);
    renderUnplanned(expenses, cats);
  } catch(e) { console.error(e); }
  initBudgetAddButtons();
  initBudgetEventBtn();
}

function renderBudgetHeader() {
  const months = ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"];
  const lbl = $("budget-month-label");
  if (lbl) lbl.textContent = `${months[budgetState.month - 1]} ${budgetState.year}`;
}

function renderBudgetSummary(cats, expenses, events = []) {
  // Регулярные = только категории с заполненным планом (мин или макс)
  const plannedIds = new Set(cats.filter(c => (c.plan_monthly || 0) > 0 || (c.plan_max || 0) > 0).map(c => c.id));
  const planReg    = cats.reduce((s, c) => s + (c.plan_monthly || 0), 0);
  const planRegMax = cats.reduce((s, c) => s + ((c.plan_max || c.plan_monthly) || 0), 0);
  const actualReg = expenses.reduce((s, e) => s + (plannedIds.has(e.category_id) ? (e.amount || 0) : 0), 0);
  const actualUnplanned = expenses.reduce((s, e) => s + (plannedIds.has(e.category_id) ? 0 : (e.amount || 0)), 0);

  // Только верхний уровень: группы + одиночные (без детей групп)
  // Чтобы не было двойного счёта: group.planned_total уже = сумма детей при создании
  const topEvents = events.filter(e => !e.parent_id);

  // Для плана берём planned_total верхнего уровня.
  // Для группы: если есть дети в events — суммируем их план (актуальнее чем grp.planned_total)
  const getPlan = (ev) => {
    if (ev.event_type === "group") {
      const kids = events.filter(k => k.parent_id === ev.id);
      const kidsSum = kids.reduce((s, k) => s + (k.planned_total || 0), 0);
      return kidsSum || (ev.planned_total || 0);
    }
    return ev.planned_total || 0;
  };

  // Для факта: прямые расходы события + расходы детей
  const getActual = (ev) => {
    const direct = Number(ev.actual_total) || 0;
    if (ev.event_type === "group") {
      const kids = events.filter(k => k.parent_id === ev.id);
      return direct + kids.reduce((s, k) => s + (Number(k.actual_total) || 0), 0);
    }
    return direct;
  };

  const planEv   = topEvents.reduce((s, t) => s + getPlan(t), 0);
  const actualEv = topEvents.reduce((s, t) => s + getActual(t), 0);
  const plan   = planReg + planEv;
  const actual = actualReg + actualUnplanned + actualEv;
  const left   = plan - actual;

  // KPI row (в topbar справа)
  const el = $("budget-summary");
  if (el) {
    el.innerHTML = `
      <div class="bud-kpi"><div class="bud-kpi-lbl">ПЛАН</div><div class="bud-kpi-val">${plan.toLocaleString("ru")} ₽</div></div>
      <div class="bud-kpi-sep"></div>
      <div class="bud-kpi"><div class="bud-kpi-lbl">ФАКТ</div><div class="bud-kpi-val ${actual > plan ? "over" : ""}">${actual.toLocaleString("ru")} ₽</div></div>
      <div class="bud-kpi-sep"></div>
      <div class="bud-kpi"><div class="bud-kpi-lbl">${left >= 0 ? "ОСТАЛОСЬ" : "ПЕРЕРАСХОД"}</div><div class="bud-kpi-val ${left < 0 ? "over" : "pos"}">${left < 0 ? "– " : "+ "}${Math.abs(left).toLocaleString("ru")} ₽</div></div>`;
  }

  // Subtitle под месяцем (считаем только top-level события)
  const sub = $("budget-month-sub");
  if (sub) sub.textContent = `регулярные траты · ${topEvents.length ? topEvents.length + " событий" : "нет событий"}`;

  // Полоса (отдельный div под topbar)
  const barRow = $("budget-bar-row");
  if (barRow) {
    const total = planReg + planEv;
    const pctReg = total > 0 ? Math.min((actualReg / total) * 100, 100) : 0;
    const pctEv  = total > 0 ? Math.min((actualEv  / total) * 100, 100) : 0;
    const overReg = planReg > 0 && actualReg > planReg;
    const overEv  = planEv  > 0 && actualEv  > planEv;
    // Находим проблемное событие (только top-level)
    const overEvent = topEvents.find(t => getActual(t) > getPlan(t) && getPlan(t) > 0);

    barRow.innerHTML = `
      <div class="bud-bar-track">
        <div class="bud-bar-reg${overReg ? " over" : ""}" style="width:${pctReg}%"></div>
        <div class="bud-bar-ev${overEv ? " over" : ""}" style="width:${pctEv}%"></div>
      </div>
      <div class="bud-bar-legend">
        <span class="bud-bleg bud-bleg-reg">▪ регулярное: ${actualReg.toLocaleString("ru")} / ${planReg.toLocaleString("ru")}${planRegMax > planReg ? "–" + planRegMax.toLocaleString("ru") : ""} ₽</span>
        ${actualUnplanned ? `<span class="bud-bleg bud-bleg-warn">▫ нерегулярное: ${actualUnplanned.toLocaleString("ru")} ₽</span>` : ""}
        <span class="bud-bleg bud-bleg-ev">□ события и поездки: ${actualEv.toLocaleString("ru")} / ${planEv.toLocaleString("ru")} ₽</span>
        ${overEvent ? `<span class="bud-bleg bud-bleg-warn">↑ ${overEvent.name} вышли за бюджет на ${(getActual(overEvent) - getPlan(overEvent)).toLocaleString("ru")} ₽</span>` : ""}
      </div>`;
  }
}

// ─── Accordion: Категория → Место → Транзакция ───────────────────────────────

function renderBudgetAccordion(cats, expenses) {
  const el = $("budget-categories-list");
  if (!el) return;
  el.innerHTML = "";

  // Регулярные = только категории с заполненным планом (мин или макс)
  const plannedCats = cats.filter(c => (c.plan_monthly || 0) > 0 || (c.plan_max || 0) > 0);
  const plannedIds  = new Set(plannedCats.map(c => c.id));

  const catMap = {};
  for (const cat of plannedCats) catMap[cat.id] = cat;

  // Группируем расходы только по запланированным категориям
  const byCat = {};
  for (const exp of expenses) {
    if (!plannedIds.has(exp.category_id)) continue;  // нерегулярные → в отдельный блок
    const key = exp.category_id;
    if (!byCat[key]) byCat[key] = { cat: catMap[key] || null, exps: [], total: 0 };
    byCat[key].exps.push(exp);
    byCat[key].total += exp.amount;
  }

  // Сортируем по сумме убыв.
  const sortedGroups = Object.values(byCat).sort((a, b) => b.total - a.total);

  for (const group of sortedGroups) {
    const cat      = group.cat;
    const catId    = cat ? cat.id : 0;
    const emoji    = cat ? cat.emoji : "💰";
    const catName  = cat ? cat.name : "Без категории";
    const plan     = cat ? (cat.plan_monthly || 0) : 0;
    const planMax  = cat ? (cat.plan_max || 0) : 0;
    const ceil     = planMax || plan;  // потолок для подсветки/бара
    const over     = ceil > 0 && group.total > ceil;

    // Подгруппа по merchant (место / заведение)
    const byMerchant = {};
    for (const exp of group.exps) {
      const mk = exp.merchant || "—";
      if (!byMerchant[mk]) byMerchant[mk] = { exps: [], total: 0 };
      byMerchant[mk].exps.push(exp);
      byMerchant[mk].total += exp.amount;
    }
    const merchantGroups = Object.entries(byMerchant).sort((a, b) => b[1].total - a[1].total);

    const catDiv = document.createElement("div");
    catDiv.className = "bacc-cat";

    const pct       = ceil > 0 ? Math.min((group.total / ceil) * 100, 100) : (group.total > 0 ? 100 : 0);
    const spentFmt  = group.total.toLocaleString("ru");
    const planStr   = plan > 0 ? plan.toLocaleString("ru") : "0";
    const planFmt   = (plan > 0 || planMax > 0)
      ? ` / ${planStr}${planMax > 0 && planMax !== plan ? "–" + planMax.toLocaleString("ru") : ""} ₽`
      : "";
    const overSign  = over ? " ↑" : "";
    catDiv.innerHTML = `
      <div class="bacc-cat-head">
        <span class="bacc-cat-emoji">${emoji}</span>
        <span class="bacc-cat-name">${catName}</span>
        <button class="bacc-plan-val ${over ? "over" : ""}" data-cat-id="${catId}" title="Нажми чтобы изменить план">${spentFmt}${planFmt} ₽${overSign}</button>
        <button class="bacc-toggle" title="Развернуть">›</button>
        ${cat ? `<button class="bacc-cat-delete" data-id="${catId}">×</button>` : ""}
      </div>
      <div class="bacc-cat-bar"><div class="bacc-cat-bar-fill${over ? " over" : ""}" style="width:${pct}%"></div></div>
      <div class="bacc-cat-body" style="display:none"></div>`;

    const head   = catDiv.querySelector(".bacc-cat-head");
    const body   = catDiv.querySelector(".bacc-cat-body");
    const toggle = catDiv.querySelector(".bacc-toggle");

    catDiv.querySelector(".bacc-plan-val").addEventListener("click", e => {
      e.stopPropagation();
      if (cat) openPlanEdit(catDiv, cat);
    });
    if (cat) {
      catDiv.querySelector(".bacc-cat-delete").addEventListener("click", async e => {
        e.stopPropagation();
        try { await apiFetch(`/budget/categories/${catId}`, { method: "DELETE" }); loadBudget(); } catch {}
      });
    }
    head.addEventListener("click", e => {
      if (e.target.classList.contains("bacc-plan-val")) return;
      if (e.target.classList.contains("bacc-cat-delete")) return;
      const open = body.style.display !== "none";
      body.style.display = open ? "none" : "";
      toggle.textContent = open ? "›" : "▾";
      catDiv.classList.toggle("bacc-open", !open);
    });

    // Уровень: место/заведение
    for (const [mName, mg] of merchantGroups) {
      const mDiv = document.createElement("div");
      mDiv.className = "bacc-merchant";
      mDiv.innerHTML = `
        <div class="bacc-merchant-head">
          <button class="bacc-toggle sm">▶</button>
          <span class="bacc-merchant-name">${mName}</span>
          <span class="bacc-merchant-total">${mg.total.toLocaleString("ru")} ₽</span>
        </div>
        <div class="bacc-merchant-body" style="display:none"></div>`;

      const mHead   = mDiv.querySelector(".bacc-merchant-head");
      const mBody   = mDiv.querySelector(".bacc-merchant-body");
      const mToggle = mDiv.querySelector(".bacc-toggle");
      mHead.addEventListener("click", e => {
        if (e.target.tagName === "BUTTON") return;
        const open = mBody.style.display !== "none";
        mBody.style.display = open ? "none" : "";
        mToggle.textContent = open ? "▶" : "▼";
      });

      // Уровень: отдельные транзакции (сортируем по сумме убыв.)
      const sortedExps = [...mg.exps].sort((a, b) => b.amount - a.amount);
      for (const exp of sortedExps) {
        const [, mo, d] = String(exp.date).slice(0, 10).split("-");
        const row = document.createElement("div");
        row.className = "bacc-exp-row";
        row.dataset.expId = exp.id;
        const noteText = exp.note && exp.note.trim() ? exp.note : (exp.merchant || "расход");
        row.innerHTML = `
          <span class="bacc-exp-date">${d}.${mo}</span>
          <span class="bacc-exp-desc" title="${exp.note || ""}">${noteText}</span>
          <span class="bacc-exp-amt">${exp.amount.toLocaleString("ru")} ₽</span>
          <button class="bacc-exp-edit" title="Редактировать">✏️</button>
          <button class="bacc-exp-del">×</button>`;

        row.querySelector(".bacc-exp-del").addEventListener("click", async () => {
          try { await apiFetch(`/budget/expenses/${exp.id}`, { method: "DELETE" }); loadBudget(); } catch {}
        });
        row.querySelector(".bacc-exp-edit").addEventListener("click", () => {
          openBudgetExpEdit(row, exp, cats);
        });
        mBody.appendChild(row);
      }
      body.appendChild(mDiv);
    }
    el.appendChild(catDiv);
  }

  // Запланированные категории без расходов (чтобы видеть план)
  const usedIds = new Set(Object.keys(byCat).map(Number));
  for (const cat of plannedCats) {
    if (usedIds.has(cat.id)) continue;
    const emptyDiv = document.createElement("div");
    emptyDiv.className = "bacc-cat bacc-cat-empty";
    const plan = cat.plan_monthly || 0;
    emptyDiv.innerHTML = `
      <div class="bacc-cat-head bacc-cat-head-empty">
        <span class="bacc-cat-emoji">${cat.emoji}</span>
        <span class="bacc-cat-name" style="opacity:.5">${cat.name}</span>
        <button class="bacc-plan-val no-plan" title="Задать план">0${plan ? ` / ${plan.toLocaleString("ru")}` : ""} ₽</button>
        <button class="bacc-toggle" disabled style="opacity:.2">›</button>
        <button class="bacc-cat-delete" data-id="${cat.id}">×</button>
      </div>
      <div class="bacc-cat-bar"><div class="bacc-cat-bar-fill" style="width:0%"></div></div>`;
    emptyDiv.querySelector(".bacc-plan-val").addEventListener("click", e => {
      e.stopPropagation(); openPlanEdit(emptyDiv, cat);
    });
    emptyDiv.querySelector(".bacc-cat-delete").addEventListener("click", async e => {
      e.stopPropagation();
      try { await apiFetch(`/budget/categories/${cat.id}`, { method: "DELETE" }); loadBudget(); } catch {}
    });
    el.appendChild(emptyDiv);
  }

  if (!el.children.length) {
    el.innerHTML = `<div class="bacc-empty-hint">Пока нет регулярных категорий.<br>Добавь категорию и задай ей план — она появится здесь.</div>`;
  }
}

function openPlanEdit(catDiv, cat) {
  const planBtn = catDiv.querySelector(".bacc-plan-val");
  if (!planBtn) return;
  const wrap = document.createElement("span");
  wrap.className = "bacc-plan-edit";
  const inp = document.createElement("input");
  inp.type = "number"; inp.min = "0"; inp.value = cat.plan_monthly || "";
  inp.className = "bacc-plan-input"; inp.placeholder = "план ₽";
  const sep = document.createElement("span");
  sep.className = "bacc-plan-sep"; sep.textContent = "–";
  const inpMax = document.createElement("input");
  inpMax.type = "number"; inpMax.min = "0"; inpMax.value = cat.plan_max || "";
  inpMax.className = "bacc-plan-input"; inpMax.placeholder = "макс ₽";
  wrap.append(inp, sep, inpMax);
  planBtn.replaceWith(wrap);
  inp.focus(); inp.select();

  let saved = false;
  const save = async () => {
    if (saved) return; saved = true;
    const val = parseInt(inp.value) || 0;
    const valMax = parseInt(inpMax.value) || 0;
    try {
      await apiFetch(`/budget/categories/${cat.id}`, {
        method: "PATCH",
        body: JSON.stringify({ plan_monthly: val, plan_max: valMax }),
      });
    } catch {}
    loadBudget();
  };
  const onBlur = () => {
    // не сохраняем, если фокус ушёл на второй input этой же пары
    setTimeout(() => {
      if (document.activeElement === inp || document.activeElement === inpMax) return;
      save();
    }, 0);
  };
  [inp, inpMax].forEach(el => {
    el.addEventListener("blur", onBlur);
    el.addEventListener("keydown", e => {
      if (e.key === "Enter") save();
      if (e.key === "Escape") { saved = true; loadBudget(); }
    });
  });
}

// ─── События и поездки (правая колонка бюджета) ──────────────────────────────

function renderBudgetEvents(events) {
  const el    = $("budget-events-list");
  const count = $("budget-events-count");
  if (!el) return;

  // Разбиваем на группы и одиночные
  const groups  = events.filter(e => e.event_type === "group");
  const children = new Set(events.filter(e => e.parent_id).map(e => e.id));
  const singles  = events.filter(e => e.event_type !== "group" && !e.parent_id);
  const total = groups.length + singles.length;

  if (count) count.textContent = total ? `${total} шт.` : "";
  el.innerHTML = "";

  if (!events.length) {
    el.innerHTML = `<div class="budget-events-empty">нет событий в этом месяце</div>`;
    return;
  }

  // Сортировка: по дате, свежие первые
  const sortFn = (a, b) => ((b.start_date || "0") > (a.start_date || "0") ? 1 : -1);

  // Сначала группы
  for (const grp of [...groups].sort(sortFn)) {
    const kids = events.filter(e => e.parent_id === grp.id).sort(sortFn);
    const grpEl = buildGroupRow(grp, kids, events);
    el.appendChild(grpEl);
  }
  // Потом одиночные (не дети групп)
  for (const ev of [...singles].sort(sortFn)) {
    const row = buildEventCard(ev);
    el.appendChild(row);
  }

  // ── Drag-and-drop для группировки ──────────────────────────────────
  initEventDragDrop(el, events);
}

function buildEventCard(ev) {
  const isTrip    = ev.event_type !== "event";
  const actual    = Number(ev.actual_total) || 0;
  const plan      = ev.planned_total || 0;
  const over      = plan > 0 && actual > plan;
  const pct       = plan > 0 ? Math.min((actual / plan) * 100, 100) : (actual > 0 ? 100 : 0);
  const typeLabel = isTrip ? "поездка" : "событие";
  const MONTHS    = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];

  // Дата
  let dateStr = "";
  if (ev.start_date) {
    const sd = new Date(ev.start_date + "T00:00:00");
    if (ev.end_date && ev.end_date !== ev.start_date) {
      const ed = new Date(ev.end_date + "T00:00:00");
      dateStr = `${sd.getDate()}–${ed.getDate()} ${MONTHS[sd.getMonth()]}`;
    } else {
      dateStr = `${sd.getDate()} ${MONTHS[sd.getMonth()]}`;
    }
  }

  // Идёт сейчас?
  const todayS = new Date().toISOString().slice(0, 10);
  const isNow  = ev.start_date && ev.end_date
    ? (todayS >= ev.start_date && todayS <= ev.end_date)
    : ev.start_date === todayS;

  const row = document.createElement("div");
  row.className = `bev-row${over ? " bev-over" : ""}`;
  row.dataset.tripId = ev.id;
  row.innerHTML = `
    <span class="bev-row-emoji">${ev.emoji}</span>
    <div class="bev-row-middle">
      <div class="bev-row-top">
        <span class="bev-row-name">${ev.name}</span>
        ${isNow ? `<span class="bev-row-now">сейчас</span>` : ""}
        <span class="bev-row-type">${typeLabel}</span>
        ${dateStr ? `<span class="bev-row-date">${dateStr}</span>` : ""}
      </div>
      ${plan > 0 ? `<div class="bev-row-bar"><div class="bev-row-bar-fill${over ? " over" : ""}" style="width:${pct}%"></div></div>` : ""}
    </div>
    <div class="bev-row-right">
      <span class="bev-row-actual${over ? " over" : ""}">${actual.toLocaleString("ru")} ₽</span>
      ${plan ? `<span class="bev-row-plan">/ ${plan.toLocaleString("ru")} ₽</span>` : ""}
      <button class="bev-row-link" title="Детали по дням">по дням →</button>
    </div>
    <button class="bev-row-del" title="Удалить">×</button>`;

  row.querySelector(".bev-row-middle").addEventListener("click", () => openEventDetail(ev));
  row.querySelector(".bev-row-name").addEventListener("click", () => openEventDetail(ev));
  row.querySelector(".bev-row-link").addEventListener("click", e => { e.stopPropagation(); openEventDetail(ev); });
  row.querySelector(".bev-row-del").addEventListener("click", async e => {
    e.stopPropagation();
    if (!confirm(`Удалить «${ev.name}»?`)) return;
    try { await apiFetch(`/trips/${ev.id}`, { method: "DELETE" }); loadBudget(); } catch {}
  });
  return row;
}

// ─── Группа поездок ─────────────────────────────────────────────────────────

function buildGroupRow(grp, kids, allEvents) {
  const actualKids = kids.reduce((s, k) => s + (Number(k.actual_total) || 0), 0);
  const planKids   = kids.reduce((s, k) => s + (k.planned_total || 0), 0);
  const actual = (Number(grp.actual_total) || 0) + actualKids;
  const plan   = (grp.planned_total || 0) || planKids;
  const over   = plan > 0 && actual > plan;
  const pct    = plan > 0 ? Math.min((actual / plan) * 100, 100) : (actual > 0 ? 100 : 0);

  const MONTHS = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];
  let dateStr = "";
  if (grp.start_date) {
    const sd = new Date(grp.start_date + "T00:00:00");
    if (grp.end_date && grp.end_date !== grp.start_date) {
      const ed = new Date(grp.end_date + "T00:00:00");
      dateStr = `${sd.getDate()}–${ed.getDate()} ${MONTHS[sd.getMonth()]}`;
    } else {
      dateStr = `${sd.getDate()} ${MONTHS[sd.getMonth()]}`;
    }
  }

  const wrap = document.createElement("div");
  wrap.className = `bev-group${over ? " bev-over" : ""}`;
  wrap.dataset.tripId = grp.id;
  wrap.innerHTML = `
    <div class="bev-group-head">
      <span class="bev-group-emoji">${grp.emoji || "📁"}</span>
      <div class="bev-group-info">
        <div class="bev-group-top">
          <span class="bev-group-name">${grp.name}</span>
          <span class="bev-group-type">группа · ${kids.length} поездок</span>
          ${dateStr ? `<span class="bev-row-date">${dateStr}</span>` : ""}
        </div>
        ${plan > 0 ? `<div class="bev-row-bar"><div class="bev-row-bar-fill${over ? " over" : ""}" style="width:${pct}%"></div></div>` : ""}
      </div>
      <div class="bev-row-right">
        <span class="bev-row-actual${over ? " over" : ""}">${actual.toLocaleString("ru")} ₽</span>
        ${plan ? `<span class="bev-row-plan">/ ${plan.toLocaleString("ru")} ₽</span>` : ""}
        <button class="bev-group-toggle" title="Свернуть/развернуть">▾</button>
      </div>
      <button class="bev-row-del" title="Расформировать группу">×</button>
    </div>
    <div class="bev-group-children" id="bev-gc-${grp.id}"></div>`;

  const childrenEl = wrap.querySelector(`#bev-gc-${grp.id}`);
  for (const kid of kids) {
    const kidRow = buildEventCard(kid);
    kidRow.classList.add("bev-row-child");
    // Кнопка «убрать из группы»
    const ungrpBtn = document.createElement("button");
    ungrpBtn.className = "bev-ungroup-btn";
    ungrpBtn.title = "Убрать из группы";
    ungrpBtn.textContent = "↗";
    ungrpBtn.addEventListener("click", async e => {
      e.stopPropagation();
      try { await apiFetch(`/trips/${kid.id}/ungroup`, { method: "POST" }); loadBudget(); } catch {}
    });
    kidRow.appendChild(ungrpBtn);
    childrenEl.appendChild(kidRow);
  }

  // Сворачивание/разворачивание
  const toggle = wrap.querySelector(".bev-group-toggle");
  let open = true;
  toggle.addEventListener("click", e => {
    e.stopPropagation();
    open = !open;
    childrenEl.style.display = open ? "" : "none";
    toggle.textContent = open ? "▾" : "▸";
  });

  // Удаление группы (расформировывает, не удаляет детей)
  wrap.querySelector(".bev-row-del").addEventListener("click", async e => {
    e.stopPropagation();
    if (!confirm(`Расформировать группу «${grp.name}»?\nПоездки останутся, группа удалится.`)) return;
    try {
      // Убираем всех детей из группы, потом удаляем группу
      await Promise.all(kids.map(k => apiFetch(`/trips/${k.id}/ungroup`, { method: "POST" })));
      await apiFetch(`/trips/${grp.id}`, { method: "DELETE" });
      loadBudget();
    } catch {}
  });

  return wrap;
}

// ─── Drag-and-drop для объединения поездок в группу ─────────────────────────

function initEventDragDrop(container, events) {
  const rows = container.querySelectorAll(".bev-row:not(.bev-row-child)");
  let dragId = null;

  rows.forEach(row => {
    const evId = parseInt(row.dataset.tripId);
    if (!evId) return;

    row.draggable = true;
    row.style.cursor = "grab";

    row.addEventListener("dragstart", e => {
      dragId = evId;
      row.classList.add("bev-dragging");
      e.dataTransfer.effectAllowed = "move";
    });
    row.addEventListener("dragend", () => {
      dragId = null;
      row.classList.remove("bev-dragging");
      container.querySelectorAll(".bev-drop-over").forEach(r => r.classList.remove("bev-drop-over"));
    });
    row.addEventListener("dragover", e => {
      if (dragId === evId || !dragId) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      container.querySelectorAll(".bev-drop-over").forEach(r => r.classList.remove("bev-drop-over"));
      row.classList.add("bev-drop-over");
    });
    row.addEventListener("dragleave", () => {
      row.classList.remove("bev-drop-over");
    });
    row.addEventListener("drop", async e => {
      e.preventDefault();
      row.classList.remove("bev-drop-over");
      if (!dragId || dragId === evId) return;

      const targetEv = events.find(x => x.id === evId);
      const sourceEv = events.find(x => x.id === dragId);
      if (!targetEv || !sourceEv) return;

      // Предлагаем название для группы
      const defaultName = `${sourceEv.name} · ${targetEv.name}`;
      const groupName = prompt(`Название группы:`, defaultName);
      if (groupName === null) return; // отмена

      try {
        await apiFetch("/trips/group", {
          method: "POST",
          body: JSON.stringify({ trip_a: dragId, trip_b: evId, name: groupName || defaultName, emoji: "📁" })
        });
        loadBudget();
        toast("Группа создана", "success");
      } catch (err) {
        toast("Ошибка: " + (err?.detail || "не удалось создать группу"), "error");
      }
    });
  });
}

// ─── Детальный вид поездки/события — по дням ────────────────────────────────

async function openEventDetail(ev) {
  const panel = $("ntab-budget");
  if (!panel) return;

  const [expenses, dayNotes] = await Promise.all([
    apiFetch(`/trips/${ev.id}/expenses`).catch(() => []),
    apiFetch(`/trips/${ev.id}/day-notes`).catch(() => []),
  ]);

  const noteMap = {};
  for (const dn of dayNotes) noteMap[String(dn.date).slice(0,10)] = dn;

  // Собираем уникальные дни
  const datesSet = new Set(expenses.map(e => String(e.date).slice(0,10)));
  // Добавляем дни из диапазона поездки
  if (ev.start_date && ev.end_date) {
    let d = new Date(ev.start_date + "T00:00:00");
    const end = new Date(ev.end_date + "T00:00:00");
    while (d <= end) {
      datesSet.add(d.toISOString().slice(0,10));
      d.setDate(d.getDate() + 1);
    }
  } else if (ev.start_date) {
    datesSet.add(ev.start_date);
  }
  const dates = [...datesSet].sort();

  // Считаем категорийные итоги для прогресс-бара
  const byCat = {};
  for (const exp of expenses) {
    const k = exp.category || "Прочее";
    byCat[k] = (byCat[k] || 0) + exp.amount;
  }
  const catTotal = Object.values(byCat).reduce((s, v) => s + v, 0);
  const PALETTE  = ["#b44840","#c9873a","#5a8a5a","#4a6da8","#8a5aaa","#6a6a6a"];
  const catEntries = Object.entries(byCat).sort((a,b) => b[1]-a[1]);

  const actual = Number(ev.actual_total) || expenses.reduce((s,e) => s+e.amount, 0);
  const plan   = ev.planned_total || 0;
  const perDay = dates.length > 0 ? Math.round(actual / dates.length) : 0;

  panel.innerHTML = `
    <div class="evd-wrap">
      <div class="evd-topbar">
        <button class="evd-back" id="evd-back">← бюджет ${["","янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"][budgetState.month]}</button>
        <div class="evd-breadcrumb">события / ${ev.emoji} ${ev.name}</div>
      </div>
      <div class="evd-header">
        <span class="evd-emoji">${ev.emoji}</span>
        <div class="evd-header-info">
          <div class="evd-title">${ev.name}</div>
          ${ev.subtitle ? `<div class="evd-subtitle">${ev.subtitle}</div>` : ""}
        </div>
        <div class="evd-kpis">
          ${plan ? `<div class="evd-kpi"><div class="evd-kpi-lbl">ПЛАН</div><div class="evd-kpi-val">${plan.toLocaleString("ru")} ₽</div></div>` : ""}
          <div class="evd-kpi"><div class="evd-kpi-lbl">ФАКТ</div><div class="evd-kpi-val ${actual>plan&&plan>0?"over":""}">${actual.toLocaleString("ru")} ₽</div></div>
          ${dates.length>1 ? `<div class="evd-kpi"><div class="evd-kpi-lbl">В ДЕНЬ</div><div class="evd-kpi-val">${perDay.toLocaleString("ru")} ₽</div></div>` : ""}
        </div>
      </div>
      <!-- Категорийная полоса -->
      ${catTotal > 0 ? `
      <div class="evd-catbar">
        ${catEntries.map(([cat, sum], i) =>
          `<div class="evd-catbar-seg" style="width:${(sum/catTotal*100).toFixed(1)}%;background:${PALETTE[i%PALETTE.length]}" title="${cat}: ${sum.toLocaleString('ru')} ₽"></div>`
        ).join("")}
      </div>
      <div class="evd-catbar-legend">
        ${catEntries.map(([cat, sum], i) =>
          `<span class="evd-catleg-item"><span class="evd-catleg-dot" style="background:${PALETTE[i%PALETTE.length]}"></span>${cat}: <b>${sum.toLocaleString("ru")} ₽</b></span>`
        ).join("")}
      </div>` : ""}
      <!-- Дни -->
      <div class="evd-days-label">По дням</div>
      <div class="evd-days-scroll">
        <div class="evd-days-row" id="evd-days-row"></div>
      </div>
    </div>`;

  $("evd-back").addEventListener("click", () => loadBudget());

  // Строим колонки дней
  const row = $("evd-days-row");
  const MONTH_NAMES = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];

  for (const dateStr of dates) {
    const dt    = new Date(dateStr + "T00:00:00");
    const dayExps = expenses.filter(e => String(e.date).slice(0,10) === dateStr);
    const dayTotal = dayExps.reduce((s,e) => s + e.amount, 0);
    const dn    = noteMap[dateStr];
    const dayTitle = dn?.title || "";
    const dayNote  = dn?.note  || "";

    const col = document.createElement("div");
    col.className = "evd-day-col";
    col.innerHTML = `
      <div class="evd-day-head">
        <div class="evd-day-date">${dt.getDate()} ${MONTH_NAMES[dt.getMonth()]}</div>
        ${dayTotal ? `<div class="evd-day-total">${dayTotal.toLocaleString("ru")} ₽</div>` : ""}
        <input class="evd-day-title-inp" value="${dayTitle}" placeholder="название дня…" data-date="${dateStr}" />
      </div>
      <div class="evd-day-exps">
        ${dayExps.length ? dayExps.map(exp => `
          <div class="evd-exp-row" data-id="${exp.id}">
            <span class="evd-exp-emoji">${exp.emoji || "💸"}</span>
            <div class="evd-exp-body">
              <div class="evd-exp-note">${exp.note || exp.category || "расход"}</div>
              ${exp.category ? `<div class="evd-exp-cat">${exp.category}</div>` : ""}
            </div>
            <span class="evd-exp-amt">${exp.amount.toLocaleString("ru")} ₽</span>
            <button class="evd-exp-del" data-id="${exp.id}">×</button>
          </div>`).join("") : ""}
      </div>
      <div class="evd-day-note-wrap">
        <textarea class="evd-day-note" placeholder="заметка о дне…" data-date="${dateStr}">${dayNote}</textarea>
      </div>
      <button class="evd-day-add-btn" data-date="${dateStr}">+ расход</button>`;

    // Сохранение заголовка дня
    const titleInp = col.querySelector(".evd-day-title-inp");
    titleInp.addEventListener("blur", async () => {
      const title = titleInp.value.trim();
      const note  = col.querySelector(".evd-day-note").value.trim();
      await apiFetch(`/trips/${ev.id}/day-notes`, {
        method: "POST", body: JSON.stringify({ date: dateStr, title, note }),
      }).catch(()=>{});
    });

    // Сохранение заметки дня
    const noteTA = col.querySelector(".evd-day-note");
    noteTA.addEventListener("blur", async () => {
      const title = titleInp.value.trim();
      const note  = noteTA.value.trim();
      await apiFetch(`/trips/${ev.id}/day-notes`, {
        method: "POST", body: JSON.stringify({ date: dateStr, title, note }),
      }).catch(()=>{});
    });

    // Удаление расхода
    col.querySelectorAll(".evd-exp-del").forEach(btn => {
      btn.addEventListener("click", async () => {
        const id = btn.dataset.id;
        try {
          await apiFetch(`/trip-expenses/${id}`, { method: "DELETE" });
          btn.closest(".evd-exp-row").remove();
        } catch {}
      });
    });

    // Добавить расход в день
    col.querySelector(".evd-day-add-btn").addEventListener("click", () => {
      openDayExpenseForm(col, ev.id, dateStr, () => openEventDetail(ev));
    });

    row.appendChild(col);
  }
}

function openDayExpenseForm(col, tripId, dateStr, onSaved) {
  const existing = col.querySelector(".evd-day-form");
  if (existing) { existing.remove(); return; }
  const form = document.createElement("div");
  form.className = "evd-day-form";
  form.innerHTML = `
    <input class="nb-inline-input sm" id="edf-emoji" placeholder="Emoji" maxlength="4" value="💸" />
    <div class="preset-wrap" style="flex:1">
      <input class="nb-inline-input md" id="edf-cat" placeholder="Категория" style="width:100%" autocomplete="off" />
      <div class="preset-dropdown" id="edf-dd" style="display:none"></div>
    </div>
    <input class="nb-inline-input md" id="edf-note" placeholder="Заметка…" />
    <input class="nb-inline-input sm" id="edf-amt" type="number" min="0" placeholder="₽" />
    <button class="nb-inline-btn" id="edf-ok">✓</button>`;

  col.querySelector(".evd-day-exps").after(form);

  const catI = form.querySelector("#edf-cat");
  const dd   = form.querySelector("#edf-dd");
  function renderP(q) {
    const f = q ? CATEGORY_PRESETS.filter(p => p.name.toLowerCase().includes(q.toLowerCase())) : CATEGORY_PRESETS;
    if (!f.length) { dd.style.display = "none"; return; }
    dd.innerHTML = f.map(p => `<div class="preset-item" data-emoji="${p.emoji}" data-name="${p.name}"><span class="preset-item-emoji">${p.emoji}</span>${p.name}</div>`).join("");
    dd.style.display = "";
  }
  catI.addEventListener("focus", () => renderP(catI.value));
  catI.addEventListener("input", () => renderP(catI.value));
  catI.addEventListener("blur",  () => setTimeout(() => { dd.style.display = "none"; }, 200));
  dd.addEventListener("mousedown", e => {
    const item = e.target.closest(".preset-item");
    if (!item) return;
    form.querySelector("#edf-emoji").value = item.dataset.emoji;
    catI.value = item.dataset.name; dd.style.display = "none";
  });

  form.querySelector("#edf-ok").addEventListener("click", async () => {
    const amount = parseInt(form.querySelector("#edf-amt").value); if (!amount) return;
    try {
      await apiFetch(`/trips/${tripId}/expenses`, {
        method: "POST",
        body: JSON.stringify({
          date: dateStr, amount,
          category: catI.value || "",
          note: form.querySelector("#edf-note").value || "",
          emoji: form.querySelector("#edf-emoji").value || "💸",
          city: "",
        }),
      });
      form.remove();
      onSaved();
    } catch {}
  });
  form.addEventListener("keydown", e => { if (e.key === "Escape") form.remove(); });
  form.querySelector("#edf-amt").focus();
}

// ─── Добавление события/поездки ──────────────────────────────────────────────

function initBudgetEventBtn() {
  const btn = $("budget-add-event-btn");
  if (!btn || btn._init) return;
  btn._init = true;
  btn.addEventListener("click", () => {
    btn.style.display = "none";
    const form = document.createElement("div");
    form.className = "nb-inline-form";
    form.innerHTML = `
      <input class="nb-inline-input sm" id="bev-emoji" placeholder="Emoji" maxlength="4" value="✈️" />
      <input class="nb-inline-input lg" id="bev-name" placeholder="Название события…" />
      <select class="nb-inline-select" id="bev-type">
        <option value="trip">✈️ Поездка</option>
        <option value="event">🎉 Событие</option>
      </select>
      <input class="nb-inline-input sm" id="bev-d1" type="date" title="Начало" />
      <input class="nb-inline-input sm" id="bev-d2" type="date" title="Конец" />
      <input class="nb-inline-input sm" id="bev-plan" placeholder="Бюджет ₽" type="number" min="0" />
      <button class="nb-inline-btn" id="bev-ok">Добавить</button>`;
    btn.parentNode.insertBefore(form, btn.nextSibling);

    form.querySelector("#bev-ok").addEventListener("click", async () => {
      const name = form.querySelector("#bev-name").value.trim();
      if (!name) return;
      try {
        await apiFetch("/trips", { method: "POST", body: JSON.stringify({
          name,
          emoji: form.querySelector("#bev-emoji").value || "✈️",
          event_type: form.querySelector("#bev-type").value,
          start_date: form.querySelector("#bev-d1").value || null,
          end_date:   form.querySelector("#bev-d2").value || null,
          planned_total: parseInt(form.querySelector("#bev-plan").value) || 0,
        })});
        form.remove(); btn.style.display = "";
        loadBudget();
      } catch {}
    });
    form.addEventListener("keydown", e => { if (e.key === "Escape") { form.remove(); btn.style.display = ""; } });
    form.querySelector("#bev-name").focus();
  });
}

// (Legacy — больше не используются, но оставляем чтобы не сломать старые вызовы)
function renderBudgetCategories(cats, expenses) {
  const el = $("budget-categories-list");
  if (!el) return;
  el.innerHTML = "";
  cats.forEach(cat => {
    const catExps = expenses.filter(e => e.category_id === cat.id);
    const spent = catExps.reduce((s, e) => s + e.amount, 0);
    const pct   = cat.plan_monthly > 0 ? Math.min((spent / cat.plan_monthly) * 100, 100) : (spent > 0 ? 100 : 0);
    const over  = cat.plan_monthly > 0 && spent > cat.plan_monthly;
    const row = document.createElement("div");
    row.className = "budget-cat-row";
    row.innerHTML = `
      <span class="budget-cat-emoji">${cat.emoji}</span>
      <span class="budget-cat-name budget-cat-clickable">${cat.name}</span>
      <div class="budget-cat-bar-wrap"><div class="budget-cat-bar ${over ? "over" : ""}" style="width:${pct}%"></div></div>
      <span class="budget-cat-nums ${over ? "over" : ""}">${spent.toLocaleString("ru")}${cat.plan_monthly ? ` / ${cat.plan_monthly.toLocaleString("ru")}` : ""}</span>
      <button class="budget-cat-delete" data-id="${cat.id}">×</button>`;

    // Клик по названию — показываем детали расходов в этой категории
    row.querySelector(".budget-cat-clickable").addEventListener("click", () => {
      showCategoryDetail(cat, catExps);
    });

    row.querySelector(".budget-cat-delete").addEventListener("click", async () => {
      try { await apiFetch(`/budget/categories/${cat.id}`, { method: "DELETE" }); loadBudget(); } catch {}
    });
    el.appendChild(row);
  });
}

function showCategoryDetail(cat, expenses) {
  const existing = document.querySelector(".cat-detail-overlay");
  if (existing) existing.remove();

  const overlay = document.createElement("div");
  overlay.className = "cat-detail-overlay";

  const sorted = [...expenses].sort((a, b) => b.amount - a.amount);
  const total  = sorted.reduce((s, e) => s + e.amount, 0);

  overlay.innerHTML = `
    <div class="cat-detail-modal">
      <div class="cat-detail-head">
        <div>
          <div class="cat-detail-title">${cat.emoji} ${cat.name}</div>
          <div class="cat-detail-meta">${sorted.length} операций · ${total.toLocaleString("ru")} ₽</div>
        </div>
        <button class="import-modal-close" id="cat-detail-close">×</button>
      </div>
      <div class="cat-detail-list">
        ${sorted.length === 0
          ? `<div style="font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3);padding:16px 0">нет операций в этом месяце</div>`
          : sorted.map(e => {
              const [y,m,d] = e.date.split("-");
              return `<div class="cat-detail-row">
                <span class="cat-detail-date">${d}.${m}</span>
                <span class="cat-detail-note">${e.note || "расход"}</span>
                <span class="cat-detail-amt">${e.amount.toLocaleString("ru")} ₽</span>
              </div>`;
            }).join("")
        }
      </div>
    </div>`;

  overlay.querySelector("#cat-detail-close").addEventListener("click", () => overlay.remove());
  overlay.addEventListener("click", e => { if (e.target === overlay) overlay.remove(); });
  document.body.appendChild(overlay);
}

function renderBudgetExpenses(expenses, cats) {
  const el = $("budget-expenses-list");
  if (!el) return;
  el.innerHTML = "";
  if (!expenses.length) {
    el.innerHTML = `<div style="font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3);padding:8px 0">нет расходов</div>`;
    return;
  }
  expenses.forEach(exp => {
    const dt = new Date(String(exp.date).slice(0,10) + "T00:00:00");
    const row = document.createElement("div");
    row.className = "budget-exp-row";
    row.dataset.expId = exp.id;
    row.innerHTML = `
      <span class="budget-exp-date">${dt.getDate()}.${String(dt.getMonth()+1).padStart(2,"0")}</span>
      <div class="budget-exp-body">
        <div class="budget-exp-note">${exp.note || "расход"}</div>
        ${exp.cat_name ? `<div class="budget-exp-cat">${exp.cat_emoji || ""} ${exp.cat_name}</div>` : ""}
      </div>
      <span class="budget-exp-amount">${exp.amount.toLocaleString("ru")} ₽</span>
      <button class="budget-exp-edit" title="Редактировать">✏️</button>
      <button class="budget-exp-delete" data-id="${exp.id}">×</button>`;

    row.querySelector(".budget-exp-delete").addEventListener("click", async () => {
      try { await apiFetch(`/budget/expenses/${exp.id}`, { method: "DELETE" }); row.remove(); } catch {}
    });

    row.querySelector(".budget-exp-edit").addEventListener("click", () => {
      openBudgetExpEdit(row, exp, cats);
    });

    el.appendChild(row);
  });
}

function openBudgetExpEdit(row, exp, cats) {
  // Inline edit form replaces the row
  const catOpts = cats.map(c =>
    `<option value="${c.id}" ${c.id === exp.category_id ? "selected" : ""}>${c.emoji} ${c.name}</option>`
  ).join("");
  const [y, m, d] = String(exp.date).slice(0,10).split("-");

  const form = document.createElement("div");
  form.className = "budget-exp-edit-form";
  form.innerHTML = `
    <input class="nb-inline-input sm"  id="bee-amt"      type="number" min="1" value="${exp.amount}" placeholder="Сумма ₽" />
    <input class="nb-inline-input md"  id="bee-merchant" value="${exp.merchant || ""}" placeholder="Место / заведение…" />
    <input class="nb-inline-input md"  id="bee-note"     value="${exp.note || ""}" placeholder="Дополнение…" />
    <select class="nb-inline-select"   id="bee-cat"><option value="">— категория —</option>${catOpts}</select>
    <input class="nb-inline-input sm"  id="bee-date" type="date" value="${y}-${m}-${d}" />
    <button class="nb-inline-btn" id="bee-save">Сохранить</button>
    <button class="nb-inline-btn" id="bee-cancel" style="background:transparent;color:var(--ink-2);border:1px solid var(--rule)">Отмена</button>`;

  row.style.display = "none";
  row.parentNode.insertBefore(form, row.nextSibling);

  form.querySelector("#bee-cancel").addEventListener("click", () => {
    form.remove(); row.style.display = "";
  });

  form.querySelector("#bee-save").addEventListener("click", async () => {
    const amount      = parseInt(form.querySelector("#bee-amt").value);
    const merchant    = form.querySelector("#bee-merchant").value.trim() || null;
    const note        = form.querySelector("#bee-note").value.trim();
    const category_id = form.querySelector("#bee-cat").value ? parseInt(form.querySelector("#bee-cat").value) : null;
    const date        = form.querySelector("#bee-date").value;
    if (!amount) return;
    try {
      await apiFetch(`/budget/expenses/${exp.id}`, {
        method: "PATCH",
        body: JSON.stringify({ amount, note, category_id, date, merchant }),
      });
      form.remove();
      loadBudget();
    } catch { form.remove(); row.style.display = ""; }
  });

  form.addEventListener("keydown", e => {
    if (e.key === "Escape") { form.remove(); row.style.display = ""; }
    if (e.key === "Enter")  form.querySelector("#bee-save").click();
  });

  form.querySelector("#bee-amt").focus();
}

// ─── Модал добавления траты ───────────────────────────────────────────────────
function openExpenseModal(prefillCatId = null) {
  const modal = $("bud-expense-modal");
  if (!modal) return;
  // Дата — сегодня
  $("bm-date").value = new Date().toISOString().slice(0, 10);
  $("bm-amount").value = "";
  $("bm-merchant").value = "";
  $("bm-note").value = "";
  // Заполняем категории
  apiFetch("/budget/categories").then(cats => {
    const sel = $("bm-category");
    sel.innerHTML = `<option value="">— незапланированная —</option>` +
      cats.map(c => `<option value="${c.id}"${prefillCatId == c.id ? " selected" : ""}>${c.emoji} ${c.name}</option>`).join("");
  }).catch(() => {});
  // Заполняем события / поездки текущего месяца
  const evSel = $("bm-event");
  if (evSel) {
    evSel.innerHTML = `<option value="">— без события / поездки —</option>`;
    const { year, month } = budgetState;
    apiFetch(`/budget/events?year=${year}&month=${month}`).then(events => {
      // дети групп показываем с отступом, сами группы — как заголовок (не выбираемый — выбираем город)
      const groups = events.filter(e => e.event_type === "group");
      const childIds = new Set(events.filter(e => e.parent_id).map(e => e.id));
      const singles = events.filter(e => e.event_type !== "group" && !e.parent_id);
      let html = "";
      for (const g of groups) {
        const kids = events.filter(e => e.parent_id === g.id);
        html += `<optgroup label="${g.emoji} ${g.name}">` +
          kids.map(k => `<option value="${k.id}">${k.emoji} ${k.name}</option>`).join("") +
          `</optgroup>`;
      }
      for (const e of singles) {
        html += `<option value="${e.id}">${e.emoji} ${e.name}</option>`;
      }
      evSel.innerHTML = `<option value="">— без события / поездки —</option>` + html;
    }).catch(() => {});
  }
  modal.style.display = "flex";
  setTimeout(() => $("bm-amount").focus(), 50);
}

function closeExpenseModal() {
  const modal = $("bud-expense-modal");
  if (modal) modal.style.display = "none";
}

function initExpenseModal() {
  const modal = $("bud-expense-modal");
  if (!modal || modal._init) return;
  modal._init = true;

  // Закрытие
  $("bud-modal-close").addEventListener("click", closeExpenseModal);
  modal.addEventListener("click", e => { if (e.target === modal) closeExpenseModal(); });
  document.addEventListener("keydown", e => { if (e.key === "Escape" && modal.style.display !== "none") closeExpenseModal(); });

  // Сохранить
  $("bm-submit").addEventListener("click", async () => {
    const amount = parseInt($("bm-amount").value);
    if (!amount || amount <= 0) { $("bm-amount").focus(); return; }
    const catId = $("bm-category").value ? parseInt($("bm-category").value) : null;
    const evSel = $("bm-event");
    const eventId = evSel && evSel.value ? parseInt(evSel.value) : null;
    const date = $("bm-date").value || new Date().toISOString().slice(0, 10);
    const merchant = $("bm-merchant").value.trim() || null;
    const note = $("bm-note").value.trim() || null;
    try {
      if (eventId) {
        // трата привязана к событию/поездке → в trip_expenses
        const catName = catId ? ($("bm-category").selectedOptions[0]?.textContent || "").trim() : "";
        await apiFetch(`/trips/${eventId}/expenses`, { method: "POST", body: JSON.stringify({
          amount,
          date,
          category: catName,
          note: [merchant, note].filter(Boolean).join(" · ") || "",
        })});
      } else {
        await apiFetch("/budget/expenses", { method: "POST", body: JSON.stringify({
          amount,
          merchant,
          note,
          category_id: catId,
          date,
        })});
      }
      closeExpenseModal();
      loadBudget();
    } catch {}
  });

  // Enter в полях
  ["bm-amount","bm-merchant","bm-note","bm-date"].forEach(id => {
    $(id) && $(id).addEventListener("keydown", e => { if (e.key === "Enter") $("bm-submit").click(); });
  });

  // FAB кнопка "+ трата"
  const fab = $("budget-add-expense-fab");
  if (fab && !fab._init) { fab._init = true; fab.addEventListener("click", () => openExpenseModal()); }
}

// ─── Раздел «Незапланированные» ──────────────────────────────────────────────
function renderUnplanned(expenses, cats = []) {
  const section = $("bud-unplanned-section");
  const body    = $("bud-unplanned-body");
  const total   = $("bud-unplanned-total");
  if (!section || !body) return;

  // Нерегулярные = всё, что НЕ относится к категории с планом
  const plannedIds = new Set(cats.filter(c => (c.plan_monthly || 0) > 0 || (c.plan_max || 0) > 0).map(c => c.id));
  const catMap = {}; for (const c of cats) catMap[c.id] = c;
  const unplanned = expenses.filter(e => !plannedIds.has(e.category_id));
  if (!unplanned.length) { section.style.display = "none"; return; }
  section.style.display = "";

  const sum = unplanned.reduce((s, e) => s + e.amount, 0);
  if (total) total.textContent = sum.toLocaleString("ru") + " ₽";

  // Группируем по категории (или «Без категории»)
  const byCat = {};
  for (const exp of unplanned) {
    const key = exp.category_id || 0;
    if (!byCat[key]) byCat[key] = { cat: catMap[key] || null, exps: [], total: 0 };
    byCat[key].exps.push(exp);
    byCat[key].total += exp.amount;
  }
  const groups = Object.values(byCat).sort((a, b) => b.total - a.total);

  body.innerHTML = "";
  for (const g of groups) {
    const emoji = g.cat ? g.cat.emoji : "🔸";
    const name  = g.cat ? g.cat.name : "Без категории";
    const grpEl = document.createElement("div");
    grpEl.className = "bud-unpl-cat";
    grpEl.innerHTML = `
      <div class="bud-unpl-cat-head">
        <span class="bud-unpl-cat-emoji">${emoji}</span>
        <span class="bud-unpl-cat-name">${name}</span>
        <span class="bud-unpl-cat-total">${g.total.toLocaleString("ru")} ₽</span>
      </div>`;
    g.exps.sort((a, b) => b.amount - a.amount).forEach(exp => {
      const [, mo, d] = String(exp.date).slice(0, 10).split("-");
      const row = document.createElement("div");
      row.className = "bacc-exp-row";
      const label = exp.merchant || exp.note || "расход";
      row.innerHTML = `
        <span class="bacc-exp-date">${d}.${mo}</span>
        <span class="bacc-exp-desc" title="${exp.note || ""}">${label}</span>
        <span class="bacc-exp-amt">${exp.amount.toLocaleString("ru")} ₽</span>
        <button class="bacc-exp-edit" title="Категория / правка">✏️</button>
        <button class="bacc-exp-del">×</button>`;
      row.querySelector(".bacc-exp-del").addEventListener("click", async () => {
        try { await apiFetch(`/budget/expenses/${exp.id}`, { method: "DELETE" }); loadBudget(); } catch {}
      });
      row.querySelector(".bacc-exp-edit").addEventListener("click", () => openBudgetExpEdit(row, exp, cats));
      grpEl.appendChild(row);
    });
    body.appendChild(grpEl);
  }

  // Toggle открытие/закрытие
  const toggle = $("bud-unplanned-toggle");
  if (toggle && !toggle._init) {
    toggle._init = true;
    toggle.addEventListener("click", () => {
      const open = body.style.display !== "none";
      body.style.display = open ? "none" : "";
      const ch = toggle.querySelector(".bud-unplanned-chevron");
      if (ch) ch.style.transform = open ? "" : "rotate(90deg)";
    });
  }
}

function initBudgetAddButtons() {
  initExpenseModal();

  const catBtn = $("budget-add-cat-btn");
  if (catBtn && !catBtn._init) {
    catBtn._init = true;
    catBtn.addEventListener("click", () => {
      catBtn.style.display = "none";
      const form = document.createElement("div");
      form.className = "nb-inline-form";
      // name input обёрнут в .preset-wrap для позиционирования дропдауна
      form.innerHTML = `
        <input class="nb-inline-input sm" id="bcat-emoji" placeholder="Emoji" maxlength="4" value="💰" />
        <div class="preset-wrap" style="flex:1">
          <input class="nb-inline-input lg" id="bcat-name" placeholder="Название…" style="width:100%" autocomplete="off" />
          <div class="preset-dropdown" id="bcat-dropdown" style="display:none"></div>
        </div>
        <input class="nb-inline-input sm" id="bcat-plan" placeholder="План ₽" type="number" min="0" />
        <input class="nb-inline-input sm" id="bcat-max" placeholder="Макс ₽" type="number" min="0" />
        <button class="nb-inline-btn" id="bcat-submit">Добавить</button>`;
      catBtn.parentNode.insertBefore(form, catBtn.nextSibling);
      const emojiI  = form.querySelector("#bcat-emoji");
      const nameI   = form.querySelector("#bcat-name");
      const planI   = form.querySelector("#bcat-plan");
      const maxI    = form.querySelector("#bcat-max");
      const dropdown = form.querySelector("#bcat-dropdown");

      // ── Preset dropdown logic ──────────────────────────────────
      function renderPresets(query) {
        const q = query.trim().toLowerCase();
        const filtered = q
          ? CATEGORY_PRESETS.filter(p => p.name.toLowerCase().includes(q))
          : CATEGORY_PRESETS;
        if (!filtered.length) { dropdown.style.display = "none"; return; }
        dropdown.innerHTML = filtered.map((p, i) =>
          `<div class="preset-item" data-idx="${i}" data-emoji="${p.emoji}" data-name="${p.name}">
            <span class="preset-item-emoji">${p.emoji}</span>${p.name}
          </div>`).join("");
        dropdown.style.display = "";
      }

      nameI.addEventListener("focus", () => renderPresets(nameI.value));
      nameI.addEventListener("input", () => renderPresets(nameI.value));
      nameI.addEventListener("blur", () => setTimeout(() => { dropdown.style.display = "none"; }, 200));

      dropdown.addEventListener("mousedown", e => {
        const item = e.target.closest(".preset-item");
        if (!item) return;
        emojiI.value = item.dataset.emoji;
        nameI.value  = item.dataset.name;
        dropdown.style.display = "none";
        planI.focus();
      });

      form.querySelector("#bcat-submit").addEventListener("click", async () => {
        const name = nameI.value.trim(); if (!name) return;
        try {
          await apiFetch("/budget/categories", { method: "POST", body: JSON.stringify({ name, emoji: emojiI.value || "💰", plan_monthly: parseInt(planI.value) || 0, plan_max: parseInt(maxI.value) || 0 }) });
          form.remove(); catBtn.style.display = ""; loadBudget();
        } catch {}
      });
      const cancel = () => { form.remove(); catBtn.style.display = ""; };
      form.addEventListener("keydown", e => { if (e.key === "Escape") cancel(); if (e.key === "Enter" && e.target !== nameI) form.querySelector("#bcat-submit").click(); });
    });
  }
}

document.addEventListener("click", e => {
  if (e.target.id === "budget-prev") { budgetState.month--; if (budgetState.month < 1) { budgetState.month = 12; budgetState.year--; } loadBudget(); }
  if (e.target.id === "budget-next") { budgetState.month++; if (budgetState.month > 12) { budgetState.month = 1; budgetState.year++; } loadBudget(); }
});


// ════════════════════════════════════════════════════════════════
//  ПОЕЗДКИ
// ════════════════════════════════════════════════════════════════

async function loadTrips() {
  const grid = $("trips-grid");
  if (!grid) return;
  grid.innerHTML = `<div style="font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3)">загружаем…</div>`;
  try {
    const trips = await apiFetch("/trips");
    renderTripsGrid(trips);
  } catch { grid.innerHTML = `<div style="color:var(--nb-red);font-size:13px">Ошибка загрузки</div>`; }
  initTripsAddBtn();
}

let _tripsSelectMode = false;
let _tripsSelected   = new Set();
let _allTrips        = [];

function buildTripCard(trip, selectMode = false) {
  const actual  = trip.actual_total || 0;
  const planned = trip.planned_total || 0;
  const pct     = planned > 0 ? Math.min((actual / planned) * 100, 100) : (actual > 0 ? 100 : 0);
  const over    = planned > 0 && actual > planned;
  const dateStr = trip.start_date
    ? `${String(trip.start_date).slice(0,10)}${trip.end_date ? " → " + String(trip.end_date).slice(0,10) : ""}`
    : "";
  const selected = _tripsSelected.has(trip.id);

  const card = document.createElement("div");
  card.className = `trip-card${selected ? " trip-card-selected" : ""}${selectMode ? " trip-card-selectable" : ""}`;
  card.dataset.tripId = trip.id;
  card.innerHTML = `
    ${selectMode ? `<div class="trip-card-check">${selected ? "✓" : ""}</div>` : ""}
    <div class="trip-card-emoji">${trip.emoji}</div>
    <div class="trip-card-name">${trip.name}</div>
    ${dateStr ? `<div class="trip-card-dates">${dateStr}</div>` : ""}
    ${planned ? `<div class="trip-card-budget">
      <div class="trip-card-budget-bar"><div class="trip-card-budget-fill ${over?"over":""}" style="width:${pct}%"></div></div>
      <div class="trip-card-nums"><span>${actual.toLocaleString("ru")} ₽</span><span class="tc-plan">${planned.toLocaleString("ru")} ₽</span></div>
    </div>` : ""}
    ${!selectMode ? `<button class="trip-card-delete">×</button>` : ""}`;

  if (!selectMode) {
    card.querySelector(".trip-card-delete").addEventListener("click", async e => {
      e.stopPropagation();
      if (!confirm(`Удалить «${trip.name}»?`)) return;
      try { await apiFetch(`/trips/${trip.id}`, { method: "DELETE" }); loadTrips(); } catch {}
    });
    card.addEventListener("click", () => openTripDetail(trip));
  } else {
    card.addEventListener("click", () => {
      if (_tripsSelected.has(trip.id)) _tripsSelected.delete(trip.id);
      else _tripsSelected.add(trip.id);
      renderTripsGrid(_allTrips);
      updateTripsGroupBar();
    });
  }
  return card;
}

function buildTripGroupCard(grp, kids, selectMode = false) {
  const kidsActual = kids.reduce((s, k) => s + (Number(k.actual_total) || 0), 0);
  const kidsPlan   = kids.reduce((s, k) => s + (k.planned_total || 0), 0);
  const actual     = (Number(grp.actual_total) || 0) + kidsActual;
  const plan       = grp.planned_total || kidsPlan;
  const over       = plan > 0 && actual > plan;

  const wrap = document.createElement("div");
  wrap.className = "trip-group-card";
  wrap.innerHTML = `
    <div class="trip-group-head">
      <span class="trip-group-emoji">${grp.emoji || "📁"}</span>
      <div class="trip-group-info">
        <span class="trip-group-name">${grp.name}</span>
        <span class="trip-group-meta">${kids.length} города · ${actual.toLocaleString("ru")} ₽${plan ? " / " + plan.toLocaleString("ru") + " ₽" : ""}</span>
      </div>
      <span class="trip-group-toggle">▾</span>
      <button class="trip-card-delete">×</button>
    </div>
    <div class="trip-group-children"></div>`;

  let expanded = true;
  const childrenEl = wrap.querySelector(".trip-group-children");
  const toggleEl   = wrap.querySelector(".trip-group-toggle");

  kids.forEach(kid => {
    const kidCard = buildTripCard(kid, false);
    kidCard.classList.add("trip-card-child");
    // Кнопка «убрать из группы»
    const ungBtn = document.createElement("button");
    ungBtn.className = "trip-ungroup-btn";
    ungBtn.title = "Убрать из группы";
    ungBtn.textContent = "↗";
    ungBtn.addEventListener("click", async e => {
      e.stopPropagation();
      try { await apiFetch(`/trips/${kid.id}/ungroup`, { method: "POST" }); loadTrips(); } catch {}
    });
    kidCard.appendChild(ungBtn);
    childrenEl.appendChild(kidCard);
  });

  wrap.querySelector(".trip-group-head").addEventListener("click", e => {
    if (e.target.closest(".trip-card-delete") || e.target.closest(".trip-ungroup-btn")) return;
    expanded = !expanded;
    childrenEl.style.display = expanded ? "" : "none";
    toggleEl.textContent = expanded ? "▾" : "▸";
  });

  wrap.querySelector(".trip-card-delete").addEventListener("click", async e => {
    e.stopPropagation();
    if (!confirm(`Удалить группу «${grp.name}» и разгруппировать поездки?`)) return;
    try {
      // Разгруппируем детей
      for (const kid of kids) {
        await apiFetch(`/trips/${kid.id}/ungroup`, { method: "POST" }).catch(() => {});
      }
      await apiFetch(`/trips/${grp.id}`, { method: "DELETE" });
      loadTrips();
    } catch {}
  });

  return wrap;
}

function updateTripsGroupBar() {
  let bar = document.querySelector(".trips-group-bar");
  if (!_tripsSelectMode) { if (bar) bar.remove(); return; }
  if (!bar) {
    bar = document.createElement("div");
    bar.className = "trips-group-bar";
    const grid = $("trips-grid");
    grid && grid.parentNode.insertBefore(bar, grid);
  }
  const n = _tripsSelected.size;
  bar.innerHTML = n >= 2
    ? `<span>Выбрано: ${n}</span><button class="trips-group-confirm" id="trips-group-confirm">Создать группу →</button><button class="trips-group-cancel" id="trips-group-cancel">Отмена</button>`
    : `<span>Выберите 2 или более поездок для группировки</span><button class="trips-group-cancel" id="trips-group-cancel">Отмена</button>`;

  bar.querySelector("#trips-group-cancel").addEventListener("click", () => {
    _tripsSelectMode = false; _tripsSelected.clear();
    renderTripsGrid(_allTrips); updateTripsGroupBar();
    const btn = $("trips-group-btn");
    if (btn) btn.textContent = "Сгруппировать";
  });

  const confirmBtn = bar.querySelector("#trips-group-confirm");
  if (confirmBtn) {
    confirmBtn.addEventListener("click", async () => {
      const name = prompt("Название группы:", "ЮГ 2025");
      if (!name) return;
      const ids = [..._tripsSelected];
      try {
        // Группируем попарно
        let groupId = null;
        for (let i = 1; i < ids.length; i++) {
          const body = { trip_a: groupId || ids[0], trip_b: ids[i], name: i === 1 ? name : undefined, emoji: "📁" };
          const result = await apiFetch("/trips/group", { method: "POST", body: JSON.stringify(body) });
          groupId = result.id;
        }
        _tripsSelectMode = false; _tripsSelected.clear();
        loadTrips();
      } catch {}
    });
  }
}

function renderTripsGrid(trips) {
  _allTrips = trips;
  const grid = $("trips-grid");
  if (!grid) return;
  grid.innerHTML = "";

  if (!trips.length) {
    grid.innerHTML = `<div class="trips-empty">нет поездок — добавь первую ✈️</div>`;
    return;
  }

  const groups   = trips.filter(t => t.event_type === "group");
  const singles  = trips.filter(t => t.event_type !== "group" && !t.parent_id);

  // Сначала группы
  groups.forEach(grp => {
    const kids = trips.filter(t => t.parent_id === grp.id);
    grid.appendChild(buildTripGroupCard(grp, kids, _tripsSelectMode));
  });
  // Потом одиночные
  singles.forEach(trip => {
    grid.appendChild(buildTripCard(trip, _tripsSelectMode));
  });
}

// Состояние открытой поездки
const _tripDetail = { trip: null, isGroup: false, items: [], cities: [], today: "" };

async function openTripDetail(trip) {
  const panel = $("ntab-trips");
  if (!panel) return;
  const page = panel.querySelector(".nb-page");
  const originalHTML = page.innerHTML;
  const today = new Date().toISOString().slice(0, 10);

  _tripDetail.trip = trip;
  _tripDetail.isGroup = trip.event_type === "group";
  _tripDetail.today = today;

  page.innerHTML = `
    <button class="trip-back-btn" id="trip-back">← Поездки</button>
    <div class="trip-detail-header">
      <div class="trip-detail-emoji">${trip.emoji}</div>
      <div class="trip-detail-name">${trip.name}</div>
      <div class="trip-detail-totals" id="trip-detail-totals"></div>
      <button class="trip-days-btn" id="trip-days-btn" title="Заметки по дням">📅 по дням</button>
    </div>
    <div class="trip-detail-cols-legend">
      <span class="tdc-label">категория / статья</span>
      <span class="tdc-num">план</span>
      <span class="tdc-num">макс</span>
      <span class="tdc-num">факт</span>
      <span class="tdc-x"></span>
    </div>
    <div id="trip-detail-body"></div>
    <button class="task-add-btn" id="trip-add-exp-btn"><span class="task-add-line">+ статья…</span></button>`;

  $("trip-back").addEventListener("click", () => {
    page.innerHTML = originalHTML;
    loadTrips();
    initTripsAddBtn();
  });

  await loadTripDetailItems();
  renderTripDetail();
  initTripAddExpBtn(trip.id, today);
  $("trip-days-btn").addEventListener("click", () => openTripDaysView(trip));
}

// ─── Вид «по дням» внутри вкладки Поездки (заметки + расходы по дням) ─────────
async function openTripDaysView(trip) {
  const panel = $("ntab-trips");
  if (!panel) return;
  const page = panel.querySelector(".nb-page");
  const isGroup = trip.event_type === "group";

  // Собираем список trip-id, по которым тянем расходы (группа → все города)
  let tripIds = [trip.id];
  let childList = [];
  if (isGroup) {
    const all = await apiFetch("/trips").catch(() => []);
    childList = all.filter(t => t.parent_id === trip.id);
    tripIds = childList.map(c => c.id);
    if (!tripIds.length) tripIds = [trip.id];
  }

  // Расходы по всем нужным поездкам + заметки по дням (заметки храним под id самой поездки/группы)
  const [expLists, dayNotes] = await Promise.all([
    Promise.all(tripIds.map(id =>
      apiFetch(`/trips/${id}/expenses`).then(x => x.map(e => ({ ...e, _tripId: id })))
        .catch(() => [])
    )),
    apiFetch(`/trips/${trip.id}/day-notes`).catch(() => []),
  ]);
  const expenses = expLists.flat();

  const noteMap = {};
  for (const dn of dayNotes) noteMap[String(dn.date).slice(0, 10)] = dn;

  // Уникальные дни: из расходов + диапазон поездки (и всех городов группы)
  const datesSet = new Set(expenses.map(e => String(e.date).slice(0, 10)));
  const ranges = isGroup ? childList : [trip];
  for (const r of ranges) {
    if (r.start_date && r.end_date) {
      let d = new Date(String(r.start_date).slice(0,10) + "T00:00:00");
      const end = new Date(String(r.end_date).slice(0,10) + "T00:00:00");
      while (d <= end) { datesSet.add(d.toISOString().slice(0,10)); d.setDate(d.getDate()+1); }
    } else if (r.start_date) {
      datesSet.add(String(r.start_date).slice(0,10));
    }
  }
  const dates = [...datesSet].sort();

  const actual = expenses.reduce((s, e) => s + (Number(e.amount) || 0), 0);
  const perDay = dates.length ? Math.round(actual / dates.length) : 0;
  const MONTH_NAMES = ["янв","фев","мар","апр","май","июн","июл","авг","сен","окт","ноя","дек"];

  page.innerHTML = `
    <button class="trip-back-btn" id="tdv-back">← ${trip.emoji} ${trip.name}</button>
    <div class="trip-detail-header">
      <div class="trip-detail-emoji">${trip.emoji}</div>
      <div class="trip-detail-name">${trip.name} · по дням</div>
      <div class="trip-detail-totals">
        <span class="tdt-item"><b>${actual.toLocaleString("ru")} ₽</b><i>факт</i></span>
        ${dates.length>1 ? `<span class="tdt-item"><b>${perDay.toLocaleString("ru")} ₽</b><i>в день</i></span>` : ""}
      </div>
    </div>
    <div class="evd-days-scroll"><div class="evd-days-row" id="tdv-days-row"></div></div>`;

  $("tdv-back").addEventListener("click", () => openTripDetail(trip));

  const row = $("tdv-days-row");
  for (const dateStr of dates) {
    const dt = new Date(dateStr + "T00:00:00");
    const dayExps = expenses.filter(e => String(e.date).slice(0,10) === dateStr);
    const dayTotal = dayExps.reduce((s,e) => s + (Number(e.amount)||0), 0);
    const dn = noteMap[dateStr];
    const dayTitle = dn?.title || "";
    const dayNote  = dn?.note  || "";

    const cityName = id => (childList.find(c => c.id === id)?.name) || "";

    const col = document.createElement("div");
    col.className = "evd-day-col";
    col.innerHTML = `
      <div class="evd-day-head">
        <div class="evd-day-date">${dt.getDate()} ${MONTH_NAMES[dt.getMonth()]}</div>
        ${dayTotal ? `<div class="evd-day-total">${dayTotal.toLocaleString("ru")} ₽</div>` : ""}
        <input class="evd-day-title-inp" value="${dayTitle}" placeholder="название дня…" />
      </div>
      <div class="evd-day-exps">
        ${dayExps.map(exp => `
          <div class="evd-exp-row" data-id="${exp.id}">
            <span class="evd-exp-emoji">${exp.emoji || "💸"}</span>
            <div class="evd-exp-body">
              <div class="evd-exp-note">${exp.note || exp.category || "расход"}</div>
              ${isGroup && cityName(exp._tripId) ? `<div class="evd-exp-cat">📍 ${cityName(exp._tripId)}</div>` : (exp.category ? `<div class="evd-exp-cat">${exp.category}</div>` : "")}
            </div>
            <span class="evd-exp-amt">${(Number(exp.amount)||0).toLocaleString("ru")} ₽</span>
            <button class="evd-exp-del" data-id="${exp.id}">×</button>
          </div>`).join("")}
      </div>
      <div class="evd-day-note-wrap">
        <textarea class="evd-day-note" placeholder="заметка о дне…">${dayNote}</textarea>
      </div>
      <button class="evd-day-add-btn">+ расход</button>`;

    const titleInp = col.querySelector(".evd-day-title-inp");
    const noteTA   = col.querySelector(".evd-day-note");
    const saveDayNote = async () => {
      await apiFetch(`/trips/${trip.id}/day-notes`, {
        method: "POST",
        body: JSON.stringify({ date: dateStr, title: titleInp.value.trim(), note: noteTA.value.trim() }),
      }).catch(()=>{});
    };
    titleInp.addEventListener("blur", saveDayNote);
    noteTA.addEventListener("blur", saveDayNote);

    col.querySelectorAll(".evd-exp-del").forEach(btn => {
      btn.addEventListener("click", async () => {
        try { await apiFetch(`/trip-expenses/${btn.dataset.id}`, { method: "DELETE" }); btn.closest(".evd-exp-row").remove(); } catch {}
      });
    });

    col.querySelector(".evd-day-add-btn").addEventListener("click", () => {
      // для группы добавляем расход в первый город (или саму поездку)
      const targetId = isGroup ? (tripIds[0]) : trip.id;
      openDayExpenseForm(col, targetId, dateStr, () => openTripDaysView(trip));
    });

    row.appendChild(col);
  }
}

// Загружает расходы поездки (или всех городов группы) в _tripDetail.items
async function loadTripDetailItems() {
  const trip = _tripDetail.trip;
  if (_tripDetail.isGroup) {
    const all = await apiFetch("/trips").catch(() => []);
    const kids = all.filter(t => t.parent_id === trip.id);
    _tripDetail.cities = kids.map(k => ({ id: k.id, name: k.name, emoji: k.emoji }));
    const lists = await Promise.all(kids.map(k =>
      apiFetch(`/trips/${k.id}/expenses`).then(exps =>
        exps.map(e => ({ ...e, _tripId: k.id, _city: k.name }))
      ).catch(() => [])
    ));
    _tripDetail.items = lists.flat();
  } else {
    const exps = await apiFetch(`/trips/${trip.id}/expenses`).catch(() => []);
    _tripDetail.cities = [];
    _tripDetail.items = exps.map(e => ({ ...e, _tripId: trip.id, _city: (e.city || "").trim() }));
  }
}

// ─── Рендер детального табличного вида поездки ───────────────────────────────
const _fmt = v => (v != null && v !== "" && Number(v) > 0)
  ? Number(v).toLocaleString("ru")
  : `<span class="trip-cell-empty">+</span>`;

function _sumItems(items) {
  return items.reduce((a, e) => ({
    plan: a.plan + (Number(e.planned_amount) || 0),
    max:  a.max  + (Number(e.planned_max)    || 0),
    fact: a.fact + (Number(e.amount)         || 0),
  }), { plan: 0, max: 0, fact: 0 });
}

function _tripItemRowHtml(exp) {
  const label = exp.subcategory || exp.note || exp.category || "статья";
  const dayChip = exp.day ? `<span class="trip-day-chip">${exp.day}</span>` : "";
  const ceil = Number(exp.planned_max) || Number(exp.planned_amount) || 0;
  const overCls = ceil > 0 && Number(exp.amount) > ceil ? " over" : "";
  return `<div class="trip-item-row" data-id="${exp.id}">
    <span class="trip-item-label">${exp.emoji || "•"} ${label}${dayChip}</span>
    <span class="trip-cell editable" data-id="${exp.id}" data-field="planned_amount">${_fmt(exp.planned_amount)}</span>
    <span class="trip-cell editable" data-id="${exp.id}" data-field="planned_max">${_fmt(exp.planned_max)}</span>
    <span class="trip-cell editable${overCls}" data-id="${exp.id}" data-field="amount">${_fmt(exp.amount)}</span>
    <button class="trip-item-del" data-id="${exp.id}" title="Удалить">×</button>
  </div>`;
}

function _tripCatBlockHtml(catName, emoji, items) {
  const s = _sumItems(items);
  const overCls = s.max > 0 && s.fact > s.max ? " over" : "";
  const _key = e => (Number(e.amount) || Number(e.planned_amount) || Number(e.planned_max) || 0);
  const rows = [...items].sort((a, b) => _key(b) - _key(a)).map(_tripItemRowHtml).join("");
  return `<div class="trip-cat-block">
    <div class="trip-cat-head">
      <span class="trip-cat-name">${emoji || "📦"} ${catName || "Без категории"}</span>
      <span class="trip-cell sub">${_fmt(s.plan)}</span>
      <span class="trip-cell sub">${_fmt(s.max)}</span>
      <span class="trip-cell sub${overCls}">${_fmt(s.fact)}</span>
      <span class="trip-x"></span>
    </div>
    ${rows}
  </div>`;
}

// Группировка items по категории (с сохранением emoji первого вхождения)
function _groupByCategory(items) {
  const map = new Map();
  for (const e of items) {
    const key = (e.category || "").trim() || "—";
    if (!map.has(key)) map.set(key, { name: key === "—" ? "Без категории" : key, emoji: e.emoji || "", items: [] });
    map.get(key).items.push(e);
  }
  return [...map.values()].sort((a, b) => {
    const sa = _sumItems(a.items), sb = _sumItems(b.items);
    return (sb.fact || sb.plan || sb.max) - (sa.fact || sa.plan || sa.max);
  });
}

function renderTripDetail() {
  const body = $("trip-detail-body");
  if (!body) return;
  const items = _tripDetail.items;

  // Итоги в шапке
  const tot = _sumItems(items);
  const totEl = $("trip-detail-totals");
  if (totEl) {
    const overFact = tot.max > 0 && tot.fact > tot.max;
    totEl.innerHTML = `
      <span class="tdt-item"><b>${tot.plan.toLocaleString("ru")} ₽</b><i>план</i></span>
      <span class="tdt-item"><b>${tot.max.toLocaleString("ru")} ₽</b><i>макс</i></span>
      <span class="tdt-item${overFact ? " over" : ""}"><b>${tot.fact.toLocaleString("ru")} ₽</b><i>факт</i></span>`;
  }

  if (!items.length) {
    body.innerHTML = `<div class="trip-detail-empty">пока нет статей — добавь первую ниже ↓</div>`;
    return;
  }

  let html = "";

  if (_tripDetail.isGroup) {
    // Сводка по категориям по всей поездке
    const overview = _groupByCategory(items);
    html += `<div class="trip-overview">
      <div class="trip-section-title">Сводка по категориям · вся поездка</div>
      ${overview.map(g => {
        const s = _sumItems(g.items);
        const overCls = s.max > 0 && s.fact > s.max ? " over" : "";
        return `<div class="trip-cat-head plain">
          <span class="trip-cat-name">${g.emoji || "📦"} ${g.name}</span>
          <span class="trip-cell sub">${_fmt(s.plan)}</span>
          <span class="trip-cell sub">${_fmt(s.max)}</span>
          <span class="trip-cell sub${overCls}">${_fmt(s.fact)}</span>
          <span class="trip-x"></span>
        </div>`;
      }).join("")}
    </div>`;

    // По городам
    for (const city of _tripDetail.cities) {
      const cityItems = items.filter(e => e._tripId === city.id);
      const cs = _sumItems(cityItems);
      const overCls = cs.max > 0 && cs.fact > cs.max ? " over" : "";
      html += `<div class="trip-city-block">
        <div class="trip-city-head">
          <span class="trip-city-name">${city.emoji || "📍"} ${city.name}</span>
          <span class="trip-cell sub">${_fmt(cs.plan)}</span>
          <span class="trip-cell sub">${_fmt(cs.max)}</span>
          <span class="trip-cell sub${overCls}">${_fmt(cs.fact)}</span>
          <span class="trip-x"></span>
        </div>
        ${cityItems.length
          ? _groupByCategory(cityItems).map(g => _tripCatBlockHtml(g.name, g.emoji, g.items)).join("")
          : `<div class="trip-detail-empty sm">нет статей по этому городу</div>`}
      </div>`;
    }
  } else {
    // Одиночная поездка: возможна разбивка по городам внутри
    const cities = [...new Set(items.map(e => (e._city || "").trim()))];
    const useCities = cities.filter(Boolean).length > 0;
    if (useCities) {
      for (const city of cities) {
        const cityItems = items.filter(e => (e._city || "").trim() === city);
        if (city) {
          const cs = _sumItems(cityItems);
          const overCls = cs.max > 0 && cs.fact > cs.max ? " over" : "";
          html += `<div class="trip-city-head">
            <span class="trip-city-name">📍 ${city || "без города"}</span>
            <span class="trip-cell sub">${_fmt(cs.plan)}</span>
            <span class="trip-cell sub">${_fmt(cs.max)}</span>
            <span class="trip-cell sub${overCls}">${_fmt(cs.fact)}</span>
            <span class="trip-x"></span>
          </div>`;
        }
        html += _groupByCategory(cityItems).map(g => _tripCatBlockHtml(g.name, g.emoji, g.items)).join("");
      }
    } else {
      html += _groupByCategory(items).map(g => _tripCatBlockHtml(g.name, g.emoji, g.items)).join("");
    }
  }

  body.innerHTML = html;

  // Делегирование: редактирование ячеек + удаление
  body.onclick = e => {
    const cell = e.target.closest(".trip-cell.editable");
    if (cell) {
      const exp = _tripDetail.items.find(x => x.id == cell.dataset.id);
      if (exp) editTripCell(cell, exp, cell.dataset.field);
      return;
    }
    const del = e.target.closest(".trip-item-del");
    if (del) {
      const id = del.dataset.id;
      apiFetch(`/trip-expenses/${id}`, { method: "DELETE" }).then(() => {
        _tripDetail.items = _tripDetail.items.filter(x => x.id != id);
        renderTripDetail();
      }).catch(() => {});
    }
  };
}

function editTripCell(cell, exp, field) {
  const inp = document.createElement("input");
  inp.type = "number"; inp.min = "0"; inp.className = "trip-cell-input";
  inp.value = exp[field] != null ? exp[field] : "";
  cell.replaceWith(inp);
  inp.focus(); inp.select();
  let done = false;
  const save = async () => {
    if (done) return; done = true;
    const raw = inp.value.trim();
    const val = raw === "" ? null : parseInt(raw);
    try {
      await apiFetch(`/trip-expenses/${exp.id}`, { method: "PATCH", body: JSON.stringify({ [field]: val }) });
      exp[field] = val;
    } catch {}
    renderTripDetail();
  };
  inp.addEventListener("blur", save);
  inp.addEventListener("keydown", e => {
    if (e.key === "Enter") inp.blur();
    if (e.key === "Escape") { done = true; renderTripDetail(); }
  });
}

function initTripAddExpBtn(tripId, today) {
  const btn = $("trip-add-exp-btn");
  if (!btn) return;
  btn.addEventListener("click", () => {
    btn.style.display = "none";
    const isGroup = _tripDetail.isGroup;
    // Список городов (для группы — дочерние поездки)
    const cityOpts = isGroup
      ? _tripDetail.cities.map(c => `<option value="${c.id}">${c.emoji || "📍"} ${c.name}</option>`).join("")
      : "";
    const form = document.createElement("div");
    form.className = "trip-add-form";
    form.innerHTML = `
      ${isGroup ? `<select class="nb-inline-select" id="texp-city">${cityOpts}</select>` : ""}
      <input class="nb-inline-input sm" id="texp-emoji" placeholder="Emoji" maxlength="4" value="💸" />
      <div class="preset-wrap" style="flex:1;min-width:120px">
        <input class="nb-inline-input" id="texp-cat" placeholder="Категория (Еда…)" style="width:100%" autocomplete="off" />
        <div class="preset-dropdown" id="texp-dropdown" style="display:none"></div>
      </div>
      <input class="nb-inline-input" id="texp-sub" placeholder="Статья (Завтрак…)" />
      <input class="nb-inline-input sm" id="texp-day" placeholder="День / дата" />
      <input class="nb-inline-input sm" id="texp-plan" placeholder="План ₽" type="number" min="0" />
      <input class="nb-inline-input sm" id="texp-max"  placeholder="Макс ₽"  type="number" min="0" />
      <input class="nb-inline-input sm" id="texp-amt"  placeholder="Факт ₽"  type="number" min="0" />
      <button class="nb-inline-btn" id="texp-submit">Добавить</button>`;
    btn.parentNode.insertBefore(form, btn.nextSibling);
    const q = id => form.querySelector(id);
    const emojiI = q("#texp-emoji"), catI = q("#texp-cat"), subI = q("#texp-sub"),
          dayI = q("#texp-day"), planI = q("#texp-plan"), maxI = q("#texp-max"),
          amtI = q("#texp-amt"), cityI = q("#texp-city"), dropdown = q("#texp-dropdown");

    function renderTripPresets(query) {
      const qq = query.trim().toLowerCase();
      const filtered = qq ? CATEGORY_PRESETS.filter(p => p.name.toLowerCase().includes(qq)) : CATEGORY_PRESETS;
      if (!filtered.length) { dropdown.style.display = "none"; return; }
      dropdown.innerHTML = filtered.map(p =>
        `<div class="preset-item" data-emoji="${p.emoji}" data-name="${p.name}">
          <span class="preset-item-emoji">${p.emoji}</span>${p.name}</div>`).join("");
      dropdown.style.display = "";
    }
    catI.addEventListener("focus", () => renderTripPresets(catI.value));
    catI.addEventListener("input", () => renderTripPresets(catI.value));
    catI.addEventListener("blur",  () => setTimeout(() => { dropdown.style.display = "none"; }, 200));
    dropdown.addEventListener("mousedown", e => {
      const item = e.target.closest(".preset-item");
      if (!item) return;
      emojiI.value = item.dataset.emoji;
      catI.value   = item.dataset.name;
      dropdown.style.display = "none";
      subI.focus();
    });

    const submit = async () => {
      const targetTrip = isGroup ? parseInt(cityI.value) : tripId;
      if (isGroup && !targetTrip) { cityI.focus(); return; }
      const plan = parseInt(planI.value) || 0;
      const pmax = parseInt(maxI.value)  || 0;
      const fact = parseInt(amtI.value)  || 0;
      if (!plan && !pmax && !fact && !catI.value.trim() && !subI.value.trim()) return;
      try {
        await apiFetch(`/trips/${targetTrip}/expenses`, {
          method: "POST",
          body: JSON.stringify({
            amount: fact,
            planned_amount: plan || null,
            planned_max: pmax || null,
            category: catI.value.trim(),
            subcategory: subI.value.trim(),
            day: dayI.value.trim(),
            note: subI.value.trim(),
            emoji: emojiI.value || "💸",
            date: today,
          })
        });
        form.remove(); btn.style.display = "";
        await loadTripDetailItems();
        renderTripDetail();
      } catch {}
    };
    q("#texp-submit").addEventListener("click", submit);
    form.addEventListener("keydown", e => {
      if (e.key === "Escape") { form.remove(); btn.style.display = ""; }
      if (e.key === "Enter" && e.target !== catI) submit();
    });
    (isGroup ? cityI : catI).focus();
  });
}

function initTripsAddBtn() {
  // Кнопка «Сгруппировать»
  const grpBtn = $("trips-group-btn");
  if (grpBtn && !grpBtn._init) {
    grpBtn._init = true;
    grpBtn.addEventListener("click", () => {
      _tripsSelectMode = !_tripsSelectMode;
      _tripsSelected.clear();
      grpBtn.textContent = _tripsSelectMode ? "Отмена" : "Сгруппировать";
      renderTripsGrid(_allTrips);
      updateTripsGroupBar();
    });
  }

  const btn = $("trips-add-btn");
  if (!btn || btn._init) return;
  btn._init = true;
  btn.addEventListener("click", () => {
    btn.style.display = "none";
    const form = document.createElement("div");
    form.className = "nb-inline-form";
    form.innerHTML = `
      <input class="nb-inline-input sm" placeholder="Emoji" maxlength="4" value="✈️" />
      <input class="nb-inline-input lg" placeholder="Куда едем…" />
      <input class="nb-inline-input sm" type="date" title="Начало" />
      <input class="nb-inline-input sm" type="date" title="Конец" />
      <input class="nb-inline-input sm" placeholder="Бюджет ₽" type="number" min="0" />
      <button class="nb-inline-btn">Добавить</button>`;
    btn.parentNode.insertBefore(form, btn.nextSibling);
    const [emojiI, nameI, startI, endI, planI] = form.querySelectorAll("input");
    form.querySelector(".nb-inline-btn").addEventListener("click", async () => {
      const name = nameI.value.trim(); if (!name) return;
      try {
        await apiFetch("/trips", { method: "POST", body: JSON.stringify({ name, emoji: emojiI.value||"✈️", start_date: startI.value||null, end_date: endI.value||null, planned_total: parseInt(planI.value)||0 }) });
        form.remove(); btn.style.display = ""; loadTrips();
      } catch {}
    });
    form.addEventListener("keydown", e => { if (e.key === "Escape") { form.remove(); btn.style.display = ""; } });
  });
}


// ════════════════════════════════════════════════════════════════
//  СПИСКИ
// ════════════════════════════════════════════════════════════════

let _activeListId = null;

async function loadLists() {
  const nav = $("lists-nav");
  if (!nav) return;
  nav.innerHTML = `<div style="font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3)">загружаем…</div>`;
  try {
    const lists = await apiFetch("/notebook/lists");
    renderListsNav(lists);
    if (lists.length && !_activeListId) openList(lists[0]);
    else if (_activeListId) { const l = lists.find(x => x.id === _activeListId); if (l) openList(l); }
  } catch { nav.innerHTML = `<div style="color:var(--nb-red);font-size:13px">Ошибка</div>`; }
  initListsAddBtn();
}

function renderListsNav(lists) {
  const nav = $("lists-nav");
  nav.innerHTML = "";
  lists.forEach(lst => {
    const items = document.querySelectorAll(`.list-item-row[data-list="${lst.id}"]`).length;
    const btn = document.createElement("button");
    btn.className = `list-nav-item${lst.id === _activeListId ? " active" : ""}`;
    btn.innerHTML = `<span class="list-nav-item-emoji">${lst.emoji}</span><span class="list-nav-item-name">${lst.name}</span><button class="list-nav-delete" data-id="${lst.id}">×</button>`;
    btn.querySelector(".list-nav-delete").addEventListener("click", async e => {
      e.stopPropagation();
      try { await apiFetch(`/notebook/lists/${lst.id}`, { method: "DELETE" }); if (_activeListId === lst.id) { _activeListId = null; $("list-detail").innerHTML = `<p class="nb-meta-line" style="opacity:.45;margin-top:40px">← выбери список</p>`; } loadLists(); } catch {}
    });
    btn.addEventListener("click", () => openList(lst));
    nav.appendChild(btn);
  });
}

async function openList(lst) {
  _activeListId = lst.id;
  document.querySelectorAll(".list-nav-item").forEach(b => b.classList.toggle("active", parseInt(b.querySelector(".list-nav-delete").dataset.id) === lst.id));
  const detail = $("list-detail");
  detail.innerHTML = `
    <div class="list-detail-header">
      <span class="list-detail-emoji">${lst.emoji}</span>
      <span class="list-detail-name">${lst.name}</span>
    </div>
    <div class="nb-ruled-area" style="padding-right:8px">
      <div id="list-items-container"></div>
      <button class="task-add-btn" id="list-add-item-btn"><span class="task-add-line">+ добавить…</span></button>
    </div>`;
  try {
    const items = await apiFetch(`/notebook/lists/${lst.id}/items`);
    renderListItems(items, lst.id);
  } catch {}
  initListItemAddBtn(lst.id);
}

function renderListItems(items, listId) {
  const cont = $("list-items-container");
  if (!cont) return;
  cont.innerHTML = "";
  items.forEach(item => cont.appendChild(buildListItemEl(item, listId)));
}

function buildListItemEl(item, listId) {
  const row = document.createElement("div");
  row.className = `list-item-row${item.done ? " done" : ""}`;
  row.dataset.list = listId;
  row.innerHTML = `
    <button class="list-item-cb"></button>
    <span class="list-item-title">${item.title}</span>
    <button class="list-item-delete">×</button>`;
  row.querySelector(".list-item-cb").addEventListener("click", async () => {
    const newDone = !item.done;
    item.done = newDone;
    row.className = `list-item-row${newDone ? " done" : ""}`;
    try { await apiFetch(`/notebook/list-items/${item.id}?done=${newDone}`, { method: "PATCH" }); } catch { item.done = !newDone; row.className = `list-item-row${item.done ? " done" : ""}`; }
  });
  row.querySelector(".list-item-delete").addEventListener("click", async () => {
    try { await apiFetch(`/notebook/list-items/${item.id}`, { method: "DELETE" }); row.remove(); } catch {}
  });
  return row;
}

function initListItemAddBtn(listId) {
  const btn = $("list-add-item-btn");
  if (!btn) return;
  btn.addEventListener("click", () => {
    btn.style.display = "none";
    const form = document.createElement("div");
    form.className = "task-add-form";
    form.innerHTML = `<input class="task-add-input" placeholder="Новый пункт…" />`;
    btn.parentNode.insertBefore(form, btn.nextSibling);
    const inp = form.querySelector("input");
    inp.focus();
    const submit = async () => {
      const title = inp.value.trim();
      form.remove(); btn.style.display = "";
      if (!title) return;
      try {
        const item = await apiFetch(`/notebook/lists/${listId}/items`, { method: "POST", body: JSON.stringify({ title }) });
        $("list-items-container").appendChild(buildListItemEl(item, listId));
      } catch {}
    };
    inp.addEventListener("keydown", e => { if (e.key === "Enter") submit(); if (e.key === "Escape") { form.remove(); btn.style.display = ""; } });
    inp.addEventListener("blur", () => setTimeout(() => { if (form.parentNode) { form.remove(); btn.style.display = ""; } }, 180));
  });
}

function initListsAddBtn() {
  const btn = $("lists-add-btn");
  if (!btn || btn._init) return;
  btn._init = true;
  btn.addEventListener("click", () => {
    btn.style.display = "none";
    const form = document.createElement("div");
    form.className = "nb-inline-form";
    form.innerHTML = `<input class="nb-inline-input sm" placeholder="Emoji" maxlength="4" value="📋" /><input class="nb-inline-input lg" placeholder="Название списка…" /><button class="nb-inline-btn">Создать</button>`;
    btn.parentNode.insertBefore(form, btn.nextSibling);
    const [emojiI, nameI] = form.querySelectorAll("input");
    form.querySelector(".nb-inline-btn").addEventListener("click", async () => {
      const name = nameI.value.trim(); if (!name) return;
      try { await apiFetch("/notebook/lists", { method: "POST", body: JSON.stringify({ name, emoji: emojiI.value||"📋" }) }); form.remove(); btn.style.display = ""; loadLists(); } catch {}
    });
    form.addEventListener("keydown", e => { if (e.key === "Escape") { form.remove(); btn.style.display = ""; } });
  });
}


// ════════════════════════════════════════════════════════════════
//  ЗАМЕТКИ
// ════════════════════════════════════════════════════════════════

const NOTE_COLORS = { yellow: "#fff3b0", green: "#d4e8c2", blue: "#c2d8e8", pink: "#f0d0cc" };

async function loadNotes() {
  const grid = $("notes-grid");
  if (!grid) return;
  grid.innerHTML = `<div style="font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3)">загружаем…</div>`;
  try {
    const notes = await apiFetch("/notebook/notes");
    renderNotesGrid(notes);
  } catch { grid.innerHTML = ""; }
  initNotesAddBtn();
}

function renderNotesGrid(notes) {
  const grid = $("notes-grid");
  if (!grid) return;
  grid.innerHTML = "";
  if (!notes.length) { grid.innerHTML = `<div style="font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3)">нет заметок — нажми + заметка</div>`; return; }
  notes.forEach(note => grid.appendChild(buildNoteCard(note)));
}

function buildNoteCard(note) {
  const card = document.createElement("div");
  card.className = `note-card color-${note.color || "yellow"}`;
  card.innerHTML = `
    <input class="note-title-input" placeholder="Заголовок…" value="${(note.title||"").replace(/"/g,"&quot;")}" />
    <textarea class="note-body-input" placeholder="Напиши что-нибудь…">${note.body||""}</textarea>
    <div class="note-footer">
      <div class="note-color-btns">
        ${Object.entries(NOTE_COLORS).map(([k,v]) => `<div class="note-color-btn ${note.color===k?"active":""}" data-color="${k}" style="background:${v}"></div>`).join("")}
      </div>
      <button class="note-delete-btn">🗑</button>
    </div>`;
  let saveTimer;
  const save = (fields) => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(async () => {
      try { await apiFetch(`/notebook/notes/${note.id}`, { method: "PATCH", body: JSON.stringify(fields) }); } catch {}
    }, 800);
  };
  card.querySelector(".note-title-input").addEventListener("input", e => { note.title = e.target.value; save({ title: note.title, body: note.body }); });
  card.querySelector(".note-body-input").addEventListener("input", e => { note.body = e.target.value; save({ title: note.title, body: note.body }); });
  card.querySelectorAll(".note-color-btn").forEach(btn => {
    btn.addEventListener("click", async () => {
      const color = btn.dataset.color;
      note.color = color;
      card.className = `note-card color-${color}`;
      card.querySelectorAll(".note-color-btn").forEach(b => b.classList.toggle("active", b.dataset.color === color));
      try { await apiFetch(`/notebook/notes/${note.id}`, { method: "PATCH", body: JSON.stringify({ color }) }); } catch {}
    });
  });
  card.querySelector(".note-delete-btn").addEventListener("click", async () => {
    try { await apiFetch(`/notebook/notes/${note.id}`, { method: "DELETE" }); card.remove(); } catch {}
  });
  return card;
}

function initNotesAddBtn() {
  const btn = $("notes-add-btn");
  if (!btn || btn._init) return;
  btn._init = true;
  btn.addEventListener("click", async () => {
    try {
      const note = await apiFetch("/notebook/notes", { method: "POST", body: JSON.stringify({ body: "", title: "", color: "yellow" }) });
      const grid = $("notes-grid");
      if (grid.querySelector(".note-card")) {
        grid.insertBefore(buildNoteCard(note), grid.firstChild);
      } else {
        grid.innerHTML = "";
        grid.appendChild(buildNoteCard(note));
      }
    } catch {}
  });
}


// ════════════════════════════════════════════════════════════════
//  ИМПОРТ ВЫПИСКИ ИЗ БАНКА
// ════════════════════════════════════════════════════════════════

// Все категории-пресеты для select в таблице ревью
const IMPORT_CATS = [
  { emoji: "🍕", name: "Доставка еды" },
  { emoji: "🚕", name: "Такси" },
  { emoji: "🛴", name: "Самокаты" },
  { emoji: "💛", name: "Яндекс" },
  { emoji: "✈️", name: "Билеты / Транспорт" },
  { emoji: "🍺", name: "Алкоголь" },
  { emoji: "🍸", name: "Бары" },
  { emoji: "🍽️", name: "Кафе / Ресторан" },
  { emoji: "🛒", name: "Продукты" },
  { emoji: "⛽", name: "АЗС / Топливо" },
  { emoji: "💊", name: "Аптека" },
  { emoji: "🏋️", name: "Спорт" },
  { emoji: "👗", name: "Одежда / Шопинг" },
  { emoji: "🎢", name: "Развлечения" },
  { emoji: "📱", name: "Связь" },
  { emoji: "💸", name: "Переводы" },
  { emoji: "💰", name: "Другое" },
];

function initBudgetImport() {
  const fileInput = $("budget-import-file");
  if (!fileInput || fileInput._init) return;
  fileInput._init = true;

  fileInput.addEventListener("change", async () => {
    const file = fileInput.files[0];
    if (!file) return;
    fileInput.value = ""; // reset so same file can be re-selected

    // Показываем оверлей «загружаем…»
    const overlay = document.createElement("div");
    overlay.className = "import-overlay";
    overlay.innerHTML = `
      <div class="import-modal" style="align-items:center;justify-content:center;padding:40px;gap:12px">
        <div style="font-size:32px">📂</div>
        <div style="font-family:'JetBrains Mono',monospace;font-size:13px;color:var(--ink-3)">Читаем выписку…</div>
      </div>`;
    document.body.appendChild(overlay);

    try {
      const formData = new FormData();
      formData.append("file", file);
      const resp = await fetch(`${API}/budget/parse-statement`, {
        method: "POST",
        body: formData,
      });
      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}));
        throw new Error(err.detail || "Ошибка сервера");
      }
      const { transactions } = await resp.json();
      overlay.remove();

      if (!transactions || !transactions.length) {
        showImportEmpty();
        return;
      }
      showImportReview(transactions);
    } catch (e) {
      overlay.remove();
      alert("Не удалось разобрать файл: " + e.message);
    }
  });
}

function showImportEmpty() {
  const overlay = document.createElement("div");
  overlay.className = "import-overlay";
  overlay.innerHTML = `
    <div class="import-modal" style="align-items:center;justify-content:center;padding:40px;gap:12px">
      <div style="font-size:32px">🤷</div>
      <div style="font-family:'Fraunces',Georgia,serif;font-size:16px;color:var(--ink)">Транзакции не найдены</div>
      <div style="font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--ink-3)">Убедись что это выписка Озон Банка в формате PDF</div>
      <button class="import-cancel-btn" style="margin-top:8px">Закрыть</button>
    </div>`;
  overlay.querySelector("button").addEventListener("click", () => overlay.remove());
  overlay.addEventListener("click", e => { if (e.target === overlay) overlay.remove(); });
  document.body.appendChild(overlay);
}

function showImportReview(transactions) {
  // Строим select options один раз
  const catOptions = IMPORT_CATS.map(c =>
    `<option value="${c.name}" data-emoji="${c.emoji}">${c.emoji} ${c.name}</option>`
  ).join("");

  const overlay = document.createElement("div");
  overlay.className = "import-overlay";

  // Считаем общую сумму
  const total = transactions.reduce((s, t) => s + t.amount, 0);

  overlay.innerHTML = `
    <div class="import-modal">
      <div class="import-modal-head">
        <div>
          <div class="import-modal-title">Импорт выписки</div>
          <div class="import-modal-meta">Найдено ${transactions.length} операций · ${total.toLocaleString("ru")} ₽</div>
        </div>
        <button class="import-modal-close" id="import-close">×</button>
      </div>
      <div class="import-table-wrap">
        <table class="import-table">
          <thead>
            <tr>
              <th><input type="checkbox" id="import-check-all" checked style="cursor:pointer;accent-color:var(--terracotta)" /></th>
              <th>Дата</th>
              <th>Описание</th>
              <th>Категория</th>
              <th>Сумма</th>
            </tr>
          </thead>
          <tbody id="import-tbody"></tbody>
        </table>
      </div>
      <div class="import-modal-foot">
        <div class="import-selected-info" id="import-info">Выбрано: ${transactions.length} / ${transactions.length}</div>
        <div style="display:flex;gap:10px">
          <button class="import-cancel-btn" id="import-cancel">Отмена</button>
          <button class="import-save-btn" id="import-save">Сохранить выбранные</button>
        </div>
      </div>
    </div>`;

  document.body.appendChild(overlay);

  const tbody = overlay.querySelector("#import-tbody");

  // Рендерим строки
  transactions.forEach((t, idx) => {
    const tr = document.createElement("tr");
    tr.dataset.idx = idx;

    // Форматируем дату: YYYY-MM-DD → DD.MM
    const [y, mo, d] = t.date.split("-");
    const dateDisplay = `${d}.${mo}`;

    tr.innerHTML = `
      <td><input type="checkbox" class="import-cb" checked data-idx="${idx}" /></td>
      <td style="white-space:nowrap;font-family:'JetBrains Mono',monospace;font-size:12px">${dateDisplay}</td>
      <td><div class="import-desc" title="${t.description}">${t.description}</div></td>
      <td>
        <div class="import-cat-wrap">
          <span class="import-cat-emoji" id="import-emoji-${idx}">${t.emoji}</span>
          <select class="import-cat-select" id="import-cat-${idx}">
            ${catOptions}
          </select>
        </div>
      </td>
      <td class="import-amount">${Math.round(t.amount).toLocaleString("ru")} ₽</td>`;

    // Ставим текущую категорию как selected
    const sel = tr.querySelector(`#import-cat-${idx}`);
    [...sel.options].forEach(opt => {
      if (opt.value === t.category) opt.selected = true;
    });

    // При смене категории — обновляем emoji и данные
    sel.addEventListener("change", () => {
      const chosen = IMPORT_CATS.find(c => c.name === sel.value);
      if (chosen) {
        tr.querySelector(`#import-emoji-${idx}`).textContent = chosen.emoji;
        transactions[idx].emoji    = chosen.emoji;
        transactions[idx].category = chosen.name;
      }
    });

    tbody.appendChild(tr);
  });

  // Чекбоксы
  const updateInfo = () => {
    const checked = overlay.querySelectorAll(".import-cb:checked").length;
    overlay.querySelector("#import-info").textContent =
      `Выбрано: ${checked} / ${transactions.length}`;
    overlay.querySelector("#import-save").disabled = checked === 0;
  };

  overlay.querySelector("#import-check-all").addEventListener("change", e => {
    overlay.querySelectorAll(".import-cb").forEach(cb => {
      cb.checked = e.target.checked;
      cb.closest("tr").classList.toggle("skip-row", !e.target.checked);
    });
    updateInfo();
  });

  overlay.addEventListener("change", e => {
    if (e.target.classList.contains("import-cb")) {
      e.target.closest("tr").classList.toggle("skip-row", !e.target.checked);
      updateInfo();
    }
  });

  // Закрытие
  const close = () => overlay.remove();
  overlay.querySelector("#import-close").addEventListener("click", close);
  overlay.querySelector("#import-cancel").addEventListener("click", close);
  overlay.addEventListener("click", e => { if (e.target === overlay) close(); });

  // Сохранение
  overlay.querySelector("#import-save").addEventListener("click", async () => {
    const selected = [];
    overlay.querySelectorAll(".import-cb:checked").forEach(cb => {
      const idx = parseInt(cb.dataset.idx);
      selected.push(transactions[idx]);
    });
    if (!selected.length) return;

    overlay.querySelector("#import-save").disabled = true;
    overlay.querySelector("#import-save").textContent = "Сохраняем…";

    try {
      const res = await apiFetch("/budget/import", {
        method: "POST",
        body: JSON.stringify({ transactions: selected }),
      });
      close();
      loadBudget();
      // Небольшое уведомление
      const toast = document.createElement("div");
      toast.style.cssText = `position:fixed;bottom:24px;right:24px;z-index:600;background:var(--terracotta);color:#fff;padding:12px 20px;border-radius:10px;font-family:'Fraunces',Georgia,serif;font-size:14px;box-shadow:0 4px 20px rgba(0,0,0,.2)`;
      toast.textContent = `✅ Сохранено ${res.saved} операций`;
      document.body.appendChild(toast);
      setTimeout(() => toast.remove(), 3000);
    } catch {
      overlay.querySelector("#import-save").disabled = false;
      overlay.querySelector("#import-save").textContent = "Сохранить выбранные";
      alert("Ошибка при сохранении");
    }
  });
}

// Инициализируем импорт когда открываем вкладку Бюджет
const _origLoadBudget = loadBudget;
loadBudget = async function() {
  await _origLoadBudget();
  initBudgetImport();
};

function _showBudgetToast(msg) {
  const t = document.createElement("div");
  t.style.cssText = "position:fixed;bottom:24px;right:24px;z-index:600;background:var(--terracotta);color:#fff;padding:12px 20px;border-radius:10px;font-family:'Fraunces',Georgia,serif;font-size:14px;box-shadow:0 4px 20px rgba(0,0,0,.2)";
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3500);
}
// ════════════════════════════════════════════════════════════════
//  🎮 ИГРЫ — ШАХМАТЫ
// ════════════════════════════════════════════════════════════════

const CHESS_PIECES = {
  wK: '♔', wQ: '♕', wR: '♖', wB: '♗', wN: '♘', wP: '♙',
  bK: '♚', bQ: '♛', bR: '♜', bB: '♝', bN: '♞', bP: '♟',
};

const _chess = {
  game: null,
  engine: null,
  ws: null,
  myColor: null,
  selected: null,
  legalSquares: [],
  myUserId: null,
  pendingPromotion: null,
  _gamePoller: null,
  _lastFen: null,
  _lastWsMsgTime: 0,  // время последнего WS-сообщения (для умного polling)
  isLocal: false,
};

function _chessApiBase() {
  return (typeof API_BASE_URL !== "undefined" ? API_BASE_URL : "") || "";
}
function _chessWsBase() {
  const base = _chessApiBase();
  if (base.startsWith("http")) return base.replace(/^http/, "ws");
  const loc = window.location;
  return (loc.protocol === "https:" ? "wss" : "ws") + "://" + loc.host;
}
function _showChessScreen(id) {
  ["games-lobby","chess-entry","chess-waiting","chess-game"].forEach(s => {
    const el = $(s); if (el) el.style.display = s === id ? "" : "none";
  });
}

function initGamesMode() {
  const uid = state.user && state.user.id;
  if (!uid) return;
  // Полный сброс состояния при каждом заходе на вкладку
  chessDisconnect();
  _chess.myUserId = uid;
  _showChessScreen("games-lobby");
  const card = $("chess-open-card");
  if (card && !card._init) { card._init = true; card.addEventListener("click", openChessEntry); }
  const durakCard = $("durak-open-card");
  if (durakCard && !durakCard._init) {
    durakCard._init = true;
    durakCard.addEventListener("click", function() { initDurakMode(); });
  }
  const unoCard = $("uno-open-card");
  if (unoCard && !unoCard._init) {
    unoCard._init = true;
    unoCard.addEventListener("click", function() { initUnoMode(); });
  }
  const g101Card = $("g101-open-card");
  if (g101Card && !g101Card._init) {
    g101Card._init = true;
    g101Card.addEventListener("click", function() { initG101Mode(); });
  }
  loadGamesHistory(uid);
}

async function loadGamesHistory(uid) {
  try {
    const history = await apiFetch("/chess/history?user_id=" + uid);
    const wrap = $("games-history-wrap"); const list = $("games-history-list");
    if (!wrap || !list || !history.length) return;
    wrap.style.display = "";
    list.innerHTML = history.slice(0, 5).map(g => {
      const isW = g.white_user_id === uid;
      const opp = isW ? (g.black_name || "?") : (g.white_name || "?");
      const res = g.winner === "draw" ? "Ничья"
        : ((g.winner === "white" && isW) || (g.winner === "black" && !isW)) ? "Победа 🏆" : "Поражение";
      const cls = res === "Победа 🏆" ? "win" : res === "Ничья" ? "draw" : "loss";
      return '<div class="games-hist-row"><span class="games-hist-vs">vs ' + opp + '</span>'
        + '<span class="games-hist-color">' + (isW ? "белыми" : "чёрными") + '</span>'
        + '<span class="games-hist-result ' + cls + '">' + res + '</span></div>';
    }).join("");
  } catch(e) {}
}

function openChessEntry() {
  _showChessScreen("chess-entry");
  initChessEntry();
  loadChessStats();
}

function initChessEntry() {
  const backBtn = $("chess-back-to-lobby");
  if (backBtn && !backBtn._init) {
    backBtn._init = true;
    backBtn.addEventListener("click", function() { _showChessScreen("games-lobby"); });
  }
  document.querySelectorAll(".chess-color-btn").forEach(function(btn) {
    btn.addEventListener("click", function() {
      document.querySelectorAll(".chess-color-btn").forEach(function(b) { b.classList.remove("active"); });
      btn.classList.add("active");
    });
  });
  const createBtn = $("chess-create-btn");
  if (createBtn && !createBtn._init) { createBtn._init = true; createBtn.addEventListener("click", chessCreateGame); }
  const joinBtn = $("chess-join-btn");
  if (joinBtn && !joinBtn._init) { joinBtn._init = true; joinBtn.addEventListener("click", chessJoinGame); }
  const joinInput = $("chess-join-input");
  if (joinInput && !joinInput._init) {
    joinInput._init = true;
    joinInput.addEventListener("keydown", function(e) { if (e.key === "Enter") chessJoinGame(); });
    joinInput.addEventListener("input", function() { joinInput.value = joinInput.value.toUpperCase(); });
  }
  const localBtn = $("chess-local-btn");
  if (localBtn && !localBtn._init) {
    localBtn._init = true;
    localBtn.addEventListener("click", chessStartLocal);
  }
}

// ── Локальная игра: один экран, два игрока ───────────────────────
function chessStartLocal() {
  _chess.isLocal = true;
  _chess.myColor = "white";   // начинаем с перспективы белых
  _chess.engine  = new Chess();
  _chess.selected = null;
  _chess.legalSquares = [];
  _chess.game = { code: null, status: "active" };

  _showChessScreen("chess-game");

  // Имена
  var me = (state.user && state.user.display_name) || "Игрок";
  var topName    = $("chess-top-name");    if (topName)    topName.textContent    = me;
  var botName    = $("chess-bottom-name"); if (botName)    botName.textContent    = me;
  var topColor   = $("chess-top-color");   if (topColor)   topColor.textContent   = "♚ чёрные";
  var botColor   = $("chess-bottom-color");if (botColor)   botColor.textContent   = "♙ белые";
  var topAv      = $("chess-top-avatar");  if (topAv)      topAv.textContent      = "♚";
  var botAv      = $("chess-bottom-avatar");if (botAv)     botAv.textContent      = "♔";

  // Прячем кнопки онлайн-режима, показываем "Новая игра"
  var resignBtn = $("chess-resign-btn");  if (resignBtn) resignBtn.style.display = "none";
  var drawBtn   = $("chess-draw-btn");    if (drawBtn)   drawBtn.style.display   = "none";

  renderChessBoard();
  renderChessMoves("");
  updateChessStatus();
  _initLocalGameOverBtns();
}

function _initLocalGameOverBtns() {
  var goNew = $("chess-gameover-new");
  if (goNew && !goNew._init) {
    goNew._init = true;
    goNew.addEventListener("click", function() {
      var goEl = $("chess-gameover"); if (goEl) goEl.style.display = "none";
      chessDisconnect(); chessStartLocal();
    });
  }
  var goLobby = $("chess-gameover-lobby");
  if (goLobby && !goLobby._init) {
    goLobby._init = true;
    goLobby.addEventListener("click", function() {
      chessDisconnect(); _showChessScreen("chess-entry");
    });
  }
}

async function loadChessStats() {
  const uid = _chess.myUserId; if (!uid) return;
  try {
    const stats = await apiFetch("/chess/stats?user_id=" + uid);
    const wrap = $("chess-stats-wrap"); const list = $("chess-stats-list");
    if (!wrap || !list || !stats.length) return;
    wrap.style.display = "";
    list.innerHTML = stats.map(function(s) {
      return '<div class="chess-stats-row">'
        + '<span class="chess-stats-name">' + s.opponent_name + '</span>'
        + '<span class="chess-stats-wld"><span class="win">' + s.wins + 'В</span> / '
        + '<span class="loss">' + s.losses + 'П</span> / <span class="draw">' + s.draws + 'Н</span></span>'
        + '<span class="chess-stats-total">' + s.total + ' партий</span></div>';
    }).join("");
  } catch(e) {}
}

async function chessCreateGame() {
  const colorBtn = document.querySelector(".chess-color-btn.active");
  const colorChoice = colorBtn ? colorBtn.dataset.color : "random";
  const uid = _chess.myUserId; if (!uid) return;
  try {
    const game = await apiFetch("/chess/games?user_id=" + uid, {
      method: "POST", body: JSON.stringify({ color_choice: colorChoice }),
    });
    _chess.game = game;
    _chess.myColor = game.white_user_id === uid ? "white" : "black";
    _showChessScreen("chess-waiting");
    const codeEl = $("chess-game-code-display");
    if (codeEl) codeEl.textContent = game.code;
    const backBtn = $("chess-back-from-waiting");
    if (backBtn && !backBtn._init) {
      backBtn._init = true;
      backBtn.addEventListener("click", function() { chessDisconnect(); _showChessScreen("chess-entry"); });
    }
    const copyBtn = $("chess-copy-code-btn");
    if (copyBtn && !copyBtn._init) {
      copyBtn._init = true;
      copyBtn.addEventListener("click", function() {
        navigator.clipboard.writeText(game.code).then(function() {
          copyBtn.textContent = "✓ Скопировано!";
          setTimeout(function() { copyBtn.textContent = "📋 Скопировать код"; }, 2000);
        });
      });
    }
    chessConnect(game.code);
    // Polling-страховка: если WebSocket не доставил game_ready — проверяем каждые 3 сек
    _chess._waitPoll = setInterval(async function() {
      // Прекращаем polling если уже перешли на игровой экран
      var gameEl = $("chess-game");
      if (!gameEl || gameEl.style.display !== "none") {
        clearInterval(_chess._waitPoll); _chess._waitPoll = null; return;
      }
      try {
        var g = await apiFetch("/chess/games/" + game.code);
        if (g && g.status === "active") {
          clearInterval(_chess._waitPoll); _chess._waitPoll = null;
          try {
            chessStartGameUI(g);
          } catch(err) {
            console.error("chessStartGameUI error:", err);
            toast("Ошибка запуска игры: " + (err && err.message || err), "error");
          }
        }
      } catch(e) { console.error("poll error:", e); }
    }, 3000);
  } catch(e) {
    console.error("chess create error:", e);
    const msg = (e && (e.detail || e.message)) || "Ошибка создания игры";
    toast(msg, "error");
  }
}

async function chessJoinGame() {
  const inp = $("chess-join-input");
  const code = (inp ? inp.value.trim().toUpperCase() : "");
  if (!code || code.length < 4) { toast("Введи код игры", "error"); return; }
  const uid = _chess.myUserId;
  try {
    const game = await apiFetch("/chess/games/" + code + "/join?user_id=" + uid, { method: "POST" });
    _chess.game = game;
    _chess.myColor = game.white_user_id === uid ? "white" : "black";
    chessStartGameUI(game);
    chessConnect(game.code);
  } catch(e) {
    toast((e && e.detail) || "Игра не найдена или уже началась", "error");
  }
}

function chessConnect(code) {
  if (_chess.ws) { try { _chess.ws.close(); } catch(e) {} }
  const uid = _chess.myUserId;
  const ws = new WebSocket(_chessWsBase() + "/chess/ws/" + code + "?user_id=" + uid);
  _chess.ws = ws;
  ws.onmessage = function(e) {
    try { handleChessMessage(JSON.parse(e.data)); }
    catch(err) { console.error("chess WS message error:", err); }
  };
  ws.onerror = function() {};
  ws.onclose = function() {
    if (_chess.game && _chess.game.status === "active") {
      setTimeout(function() {
        var gameEl = $("chess-game");
        if (_chess.game && gameEl && gameEl.style.display !== "none") chessConnect(_chess.game.code);
      }, 3000);
    }
  };
  ws._pingInterval = setInterval(function() {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({type:"ping"}));
  }, 25000);
}

function chessDisconnect() {
  if (_chess._waitPoll)  { clearInterval(_chess._waitPoll);  _chess._waitPoll = null; }
  if (_chess._gamePoller){ clearInterval(_chess._gamePoller); _chess._gamePoller = null; }
  if (_chess.ws) {
    clearInterval(_chess.ws._pingInterval);
    try { _chess.ws.close(); } catch(e) {}
    _chess.ws = null;
  }
  _chess.game = null;
  _chess.engine = null;
  _chess.myColor = null;
  _chess.selected = null;
  _chess.legalSquares = [];
  _chess.pendingPromotion = null;
  _chess._lastFen = null;
  _chess.isLocal = false;
  // Сброс _init флагов кнопок — чтобы новая игра заново вешала обработчики
  ["chess-resign-btn","chess-draw-btn","chess-draw-accept","chess-draw-decline",
   "chess-gameover-new","chess-gameover-lobby","chess-back-from-waiting","chess-copy-code-btn"].forEach(function(id) {
    var el = $(id); if (el) el._init = false;
  });
}

// Polling-синхронизация: каждые 4 сек сверяем FEN с сервером
// Страхует от потери WebSocket-сообщений (ход соперника "пропал")
// Умный polling: тикает каждую секунду, но HTTP-запрос делает
// только если WebSocket молчал последние 2+ секунды.
// В нормальной ситуации (WS работает) — 0 лишних запросов к БД.
// При сбое WS — реагирует за ≤1 сек.
function _startChessGamePoller() {
  if (_chess._gamePoller) clearInterval(_chess._gamePoller);
  _chess._lastWsMsgTime = Date.now(); // считаем WS активным при старте
  _chess._gamePoller = setInterval(async function() {
    var gameEl = $("chess-game");
    if (!gameEl || gameEl.style.display === "none" || !_chess.game || _chess.isLocal) {
      clearInterval(_chess._gamePoller); _chess._gamePoller = null; return;
    }
    // Пропускаем если WS живой (последнее сообщение < 2 сек назад)
    var wsSilentMs = Date.now() - (_chess._lastWsMsgTime || 0);
    var wsAlive = _chess.ws && _chess.ws.readyState === WebSocket.OPEN && wsSilentMs < 2000;
    if (wsAlive) return;

    // WS молчит — сверяемся с сервером
    try {
      var g = await apiFetch("/chess/games/" + _chess.game.code);
      if (!g || g.status === "finished") return;
      var serverFen = g.fen;
      var localFen  = _chess.engine ? _chess.engine.fen() : null;
      if (serverFen && serverFen !== localFen) {
        console.log("[chess poll] FEN mismatch — applying server state");
        if (_chess.engine) { try { _chess.engine.load(serverFen); } catch(e) {} }
        _chess._lastFen = serverFen;
        renderChessBoard();
        renderChessMoves(g.moves_pgn || "");
        updateChessStatus();
        _chess._lastWsMsgTime = Date.now(); // обновляем таймер после ручного sync
      }
    } catch(e) {}
  }, 1000); // тикаем каждую секунду, но без запроса если WS ок
}

function handleChessMessage(msg) {
  if (msg.type !== "pong") _chess._lastWsMsgTime = Date.now(); // фиксируем активность WS
  if (msg.type === "state") {
    _chess.game = msg.game;
    if (msg.game.status === "active") chessStartGameUI(msg.game);
  } else if (msg.type === "game_ready") {
    _chess.game = msg.game; chessStartGameUI(msg.game);
  } else if (msg.type === "move") {
    if (_chess.engine && msg.fen) {
      try { _chess.engine.load(msg.fen); } catch(e) { console.error("chess load fen:", e); }
      _chess._lastFen = msg.fen;
      _chess.selected = null; _chess.legalSquares = [];
      renderChessBoard(); renderChessMoves(msg.pgn || ""); updateChessStatus();
    }
  } else if (msg.type === "game_over") {
    handleChessGameOver(msg);
  } else if (msg.type === "draw_offer") {
    if (msg.user_id !== _chess.myUserId) { var o = $("chess-draw-offer"); if (o) o.style.display = ""; }
  } else if (msg.type === "draw_decline") {
    toast("Соперник отклонил ничью");
  } else if (msg.type === "opponent_disconnected") {
    updateChessStatusText("Соперник отключился…");
  }
}

function chessStartGameUI(game) {
  _chess.game = game;
  var uid = _chess.myUserId;
  _chess.myColor = game.white_user_id === uid ? "white" : "black";
  // Всегда создаём свежий движок — никогда не используем старый
  _chess.engine = new Chess();
  _chess.selected = null;
  _chess.legalSquares = [];
  // Загружаем позицию из БД (может быть не начальная, если игра была прервана)
  var fen = game.fen;
  if (fen) { try { _chess.engine.load(fen); } catch(e) {} }
  _showChessScreen("chess-game");
  var isW = _chess.myColor === "white";
  var myName = (state.user && state.user.display_name) || "Вы";
  var oppName = isW ? (game.black_name || "Соперник") : (game.white_name || "Соперник");
  var topName = $("chess-top-name"); if (topName) topName.textContent = oppName;
  var botName = $("chess-bottom-name"); if (botName) botName.textContent = myName;
  var topColor = $("chess-top-color"); if (topColor) topColor.textContent = isW ? "♟ чёрные" : "♙ белые";
  var botColor = $("chess-bottom-color"); if (botColor) botColor.textContent = isW ? "♙ белые" : "♟ чёрные";
  var topAv = $("chess-top-avatar"); if (topAv) topAv.textContent = isW ? "♚" : "♔";
  var botAv = $("chess-bottom-avatar"); if (botAv) botAv.textContent = isW ? "♔" : "♚";
  renderChessBoard(); renderChessMoves(game.moves_pgn || ""); updateChessStatus();
  _chess._lastFen = _chess.engine ? _chess.engine.fen() : null;
  _startChessGamePoller();

  var resignBtn = $("chess-resign-btn");
  if (resignBtn && !resignBtn._init) {
    resignBtn._init = true;
    resignBtn.addEventListener("click", function() {
      if (confirm("Сдаться?") && _chess.ws && _chess.ws.readyState === WebSocket.OPEN)
        _chess.ws.send(JSON.stringify({type:"resign"}));
    });
  }
  var drawBtn = $("chess-draw-btn");
  if (drawBtn && !drawBtn._init) {
    drawBtn._init = true;
    drawBtn.addEventListener("click", function() {
      if (_chess.ws && _chess.ws.readyState === WebSocket.OPEN)
        _chess.ws.send(JSON.stringify({type:"draw_offer"}));
      toast("Предложение ничьей отправлено");
    });
  }
  var drawAccept = $("chess-draw-accept");
  if (drawAccept && !drawAccept._init) {
    drawAccept._init = true;
    drawAccept.addEventListener("click", function() {
      if (_chess.ws && _chess.ws.readyState === WebSocket.OPEN)
        _chess.ws.send(JSON.stringify({type:"draw_accept"}));
      var o = $("chess-draw-offer"); if (o) o.style.display = "none";
    });
  }
  var drawDecline = $("chess-draw-decline");
  if (drawDecline && !drawDecline._init) {
    drawDecline._init = true;
    drawDecline.addEventListener("click", function() {
      if (_chess.ws && _chess.ws.readyState === WebSocket.OPEN)
        _chess.ws.send(JSON.stringify({type:"draw_decline"}));
      var o = $("chess-draw-offer"); if (o) o.style.display = "none";
    });
  }
  var goNew = $("chess-gameover-new");
  if (goNew && !goNew._init) {
    goNew._init = true;
    goNew.addEventListener("click", function() {
      var goEl = $("chess-gameover"); if (goEl) goEl.style.display = "none";
      chessDisconnect(); openChessEntry();
    });
  }
  var goLobby = $("chess-gameover-lobby");
  if (goLobby && !goLobby._init) {
    goLobby._init = true;
    goLobby.addEventListener("click", function() { chessDisconnect(); _showChessScreen("games-lobby"); });
  }
}

function renderChessBoard() {
  var boardEl = $("chess-board"); var engine = _chess.engine;
  if (!boardEl || !engine) return;
  var myColor = _chess.myColor || "white";
  var files = ["a","b","c","d","e","f","g","h"];
  var ranks = myColor === "black" ? [1,2,3,4,5,6,7,8] : [8,7,6,5,4,3,2,1];
  var ordFiles = myColor === "black" ? ["h","g","f","e","d","c","b","a"] : files;
  boardEl.innerHTML = "";
  for (var ri = 0; ri < ranks.length; ri++) {
    var rank = ranks[ri];
    for (var fi = 0; fi < ordFiles.length; fi++) {
      var file = ordFiles[fi];
      var sq = file + rank;
      var piece = engine.get(sq);
      var light = (files.indexOf(file) + rank) % 2 === 1;
      var isSel = _chess.selected === sq;
      var isLeg = _chess.legalSquares.indexOf(sq) >= 0;
      var cls = "chess-sq " + (light ? "chess-sq-light" : "chess-sq-dark");
      if (isSel) cls += " chess-sq-selected";
      else if (isLeg && piece) cls += " chess-sq-capture";
      else if (isLeg) cls += " chess-sq-legal";
      var div = document.createElement("div");
      div.className = cls; div.dataset.sq = sq;
      if (piece) {
        var span = document.createElement("span");
        span.className = "chess-piece chess-piece-" + piece.color;
        span.textContent = CHESS_PIECES[piece.color + piece.type.toUpperCase()] || "?";
        div.appendChild(span);
      }
      if (isLeg && !piece) {
        var dot = document.createElement("div"); dot.className = "chess-move-dot"; div.appendChild(dot);
      }
      if (file === (myColor === "black" ? "h" : "a")) {
        var lbl = document.createElement("span"); lbl.className = "chess-coord chess-coord-rank"; lbl.textContent = rank; div.appendChild(lbl);
      }
      if (rank === (myColor === "black" ? 8 : 1)) {
        var lbl2 = document.createElement("span"); lbl2.className = "chess-coord chess-coord-file"; lbl2.textContent = file; div.appendChild(lbl2);
      }
      (function(s) { div.addEventListener("click", function() { onChessSquareClick(s); }); })(sq);
      boardEl.appendChild(div);
    }
  }
}

function onChessSquareClick(sq) {
  var engine = _chess.engine; var myColor = _chess.myColor;
  if (!engine || !myColor) return;
  // В локальном режиме — ходить может тот, чья очередь
  var isMyTurn = _chess.isLocal
    ? true
    : ((engine.turn() === "w" && myColor === "white") || (engine.turn() === "b" && myColor === "black"));
  if (_chess.selected && _chess.legalSquares.indexOf(sq) >= 0) { chessDoMove(_chess.selected, sq); return; }
  if (!isMyTurn) { _chess.selected = null; _chess.legalSquares = []; renderChessBoard(); return; }
  var piece = engine.get(sq);
  if (piece && piece.color === engine.turn()) {
    _chess.selected = sq;
    var moves = engine.moves({ square: sq, verbose: true });
    _chess.legalSquares = moves.map(function(m) { return m.to; });
  } else { _chess.selected = null; _chess.legalSquares = []; }
  renderChessBoard();
}

function chessDoMove(from, to) {
  var engine = _chess.engine; if (!engine) return;
  var piece = engine.get(from);
  var isPromo = piece && piece.type === "p" &&
    ((piece.color === "w" && to[1] === "8") || (piece.color === "b" && to[1] === "1"));
  if (isPromo) { showPromotionDialog(from, to); return; }
  var move = engine.move({ from: from, to: to, promotion: "q" }); if (!move) return;
  _chess.selected = null; _chess.legalSquares = [];

  // В локальном режиме: переворачиваем доску после хода
  if (_chess.isLocal) {
    _chess.myColor = engine.turn() === "w" ? "white" : "black";
    var topColor = $("chess-top-color");
    var botColor = $("chess-bottom-color");
    var topAv    = $("chess-top-avatar");
    var botAv    = $("chess-bottom-avatar");
    if (_chess.myColor === "white") {
      if (topColor) topColor.textContent = "♚ чёрные";
      if (botColor) botColor.textContent = "♙ белые";
      if (topAv) topAv.textContent = "♚"; if (botAv) botAv.textContent = "♔";
    } else {
      if (topColor) topColor.textContent = "♙ белые";
      if (botColor) botColor.textContent = "♚ чёрные";
      if (topAv) topAv.textContent = "♔"; if (botAv) botAv.textContent = "♚";
    }
  }

  renderChessBoard(); renderChessMoves(engine.pgn()); updateChessStatus();
  var go = checkChessGameOver();

  // Онлайн-режим: шлём ход через WebSocket
  if (!_chess.isLocal && _chess.ws && _chess.ws.readyState === WebSocket.OPEN) {
    _chess.ws.send(JSON.stringify({
      type: go ? "game_over" : "move", from: from, to: to,
      fen: engine.fen(), pgn: engine.pgn(), san: move.san,
      winner: go ? go.winner : undefined, reason: go ? go.reason : undefined,
    }));
  }
}

function showPromotionDialog(from, to) {
  _chess.pendingPromotion = { from: from, to: to };
  var overlay = document.createElement("div");
  overlay.className = "chess-promo-overlay";
  // В локальном режиме используем цвет того кто ходит сейчас
  var color = _chess.isLocal ? _chess.engine.turn() : (_chess.myColor === "white" ? "w" : "b");
  var pieces = ["q","r","b","n"];
  var wPieces = ["♕","♖","♗","♘"]; var bPieces = ["♛","♜","♝","♞"];
  var btns = pieces.map(function(p, i) {
    return '<button class="chess-promo-btn" data-piece="' + p + '">' + (color === "w" ? wPieces[i] : bPieces[i]) + '</button>';
  }).join("");
  overlay.innerHTML = '<div class="chess-promo-box"><div class="chess-promo-title">Выбери фигуру</div><div class="chess-promo-btns">' + btns + '</div></div>';
  overlay.querySelectorAll(".chess-promo-btn").forEach(function(btn) {
    btn.addEventListener("click", function() {
      var prom = btn.dataset.piece; overlay.remove();
      var f = _chess.pendingPromotion.from; var t = _chess.pendingPromotion.to; _chess.pendingPromotion = null;
      var move = _chess.engine.move({ from: f, to: t, promotion: prom }); if (!move) return;
      _chess.selected = null; _chess.legalSquares = [];
      renderChessBoard(); renderChessMoves(_chess.engine.pgn()); updateChessStatus();
      var go = checkChessGameOver();
      if (_chess.ws && _chess.ws.readyState === WebSocket.OPEN) {
        _chess.ws.send(JSON.stringify({
          type: go ? "game_over" : "move", from: f, to: t, promotion: prom,
          fen: _chess.engine.fen(), pgn: _chess.engine.pgn(), san: move.san,
          winner: go ? go.winner : undefined, reason: go ? go.reason : undefined,
        }));
      }
    });
  });
  document.body.appendChild(overlay);
}

function checkChessGameOver() {
  var engine = _chess.engine; if (!engine) return null;
  if (engine.in_checkmate()) {
    var winner = engine.turn() === "w" ? "black" : "white";
    handleChessGameOver({ winner: winner, reason: "checkmate", fen: engine.fen() });
    return { winner: winner, reason: "checkmate" };
  }
  if (engine.in_draw() || engine.in_stalemate() || engine.in_threefold_repetition() || engine.insufficient_material()) {
    handleChessGameOver({ winner: "draw", reason: engine.in_stalemate() ? "stalemate" : "draw", fen: engine.fen() });
    return { winner: "draw", reason: "draw" };
  }
  return null;
}

function handleChessGameOver(msg) {
  var goEl = $("chess-gameover"); if (!goEl) return;
  var myColor = _chess.myColor;
  var icon = "🏆", title = "", sub = "";
  if (msg.winner === "draw") {
    icon = "🤝"; title = "Ничья!";
    sub = msg.reason === "agreement" ? "По соглашению" : msg.reason === "stalemate" ? "Пат" : "Ничья";
  } else if (msg.winner === myColor) {
    icon = "🏆"; title = "Победа!";
    sub = msg.reason === "resign" ? "Соперник сдался" : msg.reason === "checkmate" ? "Мат!" : "";
  } else {
    icon = "😔"; title = "Поражение";
    sub = msg.reason === "resign" ? "Вы сдались" : msg.reason === "checkmate" ? "Вам поставили мат" : "";
  }
  var iconEl = $("chess-gameover-icon"); if (iconEl) iconEl.textContent = icon;
  var titleEl = $("chess-gameover-title"); if (titleEl) titleEl.textContent = title;
  var subEl = $("chess-gameover-sub"); if (subEl) subEl.textContent = sub;
  goEl.style.display = "";
}

function renderChessMoves(pgn) {
  var list = $("chess-moves-list"); if (!list) return;
  if (!pgn) { list.innerHTML = ""; return; }
  var clean = pgn.replace(/\{[^}]*\}/g, "").trim();
  var rows = clean.split(/\d+\./).filter(function(s) { return s.trim(); });
  list.innerHTML = rows.map(function(s, i) {
    return '<div class="chess-move-row"><span class="chess-move-num">' + (i+1) + '.</span>' + s.trim() + '</div>';
  }).join("");
  list.scrollTop = list.scrollHeight;
}

function updateChessStatus() {
  var engine = _chess.engine; var myColor = _chess.myColor; if (!engine) return;
  var turn = engine.turn() === "w" ? "white" : "black";
  var text = "", dotCls = "";

  if (engine.game_over()) {
    if (engine.in_checkmate()) {
      var loser = turn === "white" ? "Белые" : "Чёрные";
      text = loser + " получили мат!";
    } else {
      text = "Ничья";
    }
    dotCls = "dot-over";
  } else if (_chess.isLocal) {
    // В локальном режиме — просто показываем чья очередь
    var whoLabel = turn === "white" ? "⬜ Ход белых" : "⬛ Ход чёрных";
    text = engine.in_check() ? whoLabel + " — шах!" : whoLabel;
    dotCls = "dot-mine";
  } else {
    var isMyTurn = turn === myColor;
    if (isMyTurn) {
      text = engine.in_check() ? "Ваш ход — шах!" : "Ваш ход";
      dotCls = "dot-mine";
    } else {
      text = "Ход соперника…"; dotCls = "dot-opp";
    }
  }
  var st = $("chess-status-text"); if (st) st.textContent = text;
  var sd = $("chess-status-dot"); if (sd) sd.className = "chess-status-dot " + dotCls;
}

function updateChessStatusText(text) {
  var el = $("chess-status-text"); if (el) el.textContent = text;
}

// ════════════════════════════════════════════════════════════════
//  🃏 ДУРАК
// ════════════════════════════════════════════════════════════════

const DURAK_SUITS = { '♠':'black','♣':'black','♥':'red','♦':'red' };
const DURAK_RANK_LABELS = { 'J':'J','Q':'Q','K':'K','A':'A' };

const _durak = {
  ws: null,
  game: null,
  state: null,
  myUserId: null,
  myHand: [],
  selectedCards: [],
  selectedCard: null,    // одна карта — для отбоя
  selectedDefense: null, // устарело, оставлено для совместимости
  code: null,
};

function _durakWsBase() {
  const base = (typeof API_BASE_URL !== 'undefined' ? API_BASE_URL : '') || '';
  if (base.startsWith('http')) return base.replace(/^http/, 'ws');
  const loc = window.location;
  return (loc.protocol === 'https:' ? 'wss' : 'ws') + '://' + loc.host;
}

function _showDurakScreen(id) {
  ['durak-setup','durak-lobby','durak-game'].forEach(function(s) {
    var el = $(s); if (el) el.style.display = s === id ? '' : 'none';
  });
}

// ── Инициализация ────────────────────────────────────────────────
function initDurakMode() {
  _durakDisconnect();
  _durak.myUserId = state.user && state.user.id;
  _showDurakScreen('durak-setup');
  _initDurakSetup();
}

function _durakDisconnect() {
  if (_durak.ws) {
    clearInterval(_durak.ws._ping);
    try { _durak.ws.close(); } catch(e) {}
    _durak.ws = null;
  }
  _durak.game = null; _durak.state = null; _durak.myHand = [];
  _durak.selectedCards = []; _durak.selectedCard = null; _durak.selectedDefense = null; _durak.code = null;
  // Reset _init flags
  ['durak-create-btn','durak-join-btn','durak-copy-btn','durak-start-btn',
   'durak-back-lobby','durak-back-setup','durak-done-btn','durak-take-btn',
   'durak-go-new','durak-go-lobby'].forEach(function(id) {
    var el = $(id); if (el) el._init = false;
  });
  // Reset radio group listeners
  ['durak-deck-group','durak-players-group','durak-variant-group','durak-neighbors-group'].forEach(function(id) {
    var el = $(id); if (el) el._init = false;
  });
}

// ── Setup screen ─────────────────────────────────────────────────
function _initDurakSetup() {
  // Radio groups
  ['durak-deck-group','durak-players-group','durak-variant-group','durak-neighbors-group'].forEach(function(gid) {
    var grp = $(gid); if (!grp || grp._init) return; grp._init = true;
    grp.addEventListener('click', function(e) {
      var btn = e.target.closest('.durak-radio'); if (!btn) return;
      grp.querySelectorAll('.durak-radio').forEach(function(b) { b.classList.remove('active'); });
      btn.classList.add('active');
    });
  });

  var backBtn = $('durak-back-lobby');
  if (backBtn && !backBtn._init) {
    backBtn._init = true;
    backBtn.addEventListener('click', function() { _showDurakScreen(null); _showChessScreen('games-lobby'); });
  }

  var createBtn = $('durak-create-btn');
  if (createBtn && !createBtn._init) {
    createBtn._init = true;
    createBtn.addEventListener('click', _durakCreateGame);
  }

  var joinBtn = $('durak-join-btn');
  if (joinBtn && !joinBtn._init) {
    joinBtn._init = true;
    joinBtn.addEventListener('click', _durakJoinByCode);
  }

  var joinInp = $('durak-join-input');
  if (joinInp && !joinInp._init) {
    joinInp._init = true;
    joinInp.addEventListener('keydown', function(e) { if (e.key === 'Enter') _durakJoinByCode(); });
    joinInp.addEventListener('input', function() { joinInp.value = joinInp.value.toUpperCase(); });
  }
}

function _getDurakSetup() {
  function activeVal(gid) {
    var btn = document.querySelector('#' + gid + ' .durak-radio.active');
    return btn ? btn.dataset.val : null;
  }
  return {
    deck_size:      parseInt(activeVal('durak-deck-group')) || 36,
    max_players:    parseInt(activeVal('durak-players-group')) || 2,
    variant:        activeVal('durak-variant-group') || 'podkidnoy',
    neighbors_only: activeVal('durak-neighbors-group') === '1',
  };
}

async function _durakCreateGame() {
  var uid = _durak.myUserId; if (!uid) return;
  var setup = _getDurakSetup();
  try {
    var resp = await apiFetch('/durak/games?user_id=' + uid, {
      method: 'POST', body: JSON.stringify(setup),
    });
    _durak.code = resp.game.code;
    _durak.game = resp.game;
    _showDurakWaiting(resp.game, resp.players);
    _durakConnect(resp.game.code);
  } catch(e) {
    toast((e && e.detail) || 'Ошибка создания игры', 'error');
  }
}

async function _durakJoinByCode() {
  var inp = $('durak-join-input');
  var code = inp ? inp.value.trim().toUpperCase() : '';
  if (code.length < 4) { toast('Введи код', 'error'); return; }
  var uid = _durak.myUserId;
  try {
    var resp = await apiFetch('/durak/games/' + code + '/join?user_id=' + uid, { method: 'POST' });
    _durak.code = code;
    _durak.game = resp.game;
    if (resp.game.status === 'active') {
      _durakConnect(code);
    } else {
      _showDurakWaiting(resp.game, resp.players);
      _durakConnect(code);
    }
  } catch(e) {
    toast((e && e.detail) || 'Игра не найдена или уже началась', 'error');
  }
}

// ── Зал ожидания ─────────────────────────────────────────────────
function _showDurakWaiting(game, players) {
  _showDurakScreen('durak-lobby');
  var codeEl = $('durak-code-display'); if (codeEl) codeEl.textContent = game.code;
  var titleEl = $('durak-lobby-title'); if (titleEl) titleEl.textContent = 'Игра создана!';
  _renderDurakPlayerList(players, game.max_players);
  _initDurakLobbyBtns(game);
}

function _renderDurakPlayerList(players, maxPlayers) {
  var list = $('durak-players-list'); if (!list) return;
  var html = '';
  for (var i = 0; i < maxPlayers; i++) {
    var p = players[i];
    html += '<div class="durak-lobby-player ' + (p ? 'filled' : 'empty') + '">';
    html += p ? ('👤 ' + p.display_name) : '⋯ ожидание';
    html += '</div>';
  }
  list.innerHTML = html;

  var dots = $('durak-waiting-dots');
  var hint  = $('durak-lobby-hint');
  var start = $('durak-start-btn');
  var uid   = _durak.myUserId;
  var isCreator = _durak.game && _durak.game.created_by === uid;
  var full  = players.length >= maxPlayers;

  if (dots) dots.style.display = full ? 'none' : '';
  if (hint) hint.textContent = full ? 'Все игроки на месте!' : 'Ожидаем игроков… (' + players.length + '/' + maxPlayers + ')';
  if (start) start.style.display = (!full && isCreator && players.length >= 2) ? '' : 'none';
}

function _initDurakLobbyBtns(game) {
  var backBtn = $('durak-back-setup');
  if (backBtn && !backBtn._init) {
    backBtn._init = true;
    backBtn.addEventListener('click', function() { _durakDisconnect(); _showDurakScreen('durak-setup'); });
  }

  var copyBtn = $('durak-copy-btn');
  if (copyBtn && !copyBtn._init) {
    copyBtn._init = true;
    copyBtn.addEventListener('click', function() {
      navigator.clipboard.writeText(game.code).then(function() {
        copyBtn.textContent = '✓ Скопировано!';
        setTimeout(function() { copyBtn.textContent = '📋 Скопировать код'; }, 2000);
      });
    });
  }

  var startBtn = $('durak-start-btn');
  if (startBtn && !startBtn._init) {
    startBtn._init = true;
    startBtn.addEventListener('click', async function() {
      try {
        await apiFetch('/durak/games/' + game.code + '/start?user_id=' + _durak.myUserId, { method: 'POST' });
      } catch(e) { toast(e && e.detail || 'Ошибка', 'error'); }
    });
  }
}

// ── WebSocket ────────────────────────────────────────────────────
function _durakConnect(code) {
  if (_durak.ws) { try { _durak.ws.close(); } catch(e) {} }
  var uid = _durak.myUserId;
  var ws = new WebSocket(_durakWsBase() + '/durak/ws/' + code + '?user_id=' + uid);
  _durak.ws = ws;
  ws.onmessage = function(e) {
    try { _handleDurakMsg(JSON.parse(e.data)); } catch(err) { console.error('durak ws:', err); }
  };
  ws.onerror = function() {};
  ws.onclose = function() {
    if (_durak.code && $('durak-game') && $('durak-game').style.display !== 'none') {
      setTimeout(function() { if (_durak.code) _durakConnect(_durak.code); }, 3000);
    }
  };
  ws._ping = setInterval(function() {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping' }));
  }, 25000);
}

function _handleDurakMsg(msg) {
  if (msg.type === 'pong') return;

  if (msg.type === 'lobby') {
    _durak.game = msg.game;
    _renderDurakPlayerList(msg.players, msg.game.max_players);
    return;
  }

  if (msg.type === 'player_joined') {
    if (_durak.game) _renderDurakPlayerList(msg.players, _durak.game.max_players);
    return;
  }

  if (msg.type === 'error') {
    toast(msg.message, 'error'); return;
  }

  if (msg.type === 'state') {
    _durak.state = msg.state;
    _durak.myHand = msg.state.my_hand || [];
    // Сбрасываем выделение при получении нового стейта с сервера
    _durak.selectedCard  = null;
    _durak.selectedCards = [];
    if (msg.state.game_status === 'active') {
      _showDurakScreen('durak-game');
      _renderDurakGame(msg.state);
    } else if (msg.state.game_status === 'waiting') {
      // Still in lobby — update player list
      var players = (msg.state.players || []);
      if (_durak.game) _renderDurakPlayerList(players, _durak.game.max_players);
    }
    return;
  }

  if (msg.type === 'game_over') {
    _showDurakGameOver(msg.loser_id, msg.loser_name);
    return;
  }
}

// ── Рендер игры ──────────────────────────────────────────────────
function _renderDurakGame(state) {
  _renderDurakOpponents(state);
  _renderDurakTable(state);
  _renderDurakDeck(state);
  _renderDurakHand(state);
  _renderDurakStatus(state);
  _renderDurakButtons(state);
  _initDurakGameBtns();
}

function _cardHtml(card, extra) {
  var rank = card.startsWith('10') ? '10' : card.slice(0, -1);
  var suit = card.slice(-1);
  var color = DURAK_SUITS[suit] || 'black';
  var cls = 'durak-card durak-card-' + color + (extra ? ' ' + extra : '');
  return '<div class="' + cls + '" data-card="' + card + '">'
    + '<span class="dc-rank">' + rank + '</span>'
    + '<span class="dc-suit">' + suit + '</span>'
    + '</div>';
}

function _cardBackHtml(count, label) {
  return '<div class="durak-card-back-wrap">'
    + '<div class="durak-card-back"></div>'
    + '<span class="dc-back-count">' + count + '</span>'
    + (label ? '<span class="dc-back-label">' + label + '</span>' : '')
    + '</div>';
}

function _renderDurakOpponents(state) {
  var el = $('durak-opponents'); if (!el) return;
  var uid = _durak.myUserId;
  var players = (state.players || []).filter(function(p) { return p.user_id !== uid; });
  el.innerHTML = players.map(function(p) {
    var isAttacker = p.user_id === state.attacker;
    var isDefender = p.user_id === state.defender;
    var role = isAttacker ? '⚔' : isDefender ? '🛡' : '';
    var finished = p.finished;
    var count = state.hands[String(p.user_id)] || 0;
    return '<div class="durak-opponent' + (finished ? ' finished' : '') + '">'
      + '<div class="durak-opp-name">' + role + ' ' + p.display_name + '</div>'
      + (finished ? '<div class="durak-opp-out">вышел</div>'
          : _cardBackHtml(count, null))
      + '</div>';
  }).join('');
}

function _renderDurakDeck(state) {
  var wrap = $('durak-deck-wrap');
  var countEl = $('durak-deck-count');
  var trump = $('durak-trump-reveal');
  if (countEl) countEl.textContent = state.deck_count || 0;
  if (trump) {
    if (state.deck_count > 0 && state.trump_card) {
      trump.innerHTML = _cardHtml(state.trump_card, 'trump-card');
      trump.style.display = '';
    } else {
      trump.style.display = 'none';
    }
  }
  if (wrap) {
    var deckCard = wrap.querySelector('.durak-card-back');
    if (deckCard) deckCard.style.display = state.deck_count > 0 ? '' : 'none';
  }
  var discardEl = $('durak-discard-count');
  if (discardEl) discardEl.textContent = state.discard_count > 0 ? (state.discard_count + ' карт в отбое') : '';
}

// ── Стол ─────────────────────────────────────────────────────────
function _renderDurakTable(state) {
  var area  = $('durak-table-area');
  var empty = $('durak-table-empty');
  if (!area) return;
  var table      = state.table || [];
  var uid        = _durak.myUserId;
  var isDefender = state.defender === uid;
  var selCard    = _durak.selectedCard;

  area.querySelectorAll('.durak-table-slot').forEach(function(el) { el.remove(); });

  if (!table.length) {
    if (empty) empty.style.display = '';
    // Drop zone на пустой стол для атаки
    _setupTableDropZone(area, state);
    return;
  }
  if (empty) empty.style.display = 'none';

  table.forEach(function(slot) {
    var div = document.createElement('div');
    div.className = 'durak-table-slot';

    // Атакующая карта
    var atkEl = document.createElement('div');
    var atkRank = slot.attack.startsWith('10') ? '10' : slot.attack.slice(0, -1);
    var atkSuit = slot.attack.slice(-1);
    atkEl.className = 'durak-card durak-card-' + (DURAK_SUITS[atkSuit] || 'black') + ' table-attack';
    if (!slot.defense && isDefender) atkEl.classList.add('needs-defense');
    atkEl.dataset.card = slot.attack;
    atkEl.innerHTML = '<span class="dc-rank">' + atkRank + '</span><span class="dc-suit">' + atkSuit + '</span>';
    div.appendChild(atkEl);

    if (slot.defense) {
      // Отбитая карта
      var defRank = slot.defense.startsWith('10') ? '10' : slot.defense.slice(0, -1);
      var defSuit = slot.defense.slice(-1);
      var defEl = document.createElement('div');
      defEl.className = 'durak-card durak-card-' + (DURAK_SUITS[defSuit] || 'black') + ' table-defense';
      defEl.innerHTML = '<span class="dc-rank">' + defRank + '</span><span class="dc-suit">' + defSuit + '</span>';
      div.appendChild(defEl);
    } else if (isDefender) {
      // Клик и дроп на атакующую карту = отбить
      if (selCard) {
        atkEl.classList.add('clickable-target');
        atkEl.addEventListener('click', function() {
          var def = selCard;
          _durak.selectedCard = null;
          _renderDurakHand(state);
          _renderDurakTable(state);
          _renderDurakButtons(state);
          _sendDurakMsg({ type: 'defend', attack_card: slot.attack, defense_card: def });
        });
      }
      // Drag-drop target на слот
      atkEl.addEventListener('dragover', function(e) { e.preventDefault(); atkEl.classList.add('drag-over'); });
      atkEl.addEventListener('dragleave', function() { atkEl.classList.remove('drag-over'); });
      atkEl.addEventListener('drop', function(e) {
        e.preventDefault(); atkEl.classList.remove('drag-over');
        var def = e.dataTransfer.getData('text/plain');
        if (def) _sendDurakMsg({ type: 'defend', attack_card: slot.attack, defense_card: def });
      });
    }

    area.appendChild(div);
  });

  _setupTableDropZone(area, state);
}

function _setupTableDropZone(area, state) {
  var uid = _durak.myUserId;
  var isAttacker = _durakCanAttack(state, uid);
  if (!isAttacker) return;
  area.addEventListener('dragover', function(e) {
    e.preventDefault(); area.classList.add('drag-over');
  });
  area.addEventListener('dragleave', function(e) {
    if (!area.contains(e.relatedTarget)) area.classList.remove('drag-over');
  });
  area.addEventListener('drop', function(e) {
    e.preventDefault(); area.classList.remove('drag-over');
    var card = e.dataTransfer.getData('text/plain');
    if (card) _sendDurakMsg({ type: 'attack', cards: [card] });
  });
  // Клик по пустому столу = бросить выбранную карту
  area.addEventListener('click', function(e) {
    if (e.target !== area && !e.target.classList.contains('durak-table-empty')) return;
    if (_durak.selectedCards.length > 0) _durakDoAttack(state);
  });
}

function _durakCanAttack(state, uid) {
  var phase = state.phase;
  if (!['attack','throwing','defense'].includes(phase)) return false;
  if ((state.finished_players || []).includes(uid)) return false;
  return state.attacker === uid || (state.attackers || []).includes(uid) || phase !== 'defense';
}

// ── Рука игрока ──────────────────────────────────────────────────
function _renderDurakHand(state) {
  var hand = $('durak-hand'); if (!hand) return;
  var uid        = _durak.myUserId;
  var cards      = _durak.myHand;
  var isDefender = state.defender === uid;
  var phase      = state.phase;
  var canAct     = ['attack','throwing','defense'].includes(phase)
                   && !(state.finished_players || []).includes(uid);

  hand.innerHTML = '';
  cards.forEach(function(card) {
    var rank = card.startsWith('10') ? '10' : card.slice(0, -1);
    var suit = card.slice(-1);
    var isSel = _durak.selectedCards.includes(card) || _durak.selectedCard === card;
    var el = document.createElement('div');
    el.className = 'durak-card durak-card-' + (DURAK_SUITS[suit] || 'black')
                   + (isSel ? ' selected' : '');
    el.dataset.card = card;
    el.draggable = canAct;
    el.innerHTML = '<span class="dc-rank">' + rank + '</span><span class="dc-suit">' + suit + '</span>';

    if (canAct) {
      // Drag start
      el.addEventListener('dragstart', function(e) {
        e.dataTransfer.setData('text/plain', card);
        el.classList.add('dragging');
      });
      el.addEventListener('dragend', function() { el.classList.remove('dragging'); });

      el.addEventListener('click', function() {
        if (isDefender && phase === 'defense') {
          // Для защитника: выбираем одну карту для отбоя
          _durak.selectedCard  = (_durak.selectedCard === card) ? null : card;
          _durak.selectedCards = [];
        } else {
          // Для атакующего / подкидывающего: тоглим в множественный выбор
          _durak.selectedCard = null;
          var idx = _durak.selectedCards.indexOf(card);
          if (idx >= 0) _durak.selectedCards.splice(idx, 1);
          else           _durak.selectedCards.push(card);
        }
        _renderDurakHand(state);
        _renderDurakTable(state);
        _renderDurakButtons(state);
      });
    }
    hand.appendChild(el);
  });
}

function _durakDoAttack(state) {
  var cards = _durak.selectedCards.slice();
  if (!cards.length) return;
  _durak.selectedCards = []; _durak.selectedCard = null;
  _sendDurakMsg({ type: 'attack', cards: cards });
}

// ── Статус ───────────────────────────────────────────────────────
function _renderDurakStatus(state) {
  var el  = $('durak-status-text');
  var dot = $('durak-status-dot2');
  if (!el) return;
  var uid        = _durak.myUserId;
  var phase      = state.phase;
  var isAttacker = state.attacker === uid;
  var isDefender = state.defender === uid;
  var isFinished = (state.finished_players || []).includes(uid);

  var text = '', color = '#888';
  if (phase === 'finished')  { text = 'Игра завершена!'; color = '#c96442'; }
  else if (isFinished)       { text = '✅ Вы вышли из игры!'; color = '#5a8a5a'; }
  else if (phase === 'attack') {
    if (isAttacker) { text = '⚔ Ваш ход — атакуй!'; color = '#c96442'; }
    else { text = _playerName(state, state.attacker) + ' ходит…'; }
  } else if (phase === 'defense') {
    if (isDefender) {
      text = _durak.selectedCard
        ? '👆 Теперь нажми на карту на столе которую хочешь побить'
        : '🛡 Выбери карту из руки для отбоя';
      color = '#4a6da8';
    } else if (isAttacker) {
      text = 'Можешь подкинуть карту того же достоинства';
    } else {
      text = _playerName(state, state.defender) + ' защищается…';
    }
  } else if (phase === 'throwing') {
    if (isDefender)  { text = '✅ Всё отбито! Ждём остальных…'; color = '#5a8a5a'; }
    else if (isAttacker) { text = 'Подкини ещё или нажми «Хватит»'; color = '#c96442'; }
    else { text = 'Можешь подкинуть карту'; }
  }
  el.textContent = text;
  if (dot) dot.style.background = color;
}

function _playerName(state, uid) {
  var p = (state.players || []).find(function(pl) { return pl.user_id === uid; });
  return p ? p.display_name : '?';
}

// ── Кнопки действий ──────────────────────────────────────────────
function _renderDurakButtons(state) {
  var uid        = _durak.myUserId;
  var phase      = state.phase;
  var isAttacker = state.attacker === uid;
  var isDefender = state.defender === uid;
  var hasSel     = _durak.selectedCards.length > 0;
  var allBeaten  = (state.table || []).length > 0
                   && (state.table || []).every(function(sl) { return sl.defense !== null; });

  var throwBtn = $('durak-throw-btn');
  var doneBtn  = $('durak-done-btn');
  var takeBtn  = $('durak-take-btn');

  // Бросить: видна когда атакующий выбрал карты
  if (throwBtn) {
    var canThrow = hasSel && !isDefender && ['attack','throwing','defense'].includes(phase);
    throwBtn.style.display = canThrow ? '' : 'none';
    if (canThrow) throwBtn.textContent = '↑ Бросить'
      + (_durak.selectedCards.length > 1 ? ' (' + _durak.selectedCards.length + ' карты)' : ' карту');
  }

  // Хватит: атакующий может завершить подкидывание когда все отбито
  if (doneBtn) {
    doneBtn.style.display = (isAttacker && (phase === 'throwing' || (phase === 'defense' && allBeaten))) ? '' : 'none';
  }

  // Взять: защитник всегда может взять карты
  if (takeBtn) {
    takeBtn.style.display = (isDefender && phase === 'defense' && (state.table || []).length > 0) ? '' : 'none';
  }
}

function _initDurakGameBtns() {
  var throwBtn = $('durak-throw-btn');
  if (throwBtn && !throwBtn._init) {
    throwBtn._init = true;
    throwBtn.addEventListener('click', function() { _durakDoAttack(_durak.state); });
  }

  var doneBtn = $('durak-done-btn');
  if (doneBtn && !doneBtn._init) {
    doneBtn._init = true;
    doneBtn.addEventListener('click', function() { _sendDurakMsg({ type: 'done_attack' }); });
  }

  var takeBtn = $('durak-take-btn');
  if (takeBtn && !takeBtn._init) {
    takeBtn._init = true;
    takeBtn.addEventListener('click', function() {
      _durak.selectedCard = null; _durak.selectedCards = [];
      _sendDurakMsg({ type: 'take' });
    });
  }

  var goNew = $('durak-go-new');
  if (goNew && !goNew._init) {
    goNew._init = true;
    goNew.addEventListener('click', function() {
      var goEl = $('durak-gameover'); if (goEl) goEl.style.display = 'none';
      _durakDisconnect(); _showDurakScreen('durak-setup'); initDurakMode();
    });
  }

  var goLobby = $('durak-go-lobby');
  if (goLobby && !goLobby._init) {
    goLobby._init = true;
    goLobby.addEventListener('click', function() {
      _durakDisconnect(); _showDurakScreen(null); _showChessScreen('games-lobby');
    });
  }
}

function _sendDurakMsg(msg) {
  if (_durak.ws && _durak.ws.readyState === WebSocket.OPEN) {
    _durak.ws.send(JSON.stringify(msg));
  }
}

function _showDurakGameOver(loserId, loserName) {
  var uid = _durak.myUserId;
  var goEl    = $('durak-gameover');
  var iconEl  = $('durak-go-icon');
  var titleEl = $('durak-go-title');
  var subEl   = $('durak-go-sub');
  if (!goEl) return;
  var isLoser = loserId === uid;
  if (iconEl)  iconEl.textContent  = isLoser ? '🤡' : '🏆';
  if (titleEl) titleEl.textContent = isLoser ? 'Ты Дурак!' : 'Ты вышел!';
  if (subEl)   subEl.textContent   = isLoser ? 'Не повезло 😅' : ('Дурак: ' + loserName);
  goEl.style.display = '';
}
