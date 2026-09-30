enum PromoType {
  percentage,
  fixed;

  String get label => this == PromoType.percentage ? "Diskon %" : "Fix";

  String get apiValue => this == PromoType.percentage ? "Diskon" : "Fix";

  static PromoType fromApiValue(String value) {
    return value.trim().toLowerCase() == "fix"
        ? PromoType.fixed
        : PromoType.percentage;
  }
}

class Promo {
  final int id;
  final String name;
  final PromoType type;

  /// 'billiard' / 'mahjong' — promo hanya tampil & berlaku untuk meja sejenis.
  final String tableType;
  final int value;

  /// Hours granted when this promo is picked while starting a Timer session
  /// — only meaningful for [PromoType.fixed]. Null means no fixed duration
  /// is configured (or the promo is a percentage discount).
  final int? hourGained;

  /// Extra hours granted free on top of [hourGained] (e.g. "2 Jam Gratis 1
  /// Jam" → hourGained=2, freeHour=1) — only meaningful for [PromoType.fixed].
  /// Purely informational for a normal (paid) booking; it only has a real
  /// effect when the session is booked using banked/saved time (see
  /// Billing_model::apply_promo_free_hour on the backend): playing longer
  /// than [hourGained] deducts at most [freeHour] fewer hours from the
  /// customer's saved-time balance — capped at freeHour, not multiplied by
  /// how much longer they play.
  final int? freeHour;

  /// Table categories (category_meja_id) this promo may be applied to.
  /// Empty/null = valid for ALL categories. Enforced on the backend in
  /// Billing::book_table()/payment() so a promo can't be applied to a table
  /// of the wrong category.
  final List<int> categoryIds;

  /// Days of week this promo may be used (1=Senin..7=Minggu, ISO weekday —
  /// matches PHP's date('N') on the backend). Empty/null means every day.
  final List<int>? validDays;

  /// Hour-of-day window (0-24) this promo may be used within — always both
  /// set together or both null (see Master::_parse_promo_schedule on the
  /// backend). A promo with a window can only be used for Timer sessions,
  /// since a Reguler (open-ended) session has no known end time to check
  /// against the window up front.
  final int? validTimeStart;
  final int? validTimeEnd;

  const Promo({
    required this.id,
    required this.name,
    required this.type,
    this.tableType = 'billiard',
    required this.value,
    this.hourGained,
    this.freeHour,
    this.categoryIds = const [],
    this.validDays,
    this.validTimeStart,
    this.validTimeEnd,
  });

  bool get hasDayRestriction => validDays != null && validDays!.isNotEmpty;

  bool get hasTimeWindow => validTimeStart != null && validTimeEnd != null;

  factory Promo.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawValue = json['value'];
    final rawHour = json['hour'];
    final rawFreeHour = json['free_hour'];
    final rawCategoryIds = json['category_ids'];
    final rawDays = json['valid_days']?.toString();
    final rawStart = json['valid_time_start'];
    final rawEnd = json['valid_time_end'];

    return Promo(
      id: rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0,
      name: json['name']?.toString() ?? "",
      type: PromoType.fromApiValue(json['tipe']?.toString() ?? ""),
      tableType: json['table_type']?.toString() == 'mahjong'
          ? 'mahjong'
          : 'billiard',
      value: rawValue is int
          ? rawValue
          : int.tryParse(rawValue.toString()) ?? 0,
      hourGained: rawHour is int
          ? rawHour
          : int.tryParse(rawHour?.toString() ?? ""),
      freeHour: rawFreeHour is int
          ? rawFreeHour
          : int.tryParse(rawFreeHour?.toString() ?? ""),
      categoryIds: rawCategoryIds is List
          ? rawCategoryIds
                .map((e) => int.tryParse(e.toString()))
                .whereType<int>()
                .toList()
          : const [],
      validDays: (rawDays != null && rawDays.isNotEmpty)
          ? rawDays
              .split(',')
              .map((d) => int.tryParse(d.trim()))
              .whereType<int>()
              .toList()
          : null,
      validTimeStart: rawStart is int
          ? rawStart
          : int.tryParse(rawStart?.toString() ?? ""),
      validTimeEnd: rawEnd is int
          ? rawEnd
          : int.tryParse(rawEnd?.toString() ?? ""),
    );
  }
}

/// Senin..Minggu labels, keyed by ISO weekday (1=Senin..7=Minggu) to match
/// [Promo.validDays] and the backend's date('N').
const Map<int, String> weekdayLabels = {
  1: "Senin",
  2: "Selasa",
  3: "Rabu",
  4: "Kamis",
  5: "Jumat",
  6: "Sabtu",
  7: "Minggu",
};
