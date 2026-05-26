"""
Парсер банковских выписок Озон Банка (PDF).

Ключевой принцип: делим весь текст по паттерну DD.MM.YYYY —
каждый блок между двумя датами = одна транзакция.
Ищем отрицательную сумму в блоке и весь остальной текст — описание.
"""

import re
import io
import pdfplumber
from typing import Optional

BANK_RULES = [
    (["DOSTAVKA IZ PYATEROCHK", "YANDEX*EDA", "YANDEX*5814*EDA",
      "SAMOKAT", "SBERMARKET", "KUPER", "DELIVERY CLUB"],
     "🍕", "Доставка еды"),

    (["YANDEX*4121*FASTEN", "YANDEX*4121*GO", "YANDEX*GO", "FASTEN", "UBER"],
     "🚕", "Такси"),

    (["YANDEX*7999*SCOOTERS", "SCOOTER", "WHOOSH", "URENT"],
     "🛴", "Самокаты"),

    (["YANDEX", "YA.RU"],
     "💛", "Яндекс"),

    # Связь — кириллица и латиница
    (["BEELINE", "БИЛАЙН", "BILAYN",
      " MTS ", " МТС ", "МТСПЛАТЕЖ",
      "MEGAFON", "МЕГАФОН",
      "TELE2", "ТЕЛЕ2",
      "ROSTELECOM", "РОСТЕЛЕКОМ",
      "TRICOLOR", "ТРИКОЛОР",
      "ПОЛЬЗУ БИЛАЙН", "ПОЛЬЗУ МТС", "ПОЛЬЗУ МЕГАФОН"],
     "📱", "Связь"),

    # Транспорт — кириллица и латиница
    (["WWW.RZD.RU", "RZD.RU", "AEROFLOT", "S7 ", "POBEDA", "TUTU",
      "OZONTRAVEL", "OZON TRAVEL", "OZON (OZON",
      "ПЛАТФОРМЕ OZON", "PLATFORM OZON", "OZONTRAVELMKK",
      "AVIASALES", "TRIP.COM", "BILET", "RAILWAY", "AIRPORT",
      "AVITO TRAVEL", "АВИТО ТРЕВЕЛ"],
     "✈️", "Билеты / Транспорт"),

    (["KRASNOE&BELOE", "KRASNOE", "ALKOTEKA", "ALKOGOL", "VINLAB", "GRADUS"],
     "🍺", "Алкоголь"),

    (["VBAR", "V-BAR", " BAR", "BAR ", "PUB", "ROCKS BAR",
      "BEY BAR", "SALOON", "WESTERN", "KHLEB DA KHMEL"],
     "🍸", "Бары"),

    (["RESTAURANT", "KAFE", "CAFE", "GASTROKAFE", "GASTRONOM",
      "BUFFET", "CHAIKA", "FRANK.", "MESTNYJ", "MINDAL",
      "QSR", "BURGER", "MCDONALDS", "KFC", "SUBWAY", "PIZZA", "TEFI"],
     "🍽️", "Кафе / Ресторан"),

    (["MAGNIT", "PYATEROCHKA", "LENTA", "AUCHAN", "PEREKRESTOK",
      "DIKSI", "PRODUKTY", "AGROKOMPLEKS", "VKUSVILL", "METRO "],
     "🛒", "Продукты"),

    (["AZS", "LUKOIL", "GAZPROMNEFT", "ROSNEFT", "TATNEFT", "AU404", "NKHP"],
     "⛽", "АЗС / Топливо"),

    (["APTEKA", "EAPTEKA", "36.6", "RIGLA", "GORZDRAV"],
     "💊", "Аптека"),

    (["SPORTMASTER", "DECATHLON", "INTERSPORT"],
     "🏋️", "Спорт"),

    (["ZARA", "H&M", "WILDBERRIES", "WB ", "LAMODA"],
     "👗", "Одежда / Шопинг"),

    (["KINO", "CINEMA", "KINOMAX", "MUSEUM", "FOTOKUB", "CASE-BATTLE",
      "CASE BATTLE", "AQUAPARK"],
     "🎢", "Развлечения"),

    (["P2P", " SBP", "SBP ", "PEREVOD", "TRANSFER"],
     "💸", "Переводы"),
]

