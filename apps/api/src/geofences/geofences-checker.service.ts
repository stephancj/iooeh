import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import * as https from 'https';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { GeofencesService } from './geofences.service';
import { VehiclesService } from '../vehicles/vehicles.service';
import { AlertsService } from '../alerts/alerts.service';
import { NotificationsService } from '../notifications/notifications.service';
import { UsersService } from '../users/users.service';
import { AlertType } from '../alerts/entities/alert.entity';
import { DeviceAssignment } from '../admin/device-assignment.entity';
import { VehicleSleepMode } from '../vehicles/vehicle-sleep-mode.entity';
import { EntitlementsService } from '../entitlements/entitlements.service';

interface AlertSettings {
  alertsEnabled: boolean;
  alertSos: boolean;
  alertLowBattery: boolean;
  alertSpeedLimit: boolean;
  alertViaPush: boolean;
  alertViaWhatsapp: boolean;
  alertViaEmail: boolean;
}

@Injectable()
export class GeofencesCheckerService {
  private readonly logger = new Logger(GeofencesCheckerService.name);

  constructor(
    private readonly geofencesService: GeofencesService,
    private readonly vehiclesService: VehiclesService,
    private readonly alertsService: AlertsService,
    private readonly notificationsService: NotificationsService,
    private readonly usersService: UsersService,
    private readonly entitlementsService: EntitlementsService,
    @InjectRepository(DeviceAssignment)
    private readonly assignmentRepo: Repository<DeviceAssignment>,
    @InjectRepository(VehicleSleepMode)
    private readonly sleepModeRepo: Repository<VehicleSleepMode>,
  ) {}

  // Cache en mémoire pour éviter le spam et les requêtes DB.
  // Clé: "{vehicleId}_{geofenceId}", Valeur: boolean (true = inside)
  private readonly insideGeofencesCache = new Map<string, boolean>();

  // Cache du subscription ID OneSignal par userId (TTL: 60s)
  private readonly subIdCache = new Map<number, string | null>();
  private readonly subIdCacheTs = new Map<number, number>();

  // Cache du numéro de téléphone par userId (TTL: 60s)
  private readonly phoneCache = new Map<number, string | null>();
  private readonly phoneCacheTs = new Map<number, number>();

  // Cache des paramètres d'alerte par userId (TTL: 60s)
  private readonly alertSettingsCache = new Map<number, AlertSettings>();
  private readonly alertSettingsCacheTs = new Map<number, number>();
  private readonly SETTINGS_CACHE_TTL_MS = 60_000;

