import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { DeviceAssignment } from './device-assignment.entity';
import { Subscription, SubscriptionStatus } from './subscription.entity';
import { UsersService } from '../users/users.service';
import { DevicesService } from '../devices/devices.service';
import { VehiclesService } from '../vehicles/vehicles.service';
import { GeofencesService } from '../geofences/geofences.service';
import { AlertsService } from '../alerts/alerts.service';
import { PositionsService } from '../positions/positions.service';
import { CreateUserDto, UpdateUserDto } from './admin.dto';
import { UserRole } from '../users/user.entity';
import { Feature, FeatureValueType } from '../entitlements/feature.entity';
import { Plan } from '../entitlements/plan.entity';
import { PlanFeature } from '../entitlements/plan-feature.entity';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { SystemSetting } from './system-setting.entity';

@Injectable()
export class AdminService {
  constructor(
    @InjectRepository(DeviceAssignment)
    private readonly assignmentRepo: Repository<DeviceAssignment>,
    @InjectRepository(Subscription)
    private readonly subscriptionRepo: Repository<Subscription>,
    @InjectRepository(Feature)
    private readonly featureRepo: Repository<Feature>,
    @InjectRepository(Plan)
    private readonly planRepo: Repository<Plan>,
    @InjectRepository(PlanFeature)
    private readonly planFeatureRepo: Repository<PlanFeature>,
    @InjectRepository(SystemSetting)
    private readonly systemSettingRepo: Repository<SystemSetting>,
    private readonly usersService: UsersService,
    private readonly devicesService: DevicesService,
    private readonly vehiclesService: VehiclesService,
    private readonly geofencesService: GeofencesService,
    private readonly alertsService: AlertsService,
    private readonly positionsService: PositionsService,
    private readonly entitlementsService: EntitlementsService,
  ) {}

  // ── System Config ────────────────────────────────────────────────────────

