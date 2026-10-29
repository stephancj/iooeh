import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, Not, Repository } from 'typeorm';
import { Subscription, SubscriptionStatus } from '../admin/subscription.entity';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { Plan } from '../entitlements/plan.entity';
import { User } from '../users/user.entity';
import { Coupon, CouponRewardType } from './entities/coupon.entity';
import { CouponRedemption } from './entities/coupon-redemption.entity';
import { Referral, ReferralStatus } from './entities/referral.entity';
import { CreateCouponDto } from './promotions.dto';
import { VehicleSubscription } from '../entitlements/vehicle-subscription.entity';
import { DeviceAssignment } from '../admin/device-assignment.entity';
import { Payment, PaymentStatus } from '../payments/payment.entity';

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
  async redeemCode(userId: number, rawCode: string, deviceId?: number) {
    const code = rawCode.trim().toUpperCase();

    // 1. Vérifier s'il s'agit d'un Code Promo / Coupon
    const coupon = await this.couponRepo.findOne({ where: { code } });
    if (coupon) {
      return this.redeemCoupon(userId, coupon, deviceId);
    }

    // 2. Vérifier s'il s'agit d'un Code Parrainage
    const referrer = await this.userRepo.findOne({ where: { referralCode: code } });
    if (referrer) {
      return this.redeemReferralCode(userId, referrer, code);
    }

    throw new NotFoundException('Code promo ou code parrainage invalide.');
  }

  async previewCode(userId: number, rawCode: string, deviceId?: number) {
    const code = rawCode.trim().toUpperCase();
    const coupon = await this.couponRepo.findOne({ where: { code } });
    if (coupon) {
      if (!coupon.isActive || (coupon.expiresAt && coupon.expiresAt < new Date())) throw new BadRequestException('Code inactif ou expiré.');
      if (coupon.rewardType !== CouponRewardType.FREE_PLAN_GIFT && coupon.rewardType !== CouponRewardType.FREE_SUBSCRIPTION_DAYS) throw new BadRequestException('Utilisez ce code lors du paiement.');
      if (!deviceId) throw new BadRequestException('Choisissez le véhicule concerné.');
      await this.entitlementsService.ensureVehicleSubscription(userId, deviceId);
      const plan = coupon.grantedPlanId ? await this.planRepo.findOne({ where: { id: coupon.grantedPlanId, isActive: true } }) : null;
      if (coupon.rewardType === CouponRewardType.FREE_PLAN_GIFT && !plan) throw new BadRequestException('Le plan offert est indisponible.');
      return { type: coupon.rewardType, days: Number(coupon.rewardValue), planName: plan?.name ?? null };
    }
    const referrer = await this.userRepo.findOne({ where: { referralCode: code } });
    if (!referrer || referrer.id === userId) throw new NotFoundException('Code promo ou parrainage invalide.');
    return { type: 'REFERRAL', days: null, planName: null };
  }

  /**
   * Traitement d'un Coupon (Dynamic Redeem)
   */
  private async redeemCoupon(userId: number, coupon: Coupon, deviceId?: number) {
    if (!deviceId) throw new BadRequestException('Choisissez le véhicule concerné.');
    const initial = await this.entitlementsService.ensureVehicleSubscription(userId, deviceId);
    const result = await this.couponRepo.manager.transaction(async (manager) => {
      const coupons = manager.getRepository(Coupon);
      const locked = await coupons.findOne({ where: { id: coupon.id }, lock: { mode: 'pessimistic_write' } });
      if (!locked || !locked.isActive || (locked.expiresAt && locked.expiresAt < new Date())) throw new BadRequestException('Ce code promo est inactif ou expiré.');
      if (locked.maxRedemptions !== null && locked.redemptionsCount >= locked.maxRedemptions) throw new BadRequestException('Ce code promo a atteint sa limite.');
      const redemptions = manager.getRepository(CouponRedemption);
      if (await redemptions.count({ where: { userId, couponId: locked.id } }) >= locked.maxRedemptionsPerUser) throw new BadRequestException('Vous avez déjà utilisé ce code promo.');
      const assignment = await manager.getRepository(DeviceAssignment).findOne({ where: { id: initial.assignmentId, userId, deviceId }, lock: { mode: 'pessimistic_write' } });
      if (!assignment) throw new NotFoundException('Véhicule introuvable.');
      const subs = manager.getRepository(VehicleSubscription);
      const sub = await subs.findOneOrFail({ where: { assignmentId: assignment.id }, lock: { mode: 'pessimistic_write' } });
      if (locked.rewardType !== CouponRewardType.FREE_SUBSCRIPTION_DAYS && locked.rewardType !== CouponRewardType.FREE_PLAN_GIFT) throw new BadRequestException('Ce code est indisponible ou doit être utilisé au paiement.');
      const currentEnd = sub.status === SubscriptionStatus.TRIAL ? sub.trialEndsAt : sub.nextBillingDate;
      const now = new Date();
      const base = currentEnd && currentEnd > now ? currentEnd : now;
      const days = Number(locked.rewardValue);
      if (!Number.isInteger(days) || days <= 0) throw new BadRequestException('Durée de coupon invalide.');
      const previousPlan = sub.plan;
      if (locked.rewardType === CouponRewardType.FREE_PLAN_GIFT) {
        if (!locked.grantedPlanId) throw new BadRequestException('Aucun plan associé au coupon.');
        const plan = await manager.getRepository(Plan).findOne({ where: { id: locked.grantedPlanId, isActive: true } });
        if (!plan) throw new NotFoundException('Plan offert introuvable.');
        sub.planId = plan.id; sub.plan = plan.code;
      }
      sub.status = SubscriptionStatus.ACTIVE;
      sub.nextBillingDate = new Date(base.getTime() + days * 86400000);
      sub.trialEndsAt = null;
      await subs.save(sub);
      locked.redemptionsCount += 1;
      await coupons.save(locked);
      await redemptions.save(redemptions.create({ userId, couponId: locked.id, rewardType: locked.rewardType, rewardValue: locked.rewardValue, metadata: { deviceId, assignmentId: assignment.id, previousPlan, nextBillingDate: sub.nextBillingDate } }));
      return { success: true, message: `${days} jour(s) offerts ajoutés à votre véhicule.`, rewardType: locked.rewardType, nextBillingDate: sub.nextBillingDate };
    });
    this.entitlementsService.invalidate(userId);
    return result;
  }

  /**
   * Traitement d'un Code Parrainage via le bouton Redeem
   */
  private async redeemReferralCode(refereeId: number, referrer: User, code: string) {
    if (referrer.id === refereeId) {
      throw new BadRequestException('Vous ne pouvez pas utiliser votre propre code parrainage.');
    }

    await this.referralRepo.manager.transaction(async (manager) => {
      await manager.getRepository(User).findOneOrFail({ where: { id: refereeId }, lock: { mode: 'pessimistic_write' } });
      const payments = manager.getRepository(Payment);
      const paid = await payments.count({ where: { userId: refereeId, status: PaymentStatus.SUCCESS, assignmentId: Not(IsNull()) } });
      const pending = await payments.createQueryBuilder('p').where('p.user_id = :userId', { userId: refereeId }).andWhere('p.assignment_id IS NOT NULL').andWhere('p.status IN (:...statuses)', { statuses: [PaymentStatus.CREATED, PaymentStatus.PENDING] }).andWhere('(p.expires_at IS NULL OR p.expires_at > NOW())').getCount();
      if (paid || pending) throw new BadRequestException('Le parrainage doit être appliqué avant le premier paiement et avant de démarrer un paiement.');
      const referrals = manager.getRepository(Referral);
      if (await referrals.findOne({ where: { refereeId } })) throw new ConflictException('Vous avez déjà bénéficié d’un parrainage.');
      await referrals.save(referrals.create({ referrerId: referrer.id, refereeId, codeUsed: code, status: ReferralStatus.PENDING, referrerRewardType: CouponRewardType.FREE_SUBSCRIPTION_DAYS, referrerRewardValue: '30', refereeRewardType: CouponRewardType.PERCENTAGE_DISCOUNT, refereeRewardValue: '20' }));
    });

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

  async claimReferralReward(userId: number, referralId: string, deviceId: number) {
    const initial = await this.entitlementsService.ensureVehicleSubscription(userId, deviceId);
    const result = await this.referralRepo.manager.transaction(async (manager) => {
      const referrals = manager.getRepository(Referral);
      const referral = await referrals.findOne({ where: { id: referralId, referrerId: userId }, lock: { mode: 'pessimistic_write' } });
      if (!referral || referral.status !== ReferralStatus.QUALIFIED) throw new BadRequestException('Récompense indisponible ou déjà utilisée.');
      const assignment = await manager.getRepository(DeviceAssignment).findOne({ where: { id: initial.assignmentId, userId, deviceId }, lock: { mode: 'pessimistic_write' } });
      if (!assignment) throw new NotFoundException('Véhicule introuvable.');
      const subs = manager.getRepository(VehicleSubscription);
      const sub = await subs.findOneOrFail({ where: { assignmentId: assignment.id }, lock: { mode: 'pessimistic_write' } });
      const now = new Date();
      const currentEnd = sub.status === SubscriptionStatus.TRIAL ? sub.trialEndsAt : sub.nextBillingDate;
      const base = currentEnd && currentEnd > now ? currentEnd : now;
      const days = Number(referral.referrerRewardValue) || 30;
      sub.nextBillingDate = new Date(base.getTime() + days * 86400000);
      sub.status = SubscriptionStatus.ACTIVE;
      sub.trialEndsAt = null;
      await subs.save(sub);
      referral.status = ReferralStatus.REWARDED;
      await referrals.save(referral);
      const redemptions = manager.getRepository(CouponRedemption);
      await redemptions.save(redemptions.create({ userId, referralId: referral.id, rewardType: referral.referrerRewardType, rewardValue: referral.referrerRewardValue, metadata: { deviceId, assignmentId: assignment.id, nextBillingDate: sub.nextBillingDate } }));
      return { deviceId, days, nextBillingDate: sub.nextBillingDate };
    });
    this.entitlementsService.invalidate(userId);
    return result;
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
