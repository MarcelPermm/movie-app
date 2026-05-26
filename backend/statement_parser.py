"""
Парсер банковских выписок Озон Банка (PDF).
Извлекает транзакции и автоматически расставляет категории по словарю ключевых слов.
"""

import re
import pdfplumber
from typing import Optional

# ── Словарь категорий: (список ключевых слов, emoji, название) ────────────────
# Порядок важен — первое совпадение побеждает
BANK_RULES = [
    # Переводы и пополнения (фильтруем первыми — не расходы)
    (["POPOLNENIE", "ПОПОЛНЕНИЕ", "ZACHISLENIE", "ЗАЧИСЛЕНИЕ",
      "ПЕРЕВОД КАРТЫ", "ПОПОЛНЕНИЕ КАРТЫ"],
     None, None),  # None = пропускаем (приход)

    # Доставка еды (до Яндекса, чтобы EDA не попала в такси)
    (["DOSTAVKA IZ PYATEROCHK", "YANDEX*EDA", "YANDEX*5814*EDA",
      "SAMOKAT", "SBERMARKET", "KUPER", "DELIVERY CLUB", "BRONIBOY"],
     "🍕", "Доставка еды"),

    # Такси
    (["YANDEX*4121*FASTEN", "YANDEX*4121*GO", "YANDEX*GO",
      "FASTEN", "CITYMOBIL", "UBER"],
     "🚕", "Такси"),

    # Самокаты / велосипеды
    (["YANDEX*7999*SCOOTERS", "SCOOTER", "WHOOSH", "URENT", "VELOBIKE"],
     "🛴", "Самокаты"),

    # Яндекс (общее — прочие сервисы)
    (["YANDEX", "YA.RU"],
     "💛", "Яндекс"),

    # РЖД / авиа / транспорт
    (["WWW.RZD.RU", "RZD.RU", "AEROFLOT", "S7 ", "POBEDA", "TUTU",
      "OZON TRAVEL", "OZONTRAVEL", "AVIASALES", "TRIP.COM"],
     "✈️", "Билеты / Транспорт"),

    # Алкоголь
    (["KRASNOE&BELOE", "KRASNOE", "ALKOTEKA", "ALKOGOL",
      "VINLAB", "GRADUS", "WINELAB"],
     "🍺", "Алкоголь"),

    # Бары и ночные заведения
    (["VBAR", "V-BAR", " BAR", "BAR ", "PUB", "ROCKS BAR",
      "BEY BAR", "SALOON", "WESTERN", "KHLEB DA KHMEL"],
     "🍸", "Бары"),

    # Рестораны и кафе
    (["RESTAURANT", "KAFE", "CAFE", "GASTROKAFE", "GASTRONOM",
      "BUFFET", "CHAIKA", "FRANK.", "MESTNYJ", "MINDAL",
      "QSR", "BURGER", "MCDONALDS", "KFC", "SUBWAY",
      "PIZZA", "SUSHI", "TEFI", "FOOOD", "STOLOVAYA"],
     "🍽️", "Кафе / Ресторан"),

    # Продукты
    (["MAGNIT", "PYATEROCHKA", "LENTA", "AUCHAN", "PEREKRESTOK",
      "DIKSI", "PRODUKTY", "AGROKOMPLEKS", "VKUSVILL", "MYASNITSKIY",
      "METRO ", "GLOBUS", "SPAR ", "FARMER"],
     "🛒", "Продукты"),

    # АЗС
    (["AZS", "LUKOIL", "GAZPROMNEFT", "ROSNEFT", "TATNEFT",
      "BP ", " BP", "SHELL", "AU404", "NKHP"],
     "⛽", "АЗС / Топливо"),

    # Аптека
    (["APTEKA", "EAPTEKA", "36.6", "RIGLA", "GORZDRAV",
      "ZDRAVCITY", "FARMACIA", "PHARMA"],
     "💊", "Аптека"),

    # Спорт
    (["SPORTMASTER", "SPORT ", "DECATHLON", "INTERSPORT", "ADIDAS",
      "NIKE ", "PUMA ", "REEBOK"],
     "🏋️", "Спорт"),

    # Одежда / шопинг
    (["ZARA", "H&M", "HM ", "OZON ", "WILDBERRIES", "WB ",
      "LAMODA", "GLORIA", "BEFREE"],
     "👗", "Одежда / Шопинг"),

    # Развлечения
    (["KINO", "CINEMA", "KINOMAX", "SINEMA", "MUSEUM",
      "FOTOKUB", "AFON", "CASE-BATTLE", "CASE BATTLE",
      "AQUAPARK", "ATTRACTION"],
     "🎢", "Развлечения"),

    # Связь
    (["BEELINE", "MTS ", " MTS", "MEGAFON", "TELE2",
      "ROSTELECOM", "TRICOLOR"],
     "📱", "Связь"),

    # Переводы исходящие (p2p, между своими)
    (["P2P", "SBP ", " SBP", "PEREVOD", "ПЕРЕВОД НА КАРТУ",
      "TRANSFER"],
     "💸", "Переводы"),
]


