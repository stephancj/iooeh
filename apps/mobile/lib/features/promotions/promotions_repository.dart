import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

class ReferralInfo {
  final String referralCode;
  final String referralLink;
  final int totalReferred;
  final int qualifiedCount;
  final List<dynamic> referrals;

  ReferralInfo({
    required this.referralCode,
    required this.referralLink,
    required this.totalReferred,
    required this.qualifiedCount,
    required this.referrals,
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> json) {
    return ReferralInfo(
      referralCode: json['referralCode'] ?? '',
      referralLink: json['referralLink'] ?? '',
      totalReferred: json['totalReferred'] ?? 0,
      qualifiedCount: json['qualifiedCount'] ?? 0,
      referrals: json['referrals'] as List<dynamic>? ?? [],
    );
  }
}

class ValidateCouponResult {
  final bool valid;
  final String code;
  final String rewardType;
  final double rewardValue;
  final double originalPrice;
  final double discountAmount;
  final double finalAmount;

  ValidateCouponResult({
    required this.valid,
    required this.code,
    required this.rewardType,
    required this.rewardValue,
    required this.originalPrice,
    required this.discountAmount,
    required this.finalAmount,
  });

  factory ValidateCouponResult.fromJson(Map<String, dynamic> json) {
    return ValidateCouponResult(
      valid: json['valid'] ?? false,
      code: json['code'] ?? '',
      rewardType: json['rewardType'] ?? '',
      rewardValue: (json['rewardValue'] as num?)?.toDouble() ?? 0.0,
      originalPrice: (json['originalPrice'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
      finalAmount: (json['finalAmount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PromotionsRepository {
  final Dio _dio;

  PromotionsRepository(this._dio);

  Future<Map<String, dynamic>> redeemCode(String code, {int? deviceId}) async {
    final response = await _dio.post('/promotions/redeem',
        data: {'code': code, if (deviceId != null) 'deviceId': deviceId});
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> previewCode(String code, {int? deviceId}) async {
    final response = await _dio.post('/promotions/preview',
        data: {'code': code, if (deviceId != null) 'deviceId': deviceId});
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<ValidateCouponResult> validateCoupon(
      String code, String planId) async {
    final response = await _dio.post('/promotions/validate', data: {
      'code': code,
      'planId': planId,
    });
    return ValidateCouponResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> claimReferralReward(String referralId, int deviceId) async {
    await _dio.post('/promotions/referrals/$referralId/claim',
        data: {'deviceId': deviceId});
  }

  Future<ReferralInfo> getReferralInfo() async {
    final response = await _dio.get('/promotions/referral-info');
    return ReferralInfo.fromJson(response.data as Map<String, dynamic>);
  }
}

final promotionsRepositoryProvider = Provider<PromotionsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return PromotionsRepository(dio);
});

final referralInfoProvider =
    FutureProvider.autoDispose<ReferralInfo>((ref) async {
  final repo = ref.watch(promotionsRepositoryProvider);
  return repo.getReferralInfo();
});