  @Cron('*/15 * * * * *')
  async checkGeofences() {
    this.logger.debug('Vérification des Geofences en cours...');
    try {
      const vehicles = await this.vehiclesService.findAll();
      const allGeofences = await this.geofencesService.findAllActive();

      for (const vehicle of vehicles) {
        if (!vehicle.position || vehicle.status === 'offline') continue;

        for (const fence of allGeofences) {
          if (
            fence.deviceIds &&
            fence.deviceIds.length > 0 &&
            !fence.deviceIds.includes(vehicle.id)
          ) {
            continue;
          }

          // Alert settings belong to the fence owner, not the vehicle
          const userAlertSettings = await this.getUserAlertSettings(
            fence.userId,
          );
          if (!userAlertSettings.alertsEnabled) continue;
          if (
            !(await this.entitlementsService.hasFeature(
              fence.userId,
              'geofence_alerts',
              vehicle.id,
            ))
          )
            continue;

          const distanceM = this.getDistanceFromLatLonInM(
            vehicle.position.lat,
            vehicle.position.lon,
            fence.centerLat,
            fence.centerLon,
          );

          const isInside = distanceM <= fence.radiusM;
          const cacheKey = `${vehicle.id}_${fence.id}`;
          const wasInside = this.insideGeofencesCache.get(cacheKey) ?? false;

          if (isInside && !wasInside) {
            this.insideGeofencesCache.set(cacheKey, true);

            if (!fence.alertOnEntry) continue;

            this.logger.log(`🚗 ${vehicle.name} ENTERED ${fence.name}`);

            await this.alertsService.createAlert(
              fence.userId,
              vehicle.id,
              AlertType.GEOFENCE_ENTER,
              `${vehicle.name} est entré dans la zone ${fence.name}`,
              vehicle.position.lat,
              vehicle.position.lon,
            );

            if (
              userAlertSettings.alertViaPush &&
              (await this.entitlementsService.hasFeature(
                fence.userId,
                'push_notifications',
                vehicle.id,
              ))
            ) {
              const subscriptionId = await this.getUserSubId(fence.userId);
              await this.notificationsService.sendPush({
                externalUserId: fence.userId.toString(),
                subscriptionId: subscriptionId ?? undefined,
                title: '🟢 Entrée de zone',
                body: `${vehicle.name} est entré dans la zone "${fence.name}"`,
                data: {
                  type: 'geofence_enter',
                  vehicleId: vehicle.id.toString(),
                  geofenceName: fence.name,
                },
              });
            }

            if (
              fence.alertViaWhatsapp &&
              userAlertSettings.alertViaWhatsapp &&
              (await this.entitlementsService.hasFeature(
                fence.userId,
                'whatsapp_notifications',
                vehicle.id,
              ))
            ) {
              await this.sendWhatsAppIfEnabled(
                fence.userId,
                vehicle.name,
                fence.name,
                'enter',
              );
            }

            if (userAlertSettings.alertViaEmail) {
              await this.sendEmailIfEnabled(
                fence.userId,
                '🟢 Entrée de zone',
                `${vehicle.name} est entré dans la zone "${fence.name}".`,
                vehicle.id,
              );
            }
          } else if (!isInside && wasInside) {
            this.insideGeofencesCache.set(cacheKey, false);

            if (!fence.alertOnExit) continue;

            this.logger.log(`🚗 ${vehicle.name} EXITED ${fence.name}`);

            await this.alertsService.createAlert(
              fence.userId,
              vehicle.id,
              AlertType.GEOFENCE_EXIT,
              `${vehicle.name} a quitté la zone ${fence.name}`,
              vehicle.position.lat,
              vehicle.position.lon,
            );

            if (
              userAlertSettings.alertViaPush &&
              (await this.entitlementsService.hasFeature(
                fence.userId,
                'push_notifications',
                vehicle.id,
              ))
            ) {
              const subscriptionId = await this.getUserSubId(fence.userId);
              await this.notificationsService.sendPush({
                externalUserId: fence.userId.toString(),
                subscriptionId: subscriptionId ?? undefined,
                title: '🔴 Sortie de zone',
                body: `${vehicle.name} a quitté la zone "${fence.name}"`,
                data: {
                  type: 'geofence_exit',
                  vehicleId: vehicle.id.toString(),
                  geofenceName: fence.name,
                },
              });
            }

            if (
              fence.alertViaWhatsapp &&
              userAlertSettings.alertViaWhatsapp &&
              (await this.entitlementsService.hasFeature(
                fence.userId,
                'whatsapp_notifications',
                vehicle.id,
              ))
            ) {
              await this.sendWhatsAppIfEnabled(
                fence.userId,
                vehicle.name,
                fence.name,
                'exit',
              );
            }

            if (userAlertSettings.alertViaEmail) {
              await this.sendEmailIfEnabled(
                fence.userId,
                '🔴 Sortie de zone',
                `${vehicle.name} a quitté la zone "${fence.name}".`,
                vehicle.id,
              );
            }
          }
        }
      }
    } catch (e) {
      this.logger.error('Erreur lors du check geofences', e);
    }
  }

  // Cache pour éviter le spam d'alertes (clé: vehicleId_alertType)
  private readonly lastAlertCache = new Map<string, Date>();

  // Suit l'épisode d'excès en cours par véhicule. `alertId` = l'UNE alerte
  // créée pour cet épisode (mise à jour au lieu d'en recréer une à chaque tick).
  private readonly speedExcessStartCache = new Map<
    number,
    {
      startTime: Date;
      lat: number;
      lon: number;
      maxSpeed: number;
      alertId: string | null;
    }
  >();

