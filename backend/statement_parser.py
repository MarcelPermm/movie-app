"""
Парсер банковских выписок Озон Банка (PDF).

Делим весь текст по паттерну DD.MM.YYYY — каждый блок между двумя
датами = одна транзакция. Ищем отрицательную сумму в блоке, весь
остальной текст — описание. По ключевым словам определяем категорию
и торговую точку (merchant).
"""

import re
import io
import pdfplumber
from typing import Optional

# ─── Категории ────────────────────────────────────────────────────────────────

BANK_RULES = [
    # Доставка еды
    (["DOSTAVKA IZ PYATEROCHK", "YANDEX*EDA", "YANDEX*5814*EDA",
      "SAMOKAT", "SAMOCAT", "SBERMARKET", "KUPER", "DELIVERY CLUB",
      "DELIVERYCLUB", "YANDEX LAVKA", "YANDEX*LAVKA", "LAVKA"],
     "🍕", "Доставка еды"),

    # Такси
    (["YANDEX*4121*FASTEN", "YANDEX*4121*GO", "YANDEX*GO", "FASTEN", "UBER",
      "CITYMOBIL", "CITY MOBIL"],
     "🚕", "Такси"),

    # Каршеринг
    (["DELIMOBIL", "ДЕЛИМОБИЛЬ", "YANDEX*DRIVE", "YANDEX DRIVE", "CITYDRIVE",
      "CARSHARINGRUS", "BELKACAR", "СИТИДРАЙВ", "ANYDRIVE", "CARSHARING"],
     "🚗", "Каршеринг"),

    # Самокаты
    (["YANDEX*7999*SCOOTERS", "WHOOSH", "URENT", "ЮРЕНТ", "MOLNIA", "MOLNIYA"],
     "🛴", "Самокаты"),

    # Яндекс (общее — после более специфичных Яндекс-правил)
    (["YANDEX", "YA.RU"],
     "💛", "Яндекс"),

    # Связь
    (["BEELINE", "БИЛАЙН", "BILAYN",
      " MTS ", " МТС ", "МТСПЛАТЕЖ",
      "MEGAFON", "МЕГАФОН",
      "TELE2", "ТЕЛЕ2",
      "ROSTELECOM", "РОСТЕЛЕКОМ",
      "MGTS", "МГТС",
      "TRICOLOR", "ТРИКОЛОР",
      "LIFECELL", "MOTIV",
      "ПОЛЬЗУ БИЛАЙН", "ПОЛЬЗУ МТС", "ПОЛЬЗУ МЕГАФОН", "ПОЛЬЗУ TELE2"],
     "📱", "Связь"),

    # Транспорт / Билеты (авиа, ж/д)
    (["WWW.RZD.RU", "RZD.RU", "AEROFLOT", "S7 ", "POBEDA", "TUTU",
      "OZONTRAVEL", "OZON TRAVEL", "OZON (OZON",
      "ПЛАТФОРМЕ OZON", "PLATFORM OZON", "OZONTRAVELMKK",
      "AVIASALES", "TRIP.COM", "BILET", "RAILWAY", "AIRPORT",
      "AVITO TRAVEL", "АВИТО ТРЕВЕЛ",
      "URAL AIRLINES", "SMARTAVIA", "NORDWIND",
      "KUPIBILET", "ONETWOTRIP", "TUTU.RU"],
     "✈️", "Билеты / Транспорт"),

    # Городской транспорт
    (["TROIKA", "ТРОЙКА", "MOSMETRO", "МОСМЕТРО",
      "MOSGORTRANS", "МОСГОРТРАНС", "T-KARTA", "ТРАНСПОРТНАЯ КАРТА"],
     "🚇", "Городской транспорт"),

    # АЗС / Топливо
    (["AZS", " АЗС", "LUKOIL", "ЛУКОЙЛ", "GAZPROMNEFT", "ГАЗПРОМНЕФТЬ",
      "ROSNEFT", "РОСНЕФТЬ", "TATNEFT", "ТАТНЕФТЬ", "AU404", "NKHP",
      "BASHNEFT", "БАШНЕФТЬ", "SHELL", "TOTAL", "NESTE", "ESSO"],
     "⛽", "АЗС / Топливо"),

    # Продукты
    (["MAGNIT", "МАГНИТ", "PYATEROCHKA", "ПЯТЁРОЧКА", "PYATYOROCHKA",
      "LENTA", "ЛЕНТА", "AUCHAN", "АШАН", "PEREKRESTOK", "ПЕРЕКРЁСТОК",
      "DIKSI", "ДИКСИ", "VKUSVILL", "ВКУСВИЛЛ", "METRO ", "МЕТРО",
      "AZBUKA", "АЗБУКА ВКУСА", "OKEY", "О'КЕЙ", "GLOBUS", "ГЛОБУС",
      "SPAR", "СПАР", "PRODUKTY", "ПРОДУКТЫ",
      "AGROKOMPLEKS", "АГРОКОМПЛЕКС",
      "SVETOFOR", "СВЕТОФОР", "MONETKA", "МОНЕТКА",
      "FIX PRICE", "FIXPRICE", "ФИКС ПРАЙС",
      "BRISTOL", "БРИСТОЛЬ"],
     "🛒", "Продукты"),

    # Алкоголь
    (["KRASNOE&BELOE", "KRASNOE", "КРАСНОЕ БЕЛОЕ", "ALKOTEKA", "АЛКОТЕКА",
      "VINLAB", "ВИНЛАБ", "GRADUS", "ГРАДУС", "ДОБРОЦЕН"],
     "🍺", "Алкоголь"),

    # Бары
    (["VBAR", "V-BAR", " BAR", "BAR ", "PUB", "ROCKS BAR",
      "BEY BAR", "SALOON", "WESTERN", "KHLEB DA KHMEL", "ХЛЕБ ДА ХМЕЛЬ",
      "PIVBAR", "ПИВБАР", "BREWERY"],
     "🍸", "Бары"),

    # Кафе / Ресторан
    (["RESTAURANT", "KAFE", "CAFE", "КАФЕ", "GASTROKAFE", "GASTRONOM",
      "BUFFET", "CHAIKA", "FRANK.", "MESTNYJ", "MINDAL",
      "QSR", "BURGER", "MCDONALDS", "KFC", "SUBWAY", "PIZZA", "TEFI",
      "BURGER KING", "BURGERKING", "DOMINOS", "DOMINO",
      "PAPA JOHNS", "PAPAJOHNS",
      "SHOKOLADNITSA", "ШОКОЛАДНИЦА", "KOFEMANYA", "КОФЕМАНИЯ",
      "SURF COFFEE", "COFFEE", "КОФЕ",
      "STARBUCKS", "DODO", "ДОДО",
      "SUSHI", "СУШИ", "WOK", "ВОК",
      "LAVASH", "ЛАВАШ", "GRILL", "ГРИЛЬ",
      "BISTRO", "БИСТРО", "STOLOVAYA", "СТОЛОВАЯ",
      "TEREMOK", "ТЕРЕМОК", "KROSHKA KARTOSHKA",
      "VAPIANO", "PINTA", "PINTERA"],
     "🍽️", "Кафе / Ресторан"),

    # Аптека
    (["APTEKA", "АПТЕКА", "EAPTEKA", "36.6", "RIGLA", "РИГЛА",
      "GORZDRAV", "ГОРЗДРАВ", "ZDRAVCITY",
      "PILULI", "APTECHKA", "SOCIALNAYA APTEKA"],
     "💊", "Аптека"),

    # Здоровье / Клиники
    (["CLINICA", "КЛИНИКА", "STOMATOLOGY", "СТОМАТОЛОГИЯ",
      "MEDCENTER", "МЕДЦЕНТР", "HOSPITAL", "БОЛЬНИЦА",
      "POLYCLINIC", "ПОЛИКЛИНИКА",
      "INVITRO", "ИНВИТРО", "HELIX", "ХЕЛИКС",
      "DENTIST", "ДАНТИСТ", "DENTAL", "ДЕНТАЛ",
      "GEMOTEST", "ГЕМОТЕСТ", "CMD", "МЕДСИ",
      "SMDCLINIC", "EUROMED"],
     "🏥", "Здоровье / Клиники"),

    # Красота / SPA
    (["SALON", "САЛОН", "BEAUTY", "КРАСОТА",
      "PARIKMAKHERSKAYA", "ПАРИКМАХЕР",
      "MANICURE", "МАНИКЮР", "PEDICURE", "ПЕДИКЮР",
      "SPA", "СПА", "MASSAZH", "МАССАЖ",
      "KOSMETOLOG", "КОСМЕТОЛОГ", "NAIL", "НОГТИ"],
     "💅", "Красота / SPA"),

    # Спорт
    (["SPORTMASTER", "СПОРТМАСТЕР", "DECATHLON", "ДЕКАТЛОН", "INTERSPORT",
      "WORLD CLASS", "WORLDCLASS", "FITNESS", "ФИТНЕС",
      "GYM ", " ЗАЛ"],
     "🏋️", "Спорт"),

    # Одежда / Шопинг
    (["ZARA", "H&M", "WILDBERRIES", "WB ", "LAMODA", "ЛАМОДА",
      "OZON", "ОЗОН",
      "AVITO", "АВИТО",
      "ALIEXPRESS", "ALI ", "ALIBABA",
      "GLORIA JEANS", "BEFREE", "ТВОЕ ", "TVOE",
      "INCITY", "DETSKY MIR", "ДЕТСКИЙ МИР",
      "BAON", "UNIQLO", "COS ", "BERSHKA",
      "PULL&BEAR", "MASSIMO DUTTI", "MANGO"],
     "👗", "Одежда / Шопинг"),

    # Развлечения
    (["KINO", "КИНО", "CINEMA", "СИНЕМА", "KINOMAX", "КИНОТЕАТР",
      "MUSEUM", "МУЗЕЙ", "FOTOKUB", "CASE-BATTLE", "CASE BATTLE",
      "AQUAPARK", "АКВАПАРК",
      "QUEST", "КВЕСТ", "ESCAPE",
      "BILLIARD", "БИЛЬЯРД", "BOWLING", "БОУЛИНГ",
      "KARAOKE", "КАРАОКЕ",
      "GAME", "ИГРА", "GAMER"],
     "🎢", "Развлечения"),

    # Подписки / Цифровые сервисы
    (["NETFLIX", "НЕТФЛИКС", "SPOTIFY",
      "KINOPOISK", "КИНОПОИСК", "PREMIER.ONE", "PREMIER ",
      "IVI.RU", "IVI ", "OKKO", "ОKKO",
      "APPSTORE", "APP STORE", "GOOGLE PLAY", "GOOGLEPLAY",
      "STEAM", "СТИМ", "PLAYSTATION", "XBOX",
      "COURSERA", "SKILLBOX", "GEEKBRAINS",
      "ADOBE", "MICROSOFT", "OFFICE 365", "DROPBOX",
      "TELEGRAM", "CHATGPT", "OPENAI"],
     "📺", "Подписки / Диджитал"),

    # ЖКХ / Аренда
    (["ZHKH", "ЖКХ", "KVARTPLATA", "КВАРТПЛАТА",
      "ERC ", "ЕРЦ ", "GKH", "ГКХ",
      "MOSENERGO", "МОСЭНЕРГО", "ENERGOSBYT", "ЭНЕРГОСБЫТ",
      "VODOKANAL", "ВОДОКАНАЛ",
      "ROSSETI", "РОССЕТИ", "INTERRAO", "ИНТЕР РАО",
      "MKD ", "МКД ", "GOSUSLUGI", "ГОСУСЛУГИ"],
     "🏠", "ЖКХ / Аренда"),

    # Переводы
    (["P2P", " SBP", "SBP ", "PEREVOD", "TRANSFER"],
     "💸", "Переводы"),
]

