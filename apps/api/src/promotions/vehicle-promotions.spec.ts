import { PromotionsService } from './promotions.service';
import { ReferralStatus } from './entities/referral.entity';

describe('Vehicle referral rewards', () => {
  function setup(status: ReferralStatus, owner: unknown = { id: 20, userId: 7, deviceId: 4 }) {
    const referral = { id: 'r', referrerId: 7, status, referrerRewardValue: '30', referrerRewardType: 'FREE_SUBSCRIPTION_DAYS' };
    const sub = { assignmentId: 20, status: 'trial', trialEndsAt: new Date(Date.now() + 86400000), nextBillingDate: null };
    const referrals = { findOne: jest.fn().mockResolvedValue(referral), save: jest.fn().mockResolvedValue(referral) };
    const assignments = { findOne: jest.fn().mockResolvedValue(owner) };
    const subscriptions = { findOneOrFail: jest.fn().mockResolvedValue(sub), save: jest.fn().mockResolvedValue(sub) };
    const redemptions = { create: jest.fn((x) => x), save: jest.fn() };
    const manager = { getRepository: (entity: { name: string }) => ({ Referral: referrals, DeviceAssignment: assignments, VehicleSubscription: subscriptions, CouponRedemption: redemptions }[entity.name]) };
    const referralRepo = { manager: { transaction: (fn: (arg: unknown) => unknown) => fn(manager) } };
    const rights = { ensureVehicleSubscription: jest.fn().mockResolvedValue(sub), invalidate: jest.fn() };
    const service = new PromotionsService({} as never, referralRepo as never, {} as never, {} as never, {} as never, {} as never, rights as never);
    return { service, sub, subscriptions, redemptions };
  }
  it('adds the reward to the chosen vehicle and retains the unexpired trial', async () => {
    const { service, sub, subscriptions, redemptions } = setup(ReferralStatus.QUALIFIED);
    const oldEnd = sub.trialEndsAt.getTime();
    await service.claimReferralReward(7, 'r', 4);
    expect(subscriptions.save).toHaveBeenCalledTimes(1);
    expect((sub.nextBillingDate as unknown as Date).getTime()).toBe(oldEnd + 30 * 86400000);
    expect(redemptions.save).toHaveBeenCalledTimes(1);
  });
  it('does not apply an already used reward', async () => {
    const { service, subscriptions } = setup(ReferralStatus.REWARDED);
    await expect(service.claimReferralReward(7, 'r', 4)).rejects.toThrow('déjà utilisée');
    expect(subscriptions.save).not.toHaveBeenCalled();
  });
  it('does not apply a reward to an unowned vehicle', async () => {
    const { service, subscriptions } = setup(ReferralStatus.QUALIFIED, null);
    await expect(service.claimReferralReward(7, 'r', 4)).rejects.toThrow('Véhicule introuvable');
    expect(subscriptions.save).not.toHaveBeenCalled();
  });
});

describe('Vehicle coupon redemption', () => {
  function setup(used: number) {
    const coupon = { id: 'c', code: 'MOTO30', isActive: true, expiresAt: null, maxRedemptions: 5, redemptionsCount: 0, maxRedemptionsPerUser: 1, rewardType: 'FREE_SUBSCRIPTION_DAYS', rewardValue: '30' };
    const sub = { assignmentId: 20, status: 'trial', plan: 'free', trialEndsAt: new Date(Date.now() + 86400000), nextBillingDate: null };
    const coupons = { findOne: jest.fn().mockResolvedValue(coupon), save: jest.fn() };
    const assignments = { findOne: jest.fn().mockResolvedValue({ id: 20, userId: 7, deviceId: 4 }) };
    const subscriptions = { findOneOrFail: jest.fn().mockResolvedValue(sub), save: jest.fn() };
    const redemptions = { count: jest.fn().mockResolvedValue(used), create: jest.fn((x) => x), save: jest.fn() };
    const manager = { getRepository: (entity: { name: string }) => ({ Coupon: coupons, DeviceAssignment: assignments, VehicleSubscription: subscriptions, CouponRedemption: redemptions }[entity.name]) };
    const couponRepo = { ...coupons, manager: { transaction: (fn: (arg: unknown) => unknown) => fn(manager) } };
    const rights = { ensureVehicleSubscription: jest.fn().mockResolvedValue(sub), invalidate: jest.fn() };
    const service = new PromotionsService(couponRepo as never, {} as never, {} as never, {} as never, {} as never, {} as never, rights as never);
    return { service, sub, subscriptions, redemptions };
  }
  it('extends the selected vehicle and records one use', async () => {
    const { service, sub, subscriptions, redemptions } = setup(0);
    const end = sub.trialEndsAt.getTime();
    await service.redeemCode(7, 'MOTO30', 4);
    expect((sub.nextBillingDate as unknown as Date).getTime()).toBe(end + 30 * 86400000);
    expect(subscriptions.save).toHaveBeenCalledTimes(1);
    expect(redemptions.save).toHaveBeenCalledTimes(1);
  });
  it('rejects another use before changing the subscription', async () => {
    const { service, subscriptions } = setup(1);
    await expect(service.redeemCode(7, 'MOTO30', 4)).rejects.toThrow('déjà utilisé');
    expect(subscriptions.save).not.toHaveBeenCalled();
  });
});