  // Seuil d'excès de vitesse (km/h) — au-delà, une alerte est générée.
  private readonly SPEED_LIMIT_KMH = 120;

  // Anti-spam des alertes batterie : on n'en ré-émet pas une avant ce délai
  // (le cron tourne toutes les 30 s ; sans ça la batterie faible spammait).
  private readonly ALERT_THROTTLE_MS = 30 * 60 * 1000; // 30 min

  /**
   * Veille antivol : une alerte unique dès que le véhicule quitte le rayon
   * d'armement. L'état reste déclenché jusqu'au désarmement par l'utilisateur.
   */
  @Cron('*/15 * * * * *')
  async checkSleepModes() {
    try {
      const modes = await this.sleepModeRepo.find({ where: { active: true } });
      if (modes.length === 0) return;

      const vehicles = await this.vehiclesService.findAll();
      const vehicleMap = new Map(
        vehicles.map((vehicle) => [vehicle.id, vehicle]),
      );

      for (const mode of modes) {
        if (mode.triggeredAt) continue;
        if (
          !(await this.entitlementsService.hasFeature(
            mode.ownerId,
            'sleep_mode',
            mode.deviceId,
          ))
        )
          continue;
        const vehicle = vehicleMap.get(mode.deviceId);
        if (!vehicle?.position || vehicle.status === 'offline') continue;

        const distanceM = this.getDistanceFromLatLonInM(
          mode.armedLat,
          mode.armedLon,
          vehicle.position.lat,
          vehicle.position.lon,
        );
        mode.lastDistanceM = Math.round(distanceM);

        if (distanceM < mode.movementThresholdM) {
          await this.sleepModeRepo.save(mode);
          continue;
        }

        mode.triggeredAt = new Date();
        await this.sleepModeRepo.save(mode);

        const message = `Mouvement détecté à ${Math.round(distanceM)} m du point de veille`;
        await this.alertsService.createAlert(
          mode.ownerId,
          mode.deviceId,
          AlertType.SLEEP_MOVEMENT,
          message,
          vehicle.position.lat,
          vehicle.position.lon,
        );

        const settings = await this.getUserAlertSettings(mode.ownerId);
        await this.notifyAlert(
          mode.ownerId,
          mode.deviceId,
          vehicle.name,
          AlertType.SLEEP_MOVEMENT,
          message,
          settings,
        );
        this.logger.warn(`VEILLE DÉCLENCHÉE ${vehicle.name}: ${message}`);
      }
    } catch (e) {
      this.logger.error('Erreur lors du check des modes veille', e);
    }
  }

