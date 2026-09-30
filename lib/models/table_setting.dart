/// A physical table's hardware/config settings, managed via
/// Billing/setting_table and Billing/update_setting_table.
class TableSetting {
  final int id;
  final int relay;
  final String number;
  final int point;
  final int? categoryId;
  final String? categoryName;

  /// 'billiard' atau 'mahjong' (table_active.table_type).
  final String type;

  const TableSetting({
    required this.id,
    required this.relay,
    required this.number,
    required this.point,
    this.categoryId,
    this.categoryName,
    this.type = 'billiard',
  });

  factory TableSetting.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? "") ?? 0;
    }

    final rawCategoryId = json['table_category_id'];
    final categoryId = rawCategoryId == null
        ? null
        : (rawCategoryId is int
              ? rawCategoryId
              : int.tryParse(rawCategoryId.toString()));

    return TableSetting(
      id: asInt(json['table_id']),
      relay: asInt(json['table_relay']),
      number: json['table_number']?.toString() ?? "",
      point: asInt(json['table_point']),
      categoryId: (categoryId != null && categoryId != 0) ? categoryId : null,
      categoryName: json['table_category_name']?.toString(),
      type: json['table_type']?.toString() == 'mahjong' ? 'mahjong' : 'billiard',
    );
  }

  /// Unlike the other fields, [categoryId] is genuinely optional (a table
  /// can have none), so this always sets it to whatever is passed —
  /// including null, to actually clear it — rather than falling back to the
  /// current value like the other params do.
  TableSetting copyWith({
    int? relay,
    String? number,
    int? point,
    int? categoryId,
    String? categoryName,
  }) {
    return TableSetting(
      id: id,
      relay: relay ?? this.relay,
      number: number ?? this.number,
      point: point ?? this.point,
      categoryId: categoryId,
      categoryName: categoryName,
      type: type,
    );
  }
}
