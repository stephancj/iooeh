import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Subscription, SubscriptionStatus } from '../admin/subscription.entity';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { Plan } from '../entitlements/plan.entity';
import { User } from '../users/user.entity';
import { Coupon, CouponRewardType } from './entities/coupon.entity';
import { CouponRedemption } from './entities/coupon-redemption.entity';
import { Referral, ReferralStatus } from './entities/referral.entity';
import { CreateCouponDto } from './promotions.dto';

@Injectable()
export class PromotionsService {
  constructor(
    @InjectRepository(Coupon)
    private readonly couponRepo: Repository<Coupon>,
    @InjectRepository(Referral)
    private readonly referralRepo: Repository<Referral>,
    @InjectRepository(CouponRedemption)
    private readonly redemptionRepo: Repository<CouponRedemption>,
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
    @InjectRepository(Subscription)
    private readonly subscriptionRepo: Repository<Subscription>,
    @InjectRepository(Plan)
    private readonly planRepo: Repository<Plan>,
    private readonly entitlementsService: EntitlementsService,
  ) {}

  /**
   * Utilise (Redeem) un code coupon ou un code parrainage directement.
   */
  async redeemCode(userId: number, rawCode: string) {
    const code = rawCode.trim().toUpperCase();

    // 1. Vérifier s'il s'agit d'un Code Promo / Coupon
    const coupon = await this.couponRepo.findOne({ where: { code } });
    if (coupon) {
      return this.redeemCoupon(userId, coupon);
    }

    // 2. Vérifier s'il s'agit d'un Code Parrainage
    const referrer = await this.userRepo.findOne({ where: { referralCode: code } });
    if (referrer) {
      return this.redeemReferralCode(userId, referrer, code);
    }

    throw new NotFoundException('Code promo ou code parrainage invalide.');
  }

  /**
   * Traitement d'un Coupon (Dynamic Redeem)
   */
  private async redeemCoupon(userId: number, coupon: Coupon) {
    if (!coupon.isActive) {
      throw new BadRequestException('Ce code promo n’est plus actif.');
    }
    if (coupon.expiresAt && new Date(coupon.expiresAt) < new Date()) {
      throw new BadRequestException('Ce code promo a expiré.');
    }
    if (coupon.maxRedemptions !== null && coupon.redemptionsCount >= coupon.maxRedemptions) {
      throw new BadRequestException('Ce code promo a atteint le nombre maximal d’utilisations.');
    }

    // Nombre d'utilisations par cet utilisateur
    const userRedemptionsCount = await this.redemptionRepo.count({
      where: { userId, couponId: coupon.id },
    });
    if (userRedemptionsCount >= coupon.maxRedemptionsPerUser) {
      throw new BadRequestException('Vous avez déjà utilisé ce code promo.');
    }

    const sub = await this.entitlementsService.ensureDefaultSubscription(userId);
    let message = '';
    const metadata: Record<string, unknown> = { previousPlan: sub.plan };

    switch (coupon.rewardType) {
      case CouponRewardType.FREE_PLAN_GIFT: {
        if (!coupon.grantedPlanId) {
          throw new BadRequestException('Ce coupon ne spécifie aucun plan d’abonnement offert.');
        }
        const grantedPlan = await this.planRepo.findOne({ where: { id: coupon.grantedPlanId } });
        if (!grantedPlan) {
          throw new NotFoundException('Le plan offert par ce coupon n’existe plus.');
        }

        sub.planId = grantedPlan.id;
        sub.plan = grantedPlan.code;
        sub.status = SubscriptionStatus.ACTIVE;
        sub.trialEndsAt = null;

        const durationDays = Number(coupon.rewardValue) || 30;
        const now = new Date();
        const baseDate = sub.nextBillingDate && sub.nextBillingDate > now ? sub.nextBillingDate : now;
        sub.nextBillingDate = new Date(baseDate.getTime() + durationDays * 24 * 3600 * 1000);

        message = `Félicitations ! Vous bénéficiez désormais du plan « ${grantedPlan.name} » offert pour ${durationDays} jour(s).`;
        metadata.grantedPlanName = grantedPlan.name;
        metadata.newNextBillingDate = sub.nextBillingDate;
        break;
      }

      case CouponRewardType.FREE_SUBSCRIPTION_DAYS: {
        const days = Number(coupon.rewardValue) || 30;
        const now = new Date();
        const baseDate = sub.nextBillingDate && sub.nextBillingDate > now ? sub.nextBillingDate : now;
        sub.nextBillingDate = new Date(baseDate.getTime() + days * 24 * 3600 * 1000);
        sub.status = SubscriptionStatus.ACTIVE;

        message = `${days} jour(s) d’abonnement offerts ajoutés à votre compte !`;
        metadata.newNextBillingDate = sub.nextBillingDate;
        break;
      }

      case CouponRewardType.VEHICLE_QUOTA_BONUS:
        throw new BadRequestException('Ce type de coupon n’est plus disponible.');

      case CouponRewardType.PERCENTAGE_DISCOUNT:
      case CouponRewardType.FIXED_DISCOUNT:
        throw new BadRequestException(
          'Ce code promo s’applique lors du paiement d’un abonnement (au checkout).',
        );

      default:
        throw new BadRequestException('Type de récompense inconnu.');
    }

    await this.subscriptionRepo.save(sub);
    this.entitlementsService.invalidate(userId);

    // Mettre à jour les compteurs du coupon et enregistrer la rédemption
    coupon.redemptionsCount += 1;
    await this.couponRepo.save(coupon);

    await this.redemptionRepo.save(
      this.redemptionRepo.create({
        userId,
        couponId: coupon.id,
        rewardType: coupon.rewardType,
        rewardValue: coupon.rewardValue,
        metadata,
      }),
    );

    return { success: true, message, rewardType: coupon.rewardType };
  }

