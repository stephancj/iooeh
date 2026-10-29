import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash, createHmac, randomBytes } from 'node:crypto';
import {
  DataSource,
  In,
  IsNull,
  LessThanOrEqual,
  MoreThan,
  Repository,
} from 'typeorm';
import { AlertsService } from '../alerts/alerts.service';
import { AlertType } from '../alerts/entities/alert.entity';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { NotificationsService } from '../notifications/notifications.service';
import { UsersService } from '../users/users.service';
import { VehiclesService } from '../vehicles/vehicles.service';
import { IncidentEvent } from './incident-event.entity';
import {
  IncidentStatus,
  IncidentType,
  SecurityIncident,
} from './incident.entity';
import { PublicTrackingLink } from './tracking-link.entity';

@Injectable()
export class SecurityService {
  constructor(
    @InjectRepository(SecurityIncident)
    private readonly incidentRepo: Repository<SecurityIncident>,
    @InjectRepository(IncidentEvent)
    private readonly eventRepo: Repository<IncidentEvent>,
    @InjectRepository(PublicTrackingLink)
    private readonly linkRepo: Repository<PublicTrackingLink>,
    private readonly vehicles: VehiclesService,
    private readonly alerts: AlertsService,
    private readonly users: UsersService,
    private readonly notifications: NotificationsService,
    private readonly entitlements: EntitlementsService,
    private readonly dataSource: DataSource,
  ) {}

  async createSos(ownerId: number, deviceId: number) {
    await this.entitlements.assertFeature(ownerId, 'sos_alerts', deviceId);
    return this.createCritical(
      ownerId,
      deviceId,
      IncidentType.SOS,
      'SOS déclenché',
      false,
    );
  }

  async declareTheft(ownerId: number, deviceId: number) {
    await this.entitlements.assertFeature(ownerId, 'theft_mode', deviceId);
    const existing = await this.incidentRepo.findOne({
      where: {
        ownerId,
        deviceId,
        type: IncidentType.THEFT,
        status: In([
          IncidentStatus.OPEN,
          IncidentStatus.ACKNOWLEDGED,
          IncidentStatus.IN_PROGRESS,
          IncidentStatus.ESCALATED,
        ]),
      },
    });
    if (existing)
      throw new BadRequestException(
        'Un dossier de vol est déjà actif pour ce véhicule.',
      );
    return this.createCritical(
      ownerId,
      deviceId,
      IncidentType.THEFT,
      'Véhicule déclaré volé',
      true,
    );
  }

  private async createCritical(
    ownerId: number,
    deviceId: number,
    type: IncidentType,
    title: string,
    cancellable: boolean,
    sourceEventId?: string,
  ) {
    await this.vehicles.assertOwner(deviceId, ownerId);
    const [position, vehicle, user] = await Promise.all([
      this.vehicles.getLastPosition(deviceId),
      this.vehicles.findOne(deviceId),
      this.users.findById(ownerId),
    ]);
    const alert = await this.alerts.createAlert(
      ownerId,
      deviceId,
      type === IncidentType.SOS ? AlertType.SOS : AlertType.THEFT,
      title,
      position?.lat,
      position?.lon,
    );
    const now = Date.now();
    const incident = await this.incidentRepo.save(
      this.incidentRepo.create({
        ownerId,
        deviceId,
        alertId: alert.id,
        sourceEventId: sourceEventId ?? null,
        type,
        status: IncidentStatus.OPEN,
        severity: 'critical',
        title,
        description: `${vehicle.name} · intervention requise`,
        lat: position?.lat ?? null,
        lon: position?.lon ?? null,
        cancelUntil: cancellable ? new Date(now + 60_000) : null,
        escalateAt: new Date(
          now + Number(process.env.INCIDENT_ESCALATION_MINUTES ?? 10) * 60_000,
        ),
      }),
    );
    await this.audit(incident.id, ownerId, 'created', title);
    if (user?.alertViaPush)
      await this.notifications.sendPush({
        externalUserId: String(ownerId),
        subscriptionId: user.onesignalSubId ?? undefined,
        title: '🚨 Alerte sécurité iooeh',
        body: `${title} — ${vehicle.name}`,
        data: { incidentId: incident.id, deviceId: String(deviceId) },
      });
    if (user?.alertViaWhatsapp && user.phone)
      await this.notifications.sendWhatsApp({
        phone: user.phone,
        vehicleName: vehicle.name,
        geofenceName: title,
        alertType: 'movement',
      });
    if (user?.alertViaEmail)
      await this.notifications.sendEmail({
        email: user.email,
        name: user.name ?? undefined,
        title: '🚨 Alerte sécurité iooeh',
        body: `${title} — ${vehicle.name}`,
        actionUrl: `${process.env.PUBLIC_APP_URL ?? 'https://app.iooeh.com'}/security/incidents/${incident.id}`,
      });
    return incident;
  }

