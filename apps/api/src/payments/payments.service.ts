import {
  BadGatewayException,
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { randomUUID, timingSafeEqual } from 'node:crypto';
import { In, IsNull, Not, Repository } from 'typeorm';
import { Subscription, SubscriptionStatus } from '../admin/subscription.entity';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { Plan } from '../entitlements/plan.entity';
import { UsersService } from '../users/users.service';
import { User } from '../users/user.entity';
import { PromotionsService } from '../promotions/promotions.service';
import { CreatePaymentDto, PapiNotificationDto } from './payments.dto';
import { Payment, PaymentStatus } from './payment.entity';
import { VehicleSubscription } from '../entitlements/vehicle-subscription.entity';
import { DeviceAssignment } from '../admin/device-assignment.entity';
import { Referral, ReferralStatus } from '../promotions/entities/referral.entity';
import { Coupon, CouponRewardType } from '../promotions/entities/coupon.entity';
import { CouponRedemption } from '../promotions/entities/coupon-redemption.entity';

@Injectable()
export class PaymentsService {
  private readonly endpoint = 'https://app.papi.mg/dashboard/api/payment-links';
  constructor(
    @InjectRepository(Payment)
    private readonly paymentRepo: Repository<Payment>,
    @InjectRepository(Plan) private readonly planRepo: Repository<Plan>,
    @InjectRepository(Subscription)
    private readonly subscriptionRepo: Repository<Subscription>,
    private readonly users: UsersService,
    private readonly entitlements: EntitlementsService,
    private readonly promotionsService: PromotionsService,
  ) {}

  async quote(userId: number, dto: CreatePaymentDto) {
    await this.entitlements.ensureVehicleSubscription(userId, dto.deviceId);
    const plan = await this.planRepo.findOne({ where: { id: dto.planId, isActive: true } });
    if (!plan) throw new NotFoundException('Plan introuvable.');
    if (plan.currency !== 'MGA') throw new BadRequestException('Devise du plan non prise en charge.');
    const price = Math.round(Number(plan.priceMonthly));
    const referral = await this.paymentRepo.manager.getRepository(Referral).findOne({ where: { refereeId: userId, status: ReferralStatus.PENDING } });
    const paid = await this.paymentRepo.count({ where: { userId, status: PaymentStatus.SUCCESS, assignmentId: Not(IsNull()) } });
    if (referral && !paid && dto.couponCode) throw new BadRequestException('La réduction de parrainage ne se cumule pas avec un autre code.');
    const coupon = dto.couponCode ? await this.promotionsService.validateCouponForCheckout(dto.couponCode, dto.planId, userId) : null;
    const amount = referral && !paid ? Math.round(price * (1 - Number(referral.refereeRewardValue) / 100)) : coupon?.finalAmount ?? price;
    return { price, amount, currency: plan.currency, referralDiscount: !!referral && !paid, testMode: process.env.PAPI_TEST_MODE !== 'false' };
  }

  async create(userId: number, dto: CreatePaymentDto) {
    const vehicleSubscription = await this.entitlements.ensureVehicleSubscription(userId, dto.deviceId);
    const apiKey = process.env.PAPI_API_KEY;
    if (!apiKey)
      throw new ServiceUnavailableException(
        'Le paiement PAPI n’est pas encore configuré.',
      );
    const [plan, user] = await Promise.all([
      this.planRepo.findOne({ where: { id: dto.planId, isActive: true } }),
      this.users.findById(userId),
    ]);
    if (!plan || !user)
      throw new NotFoundException('Plan ou utilisateur introuvable.');
    if (plan.currency !== 'MGA') throw new BadRequestException('Devise du plan non prise en charge.');

    const reference = `IOOEH-${randomUUID()}`;
    const publicApp = process.env.PUBLIC_APP_URL ?? 'https://app.iooeh.com';
    const publicApi = process.env.PUBLIC_API_URL ?? 'https://api.iooeh.com';
    const requestedCoupon = dto.couponCode ? await this.promotionsService.validateCouponForCheckout(dto.couponCode, dto.planId, userId) : null;
    let payment = await this.paymentRepo.manager.transaction(async (manager) => {
      const payments = manager.getRepository(Payment);
      await manager.getRepository(User).findOneOrFail({ where: { id: userId }, lock: { mode: 'pessimistic_write' } });
      const referral = await manager.getRepository(Referral).findOne({ where: { refereeId: userId, status: ReferralStatus.PENDING }, lock: { mode: 'pessimistic_write' } });
      const alreadyPaid = await payments.count({ where: { userId, status: PaymentStatus.SUCCESS, assignmentId: Not(IsNull()) } });
      const eligibleReferral = referral && !alreadyPaid ? referral : null;
      if (eligibleReferral && requestedCoupon) throw new BadRequestException('La réduction de parrainage ne se cumule pas avec un autre code.');
      let amount = Math.round(Number(plan.priceMonthly));
      let couponId: string | null = null;
      if (eligibleReferral) {
        const pending = await payments.createQueryBuilder('p').where('p.referral_id = :id', { id: eligibleReferral.id }).andWhere('p.status IN (:...statuses)', { statuses: [PaymentStatus.CREATED, PaymentStatus.PENDING] }).andWhere('p.expires_at > NOW()').getCount();
        if (pending) throw new BadRequestException('Un paiement avec votre réduction de parrainage est déjà en attente.');
        amount = Math.round(amount * (1 - Number(eligibleReferral.refereeRewardValue) / 100));
      } else if (requestedCoupon) {
        const coupons = manager.getRepository(Coupon);
        const coupon = await coupons.findOne({ where: { id: requestedCoupon.couponId }, lock: { mode: 'pessimistic_write' } });
        if (!coupon || !coupon.isActive || (coupon.expiresAt && coupon.expiresAt < new Date())) throw new BadRequestException('Code promo expiré ou inactif.');
        const pending = await payments.createQueryBuilder('p').where('p.coupon_id = :id', { id: coupon.id }).andWhere('p.status IN (:...statuses)', { statuses: [PaymentStatus.CREATED, PaymentStatus.PENDING] }).andWhere('p.expires_at > NOW()').getMany();
        if (coupon.maxRedemptions !== null && coupon.redemptionsCount + pending.length >= coupon.maxRedemptions) throw new BadRequestException('Ce code promo a atteint sa limite.');
        const used = await manager.getRepository(CouponRedemption).count({ where: { couponId: coupon.id, userId } });
        if (used + pending.filter((p) => p.userId === userId).length >= coupon.maxRedemptionsPerUser) throw new BadRequestException('Ce code a déjà été utilisé ou réservé.');
        if (coupon.targetPlanId && coupon.targetPlanId !== plan.id) throw new BadRequestException('Ce code ne concerne pas ce plan.');
        if (Number(coupon.minPlanPrice) > amount) throw new BadRequestException('Montant minimum non atteint pour ce code.');
        if (coupon.rewardType === CouponRewardType.PERCENTAGE_DISCOUNT) amount = Math.max(0, amount - Math.round(amount * Number(coupon.rewardValue) / 100));
        else if (coupon.rewardType === CouponRewardType.FIXED_DISCOUNT) amount = Math.max(0, amount - Number(coupon.rewardValue));
        else throw new BadRequestException('Ce code ne peut pas être utilisé au paiement.');
        couponId = coupon.id;
      }
      if (amount < 300) throw new BadRequestException('Ce montant ne nécessite pas de paiement PAPI.');
      if (dto.expectedAmount == null || dto.expectedAmount !== amount) throw new BadRequestException('Le montant a changé. Vérifiez le récapitulatif avant de continuer.');
      return payments.save(payments.create({ userId, assignmentId: vehicleSubscription.assignmentId, planId: plan.id, couponId, referralId: eligibleReferral?.id ?? null, reference, amount, currency: 'MGA', status: PaymentStatus.CREATED, provider: dto.provider ?? null, expiresAt: new Date(Date.now() + 30 * 60000) }));
    });
    const amount = payment.amount;
    const testMode = process.env.PAPI_TEST_MODE !== 'false';
    const payload = {
      amount,
      clientName: user.name || user.email,
      reference,
      description: `Abonnement iooeh ${plan.name}`.slice(0, 255),
      successUrl: `${publicApp}/payment/return?reference=${encodeURIComponent(reference)}&status=success`,
      failureUrl: `${publicApp}/payment/return?reference=${encodeURIComponent(reference)}&status=failed`,
      notificationUrl: `${publicApi}/payments/papi/notification`,
      validDuration: 30,
      ...(dto.provider ? { provider: dto.provider } : {}),
      payerEmail: user.email,
      ...(user.phone ? { payerPhone: user.phone } : {}),
      isTestMode: testMode,
      ...(testMode ? { testReason: 'Validation intégration iooeh' } : {}),
    };
    const response = await fetch(this.endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Token: apiKey },
      body: JSON.stringify(payload),
    });
    const raw: unknown = await response.json().catch(() => null);
    if (
      !response.ok ||
      typeof raw !== 'object' ||
      raw === null ||
      !('data' in raw)
    ) {
      payment.status = PaymentStatus.FAILED;
      payment.failureMessage = `PAPI HTTP ${response.status}`;
      await this.paymentRepo.save(payment);
      throw new BadGatewayException(
        'PAPI n’a pas pu créer le lien de paiement.',
      );
    }
    const data = (raw as { data: Record<string, unknown> }).data;
    if (
      typeof data.paymentLink !== 'string' ||
      typeof data.notificationToken !== 'string'
    )
      throw new BadGatewayException('Réponse PAPI incomplète.');
    payment.status = PaymentStatus.PENDING;
    payment.paymentLink = data.paymentLink;
    payment.papiNotificationToken = data.notificationToken;
    payment.expiresAt =
      typeof data.linkExpirationDateTime === 'number'
        ? new Date(data.linkExpirationDateTime * 1000)
        : new Date(Date.now() + 30 * 60_000);
    payment = await this.paymentRepo.save(payment);
    return {
      id: payment.id,
      reference,
      paymentLink: payment.paymentLink,
      expiresAt: payment.expiresAt,
    };
  }

  async handleNotification(dto: PapiNotificationDto) {
    // PAPI distingue sa référence interne (`paymentReference`) de la référence
    // fournie par le marchand (`merchantPaymentReference`). Notre ligne locale
    // est toujours indexée par cette dernière.
    const merchantReference =
      dto.merchantPaymentReference?.trim() ||
      (dto.paymentReference.startsWith('IOOEH-')
        ? dto.paymentReference.trim()
        : null);
    if (!merchantReference)
      throw new BadRequestException(
        'Référence marchand PAPI manquante ou invalide.',
      );
    const qualified = await this.paymentRepo.manager.transaction(async (manager) => {
      const payments = manager.getRepository(Payment);
      const payment = await payments.createQueryBuilder('payment')
        .addSelect('payment.papiNotificationToken')
        .setLock('pessimistic_write')
        .where('payment.reference = :reference', { reference: merchantReference })
        .getOne();
      if (!payment || !payment.papiNotificationToken || !this.safeEqual(payment.papiNotificationToken, dto.notificationToken))
        throw new BadRequestException('Notification PAPI invalide.');
      if (Number(dto.amount) !== payment.amount || dto.currency !== payment.currency)
        throw new BadRequestException('Montant ou devise incohérent.');
      if (payment.status === PaymentStatus.SUCCESS || payment.status === PaymentStatus.REQUIRES_REVIEW) return null;
      payment.paymentMethod = dto.paymentMethod ?? null;
      payment.papiMerchantReference = merchantReference;
      payment.papiPaymentReference = dto.paymentReference;
      payment.rawNotification = { ...(dto as unknown as Record<string, unknown>), notificationToken: '[redacted]' };
      if (dto.paymentStatus === 'SUCCESS') {
        if (!payment.assignmentId) throw new BadRequestException('Ce paiement de test ne correspond pas à un véhicule.');
        const assignment = await manager.getRepository(DeviceAssignment).findOne({ where: { id: payment.assignmentId, userId: payment.userId }, lock: { mode: 'pessimistic_write' } });
        if (!assignment) {
          payment.status = PaymentStatus.REQUIRES_REVIEW;
          payment.paidAt = new Date();
          payment.failureMessage = 'Véhicule réaffecté : intervention du support nécessaire.';
          await payments.save(payment);
          return null;
        }
        const subscriptions = manager.getRepository(VehicleSubscription);
        const sub = await subscriptions.findOne({ where: { assignmentId: assignment.id }, lock: { mode: 'pessimistic_write' } });
        if (!sub) throw new BadRequestException('Abonnement du véhicule introuvable.');
        const plan = await manager.getRepository(Plan).findOneByOrFail({ id: payment.planId });
        sub.planId = plan.id; sub.plan = plan.code; sub.status = SubscriptionStatus.ACTIVE; sub.trialEndsAt = null;
        const next = sub.nextBillingDate && sub.nextBillingDate > new Date() ? new Date(sub.nextBillingDate) : new Date();
        next.setMonth(next.getMonth() + 1); sub.nextBillingDate = next;
        await subscriptions.save(sub);
        if (payment.couponId) {
          const coupons = manager.getRepository(Coupon);
          const coupon = await coupons.findOneOrFail({ where: { id: payment.couponId }, lock: { mode: 'pessimistic_write' } });
          coupon.redemptionsCount += 1; await coupons.save(coupon);
          const redemptions = manager.getRepository(CouponRedemption);
          await redemptions.save(redemptions.create({ userId: payment.userId, couponId: coupon.id, rewardType: coupon.rewardType, rewardValue: coupon.rewardValue, appliedToPaymentId: payment.id, metadata: { assignmentId: assignment.id } }));
        }
        if (payment.referralId) {
          const referrals = manager.getRepository(Referral);
          const referral = await referrals.findOne({ where: { id: payment.referralId, refereeId: payment.userId }, lock: { mode: 'pessimistic_write' } });
          if (referral && referral.status === ReferralStatus.PENDING) { referral.status = ReferralStatus.QUALIFIED; await referrals.save(referral); }
        }
        payment.status = PaymentStatus.SUCCESS; payment.paidAt = new Date();
      } else if (dto.paymentStatus === 'FAILED') {
        payment.status = PaymentStatus.FAILED; payment.failureMessage = dto.message ?? null;
      } else if (payment.status !== PaymentStatus.FAILED) payment.status = PaymentStatus.PENDING;
      await payments.save(payment);
      return payment.status === PaymentStatus.SUCCESS ? { userId: payment.userId, id: payment.id } : null;
    });
    if (qualified) {
      this.entitlements.invalidate(qualified.userId);

    }
    return { received: true };
  }

  async status(userId: number, reference: string) {
    const p = await this.paymentRepo.findOne({ where: { userId, reference } });
    if (!p) throw new NotFoundException('Paiement introuvable.');
    return {
      reference: p.reference,
      status: p.status,
      amount: p.amount,
      currency: p.currency,
      paidAt: p.paidAt,
      planId: p.planId,
    };
  }
  async history(userId: number) {
    return this.paymentRepo.find({
      where: { userId },
      order: { createdAt: 'DESC' },
      take: 50,
    });
  }
  listPlans() {
    return this.planRepo.find({
      where: { isActive: true },
      order: { displayOrder: 'ASC' },
      relations: { planFeatures: { feature: true } },
    });
  }
  private safeEqual(a: string, b: string) {
    const aa = Buffer.from(a);
    const bb = Buffer.from(b);
    return aa.length === bb.length && timingSafeEqual(aa, bb);
  }

  async listAdminPayments(page = 1, limit = 50) {
    const [payments, total] = await this.paymentRepo.findAndCount({
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    if (payments.length === 0) return { data: [], meta: { total, page, limit, totalPages: 0 } };

    const userIds = [...new Set(payments.map((p) => p.userId))];
    const planIds = [...new Set(payments.map((p) => p.planId))];

    const [usersList, plansList] = await Promise.all([
      this.users.findAll(),
      this.planRepo.find({ where: { id: In(planIds) } }),
    ]);

    const userMap = new Map(usersList.map((u) => [u.id, u]));
    const planMap = new Map(plansList.map((p) => [p.id, p]));

    const data = payments.map((p) => {
      const u = userMap.get(p.userId);
      const plan = planMap.get(p.planId);
      return {
        ...p,
        userName: u?.name || u?.email || `Utilisateur #${p.userId}`,
        userEmail: u?.email || '',
        planName: plan?.name || 'Plan',
        planCode: plan?.code || '',
      };
    });

    return {
      data,
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }
}
