import 'json.dart';

/// Категория трат с месячным планом.
class BudgetCategory {
  final int id;
  final String name;
  final String emoji;

  /// Ориентир на месяц и потолок, за который выходить не хочется.
  final int planMonthly;
  final int planMax;

  const BudgetCategory({
    required this.id,
    required this.name,
    this.emoji = '💰',
    this.planMonthly = 0,
    this.planMax = 0,
  });

  factory BudgetCategory.fromJson(Map<String, dynamic> j) => BudgetCategory(
        id: asInt(j['id']),
        name: asString(j['name']),
        emoji: asString(j['emoji'], '💰'),
        planMonthly: asInt(j['plan_monthly']),
        planMax: asInt(j['plan_max']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'plan_monthly': planMonthly,
        'plan_max': planMax,
      };

  BudgetCategory copyWith({String? name, String? emoji, int? planMonthly, int? planMax}) =>
      BudgetCategory(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        planMonthly: planMonthly ?? this.planMonthly,
        planMax: planMax ?? this.planMax,
      );
}

/// Одна трата. Суммы на бэкенде целые — рубли без копеек.
class Expense {
  final int id;
  final String date;
  final int amount;
  final int? categoryId;
  final String? note;
  final String? merchant;

  const Expense({
    required this.id,
    required this.date,
    required this.amount,
    this.categoryId,
    this.note,
    this.merchant,
  });

  /// Что показать в строке списка: магазин, комментарий или прочерк.
  String get label {
    final m = merchant?.trim();
    if (m != null && m.isNotEmpty) return m;
    final n = note?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Без описания';
  }

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: asInt(j['id']),
        date: asString(j['date']).split('T').first,
        amount: asInt(j['amount']),
        categoryId: asIntOrNull(j['category_id']),
        note: asStringOrNull(j['note']),
        merchant: asStringOrNull(j['merchant']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'amount': amount,
        'category_id': categoryId,
        'note': note,
        'merchant': merchant,
      };

  Expense copyWith({int? amount, String? note, int? categoryId, String? merchant}) => Expense(
        id: id,
        date: date,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        note: note ?? this.note,
        merchant: merchant ?? this.merchant,
      );
}