  async listForUser(ownerId: number) {
    return this.incidentRepo.find({
      where: { ownerId },
      order: { createdAt: 'DESC' },
    });
  }
  async listAll() {
    return this.incidentRepo.find({ order: { createdAt: 'DESC' } });
  }
  async timeline(id: string, ownerId?: number) {
    if (ownerId) await this.getOwned(id, ownerId);
    return this.eventRepo.find({
      where: { incidentId: id },
      order: { createdAt: 'ASC' },
    });
  }
  private async getOwned(id: string, ownerId: number) {
    const incident = await this.incidentRepo.findOne({
      where: { id, ownerId },
    });
    if (!incident) throw new NotFoundException('Incident introuvable.');
    return incident;
  }
  async acknowledge(id: string, ownerId: number) {
    const incident = await this.getOwned(id, ownerId);
    if (incident.status !== IncidentStatus.OPEN) return incident;
    incident.status = IncidentStatus.ACKNOWLEDGED;
    incident.acknowledgedAt = new Date();
    await this.audit(id, ownerId, 'acknowledged');
    return this.incidentRepo.save(incident);
  }
  async cancelTheft(id: string, ownerId: number) {
    const incident = await this.getOwned(id, ownerId);
    if (
      incident.type !== IncidentType.THEFT ||
      !incident.cancelUntil ||
      incident.cancelUntil.getTime() < Date.now()
    )
      throw new ForbiddenException(
        'La fenêtre d’annulation de 60 secondes est terminée.',
      );
    incident.status = IncidentStatus.CANCELLED;
    incident.resolvedAt = new Date();
    await this.audit(
      id,
      ownerId,
      'cancelled',
      'Annulation dans la fenêtre de sécurité',
    );
    return this.incidentRepo.save(incident);
  }
  async updateByAdmin(
    id: string,
    status: IncidentStatus,
    note?: string,
    actorId?: number,
  ) {
    const incident = await this.incidentRepo.findOne({ where: { id } });
    if (!incident) throw new NotFoundException('Incident introuvable.');
    incident.status = status;
    if (status === IncidentStatus.ACKNOWLEDGED)
      incident.acknowledgedAt = new Date();
    if (
      [IncidentStatus.RESOLVED, IncidentStatus.FALSE_ALARM].includes(status)
    ) {
      incident.resolvedAt = new Date();
      incident.resolutionNote = note ?? null;
    }
    await this.audit(id, actorId ?? null, status, note);
    return this.incidentRepo.save(incident);
  }