  /**
   * Traitement d'un Code Parrainage via le bouton Redeem
   */
  private async redeemReferralCode(refereeId: number, referrer: User, code: string) {
    if (referrer.id === refereeId) {
      throw new BadRequestException('Vous ne pouvez pas utiliser votre propre code parrainage.');
    }

    const existing = await this.referralRepo.findOne({ where: { refereeId } });
    if (existing) {
      throw new ConflictException('Vous avez déjà bénéficié d’un parrainage.');
    }

    await this.referralRepo.save(
      this.referralRepo.create({
        referrerId: referrer.id,
        refereeId,
        codeUsed: code,
        status: ReferralStatus.PENDING,
        referrerRewardType: CouponRewardType.FREE_SUBSCRIPTION_DAYS,
        referrerRewardValue: '30',
        refereeRewardType: CouponRewardType.PERCENTAGE_DISCOUNT,
        refereeRewardValue: '20',
      }),
    );

    return {
      success: true,
      message: 'Code parrainage appliqué ! Vous bénéficierez de 20% de réduction sur votre 1er abonnement.',
      rewardType: CouponRewardType.PERCENTAGE_DISCOUNT,
    };
  }

  /**
   * Valide un coupon pour le paiement (Checkout) et calcule le prix final.
   */
  async validateCouponForCheckout(code: string, planId: string, userId: number) {
    const normalizedCode = code.trim().toUpperCase();
    const [coupon, plan] = await Promise.all([
      this.couponRepo.findOne({ where: { code: normalizedCode, isActive: true } }),
      this.planRepo.findOne({ where: { id: planId, isActive: true } }),
    ]);

    if (!coupon) throw new NotFoundException('Code promo introuvable ou inactif.');
    if (!plan) throw new NotFoundException('Plan introuvable.');

    if (coupon.expiresAt && new Date(coupon.expiresAt) < new Date()) {
      throw new BadRequestException('Ce code promo a expiré.');
    }
    if (coupon.maxRedemptions !== null && coupon.redemptionsCount >= coupon.maxRedemptions) {
      throw new BadRequestException('Ce code promo a atteint sa limite d’utilisations.');
    }

    // Vérifier l'éligibilité du plan
    if (coupon.targetPlanId && coupon.targetPlanId !== plan.id) {
      const targetPlan = await this.planRepo.findOne({ where: { id: coupon.targetPlanId } });
      throw new BadRequestException(
        `Ce code promo n'est valable que pour le plan « ${targetPlan?.name ?? 'spécifique'} ».`,
      );
    }

    const originalPrice = Number(plan.priceMonthly);
    if (coupon.minPlanPrice && originalPrice < Number(coupon.minPlanPrice)) {
      throw new BadRequestException(
        `Ce code promo nécessite un abonnement d’un montant minimal de ${coupon.minPlanPrice} MGA.`,
      );
    }

    let discountAmount = 0;
    if (coupon.rewardType === CouponRewardType.PERCENTAGE_DISCOUNT) {
      discountAmount = Math.round((originalPrice * Number(coupon.rewardValue)) / 100);
    } else if (coupon.rewardType === CouponRewardType.FIXED_DISCOUNT) {
      discountAmount = Math.min(originalPrice, Number(coupon.rewardValue));
    } else {
      throw new BadRequestException('Ce code promo n’est pas un coupon de réduction tarifaire.');
    }

    const finalAmount = Math.max(0, originalPrice - discountAmount);

    return {
      valid: true,
      couponId: coupon.id,
      code: coupon.code,
      rewardType: coupon.rewardType,
      rewardValue: Number(coupon.rewardValue),
      originalPrice,
      discountAmount,
      finalAmount,
    };
  }