# Словарь keyword → отображаемое название торговой точки
MERCHANT_DISPLAY = {
    # Связь
    "BEELINE": "Билайн", "БИЛАЙН": "Билайн", "BILAYN": "Билайн",
    "ПОЛЬЗУ БИЛАЙН": "Билайн",
    "MEGAFON": "МегаФон", "МЕГАФОН": "МегаФон", "ПОЛЬЗУ МЕГАФОН": "МегаФон",
    "МТСПЛАТЕЖ": "МТС", " MTS ": "МТС", " МТС ": "МТС", "ПОЛЬЗУ МТС": "МТС",
    "TELE2": "Tele2", "ТЕЛЕ2": "Tele2", "ПОЛЬЗУ TELE2": "Tele2",
    "ROSTELECOM": "Ростелеком", "РОСТЕЛЕКОМ": "Ростелеком",
    "MGTS": "МГТС", "МГТС": "МГТС",
    "TRICOLOR": "Триколор", "ТРИКОЛОР": "Триколор",
    # Транспорт
    "OZONTRAVEL": "Ozon Travel", "OZONTRAVELMKK": "Ozon Travel",
    "ПЛАТФОРМЕ OZON": "Ozon Travel", "OZON TRAVEL": "Ozon Travel",
    "OZON (OZON": "Ozon Travel",
    "AEROFLOT": "Аэрофлот",
    "S7 ": "S7 Airlines",
    "POBEDA": "Победа",
    "RZD.RU": "РЖД", "WWW.RZD.RU": "РЖД",
    "AVIASALES": "Aviasales",
    "TUTU": "Tutu.ru",
    "KUPIBILET": "KupiBilet",
    "ONETWOTRIP": "OneTwoTrip",
    # Такси
    "YANDEX*4121*GO": "Яндекс Такси", "YANDEX*GO": "Яндекс Такси",
    "YANDEX*4121*FASTEN": "Яндекс Такси",
    "UBER": "Uber",
    "CITYMOBIL": "Ситимобил", "CITY MOBIL": "Ситимобил",
    "FASTEN": "Яндекс Такси",
    # Каршеринг
    "DELIMOBIL": "Делимобиль", "ДЕЛИМОБИЛЬ": "Делимобиль",
    "YANDEX*DRIVE": "Яндекс Драйв", "YANDEX DRIVE": "Яндекс Драйв",
    "CITYDRIVE": "СитиДрайв", "СИТИДРАЙВ": "СитиДрайв",
    "BELKACAR": "BelkaCar",
    # Самокаты
    "WHOOSH": "Whoosh",
    "URENT": "uRent", "ЮРЕНТ": "uRent",
    "YANDEX*7999*SCOOTERS": "Яндекс Самокаты",
    # Доставка
    "YANDEX*EDA": "Яндекс Еда", "YANDEX*5814*EDA": "Яндекс Еда",
    "YANDEX LAVKA": "Яндекс Лавка", "YANDEX*LAVKA": "Яндекс Лавка", "LAVKA": "Яндекс Лавка",
    "SAMOKAT": "Самокат", "SAMOCAT": "Самокат",
    "SBERMARKET": "СберМаркет",
    "KUPER": "Купер",
    "DOSTAVKA IZ PYATEROCHK": "Пятёрочка Доставка",
    "DELIVERY CLUB": "Delivery Club", "DELIVERYCLUB": "Delivery Club",
    # Продукты
    "PYATEROCHKA": "Пятёрочка", "ПЯТЁРОЧКА": "Пятёрочка", "PYATYOROCHKA": "Пятёрочка",
    "MAGNIT": "Магнит", "МАГНИТ": "Магнит",
    "LENTA": "Лента", "ЛЕНТА": "Лента",
    "AUCHAN": "Ашан", "АШАН": "Ашан",
    "PEREKRESTOK": "Перекрёсток", "ПЕРЕКРЁСТОК": "Перекрёсток",
    "VKUSVILL": "ВкусВилл", "ВКУСВИЛЛ": "ВкусВилл",
    "DIKSI": "Дикси", "ДИКСИ": "Дикси",
    "AZBUKA": "Азбука Вкуса", "АЗБУКА ВКУСА": "Азбука Вкуса",
    "OKEY": "О'Кей",
    "GLOBUS": "Глобус",
    "METRO ": "Метро", "МЕТРО": "Метро",
    "SPAR": "Spar", "СПАР": "Spar",
    "FIX PRICE": "Fix Price", "FIXPRICE": "Fix Price", "ФИКС ПРАЙС": "Fix Price",
    "SVETOFOR": "Светофор", "СВЕТОФОР": "Светофор",
    "MONETKA": "Монетка", "МОНЕТКА": "Монетка",
    "BRISTOL": "Бристоль", "БРИСТОЛЬ": "Бристоль",
    "AGROKOMPLEKS": "Агрокомплекс", "АГРОКОМПЛЕКС": "Агрокомплекс",
    # Алкоголь
    "KRASNOE&BELOE": "Красное & Белое", "KRASNOE": "Красное & Белое",
    "КРАСНОЕ БЕЛОЕ": "Красное & Белое",
    "VINLAB": "ВинЛаб", "ВИНЛАБ": "ВинЛаб",
    "ALKOTEKA": "Алкотека", "АЛКОТЕКА": "Алкотека",
    "GRADUS": "Градус", "ГРАДУС": "Градус",
    # АЗС
    "LUKOIL": "Лукойл", "ЛУКОЙЛ": "Лукойл",
    "GAZPROMNEFT": "Газпромнефть", "ГАЗПРОМНЕФТЬ": "Газпромнефть",
    "ROSNEFT": "Роснефть", "РОСНЕФТЬ": "Роснефть",
    "TATNEFT": "Татнефть", "ТАТНЕФТЬ": "Татнефть",
    "BASHNEFT": "Башнефть", "БАШНЕФТЬ": "Башнефть",
    "SHELL": "Shell", "NESTE": "Neste",
    # Кафе/Рестораны
    "MCDONALDS": "McDonald's",
    "KFC": "KFC",
    "BURGER KING": "Burger King", "BURGERKING": "Burger King",
    "STARBUCKS": "Starbucks",
    "DODO": "Додо Пицца", "ДОДО": "Додо Пицца",
    "SHOKOLADNITSA": "Шоколадница", "ШОКОЛАДНИЦА": "Шоколадница",
    "KOFEMANYA": "Кофемания", "КОФЕМАНИЯ": "Кофемания",
    "TEREMOK": "Теремок", "ТЕРЕМОК": "Теремок",
    "SUBWAY": "Subway",
    # Аптека
    "EAPTEKA": "Еаптека",
    "36.6": "Аптека 36.6",
    "RIGLA": "Ригла", "РИГЛА": "Ригла",
    "GORZDRAV": "Горздрав", "ГОРЗДРАВ": "Горздрав",
    # Здоровье
    "INVITRO": "Инвитро", "ИНВИТРО": "Инвитро",
    "HELIX": "Helix", "ХЕЛИКС": "Helix",
    "GEMOTEST": "Гемотест", "ГЕМОТЕСТ": "Гемотест",
    # Шопинг
    "WILDBERRIES": "Wildberries",
    "OZON": "Ozon",
    "AVITO": "Авито", "АВИТО": "Авито",
    "LAMODA": "Lamoda", "ЛАМОДА": "Lamoda",
    "ZARA": "Zara",
    "H&M": "H&M",
    "UNIQLO": "Uniqlo",
    "ALIEXPRESS": "AliExpress",
    "DETSKY MIR": "Детский Мир", "ДЕТСКИЙ МИР": "Детский Мир",
    "GLORIA JEANS": "Gloria Jeans",
    # Подписки
    "NETFLIX": "Netflix",
    "SPOTIFY": "Spotify",
    "KINOPOISK": "Кинопоиск", "КИНОПОИСК": "Кинопоиск",
    "APPSTORE": "App Store", "APP STORE": "App Store",
    "GOOGLE PLAY": "Google Play", "GOOGLEPLAY": "Google Play",
    "STEAM": "Steam",
    "MICROSOFT": "Microsoft", "OFFICE 365": "Microsoft",
    "ADOBE": "Adobe",
    "OPENAI": "OpenAI", "CHATGPT": "ChatGPT",
    # Яндекс
    "YANDEX": "Яндекс", "YA.RU": "Яндекс",
    # Городской транспорт
    "TROIKA": "Тройка", "ТРОЙКА": "Тройка",
    "MOSMETRO": "Московское метро", "МОСМЕТРО": "Московское метро",
}