  async createTrackingLink(
    ownerId: number,
    deviceId: number,
    durationMinutes: number,
  ) {
    await this.entitlements.assertFeature(ownerId, 'public_tracking_links', deviceId);
    await this.vehicles.assertOwner(deviceId, ownerId);
    const max = await this.entitlements.getNumber(
      ownerId,
      'max_active_tracking_links',
    );
    const active = await this.linkRepo.count({
      where: { ownerId, revokedAt: IsNull(), expiresAt: MoreThan(new Date()) },
    });
    if (active >= max)
      throw new ForbiddenException(`Limite de ${max} liens actifs atteinte.`);
    const token = randomBytes(32).toString('base64url');
    const link = await this.linkRepo.save(
      this.linkRepo.create({
        ownerId,
        deviceId,
        tokenHash: this.hash(token),
        expiresAt: new Date(Date.now() + durationMinutes * 60_000),
        revokedAt: null,
      }),
    );
    return {
      id: link.id,
      url: `${process.env.PUBLIC_APP_URL ?? 'https://app.iooeh.com'}/track/${token}`,
      expiresAt: link.expiresAt,
    };
  }
  async listLinks(ownerId: number, deviceId: number) {
    await this.vehicles.assertOwner(deviceId, ownerId);
    return this.linkRepo.find({
      where: { ownerId, deviceId },
      order: { createdAt: 'DESC' },
    });
  }
  async revokeLink(ownerId: number, id: string) {
    const link = await this.linkRepo.findOne({ where: { id, ownerId } });
    if (!link) throw new NotFoundException('Lien introuvable.');
    link.revokedAt = new Date();
    return this.linkRepo.save(link);
  }
  async resolvePublic(token: string) {
    const link = await this.linkRepo.findOne({
      where: { tokenHash: this.hash(token), revokedAt: IsNull() },
    });
    if (!link || link.expiresAt.getTime() <= Date.now())
      throw new NotFoundException('Ce lien est invalide ou expiré.');
    const vehicle = await this.vehicles.findOne(link.deviceId);
    link.viewCount += 1;
    link.lastViewedAt = new Date();
    await this.linkRepo.save(link);
    return {
      vehicle: {
        name: vehicle.name,
        plate: vehicle.plate,
        status: vehicle.status,
        position: vehicle.position,
      },
      expiresAt: link.expiresAt,
    };
  }
  private hash(value: string) {
    return createHash('sha256').update(value).digest('hex');
  }
  private audit(
    incidentId: string,
    actorId: number | null,
    action: string,
    note?: string,
  ) {
    return this.eventRepo.save(
      this.eventRepo.create({
        incidentId,
        actorId,
        action,
        note: note ?? null,
        metadata: null,
      }),
    );
  }

  @Cron('0 * * * * *')
  async escalateDue() {
    const due = await this.incidentRepo.find({
      where: {
        status: IncidentStatus.OPEN,
        escalateAt: LessThanOrEqual(new Date()),
      },
    });
    for (const incident of due) {
      if (
        !(await this.entitlements.hasFeature(
          incident.ownerId,
          'automatic_escalation',
          incident.deviceId,
        ))
      )
        continue;
      incident.status = IncidentStatus.ESCALATED;
      incident.escalatedAt = new Date();
      await this.incidentRepo.save(incident);
      await this.audit(
        incident.id,
        null,
        'escalated',
        'Délai sans réponse dépassé',
      );
      await this.notifyPartner(incident);
    }
  }

  @Cron('*/15 * * * * *')
  async ingestTraccarSos() {
    const rows = (await this.dataSource
      .query(
        `SELECT e.id::text, e.deviceid AS "deviceId", da.user_id AS "ownerId"
         FROM tc_events e
         JOIN device_assignments da ON da.device_id = e.deviceid
         WHERE e.eventtime >= NOW() - INTERVAL '2 minutes'
           AND e.type = 'alarm'
           AND COALESCE((e.attributes::jsonb ->> 'alarm'), '') = 'sos'
         ORDER BY e.id DESC LIMIT 100`,
      )
      .catch(() => [])) as Array<{
      id: string;
      deviceId: number;
      ownerId: number;
    }>;
    for (const row of rows) {
      const exists = await this.incidentRepo.findOne({
        where: { sourceEventId: row.id },
      });
      if (
        exists ||
        !(await this.entitlements.hasFeature(row.ownerId, 'sos_alerts', Number(row.deviceId)))
      )
        continue;
      await this.createCritical(
        row.ownerId,
        Number(row.deviceId),
        IncidentType.SOS,
        'SOS matériel déclenché',
        false,
        row.id,
      ).catch(() => undefined);
    }
  }

  private async notifyPartner(incident: SecurityIncident) {
    const url = process.env.SECURITY_PARTNER_WEBHOOK_URL;
    const secret = process.env.SECURITY_PARTNER_WEBHOOK_SECRET;
    if (!url || !secret) return;
    const body = JSON.stringify({
      event: 'incident.escalated',
      incident: {
        id: incident.id,
        type: incident.type,
        deviceId: incident.deviceId,
        lat: incident.lat,
        lon: incident.lon,
        createdAt: incident.createdAt,
      },
    });
    const signature = createHmac('sha256', secret).update(body).digest('hex');
    await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-iooeh-signature': signature,
      },
      body,
    }).catch(() => undefined);
  }
}
