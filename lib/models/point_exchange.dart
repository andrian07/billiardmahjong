/// One member point-redemption record, from the gameon `reward_redemption`
/// table (member redeems points for a reward in the GameOn app). Shown
/// read-only in the "Tukar Point" menu as redemption history — the reward
/// catalogue itself is no longer managed here.
class PointRedemption {
  final int id;
  final String customerName;
  final String customerPhone;
  final String rewardName;
  final int pointSpent;
  final String redeemCode;
  final String status;
  final int? branch;
  final DateTime? claimedAt;
  final String claimedBy;
  final DateTime? createdAt;

  const PointRedemption({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.rewardName,
    required this.pointSpent,
    required this.redeemCode,
    required this.status,
    required this.branch,
    required this.claimedAt,
    required this.claimedBy,
    required this.createdAt,
  });

  /// Coupon issued, points already spent, not yet used at the counter.
  bool get isRedeemed => status.toLowerCase() == "redeemed";

  /// Coupon has been handed over / used at the counter.
  bool get isClaimed => status.toLowerCase() == "claimed";

  factory PointRedemption.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? "") ?? 0;
    }

    DateTime? parseAt(String key) {
      final raw = json[key]?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw.replaceFirst(" ", "T"));
    }

    final rawBranch = json['branch'];
    return PointRedemption(
      id: asInt(json['id']),
      customerName: json['customer_name']?.toString() ?? "-",
      customerPhone: json['customer_phone']?.toString() ?? "",
      rewardName: json['reward_name']?.toString() ?? "-",
      pointSpent: asInt(json['point_spent']),
      redeemCode: json['redeem_code']?.toString() ?? "",
      status: json['status']?.toString() ?? "",
      branch: rawBranch == null ? null : asInt(rawBranch),
      claimedAt: parseAt('claimed_at'),
      claimedBy: json['claimed_by']?.toString() ?? "",
      createdAt: parseAt('created_at'),
    );
  }
}