# Служебные — пропускаем
SKIP_WORDS = [
    "ПОПОЛНЕНИЕ", "ЗАЧИСЛЕНИЕ", "SALARY", "ЗАРПЛАТА",
    "ВОЗВРАТ ПЛАТЕЖА",
    "ПЕРЕВОД СОБСТВЕННЫХ",
    "СОБСТВЕННЫХ СРЕДСТВ",
    "НА СОБСТВЕННЫЙ",
    "НАКОПИТЕЛЬНЫЙ СЧЕТ", "НАКОПИТЕЛЬНЫЙ СЧЁТ",
]


def _categorize(text: str) -> tuple[str, str]:
    t = text.upper()
    for kws, emoji, name in BANK_RULES:
        for kw in kws:
            if kw.upper() in t:
                return emoji, name
    return "💰", "Другое"


def _extract_merchant(text: str, category: str) -> str:
    """Определяет название торговой точки по тексту транзакции."""
    t = text.upper()
    for kw, merchant_name in MERCHANT_DISPLAY.items():
        if kw.upper() in t:
            return merchant_name
    # Если не нашли в словаре — берём первое значимое слово (≥ 3 символов)
    for word in text.split():
        if len(word) >= 3 and word.isalpha():
            return word[:30]
    return category


def _is_incoming(text: str) -> bool:
    t = text.upper()
    return any(kw.upper() in t for kw in SKIP_WORDS)