def _categorize(description: str) -> tuple[str, str]:
    """Возвращает (emoji, category_name) по описанию транзакции."""
    desc_upper = description.upper()
    for keywords, emoji, name in BANK_RULES:
        for kw in keywords:
            if kw.upper() in desc_upper:
                return emoji, name
    return "💰", "Другое"


def _parse_amount(raw: str) -> Optional[float]:
    """'- 3 108.25' → -3108.25"""
    raw = raw.replace(" ", "").replace("\xa0", "")
    try:
        return float(raw)
    except ValueError:
        return None


def parse_ozon_pdf(file_bytes: bytes) -> list[dict]:
    """
    Принимает байты PDF-файла выписки Озон Банка.
    Возвращает список транзакций:
      { date, description, amount, emoji, category, raw }
    """
    import io

    transactions = []

    with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
        full_text = ""
        for page in pdf.pages:
            text = page.extract_text()
            if text:
                full_text += text + "\n"

    # ── Разбиваем на строки и ищем блоки транзакций ───────────────────────────
    # Каждая транзакция начинается со строки вида:
    #   "25.05.2026 11:12:54  10738806677  DOSTAVKA IZ PYATEROCHK ..."
    # или дата и время могут быть разделены переносом.
    #
    # Стратегия: находим все вхождения дат и вырезаем блоки между ними.

    # Паттерн даты в начале строки
    DATE_RE = re.compile(
        r'(\d{2}\.\d{2}\.\d{4})\s+'       # дата
        r'(\d{2}:\d{2}:\d{2})\s+'          # время
        r'(\d{6,})\s+'                      # номер документа
        r'(.+?)\s+'                          # описание (жадный до суммы)
        r'([+-]\s*[\d\s]+\.\d{2})',          # сумма
        re.DOTALL
    )

    # Более надёжный подход — построчный конечный автомат
    lines = full_text.splitlines()

    # Ищем строки с датой DD.MM.YYYY
    date_line_re = re.compile(r'^(\d{2}\.\d{2}\.\d{4})\s+(\d{2}:\d{2}:\d{2})')
    amount_re    = re.compile(r'([+-])\s*([\d\s\xa0]+\.\d{2})')

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        dm = date_line_re.match(line)
        if not dm:
            i += 1
            continue

        date_str = dm.group(1)   # DD.MM.YYYY
        time_str = dm.group(2)

        # Собираем весь блок до следующей даты (макс 8 строк)
        block_lines = [line]
        j = i + 1
        while j < len(lines) and j < i + 8:
            next_line = lines[j].strip()
            if date_line_re.match(next_line):
                break
            block_lines.append(next_line)
            j += 1

        block = " ".join(block_lines)

        # Ищем суммы в блоке (берём первую)
        amounts = amount_re.findall(block)
        if not amounts:
            i += 1
            continue

        sign, amt_raw = amounts[0]
        amount = _parse_amount(sign + amt_raw)
        if amount is None:
            i += 1
            continue

        # Пропускаем входящие (+ суммы от пополнений)
        # Но оставляем — пусть пользователь сам решает
        is_debit = (sign == "-")

        # Описание — всё между номером документа и первой суммой
        # Ищем номер документа (7-11 цифр подряд)
        doc_re = re.compile(r'\d{7,11}')
        doc_m  = doc_re.search(block)
        if doc_m:
            after_doc = block[doc_m.end():].strip()
        else:
            after_doc = block

        # Обрезаем хвост с суммой
        amt_pos = amount_re.search(after_doc)
        description = after_doc[:amt_pos.start()].strip() if amt_pos else after_doc.strip()
        # Чистим мусор: "дата 2026-05-25 время 11:12:54", "сумма X ?", лишние пробелы
        description = re.sub(r'дата\s+\d{4}-\d{2}-\d{2}\s+время\s+[\d:]+', '', description)
        description = re.sub(r'сумма\s+[\d\s.]+[?₽]', '', description)
        description = re.sub(r'\s{2,}', ' ', description).strip()

        if not description or len(description) < 3:
            i += 1
            continue

        emoji, category = _categorize(description)

        # Если правило вернуло None — это приход, пропускаем
        if emoji is None:
            i = j
            continue

        # Пропускаем приходы (пополнения карты) — не расходы
        if not is_debit:
            i = j
            continue

        # Форматируем дату в YYYY-MM-DD
        d, m_d, y = date_str.split(".")
        iso_date = f"{y}-{m_d}-{d}"

        transactions.append({
            "date":        iso_date,
            "description": description,
            "amount":      abs(amount),
            "emoji":       emoji,
            "category":    category,
        })

        i = j

    return transactions