# Служебные — пропускаем
SKIP_WORDS = [
    "ПОПОЛНЕНИЕ", "ЗАЧИСЛЕНИЕ", "SALARY", "ЗАРПЛАТА",
    "ВОЗВРАТ ПЛАТЕЖА",
]


def _categorize(text: str) -> tuple:
    t = text.upper()
    for kws, emoji, name in BANK_RULES:
        for kw in kws:
            if kw.upper() in t:
                return emoji, name
    return "💰", "Другое"


def _is_incoming(text: str) -> bool:
    t = text.upper()
    return any(kw.upper() in t for kw in SKIP_WORDS)


def _parse_amount(sign: str, raw: str) -> Optional[float]:
    cleaned = re.sub(r'[\s\xa0  ]', '', raw)
    try:
        return float(cleaned)
    except ValueError:
        return None


def _clean(text: str) -> str:
    """Убирает технический мусор."""
    # Временны́е метки и даты
    text = re.sub(r'дата\s+\d{4}-\d{2}-\d{2}', '', text, flags=re.IGNORECASE)
    text = re.sub(r'время\s+\d{2}:\d{2}:\d{2}', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\b\d{2}:\d{2}:\d{2}\b', '', text)
    text = re.sub(r'\b\d{4}-\d{2}-\d{2}\b', '', text)
    # Суммы (формат "сумма X.XX")
    text = re.sub(r'сумма\s+[\d\s.,]+', '', text, flags=re.IGNORECASE)
    # НДС
    text = re.sub(r'без\s+ндс\.?', '', text, flags=re.IGNORECASE)
    text = re.sub(r'ндс\s+(не)?облагается', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\bндс\b', '', text, flags=re.IGNORECASE)
    # Символ рубля и заменители
    text = re.sub(r'[₽?]', '', text)
    # Длинные числа (номера документов, телефонов)
    text = re.sub(r'\b\d{9,}\b', '', text)
    # Множественные пробелы и пустые строки
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip(' ,.-\n')


def parse_ozon_pdf(file_bytes: bytes) -> list:
    """Парсит PDF-выписку Озон Банка. Возвращает список расходов."""
    transactions = []

    # Извлекаем весь текст
    with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
        full_text = ""
        for page in pdf.pages:
            t = page.extract_text() or ""
            full_text += t + "\n"

    AMOUNT_RE = re.compile(r'([+\-])\s*([\d][\d\s\xa0 ]*\.\d{2})')
    # Делим по паттерну DD.MM.YYYY
    DATE_PAT  = re.compile(r'(\d{2}\.\d{2}\.\d{4})')

    parts = DATE_PAT.split(full_text)
    # parts = [pre_text, date1, block1, date2, block2, ...]
    # parts[0] — текст до первой даты (заголовок отчёта) — пропускаем

    for k in range(1, len(parts) - 1, 2):
        date_str  = parts[k]          # DD.MM.YYYY
        block     = parts[k + 1]      # текст до следующей даты

        # Ищем первую отрицательную сумму
        m = AMOUNT_RE.search(block)
        if not m:
            continue
        if m.group(1) != '-':
            continue
        amount = _parse_amount('-', m.group(2))
        if amount is None or amount <= 0:
            continue

        # Описание = весь блок минус суммы
        description = AMOUNT_RE.sub(' ', block)
        description = _clean(description)

        # Пропускаем пополнения / зарплаты
        if _is_incoming(description):
            continue

        # Пропускаем блоки без содержательного описания
        if not description or len(description) < 2:
            continue

        emoji, category = _categorize(description)

        d, mo, y = date_str.split('.')
        transactions.append({
            "date":        f"{y}-{mo}-{d}",
            "description": description[:120],
            "amount":      round(abs(amount), 2),
            "emoji":       emoji,
            "category":    category,
        })

    return transactions
