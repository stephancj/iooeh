import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Subscription, SubscriptionStatus } from '../admin/subscription.entity';
import { DeviceAssignment } from '../admin/device-assignment.entity';
import { VehicleSubscription } from './vehicle-subscription.entity';
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
    @InjectRepository(DeviceAssignment)
    private readonly assignmentRepo: Repository<DeviceAssignment>,
    @InjectRepository(VehicleSubscription)
    private readonly vehicleSubscriptionRepo: Repository<VehicleSubscription>,
  ) {}

  /** Returns the subscription for an owned vehicle, creating its seven-day trial once. */
  async ensureVehicleSubscription(userId: number, deviceId: number): Promise<VehicleSubscription> {
    const assignment = await this.assignmentRepo.findOne({ where: { userId, deviceId } });
    if (!assignment) throw new NotFoundException('Véhicule introuvable.');
    const existing = await this.vehicleSubscriptionRepo.findOne({ where: { assignmentId: assignment.id } });
    if (existing) return existing;
    const plan = await this.planRepo.findOne({ where: { code: 'free', isActive: true } });
    if (!plan) throw new NotFoundException('Le plan Free par défaut est introuvable.');
    await this.vehicleSubscriptionRepo.createQueryBuilder().insert().values({
      assignmentId: assignment.id,
      planId: plan.id,
      plan: plan.code,
      status: SubscriptionStatus.TRIAL,
      trialEndsAt: new Date(new Date(assignment.createdAt).getTime() + 7 * 24 * 3600 * 1000),
      nextBillingDate: null,
      notes: null,
    }).orIgnore().execute();
    return this.vehicleSubscriptionRepo.findOneOrFail({ where: { assignmentId: assignment.id } });
  }

  async findVehicleSubscriptionForPayment(userId: number, assignmentId: number): Promise<VehicleSubscription> {
    const assignment = await this.assignmentRepo.findOne({ where: { id: assignmentId, userId } });
    if (!assignment) throw new NotFoundException('Affectation du véhicule introuvable.');
    return this.vehicleSubscriptionRepo.findOneOrFail({ where: { assignmentId } });
  }

  saveVehicleSubscription(subscription: VehicleSubscription): Promise<VehicleSubscription> {
    return this.vehicleSubscriptionRepo.save(subscription);
  }

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
    const assignments = await this.assignmentRepo.find({ where: { userId } });
    const vehicleRights = await Promise.all(assignments.map((item) => this.getForVehicle(userId, item.deviceId)));
    let representative = vehicleRights.find((item) => item.accessAllowed) ?? vehicleRights[0];
    if (!representative) {
      const freePlan = await this.planRepo.findOne({ where: { code: 'free', isActive: true } });
      if (!freePlan) throw new NotFoundException('Le plan Free par défaut est introuvable.');
      representative = await this.resolveSubscription({ id: '', planId: freePlan.id, plan: freePlan.code, status: SubscriptionStatus.TRIAL, trialEndsAt: null, nextBillingDate: null } as Subscription);
    }
    const result: UserEntitlements = { ...representative, features: { ...representative.features } };
    if (vehicleRights.length) {
      result.accessAllowed = vehicleRights.some((item) => item.accessAllowed);
      result.features = {};
      for (const rights of vehicleRights.filter((item) => item.accessAllowed)) {
        for (const [code, value] of Object.entries(rights.features)) {
          if (typeof value === 'boolean') result.features[code] = value || result.features[code] === true;
          else if (typeof value === 'number') result.features[code] = Math.max(value, typeof result.features[code] === 'number' ? result.features[code] as number : 0);
          else result.features[code] = value;
        }
      }
    }
    this.cache.set(userId, { at: Date.now(), value: result });
    return result;
  }

  async getForVehicle(userId: number, deviceId: number): Promise<UserEntitlements> {
    return this.resolveSubscription(await this.ensureVehicleSubscription(userId, deviceId));
  }

  private async resolveSubscription(subscription: Subscription | VehicleSubscription): Promise<UserEntitlements> {
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
        new Date(subscription.trialEndsAt).getTime() > now) &&
      (subscription.status !== SubscriptionStatus.ACTIVE ||
        !subscription.nextBillingDate ||
        new Date(subscription.nextBillingDate).getTime() > now);

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
    return result;
  }

  invalidate(userId: number): void {
    this.cache.delete(userId);
  }

  async hasFeature(userId: number, code: string, deviceId?: number): Promise<boolean> {
    try {
      const entitlements = await (deviceId == null ? this.getForUser(userId) : this.getForVehicle(userId, deviceId));
      return entitlements.accessAllowed && entitlements.features[code] === true;
    } catch (error) {
      if (error instanceof NotFoundException && deviceId != null) return false;
      throw error;
    }
  }

  async assertFeature(userId: number, code: string, deviceId?: number): Promise<void> {
    const entitlements = await (deviceId == null ? this.getForUser(userId) : this.getForVehicle(userId, deviceId));
    if (!entitlements.accessAllowed || entitlements.features[code] !== true) {
      throw new ForbiddenException(
        `La fonctionnalité « ${code} » n’est pas incluse dans votre abonnement.`,
      );
    }
  }

  async getNumber(userId: number, code: string, deviceId?: number): Promise<number> {
    const entitlements = await (deviceId == null ? this.getForUser(userId) : this.getForVehicle(userId, deviceId));
    const value = entitlements.features[code];
    if (!entitlements.accessAllowed || typeof value !== 'number') {
      throw new ForbiddenException(
        `La limite « ${code} » n’est pas incluse dans votre abonnement.`,
      );
    }
    return value;
  }

  async assertHistoryRange(userId: number, from: Date, deviceId?: number): Promise<void> {
    const days = await this.getNumber(userId, 'history_retention_days', deviceId);
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
