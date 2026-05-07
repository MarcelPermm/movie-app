# 🎬 CineMatch — умные рекомендации фильмов

Приложение рекомендует фильмы на основе твоего избранного.
Алгоритм: Content-Based Filtering (TF-IDF + Cosine Similarity).

---

## Установка и запуск (пошагово)

### Шаг 1 — Получи ключ TMDB API (бесплатно)

1. Зайди на https://www.themoviedb.org/signup и зарегистрируйся
2. Перейди в Settings → API → Create → Developer
3. Скопируй ключ из поля «API Key (v3 auth)»

### Шаг 2 — Настрой ключ

```bash
cd movie-app/backend
cp .env.example .env
```

Открой файл `.env` и замени `вставь_сюда_свой_ключ` на реальный ключ.

### Шаг 3 — Установи зависимости Python

Убедись, что Python 3.10+ установлен:
```bash
python --version
```

Установи библиотеки:
```bash
cd movie-app/backend
pip install -r requirements.txt
```

### Шаг 4 — Запусти сервер

```bash
cd movie-app/backend
python -m uvicorn main:app --reload
```

Сервер запустится на http://127.0.0.1:8000
Документация API: http://127.0.0.1:8000/docs

### Шаг 5 — Открой приложение

Открой файл `movie-app/frontend/index.html` в браузере.

Готово! 🎉

---

## Как пользоваться

1. **Обзор** — смотри популярные фильмы, используй поиск
2. **♡** — нажми на сердечко на карточке, чтобы добавить в избранное
3. **Рекомендации** → «Подобрать фильмы» — алгоритм найдёт похожие

---

## Структура проекта

```
movie-app/
├── backend/
│   ├── main.py          # FastAPI сервер (маршруты API)
│   ├── recommender.py   # ML алгоритм (TF-IDF + Cosine Similarity)
│   ├── database.py      # SQLite (хранение избранного)
│   ├── requirements.txt # Зависимости Python
│   └── .env             # Твой ключ TMDB (создай из .env.example)
└── frontend/
    ├── index.html       # Разметка
    ├── style.css        # Стили
    └── app.js           # Логика интерфейса
```