def _parse_amount(sign: str, raw: str) -> Optional[float]:
    cleaned = re.sub(r'[\s\xa0   ]', '', raw)
    try:
        return float(cleaned)
    except ValueError:
        return None


def _clean(text: str) -> str:
    """Убирает технический мусор из описания транзакции."""
    text = re.sub(r'дата\s+\d{4}-\d{2}-\d{2}', '', text, flags=re.IGNORECASE)
    text = re.sub(r'время\s+\d{2}:\d{2}:\d{2}', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\b\d{2}:\d{2}:\d{2}\b', '', text)
    text = re.sub(r'\b\d{4}-\d{2}-\d{2}\b', '', text)
    text = re.sub(r'сумма\s+[\d\s.,]+', '', text, flags=re.IGNORECASE)
    text = re.sub(r'без\s+ндс\.?', '', text, flags=re.IGNORECASE)
    text = re.sub(r'ндс\s+(не)?облагается', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\bндс\b', '', text, flags=re.IGNORECASE)
    text = re.sub(r'[₽?]', '', text)
    text = re.sub(r'\b\d{9,}\b', '', text)
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip(' ,.-\n')


def parse_ozon_pdf(file_bytes: bytes) -> list:
    """Парсит PDF-выписку Озон Банка. Возвращает список расходов."""
    transactions = []

    with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
        full_text = ""
        for page in pdf.pages:
            t = page.extract_text() or ""
            full_text += t + "\n"

    AMOUNT_RE = re.compile(r'([+\-])\s*([\d][\d\s\xa0   ]*\.\d{2})')
    DATE_PAT  = re.compile(r'(\d{2}\.\d{2}\.\d{4})')

    parts = DATE_PAT.split(full_text)
    # parts = [pre_text, date1, block1, date2, block2, ...]

    for k in range(1, len(parts) - 1, 2):
        date_str = parts[k]
        block    = parts[k + 1]

        m = AMOUNT_RE.search(block)
        if not m:
            continue
        if m.group(1) != '-':
            continue
        amount = _parse_amount('-', m.group(2))
        if amount is None or amount <= 0:
            continue

        description = AMOUNT_RE.sub(' ', block)
        description = _clean(description)

        if _is_incoming(description):
            continue
        if not description or len(description) < 2:
            continue

        emoji, category = _categorize(description)
        merchant = _extract_merchant(description, category)

        d, mo, y = date_str.split('.')
        transactions.append({
            "date":        f"{y}-{mo}-{d}",
            "description": description[:120],
            "amount":      round(abs(amount), 2),
            "emoji":       emoji,
            "category":    category,
            "merchant":    merchant,
        })

    return transactions