  /**
   * Enregistre le parrainage automatique lors de l'inscription (Register).
   */
  async processRegistrationReferral(refereeId: number, rawCode: string) {
    if (!rawCode) return;
    const code = rawCode.trim().toUpperCase();
    const referrer = await this.userRepo.findOne({ where: { referralCode: code } });
    if (!referrer || referrer.id === refereeId) return;

    const existing = await this.referralRepo.findOne({ where: { refereeId } });
    if (existing) return;

    await this.referralRepo.save(
      this.referralRepo.create({
        referrerId: referrer.id,
        refereeId,
        codeUsed: code,
        status: ReferralStatus.PENDING,
        referrerRewardType: CouponRewardType.FREE_SUBSCRIPTION_DAYS,
        referrerRewardValue: '30',
        refereeRewardType: CouponRewardType.PERCENTAGE_DISCOUNT,
        refereeRewardValue: '20',
      }),
    );
  }

  /**
   * Déclenché lors d'un paiement réussi : Qualifie le parrainage et crédite le parrain !
   */
  async qualifyReferralOnPayment(refereeId: number, paymentId?: string) {
    const referral = await this.referralRepo.findOne({
      where: { refereeId, status: ReferralStatus.PENDING },
    });
    if (!referral) return;

    referral.status = ReferralStatus.QUALIFIED;
    await this.referralRepo.save(referral);

    // Recompenser le Parrain (ex: 30 jours offerts sur son abonnement)
    const referrerSub = await this.entitlementsService.ensureDefaultSubscription(referral.referrerId);
    const days = Number(referral.referrerRewardValue) || 30;
    const now = new Date();
    const baseDate = referrerSub.nextBillingDate && referrerSub.nextBillingDate > now ? referrerSub.nextBillingDate : now;
    referrerSub.nextBillingDate = new Date(baseDate.getTime() + days * 24 * 3600 * 1000);
    referrerSub.status = SubscriptionStatus.ACTIVE;
    await this.subscriptionRepo.save(referrerSub);
    this.entitlementsService.invalidate(referral.referrerId);

    referral.status = ReferralStatus.REWARDED;
    await this.referralRepo.save(referral);

    // Enregistrer dans coupon_redemptions
    await this.redemptionRepo.save(
      this.redemptionRepo.create({
        userId: referral.referrerId,
        referralId: referral.id,
        rewardType: referral.referrerRewardType,
        rewardValue: referral.referrerRewardValue,
        appliedToPaymentId: paymentId ?? null,
        metadata: { refereeId, message: `Récompense parrainage filleul ID ${refereeId}` },
      }),
    );
  }

  /**
   * Statistiques et liens de parrainage pour l'utilisateur.
   */
  async getReferralInfo(userId: number) {
    let user = await this.userRepo.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('Utilisateur introuvable.');

    if (!user.referralCode) {
      user.referralCode = `REF-${Math.random().toString(36).substring(2, 8).toUpperCase()}`;
      await this.userRepo.save(user);
    }

    const publicApp = process.env.PUBLIC_APP_URL ?? 'https://trackeo.mg';
    const referralLink = `${publicApp}/register?ref=${user.referralCode}`;

    const referrals = await this.referralRepo.find({
      where: { referrerId: userId },
      order: { createdAt: 'DESC' },
    });

    const totalReferred = referrals.length;
    const qualifiedCount = referrals.filter((r) => r.status === ReferralStatus.REWARDED || r.status === ReferralStatus.QUALIFIED).length;

    return {
      referralCode: user.referralCode,
      referralLink,
      totalReferred,
      qualifiedCount,
      referrals: referrals.map((r) => ({
        id: r.id,
        refereeId: r.refereeId,
        status: r.status,
        createdAt: r.createdAt,
      })),
    };
  }

  // ── Admin Endpoints ────────────────────────────────────────────────────────
  async createCoupon(dto: CreateCouponDto) {
    if (dto.rewardType === CouponRewardType.VEHICLE_QUOTA_BONUS) {
      throw new BadRequestException('Ce type de coupon n’est plus disponible.');
    }
    const existing = await this.couponRepo.findOne({ where: { code: dto.code.trim().toUpperCase() } });
    if (existing) throw new ConflictException('Un coupon avec ce code existe déjà.');

    const coupon = this.couponRepo.create({
      code: dto.code.trim().toUpperCase(),
      rewardType: dto.rewardType,
      rewardValue: String(dto.rewardValue),
      grantedPlanId: dto.grantedPlanId ?? null,
      targetPlanId: dto.targetPlanId ?? null,
      minPlanPrice: dto.minPlanPrice ? String(dto.minPlanPrice) : '0',
      maxRedemptions: dto.maxRedemptions ?? null,
      maxRedemptionsPerUser: dto.maxRedemptionsPerUser ?? 1,
      expiresAt: dto.expiresAt ? new Date(dto.expiresAt) : null,
    });

    return this.couponRepo.save(coupon);
  }

  listCoupons() {
    return this.couponRepo.find({ order: { createdAt: 'DESC' } });
  }

  async deleteCoupon(id: string) {
    await this.couponRepo.delete(id);
    return { success: true };
  }
}
