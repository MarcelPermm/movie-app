"""
Парсер банковских выписок Озон Банка (PDF).

Две структуры строк в выписке:
  Pattern 1: DD.MM.YYYY HH:MM:SS  DOCNUM  MERCHANT CITY RU ... -AMOUNT -AMOUNT
  Pattern 2: DD.MM.YYYY            (дата на отдельной строке)
             DOCNUM  MERCHANT CITY RU ... -AMOUNT -AMOUNT
             HH:MM:SS              (время на следующей строке)
"""

import re
import io
import pdfplumber
from typing import Optional

# ── Словарь категорий ─────────────────────────────────────────────────────────
BANK_RULES = [
    # Доставка еды (до Яндекса — EDA не попадёт в такси)
    (["DOSTAVKA IZ PYATEROCHK", "YANDEX*EDA", "YANDEX*5814*EDA",
      "SAMOKAT", "SBERMARKET", "KUPER", "DELIVERY CLUB", "BRONIBOY",
      "VKUSNO", "DOMINOS", "SUSHI"],
     "🍕", "Доставка еды"),

    # Такси
    (["YANDEX*4121*FASTEN", "YANDEX*4121*GO", "YANDEX*GO",
      "FASTEN", "CITYMOBIL", "UBER"],
     "🚕", "Такси"),

    # Самокаты / велосипеды
    (["YANDEX*7999*SCOOTERS", "SCOOTER", "WHOOSH", "URENT", "VELOBIKE"],
     "🛴", "Самокаты"),

    # Яндекс (прочие сервисы)
    (["YANDEX", "YA.RU"],
     "💛", "Яндекс"),

    # РЖД / авиа / транспорт
    (["WWW.RZD.RU", "RZD.RU", "AEROFLOT", "S7 ", "POBEDA", "TUTU",
      "OZON TRAVEL", "OZONTRAVEL", "AVIASALES", "TRIP.COM",
      "BILET", "RAILWAY", "AIRPORT"],
     "✈️", "Билеты / Транспорт"),

    # Алкоголь
    (["KRASNOE&BELOE", "KRASNOE", "ALKOTEKA", "ALKOGOL",
      "VINLAB", "GRADUS", "WINELAB", "NOVUS"],
     "🍺", "Алкоголь"),

    # Бары и ночные заведения
    (["VBAR", "V-BAR", " BAR", "BAR ", "PUB", "ROCKS BAR",
      "BEY BAR", "SALOON", "WESTERN", "KHLEB DA KHMEL",
      "COCKTAIL", "NIGHT CLUB"],
     "🍸", "Бары"),

    # Рестораны и кафе
    (["RESTAURANT", "KAFE", "CAFE", "GASTROKAFE", "GASTRONOM",
      "BUFFET", "CHAIKA", "FRANK.", "MESTNYJ", "MINDAL",
      "QSR", "BURGER", "MCDONALDS", "KFC", "SUBWAY",
      "PIZZA", "TEFI", "FOOOD", "STOLOVAYA", "BISTRO",
      "GRILL", "KITCHEN", "RESTORAN"],
     "🍽️", "Кафе / Ресторан"),

    # Продукты
    (["MAGNIT", "PYATEROCHKA", "LENTA", "AUCHAN", "PEREKRESTOK",
      "DIKSI", "PRODUKTY", "AGROKOMPLEKS", "VKUSVILL", "MYASNITSKIY",
      "METRO ", "GLOBUS", "SPAR ", "FARMER", "MIRATORG"],
     "🛒", "Продукты"),

    # АЗС
    (["AZS", "LUKOIL", "GAZPROMNEFT", "ROSNEFT", "TATNEFT",
      "BP ", " BP", "SHELL", "AU404", "NKHP", "NEFTYANOY"],
     "⛽", "АЗС / Топливо"),

    # Аптека
    (["APTEKA", "EAPTEKA", "36.6", "RIGLA", "GORZDRAV",
      "ZDRAVCITY", "FARMACIA", "PHARMA"],
     "💊", "Аптека"),

    # Спорт
    (["SPORTMASTER", "DECATHLON", "INTERSPORT", "ADIDAS",
      "SPORT "],
     "🏋️", "Спорт"),

    # Одежда / шопинг
    (["ZARA", "H&M", "HM ", "OZON ", "WILDBERRIES", "WB ",
      "LAMODA", "GLORIA", "BEFREE"],
     "👗", "Одежда / Шопинг"),

    # Развлечения
    (["KINO", "CINEMA", "KINOMAX", "SINEMA", "MUSEUM",
      "FOTOKUB", "AFON", "CASE-BATTLE", "CASE BATTLE",
      "AQUAPARK", "ATTRACTION", "AMUSEMENT", "QUEST"],
     "🎢", "Развлечения"),

    # Связь
    (["BEELINE", "MTS ", " MTS", "MEGAFON", "TELE2",
      "ROSTELECOM", "TRICOLOR"],
     "📱", "Связь"),

    # Переводы исходящие
    (["P2P", "SBP ", " SBP", "PEREVOD", "TRANSFER"],
     "💸", "Переводы"),
]


