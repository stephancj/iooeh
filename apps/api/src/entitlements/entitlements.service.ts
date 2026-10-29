import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Subscription, SubscriptionStatus } from '../admin/subscription.entity';
import { Geofence } from '../geofences/entities/geofence.entity';
import { Feature } from './feature.entity';
import { PlanFeature } from './plan-feature.entity';
import { Plan } from './plan.entity';

export interface UserEntitlements {
  subscription: {
    id: string;
    status: SubscriptionStatus;
    trialEndsAt: Date | null;
    nextBillingDate: Date | null;
  };
  plan: {
    id: string;
    code: string;
    name: string;
  };
  accessAllowed: boolean;
  features: Record<string, boolean | number | string>;
}

@Injectable()
export class EntitlementsService {
  private readonly cache = new Map<
    number,
    { at: number; value: UserEntitlements }
  >();
  private readonly cacheTtlMs = 5_000;

  constructor(
    @InjectRepository(Subscription)
    private readonly subscriptionRepo: Repository<Subscription>,
    @InjectRepository(Plan)
    private readonly planRepo: Repository<Plan>,
    @InjectRepository(Feature)
    private readonly featureRepo: Repository<Feature>,
    @InjectRepository(PlanFeature)
    private readonly planFeatureRepo: Repository<PlanFeature>,
    @InjectRepository(Geofence)
    private readonly geofenceRepo: Repository<Geofence>,
  ) {}

  async ensureDefaultSubscription(userId: number): Promise<Subscription> {
    const existing = await this.subscriptionRepo.findOne({ where: { userId } });
    if (existing) return existing;

    const freePlan = await this.planRepo.findOne({
      where: { code: 'free', isActive: true },
    });
    if (!freePlan) {
      throw new NotFoundException('Le plan Free par défaut est introuvable.');
    }

    const defaults = this.subscriptionRepo.create({
      userId,
      planId: freePlan.id,
      plan: freePlan.code,
      status: SubscriptionStatus.TRIAL,
      trialEndsAt: new Date(Date.now() + 30 * 24 * 3600 * 1000),
      nextBillingDate: null,
      notes: null,
    });
    await this.subscriptionRepo
      .createQueryBuilder()
      .insert()
      .values(defaults)
      .orIgnore()
      .execute();
    return this.subscriptionRepo.findOneOrFail({ where: { userId } });
  }

  async getForUser(userId: number): Promise<UserEntitlements> {
    const cached = this.cache.get(userId);
    if (cached && Date.now() - cached.at < this.cacheTtlMs) return cached.value;
    const subscription = await this.ensureDefaultSubscription(userId);
    let plan = subscription.planId
      ? await this.planRepo.findOne({ where: { id: subscription.planId } })
      : null;
    plan ??= await this.planRepo.findOne({
      where: { code: subscription.plan },
    });
    if (!plan) throw new NotFoundException('Plan d’abonnement introuvable.');

    const assignments = await this.planFeatureRepo.find({
      where: { planId: plan.id },
      relations: { feature: true },
    });
    const now = Date.now();
    const accessAllowed =
      (subscription.status === SubscriptionStatus.ACTIVE ||
        subscription.status === SubscriptionStatus.TRIAL) &&
      (subscription.status !== SubscriptionStatus.TRIAL ||
        !subscription.trialEndsAt ||
        new Date(subscription.trialEndsAt).getTime() > now);

    const features: Record<string, boolean | number | string> = {};
    for (const item of assignments) {
      if (!item.feature?.isActive) continue;
      features[item.feature.code] = accessAllowed
        ? item.enabled
          ? (item.value ?? true)
          : false
        : false;
    }

    const result: UserEntitlements = {
      subscription: {
        id: subscription.id,
        status: subscription.status,
        trialEndsAt: subscription.trialEndsAt,
        nextBillingDate: subscription.nextBillingDate,
      },
      plan: { id: plan.id, code: plan.code, name: plan.name },
      accessAllowed,
      features,
    };
    this.cache.set(userId, { at: Date.now(), value: result });
    return result;
  }

  invalidate(userId: number): void {
    this.cache.delete(userId);
  }

  async hasFeature(userId: number, code: string): Promise<boolean> {
    const entitlements = await this.getForUser(userId);
    return entitlements.accessAllowed && entitlements.features[code] === true;
  }

  async assertFeature(userId: number, code: string): Promise<void> {
    const entitlements = await this.getForUser(userId);
    if (!entitlements.accessAllowed || entitlements.features[code] !== true) {
      throw new ForbiddenException(
        `La fonctionnalité « ${code} » n’est pas incluse dans votre abonnement.`,
      );
    }
  }

  async getNumber(userId: number, code: string): Promise<number> {
    const entitlements = await this.getForUser(userId);
    const value = entitlements.features[code];
    if (!entitlements.accessAllowed || typeof value !== 'number') {
      throw new ForbiddenException(
        `La limite « ${code} » n’est pas incluse dans votre abonnement.`,
      );
    }
    return value;
  }

  async assertHistoryRange(userId: number, from: Date): Promise<void> {
    const days = await this.getNumber(userId, 'history_retention_days');
    const earliest = Date.now() - days * 24 * 3600 * 1000;
    if (from.getTime() < earliest) {
      throw new ForbiddenException(
        `Votre abonnement permet de consulter ${days} jour(s) d’historique.`,
      );
    }
  }

  async assertCanAddGeofence(userId: number): Promise<void> {
    const [limit, count] = await Promise.all([
      this.getNumber(userId, 'max_geofences'),
      this.geofenceRepo.count({ where: { userId } }),
    ]);
    if (count >= limit) {
      throw new ForbiddenException(
        `Limite de ${limit} zone(s) atteinte pour votre abonnement.`,
      );
    }
  }

  listFeatures(): Promise<Feature[]> {
    return this.featureRepo.find({
      order: { category: 'ASC', displayOrder: 'ASC', name: 'ASC' },
    });
  }
}