  async getConfig() {
    const settings = await this.systemSettingRepo.find();
    const settingsMap = settings.reduce((acc, s) => {
      acc[s.key] = s.value;
      return acc;
    }, {} as Record<string, any>);

    return {
      apiUrl: process.env.NODE_ENV === 'production' ? 'https://api.trackeo.zenkai.mg/api' : (process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3000/api'),
      traccarUrl: process.env.TRACCAR_URL || 'http://localhost:8082',
      oneSignalAppId: process.env.ONESIGNAL_APP_ID || 'Configured via backend .env',
      whatsappEnabled: settingsMap['whatsapp_enabled'] ?? true,
      pushEnabled: settingsMap['push_enabled'] ?? true,
      database: 'TimescaleDB',
    };
  }

  async updateConfig(key: string, value: any) {
    let setting = await this.systemSettingRepo.findOne({ where: { key } });
    if (!setting) {
      setting = this.systemSettingRepo.create({ key, value });
    } else {
      setting.value = value;
    }
    return this.systemSettingRepo.save(setting);
  }

  // ── Feature catalogue & plans ────────────────────────────────────────────

  listFeatures() {
    return this.featureRepo.find({
      order: { category: 'ASC', displayOrder: 'ASC', name: 'ASC' },
    });
  }

  async createFeature(data: Partial<Feature>) {
    const code = String(data.code ?? '')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_]+/g, '_');
    if (!code) throw new NotFoundException('Feature code is required');
    return this.featureRepo.save(this.featureRepo.create({ ...data, code }));
  }

  async updateFeature(id: string, data: Partial<Feature>) {
    const feature = await this.featureRepo.findOne({ where: { id } });
    if (!feature) throw new NotFoundException(`Feature ${id} not found`);
    Object.assign(feature, data, { code: feature.code });
    return this.featureRepo.save(feature);
  }

  async deactivateFeature(id: string) {
    return this.updateFeature(id, { isActive: false });
  }

  listPlans() {
    return this.planRepo.find({
      relations: { planFeatures: { feature: true } },
      order: { displayOrder: 'ASC', name: 'ASC' },
    });
  }

  async getPlan(id: string) {
    const plan = await this.planRepo.findOne({
      where: { id },
      relations: { planFeatures: { feature: true } },
    });
    if (!plan) throw new NotFoundException(`Plan ${id} not found`);
    return plan;
  }

  async createPlan(data: Partial<Plan>) {
    const code = String(data.code ?? '')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_]+/g, '_');
    return this.planRepo.save(this.planRepo.create({ ...data, code }));
  }

  async updatePlan(id: string, data: Partial<Plan>) {
    const plan = await this.getPlan(id);
    Object.assign(plan, data, {
      code: plan.code,
      planFeatures: plan.planFeatures,
    });
    return this.planRepo.save(plan);
  }

  async deactivatePlan(id: string) {
    const subscriptions = await this.subscriptionRepo.count({
      where: { planId: id },
    });
    if (subscriptions > 0) {
      throw new NotFoundException(
        'Ce plan est encore utilisé par des abonnements.',
      );
    }
    return this.updatePlan(id, { isActive: false });
  }

  async replacePlanFeatures(
    planId: string,
    inputs: Array<{
      featureId: string;
      enabled: boolean;
      value?: boolean | number | string | null;
    }>,
  ) {
    await this.getPlan(planId);
    const ids = inputs.map((item) => item.featureId);
    const features = ids.length
      ? await this.featureRepo.find({ where: { id: In(ids) } })
      : [];
    if (features.length !== new Set(ids).size)
      throw new NotFoundException('Une fonctionnalité est introuvable.');
    const featureMap = new Map(
      features.map((feature) => [feature.id, feature]),
    );

    const rows = inputs.map((input) => {
      const feature = featureMap.get(input.featureId)!;
      let value = input.value ?? null;
      if (feature.valueType === FeatureValueType.NUMBER) {
        value = Number(value);
        if (!Number.isFinite(value) || Number(value) < 0) {
          throw new NotFoundException(
            `Valeur numérique invalide pour ${feature.name}.`,
          );
        }
      } else if (feature.valueType === FeatureValueType.BOOLEAN) {
        value = true;
      } else if (value != null) {
        value = String(value);
      }
      return this.planFeatureRepo.create({
        planId,
        featureId: feature.id,
        enabled: input.enabled,
        value,
      });
    });

    await this.planFeatureRepo.manager.transaction(async (manager) => {
      await manager.delete(PlanFeature, { planId });
      if (rows.length) await manager.save(PlanFeature, rows);
    });

    const subscribers = await this.subscriptionRepo.find({ where: { planId } });
    subscribers.forEach((subscription) =>
      this.entitlementsService.invalidate(subscription.userId),
    );
    return this.getPlan(planId);
  }

  // ── Users ────────────────────────────────────────────────────────────────

  async listUsers(page = 1, limit = 50) {
    const [users, total] = await this.usersService.findAllPaginated(page, limit);
    
    if (users.length === 0) {
      return { data: [], meta: { total, page, limit, totalPages: 0 } };
    }

    const assignments = await this.assignmentRepo.find({
      where: { userId: In(users.map(u => u.id)) }
    });

    const vehicleCountByUser = new Map<number, number>();
    for (const a of assignments) {
      vehicleCountByUser.set(
        a.userId,
        (vehicleCountByUser.get(a.userId) ?? 0) + 1,
      );
    }

    const data = users.map((u) => ({
      ...u,
      vehicleCount: vehicleCountByUser.get(u.id) ?? 0,
    }));

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

  async createUser(dto: CreateUserDto) {
    const user = await this.usersService.create({
      email: dto.email,
      password: dto.password,
      name: dto.name,
      role: dto.role ?? UserRole.USER,
    });
    return user;
  }

  async updateUser(userId: number, dto: UpdateUserDto) {
    const user = await this.usersService.findByIdAdmin(userId);
    if (!user) throw new NotFoundException(`User ${userId} not found`);
    return this.usersService.adminUpdate(userId, dto);
  }

  async deactivateUser(userId: number) {
    const user = await this.usersService.findByIdAdmin(userId);
    if (!user) throw new NotFoundException(`User ${userId} not found`);
    return this.usersService.adminUpdate(userId, { isActive: false });
  }

  /** Admin — détail d'un utilisateur avec ses véhicules, alertes et geofences */
  async getUserDetail(userId: number) {
    const user = await this.usersService.findByIdAdmin(userId);
    if (!user) throw new NotFoundException(`User ${userId} not found`);

    const [vehicles, openAlertsCount, geofencesCount] = await Promise.all([
      this.vehiclesService.findAllForUser(userId),
      this.alertsService.countOpenForUser(userId),
      this.geofencesService.countForUser(userId),
    ]);

    return {
      ...user,
      vehicles,
      openAlertsCount,
      geofencesCount,
    };
  }

  // ── Vehicles (enriched — device + position + assignment) ─────────────────

  async listVehicles(page = 1, limit = 50) {
    const [[vehicles, total], assignments, users, allAlerts] = await Promise.all([
      this.vehiclesService.findAllPaginated(page, limit),
      this.assignmentRepo.find(),
      this.usersService.findAll(),
      this.alertsService.findAll(),
    ]);

    if (vehicles.length === 0) {
      return { data: [], meta: { total, page, limit, totalPages: 0 } };
    }

    const userMap = new Map(users.map((u) => [u.id, u.name ?? u.email]));

    const openAlertsByDevice = new Map<number, number>();
    for (const a of allAlerts) {
      if (a.status === 'open') {
        openAlertsByDevice.set(
          a.deviceId,
          (openAlertsByDevice.get(a.deviceId) ?? 0) + 1,
        );
      }
    }

    const data = vehicles.map((v) => {
      const assignment = assignments.find((a) => a.deviceId === v.id);
      return {
        ...v,
        assignedUserId: assignment?.userId ?? null,
        assignedUserName: assignment
          ? (userMap.get(assignment.userId) ?? null)
          : null,
        openAlertsCount: openAlertsByDevice.get(v.id) ?? 0,
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

  /** Admin — détail d'un véhicule avec alertes récentes, geofences liées et assignation */
  async getVehicleDetail(deviceId: number) {
    const [vehicle, recentAlerts, linkedGeofences, assignment] =
      await Promise.all([
        this.vehiclesService.findOne(deviceId),
        this.alertsService.findByDeviceId(deviceId, 20),
        this.geofencesService.findByDeviceId(deviceId),
        this.assignmentRepo.findOne({ where: { deviceId } }),
      ]);

    let assignedUser: import('../users/user.entity').User | null = null;
    if (assignment) {
      assignedUser = await this.usersService.findByIdAdmin(assignment.userId);
    }

    return {
      ...vehicle,
      assignedUserId: assignment?.userId ?? null,
      assignedUserName: assignedUser
        ? (assignedUser.name ?? assignedUser.email)
        : null,
      assignedUserPhone: assignedUser?.phone ?? null,
      recentAlerts,
      linkedGeofences,
    };
  }

  // ── Assignments ───────────────────────────────────────────────────────────

  async assignDevice(deviceId: number, userId: number) {
    await this.devicesService.findOne(deviceId);
    const user = await this.usersService.findByIdAdmin(userId);
    if (!user) throw new NotFoundException(`User ${userId} not found`);

    const existing = await this.assignmentRepo.findOne({ where: { deviceId } });

    if (existing) {
      if (existing.userId !== userId) {
        await this.assignmentRepo.manager.transaction(async (manager) => {
          await manager.delete(DeviceAssignment, { id: existing.id });
          await manager.save(DeviceAssignment, manager.create(DeviceAssignment, { deviceId, userId }));
        });
        this.entitlementsService.invalidate(existing.userId);
        this.entitlementsService.invalidate(userId);
      }
      return { deviceId, userId, updated: true };
    }

    await this.assignmentRepo.save(
      this.assignmentRepo.create({ deviceId, userId }),
    );
    return { deviceId, userId, updated: false };
  }

  async unassignDevice(deviceId: number) {
    const result = await this.assignmentRepo.delete({ deviceId });
    if (result.affected === 0) {
      throw new NotFoundException(`No assignment found for device ${deviceId}`);
    }
  }

  /** Retourne les IDs de devices assignés à un user donné */
  async getDeviceIdsForUser(userId: number): Promise<number[]> {
    const assignments = await this.assignmentRepo.find({ where: { userId } });
    return assignments.map((a) => a.deviceId);
  }

  // ── Geofences ────────────────────────────────────────────────────────────

  listGeofences() {
    return this.geofencesService.findAll();
  }

  removeGeofence(id: string) {
    return this.geofencesService.removeByIdAdmin(id);
  }

  // ── Alerts ───────────────────────────────────────────────────────────────

  async listAlerts(page = 1, limit = 50) {
    const [alerts, total] = await this.alertsService.findAllPaginated(page, limit);
    return {
      data: alerts,
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  ackAlert(id: string) {
    return this.alertsService.ackAlert(id);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /** Vue d'ensemble globale — stats agrégées pour le dashboard reports */
  async getReportsOverview() {
    const [users, vehicles, allAlerts] = await Promise.all([
      this.usersService.findAll(),
      this.vehiclesService.findAll(),
      this.alertsService.findAll(),
    ]);

    const statusCounts = { online: 0, idle: 0, offline: 0 };
    for (const v of vehicles) statusCounts[v.status]++;

    const assignments = await this.assignmentRepo.find();
    const assignedDeviceIds = new Set(assignments.map(a => a.deviceId));
    const unassignedVehicles = vehicles.filter(v => !assignedDeviceIds.has(v.id)).length;

    const alertsByType = allAlerts.reduce<Record<string, number>>((acc, a) => {
      acc[a.type] = (acc[a.type] ?? 0) + 1;
      return acc;
    }, {});

    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const alertsThisMonth = allAlerts.filter(
      (a) => new Date(a.createdAt) >= startOfMonth,
    ).length;

    const openAlerts = allAlerts.filter((a) => a.status === 'open').length;
    const recentOpenAlerts = allAlerts.filter((a) => a.status === 'open')
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
      .slice(0, 5);

    return {
      totalUsers: users.length,
      activeUsers: users.filter((u) => u.isActive).length,
      totalVehicles: vehicles.length,
      statusCounts,
      totalAlerts: allAlerts.length,
      openAlerts,
      recentOpenAlerts,
      alertsThisMonth,
      alertsByType,
      unassignedVehicles,
    };
  }

  /**
   * Rapport par véhicule : distance, alertes, vitesse max sur la période.
   * `period` = 'today' | '7d' | '30d'
   */
  async getVehicleReports(period: 'today' | '7d' | '30d') {
    const now = new Date();
    let from: Date;
    if (period === 'today') {
      from = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    } else if (period === '7d') {
      from = new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    } else {
      from = new Date(now.getTime() - 30 * 24 * 3600 * 1000);
    }

    const [vehicles, assignments, users, allAlerts] = await Promise.all([
      this.vehiclesService.findAll(),
      this.assignmentRepo.find(),
      this.usersService.findAll(),
      this.alertsService.findAll(),
    ]);

    const userMap = new Map(users.map((u) => [u.id, u.name ?? u.email]));
    const periodAlerts = allAlerts.filter((a) => new Date(a.createdAt) >= from);

    const results = await Promise.all(
      vehicles.map(async (v) => {
        const assignment = assignments.find((a) => a.deviceId === v.id);
        const distanceSummary = await this.positionsService
          .getDistanceSummary(v.id, from, now)
          .catch(() => ({ distanceKm: 0, pointCount: 0, maxSpeedKmh: 0 }));

        const alertCount = periodAlerts.filter(
          (a) => a.deviceId === v.id,
        ).length;

        return {
          id: v.id,
          name: v.name,
          plate: v.plate,
          status: v.status,
          lastUpdate: v.lastUpdate,
          assignedUserName: assignment
            ? (userMap.get(assignment.userId) ?? null)
            : null,
          distanceKm: distanceSummary.distanceKm,
          maxSpeedKmh: distanceSummary.maxSpeedKmh,
          pointCount: distanceSummary.pointCount,
          alertCount,
        };
      }),
    );

    return { from, to: now, period, vehicles: results };
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────

  /** Liste tous les users avec leur abonnement (crée un enregistrement free/trial si absent) */
  async listSubscriptions(page = 1, limit = 50) {
    const [assignments, total] = await this.assignmentRepo.findAndCount({ order: { id: 'DESC' }, skip: (page - 1) * limit, take: limit });
    const plans = await this.planRepo.find();
    const planMap = new Map(plans.map((plan) => [plan.id, plan]));
    const data = await Promise.all(assignments.map(async (assignment) => {
      const [user, vehicle, sub] = await Promise.all([
        this.usersService.findByIdAdmin(assignment.userId),
        this.vehiclesService.findOne(assignment.deviceId),
        this.entitlementsService.ensureVehicleSubscription(assignment.userId, assignment.deviceId),
      ]);
      return { userId: assignment.userId, deviceId: assignment.deviceId, vehicleName: vehicle.name, vehiclePlate: vehicle.plate,
        name: user?.name ?? null, email: user?.email ?? '', phone: user?.phone ?? null, isActive: user?.isActive ?? false,
        subscription: { ...sub, planDetails: sub.planId ? (planMap.get(sub.planId) ?? null) : null } };
    }));
    return { data, meta: { total, page, limit, totalPages: Math.ceil(total / limit) } };
  }

  /** Met à jour l’abonnement du véhicule affecté. */
  async upsertSubscription(
    deviceId: number,
    data: {
      planId?: string;
      plan?: string;
      status?: SubscriptionStatus;
      nextBillingDate?: string | null;
      trialEndsAt?: string | null;
      notes?: string | null;
    },
  ) {
    const assignment = await this.assignmentRepo.findOne({ where: { deviceId } });
    if (!assignment) throw new NotFoundException('Véhicule non affecté.');
    const userId = assignment.userId;
    const sub = await this.entitlementsService.ensureVehicleSubscription(userId, deviceId);

    if (data.planId || data.plan) {
      const targetPlan = data.planId
        ? await this.planRepo.findOne({
            where: { id: data.planId, isActive: true },
          })
        : await this.planRepo.findOne({
            where: { code: data.plan!, isActive: true },
          });
      if (!targetPlan)
        throw new BadRequestException('Plan invalide ou inactif.');
      sub.planId = targetPlan.id;
      sub.plan = targetPlan.code;

    }
    if (data.status) sub.status = data.status;
    if (data.nextBillingDate !== undefined)
      sub.nextBillingDate = data.nextBillingDate
        ? new Date(data.nextBillingDate)
        : null;
    if (data.trialEndsAt !== undefined)
      sub.trialEndsAt = data.trialEndsAt ? new Date(data.trialEndsAt) : null;
    if (data.notes !== undefined) sub.notes = data.notes ?? null;

    const saved = await this.entitlementsService.saveVehicleSubscription(sub);
    this.entitlementsService.invalidate(userId);
    return saved;
  }

  // ── Detailed vehicle reports ──────────────────────────────────────────────

  private periodToDates(period: 'today' | '7d' | '30d'): {
    from: Date;
    to: Date;
  } {
    const now = new Date();
    let from: Date;
    if (period === 'today') {
      from = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    } else if (period === '7d') {
      from = new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    } else {
      from = new Date(now.getTime() - 30 * 24 * 3600 * 1000);
    }
    return { from, to: now };
  }

  async getVehicleActivitySummary(
    deviceId: number,
    period: 'today' | '7d' | '30d',
  ) {
    const { from, to } = this.periodToDates(period);
    const summary = await this.positionsService
      .getActivitySummary(deviceId, from, to)
      .catch(() => ({
        distanceKm: 0,
        drivingMinutes: 0,
        idleMinutes: 0,
        maxSpeedKmh: 0,
        tripCount: 0,
        speedViolationCount: 0,
        pointCount: 0,
      }));
    return { deviceId, period, from, to, ...summary };
  }

  async getVehicleTripLog(deviceId: number, from: Date, to: Date) {
    const trips = await this.positionsService
      .getTripLog(deviceId, from, to)
      .catch(() => []);
    return { deviceId, from, to, trips };
  }

  async getVehicleSpeedViolations(
    deviceId: number,
    from: Date,
    to: Date,
    thresholdKmh = 120,
  ) {
    const violations = await this.positionsService
      .getSpeedViolations(deviceId, from, to, thresholdKmh)
      .catch(() => []);
    return { deviceId, from, to, thresholdKmh, violations };
  }

  async getVehicleIdleTime(deviceId: number, from: Date, to: Date) {
    const episodes = await this.positionsService
      .getIdleTime(deviceId, from, to)
      .catch(
        (): Awaited<ReturnType<typeof this.positionsService.getIdleTime>> => [],
      );
    const totalIdleMinutes = episodes.reduce((s, e) => s + e.durationMin, 0);
    return { deviceId, from, to, totalIdleMinutes, episodes };
  }

  async getVehicleGeofenceActivity(deviceId: number, from: Date, to: Date) {
    const geofences = await this.alertsService
      .getGeofenceActivity(deviceId, from, to)
      .catch(() => []);
    return { deviceId, from, to, geofences };
  }
}