def _categorize(description: str) -> tuple:
    desc_upper = description.upper()
    for keywords, emoji, name in BANK_RULES:
        for kw in keywords:
            if kw.upper() in desc_upper:
                return emoji, name
    return "💰", "Другое"


def _parse_amount(sign: str, raw: str) -> Optional[float]:
    cleaned = re.sub(r'[\s\xa0 ]', '', raw)
    try:
        val = float(cleaned)
        return -val if sign == "-" else val
    except ValueError:
        return None


def _clean_description(text: str) -> str:
    """Убирает технические части, оставляет название мерчанта."""
    # Убираем 'дата 2026-05-25', 'время 11:12:54', 'сумма X.XX ₽' и т.п.
    text = re.sub(r'дата\s+\d{4}-\d{2}-\d{2}', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\d{4}-\d{2}-\d{2}', '', text)  # остатки дат
    text = re.sub(r'время\s+\d{2}:\d{2}:\d{2}', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\d{2}:\d{2}:\d{2}', '', text)  # время
    text = re.sub(r'сумма\s+[\d\s.,]+[₽?]?', '', text, flags=re.IGNORECASE)
    text = re.sub(r'[₽?]', '', text)
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip(' ,.')


def parse_ozon_pdf(file_bytes: bytes) -> list:
    """
    Принимает байты PDF-выписки Озон Банка.
    Возвращает список транзакций (только расходы — отрицательные суммы).
    """
    transactions = []

    with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
        all_lines = []
        for page in pdf.pages:
            text = page.extract_text() or ""
            all_lines.extend(text.splitlines())
            all_lines.append("")  # разрыв страницы

    DATE_ALONE_RE = re.compile(r'^(\d{2}\.\d{2}\.\d{4})\s*$')
    DATE_TIME_RE  = re.compile(r'^(\d{2}\.\d{2}\.\d{4})\s+(\d{2}:\d{2}:\d{2})\s+(.*)')
    DOC_START_RE  = re.compile(r'^(\d{7,12})\s+(.*)')
    AMOUNT_RE     = re.compile(r'([+\-])\s*([\d\s\xa0 ]+\.\d{2})')

    def process_block(date_str: str, block: str):
        """Извлекает транзакцию из блока текста (после номера документа)."""
        # Чистим от "дата 2026-05-25" внутри блока (сокращает шум для amount_re)
        # Находим ВСЕ вхождения amount_re
        amounts = AMOUNT_RE.findall(block)
        if not amounts:
            return

        sign, amt_raw = amounts[0]
        amount = _parse_amount(sign, amt_raw)
        if amount is None or amount >= 0:
            return  # пропускаем входящие

        # Описание: всё от начала блока до первой суммы
        amt_match = AMOUNT_RE.search(block)
        raw_desc = block[:amt_match.start()].strip() if amt_match else block.strip()

        # Убираем остатки номера документа в начале (если попал)
        raw_desc = re.sub(r'^\d{7,12}\s*', '', raw_desc)

        description = _clean_description(raw_desc)
        if not description or len(description) < 2:
            description = "расход"

        emoji, category = _categorize(description)

        d, m, y = date_str.split(".")
        iso_date = f"{y}-{m}-{d}"

        transactions.append({
            "date":        iso_date,
            "description": description,
            "amount":      abs(amount),
            "emoji":       emoji,
            "category":    category,
        })

    i = 0
    n = len(all_lines)

    while i < n:
        line = all_lines[i].strip()

        # ── Pattern 1: дата + время + doc + описание на одной строке ──────────
        m1 = DATE_TIME_RE.match(line)
        if m1:
            date_str = m1.group(1)
            rest     = m1.group(3)  # всё после HH:MM:SS

            # Пропускаем строки без числа документа (заголовки таблицы, итоги)
            doc_m = DOC_START_RE.match(rest)
            if doc_m:
                content = doc_m.group(2)
                # Берём ещё до 2 следующих строк (на случай переноса)
                for extra in range(1, 3):
                    if i + extra < n:
                        nxt = all_lines[i + extra].strip()
                        if DATE_ALONE_RE.match(nxt) or DATE_TIME_RE.match(nxt):
                            break
                        content += " " + nxt
                process_block(date_str, content)
            i += 1
            continue

        # ── Pattern 2: дата на отдельной строке ───────────────────────────────
        m2 = DATE_ALONE_RE.match(line)
        if m2:
            date_str = m2.group(1)

            # Ищем следующую непустую строку — должна начинаться с doc number
            j = i + 1
            while j < n and not all_lines[j].strip():
                j += 1

            if j < n:
                content_line = all_lines[j].strip()
                doc_m = DOC_START_RE.match(content_line)
                if doc_m:
                    content = doc_m.group(2)
                    # Берём ещё до 2 следующих строк
                    for extra in range(1, 3):
                        if j + extra < n:
                            nxt = all_lines[j + extra].strip()
                            if DATE_ALONE_RE.match(nxt) or DATE_TIME_RE.match(nxt):
                                break
                            # Не берём строки с только временем
                            if re.match(r'^\d{2}:\d{2}:\d{2}$', nxt):
                                break
                            content += " " + nxt
                    process_block(date_str, content)
                    i = j + 1
                    continue

        i += 1

    return transactions
