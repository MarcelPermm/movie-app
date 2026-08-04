import 'dart:convert';

/// Разбор значений, приходящих с бэкенда.
///
/// Форматы гуляют: psycopg отдаёт NUMERIC строкой, целые иногда приходят
/// как int, иногда как double, а списки жанров хранятся в TEXT-колонке
/// JSON-строкой. Парсер должен переживать всё это молча.

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
  return fallback;
}

int? asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? fallback;
  return fallback;
}

double? asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

String asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return '$v';
}

String? asStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v is String ? v : '$v';
  return s.isEmpty ? null : s;
}

bool asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == 't' || v == '1';
  return false;
}

/// Список строк, который может приехать как массив или как JSON в TEXT-колонке.
List<String> asStringList(dynamic v) {
  if (v is List) return v.map((e) => '$e').toList();
  if (v is String && v.isNotEmpty) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is List) return decoded.map((e) => '$e').toList();
    } catch (_) {
      // не JSON — считаем, что список пуст
    }
  }
  return const [];
}

/// Дата без времени в формате, который понимают эндпоинты (YYYY-MM-DD).
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDate(dynamic v) {
  final s = asStringOrNull(v);
  if (s == null) return null;
  return DateTime.tryParse(s);
}
