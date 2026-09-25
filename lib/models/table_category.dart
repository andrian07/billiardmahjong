/// A table category (e.g. "VIP", "Reguler"), managed via the
/// Setting/*_category_meja endpoints. Deletion is a soft delete — it just
/// flips [active] to false rather than removing the row.
class TableCategory {
  final int id;
  final String name;
  final bool active;

  /// 'billiard' or 'mahjong' — which price table (tier column set) this
  /// category's [priceOption] indexes into: ms_master_price for billiard,
  /// ms_master_price_mahjong for mahjong. See Billing_model's
  /// get_category_meja_price_tier() on the backend.
  final String type;

  /// Which of the 5 backend price tiers (master_price_price..price_5) this
  /// category bills at — 1 to 5. Only tier 1 ("Harga") is editable from the
  /// Pengaturan Harga page; tiers 2-5 exist server-side for categories that
  /// pick them here but aren't otherwise surfaced in the app.
  final int priceOption;

  const TableCategory({
    required this.id,
    required this.name,
    required this.active,
    required this.type,
    required this.priceOption,
  });

  factory TableCategory.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawPrice = json['price'];

    return TableCategory(
      id: rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0,
      name: json['name']?.toString() ?? "",
      active: json['active']?.toString().toUpperCase() != "N",
      type: json['type']?.toString() == "mahjong" ? "mahjong" : "billiard",
      priceOption: rawPrice is int
          ? rawPrice
          : int.tryParse(rawPrice?.toString() ?? "") ?? 1,
    );
  }

  TableCategory copyWith({
    String? name,
    bool? active,
    String? type,
    int? priceOption,
  }) {
    return TableCategory(
      id: id,
      name: name ?? this.name,
      active: active ?? this.active,
      type: type ?? this.type,
      priceOption: priceOption ?? this.priceOption,
    );
  }
}