  @Cron('*/30 * * * * *')
  async checkVehicleAlerts() {
    this.logger.debug('Vérification des alertes véhicule...');
    try {
      const vehicles = await this.vehiclesService.findAll();

      // Build deviceId → userId map from assignments table
      const assignments = await this.assignmentRepo.find();
      const deviceUserMap = new Map(
        assignments.map((a) => [a.deviceId, a.userId]),
      );

      for (const vehicle of vehicles) {
        if (!vehicle.position || vehicle.status === 'offline') continue;

        const userId = deviceUserMap.get(vehicle.id);
        if (!userId) continue;

        const userAlertSettings = await this.getUserAlertSettings(userId);
        if (!userAlertSettings.alertsEnabled) continue;

        // Low Battery Alert
        if (
          userAlertSettings.alertLowBattery &&
          (await this.entitlementsService.hasFeature(
            userId,
            'low_battery_alerts',
            vehicle.id,
          )) &&
          vehicle.position.battery != null &&
          vehicle.position.battery < 20
        ) {
          await this.sendAlertIfNotSpammed(
            userId,
            vehicle.id,
            vehicle.name,
            AlertType.LOW_BATTERY,
            `Batterie faible: ${vehicle.position.battery}%`,
            userAlertSettings,
            vehicle.position.lat,
            vehicle.position.lon,
          );
        }

        // Excès de vitesse — UNE alerte par épisode, mise à jour au fil du temps
        const speedKmh = vehicle.position.speedKmh;
        if (
          userAlertSettings.alertSpeedLimit &&
          (await this.entitlementsService.hasFeature(userId, 'speed_alerts', vehicle.id)) &&
          speedKmh != null
        ) {
          if (speedKmh > this.SPEED_LIMIT_KMH) {
            const existing = this.speedExcessStartCache.get(vehicle.id);
            if (!existing) {
              // Début d'un nouvel épisode
              this.speedExcessStartCache.set(vehicle.id, {
                startTime: new Date(),
                lat: vehicle.position.lat,
                lon: vehicle.position.lon,
                maxSpeed: speedKmh,
                alertId: null,
              });
            } else if (speedKmh > existing.maxSpeed) {
              existing.maxSpeed = speedKmh; // suit le pic
            }

            const excess = this.speedExcessStartCache.get(vehicle.id)!;
            const message = await this.buildSpeedMessage(excess);

            if (excess.alertId == null) {
              // Première détection → UNE alerte + notification (une seule fois)
              const alert = await this.alertsService.createAlert(
                userId,
                vehicle.id,
                AlertType.SPEED_LIMIT,
                message,
                excess.lat,
                excess.lon,
              );
              excess.alertId = alert.id;
              this.logger.log(`🚨 ${vehicle.name} SPEED_LIMIT: ${message}`);
              await this.notifyAlert(
                userId,
                vehicle.id,
                vehicle.name,
                AlertType.SPEED_LIMIT,
                message,
                userAlertSettings,
              );
            } else {
              // Épisode en cours → on met à jour l'alerte existante (pic/durée)
              await this.alertsService.updateAlertMessage(
                excess.alertId,
                message,
              );
            }
          } else {
            // Retour sous la limite → mise à jour finale puis reset de l'épisode
            const excess = this.speedExcessStartCache.get(vehicle.id);
            if (excess?.alertId) {
              await this.alertsService.updateAlertMessage(
                excess.alertId,
                await this.buildSpeedMessage(excess),
              );
            }
            this.speedExcessStartCache.delete(vehicle.id);
          }
        }
      }
    } catch (e) {
      this.logger.error('Erreur lors du check alerts véhicule', e);
    }
  }

  /** Message épuré d'un excès : pic, limite, lieu, et durée si ≥ 1 min. */
  private async buildSpeedMessage(excess: {
    startTime: Date;
    lat: number;
    lon: number;
    maxSpeed: number;
  }): Promise<string> {
    const durationMs = Date.now() - excess.startTime.getTime();
    const sustained = durationMs >= 60_000;
    const peakKmh = Math.round(excess.maxSpeed);
    const location = await this.reverseGeocode(excess.lat, excess.lon);
    let message = `${peakKmh} km/h (limite ${this.SPEED_LIMIT_KMH} km/h)`;
    if (location) message += ` · ${location}`;
    if (sustained) message += ` · sur ${this.formatDuration(durationMs)}`;
    return message;
  }

  private formatDuration(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    if (minutes === 0) return `${seconds}s`;
    if (seconds === 0) return `${minutes}min`;
    return `${minutes}min ${seconds}s`;
  }

  private async sendAlertIfNotSpammed(
    userId: number,
    vehicleId: number,
    vehicleName: string,
    alertType: AlertType,
    message: string,
    settings: AlertSettings,
    lat?: number,
    lon?: number,
  ): Promise<void> {
    const cacheKey = `${vehicleId}_${alertType}`;
    const lastAlert = this.lastAlertCache.get(cacheKey);

    if (
      lastAlert &&
      Date.now() - lastAlert.getTime() < this.ALERT_THROTTLE_MS
    ) {
      return;
    }

    this.lastAlertCache.set(cacheKey, new Date());
    this.logger.log(`🚨 ${vehicleName} ${alertType}: ${message}`);

    await this.alertsService.createAlert(
      userId,
      vehicleId,
      alertType,
      message,
      lat,
      lon,
    );
    await this.notifyAlert(
      userId,
      vehicleId,
      vehicleName,
      alertType,
      message,
      settings,
    );
  }

  /** Notifications (push + WhatsApp) d'une alerte, sans la créer en base. */
  private async notifyAlert(
    userId: number,
    vehicleId: number,
    vehicleName: string,
    alertType: AlertType,
    message: string,
    settings: AlertSettings,
  ): Promise<void> {
    if (
      settings.alertViaPush &&
      (await this.entitlementsService.hasFeature(userId, 'push_notifications', vehicleId))
    ) {
      const subscriptionId = await this.getUserSubId(userId);
      const title =
        alertType === AlertType.LOW_BATTERY
          ? '🔋 Batterie faible'
          : alertType === AlertType.SLEEP_MOVEMENT
            ? '🚨 Mouvement en mode veille'
            : '⚡ Excès de vitesse';
      // Préfixe le nom du véhicule : le push n'a pas de puce véhicule comme l'in-app.
      const pushBody = `${vehicleName} • ${message}`;
      await this.notificationsService.sendPush({
        externalUserId: userId.toString(),
        subscriptionId: subscriptionId ?? undefined,
        title,
        body: pushBody,
        data: {
          type: alertType,
          vehicleId: vehicleId.toString(),
        },
      });
    }

    if (
      settings.alertViaWhatsapp &&
      (await this.entitlementsService.hasFeature(
        userId,
        'whatsapp_notifications',
        vehicleId,
      ))
    ) {
      await this.sendWhatsAppIfEnabled(
        userId,
        vehicleName,
        message,
        alertType === AlertType.SLEEP_MOVEMENT
          ? 'movement'
          : alertType === AlertType.LOW_BATTERY
            ? 'enter'
            : 'exit',
      );
    }

    if (settings.alertViaEmail) {
      const title =
        alertType === AlertType.LOW_BATTERY
          ? '🔋 Batterie faible'
          : alertType === AlertType.SLEEP_MOVEMENT
            ? '🚨 Mouvement en mode veille'
            : '⚡ Excès de vitesse';
      await this.sendEmailIfEnabled(
        userId,
        title,
        `${vehicleName} • ${message}`,
        vehicleId,
      );
    }
  }

  /**
   * Retourne le subscription ID OneSignal de l'utilisateur.
   * Met en cache le résultat pour éviter les requêtes DB répétitives.
   */
  private async getUserSubId(userId: number): Promise<string | null> {
    const cachedTs = this.subIdCacheTs.get(userId) ?? 0;
    if (
      this.subIdCache.has(userId) &&
      Date.now() - cachedTs < this.SETTINGS_CACHE_TTL_MS
    ) {
      return this.subIdCache.get(userId) ?? null;
    }
    const user = await this.usersService.findById(userId);
    const subId = user?.onesignalSubId ?? null;
    this.subIdCache.set(userId, subId);
    this.subIdCacheTs.set(userId, Date.now());
    return subId;
  }

  /**
   * Retourne le numéro de téléphone de l'utilisateur.
   * Met en cache le résultat pour éviter les requêtes DB répétitives.
   */
  private async getUserPhone(userId: number): Promise<string | null> {
    const cachedTs = this.phoneCacheTs.get(userId) ?? 0;
    if (
      this.phoneCache.has(userId) &&
      Date.now() - cachedTs < this.SETTINGS_CACHE_TTL_MS
    ) {
      return this.phoneCache.get(userId) ?? null;
    }
    const user = await this.usersService.findById(userId);
    const phone = user?.phone ?? null;
    this.phoneCache.set(userId, phone);
    this.phoneCacheTs.set(userId, Date.now());
    return phone;
  }

  /**
   * Retourne les paramètres d'alerte de l'utilisateur.
   * Met en cache le résultat pour éviter les requêtes DB répétitives.
   */
  private async getUserAlertSettings(userId: number): Promise<AlertSettings> {
    const cachedTs = this.alertSettingsCacheTs.get(userId) ?? 0;
    if (
      this.alertSettingsCache.has(userId) &&
      Date.now() - cachedTs < this.SETTINGS_CACHE_TTL_MS
    ) {
      return this.alertSettingsCache.get(userId)!;
    }
    const user = await this.usersService.findById(userId);
    const settings: AlertSettings = {
      alertsEnabled: user?.alertsEnabled ?? true,
      alertSos: user?.alertSos ?? true,
      alertLowBattery: user?.alertLowBattery ?? true,
      alertSpeedLimit: user?.alertSpeedLimit ?? false,
      alertViaPush: user?.alertViaPush ?? true,
      alertViaWhatsapp: user?.alertViaWhatsapp ?? false,
      alertViaEmail: user?.alertViaEmail ?? false,
    };
    this.alertSettingsCache.set(userId, settings);
    this.alertSettingsCacheTs.set(userId, Date.now());
    return settings;
  }

  /**
   * Envoie une notification WhatsApp si l'utilisateur a un numéro de téléphone configuré.
   */
  private async sendWhatsAppIfEnabled(
    userId: number,
    vehicleName: string,
    alertMessage: string,
    alertType: 'enter' | 'exit' | 'movement',
  ): Promise<void> {
    const phone = await this.getUserPhone(userId);
    if (!phone) {
      this.logger.warn(
        `User ${userId} n'a pas de numéro de téléphone pour WhatsApp`,
      );
      return;
    }
    await this.notificationsService.sendWhatsApp({
      phone,
      vehicleName,
      geofenceName: alertMessage,
      alertType,
    });
  }

  private async sendEmailIfEnabled(
    userId: number,
    title: string,
    body: string,
    vehicleId: number,
  ): Promise<void> {
    const user = await this.usersService.findById(userId);
    if (!user?.email) return;

    await this.notificationsService.sendEmail({
      email: user.email,
      name: user.name ?? undefined,
      title,
      body,
      actionUrl: `${process.env.PUBLIC_APP_URL ?? 'https://app.iooeh.com'}/vehicles/${vehicleId}`,
    });
  }

  // Reverse geocoding cache: "lat,lon" (1 decimal) → address string
  private readonly geocodeCache = new Map<string, string>();

  private async reverseGeocode(lat: number, lon: number): Promise<string> {
    // Round to ~11km grid to maximize cache hits for nearby points
    const key = `${lat.toFixed(1)},${lon.toFixed(1)}`;
    if (this.geocodeCache.has(key)) return this.geocodeCache.get(key)!;

    try {
      const address = await new Promise<string>((resolve) => {
        const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&zoom=16`;
        https
          .get(url, { headers: { 'User-Agent': 'iooeh/1.0' } }, (res) => {
            let data = '';
            res.on('data', (chunk) => (data += chunk));
            res.on('end', () => {
              try {
                const parsed: unknown = JSON.parse(data);
                const json =
                  typeof parsed === 'object' && parsed !== null
                    ? (parsed as Record<string, unknown>)
                    : {};
                const rawAddress = json.address;
                const a =
                  typeof rawAddress === 'object' && rawAddress !== null
                    ? (rawAddress as Record<string, unknown>)
                    : {};
                const parts = [
                  a.road ?? a.pedestrian ?? a.path,
                  a.suburb ?? a.neighbourhood ?? a.village ?? a.town ?? a.city,
                ].filter((part): part is string => typeof part === 'string');
                const displayName =
                  typeof json.display_name === 'string'
                    ? json.display_name
                    : undefined;
                resolve(
                  parts.length > 0
                    ? parts.join(', ')
                    : (displayName?.split(',')[0] ??
                        `${lat.toFixed(4)},${lon.toFixed(4)}`),
                );
              } catch {
                resolve(`${lat.toFixed(4)},${lon.toFixed(4)}`);
              }
            });
          })
          .on('error', () => resolve(`${lat.toFixed(4)},${lon.toFixed(4)}`));
      });
      this.geocodeCache.set(key, address);
      return address;
    } catch {
      return `${lat.toFixed(4)},${lon.toFixed(4)}`;
    }
  }

  private getDistanceFromLatLonInM(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
  ) {
    const R = 6371e3;
    const dLat = this.deg2rad(lat2 - lat1);
    const dLon = this.deg2rad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(this.deg2rad(lat1)) *
        Math.cos(this.deg2rad(lat2)) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  private deg2rad(deg: number) {
    return deg * (Math.PI / 180);
  }
}
