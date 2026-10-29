import {
  Controller,
  Get,
  Post,
  Delete,
  Patch,
  Body,
  Param,
  Query,
  ParseIntPipe,
  UseGuards,
  BadRequestException,
  NotFoundException,
  Request,
} from '@nestjs/common';
import { VehiclesService } from './vehicles.service';
import { PositionsService } from '../positions/positions.service';
import { AlertsService } from '../alerts/alerts.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Device } from '../devices/device.entity';
import { ClaimVehicleDto } from './dto/claim-vehicle.dto';
import { EntitlementsService } from '../entitlements/entitlements.service';

@Controller('vehicles')
@UseGuards(JwtAuthGuard)
export class VehiclesController {
  constructor(
    private readonly vehiclesService: VehiclesService,
    private readonly positionsService: PositionsService,
    private readonly alertsService: AlertsService,
    private readonly entitlementsService: EntitlementsService,
  ) {}

  /**
   * GET /api/vehicles
   * Retourne uniquement les véhicules assignés à l'utilisateur connecté.
   */
  @Get()
  async findAll(@Request() req: { user: { id: number } }) {
    const vehicles = await this.vehiclesService.findAllForUser(req.user.id);
    return Promise.all(vehicles.map(async (vehicle) => {
      const allowed = await this.entitlementsService.hasFeature(req.user.id, 'live_tracking', vehicle.id);
      return allowed ? vehicle : { ...vehicle, position: null, sleepMode: null };
    }));
  }

  /** POST /api/vehicles/claim — associe un device via IMEI / numéro de série. */
  @Post('claim')
  claimVehicle(
    @Body() dto: ClaimVehicleDto,
    @Request() req: { user: { id: number } },
  ) {
    return this.vehiclesService.claimVehicle(req.user.id, dto);
  }

  @Get('subscriptions')
  async subscriptions(@Request() req: { user: { id: number } }) {
    const vehicles = await this.vehiclesService.findAllForUser(req.user.id);
    return Promise.all(vehicles.map(async (vehicle) => ({
      vehicle: { id: vehicle.id, name: vehicle.name, plate: vehicle.plate, serialNumber: vehicle.serialNumber },
      entitlements: await this.entitlementsService.getForVehicle(req.user.id, vehicle.id),
    })));
  }

  /**
   * GET /api/vehicles/:id
   * Détails complets d'un seul véhicule — vérifie que le device appartient à l'user.
   */
  @Get(':id')
  async findOne(
    @Param('id', ParseIntPipe) id: number,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(req.user.id, 'live_tracking', id);
    await this.vehiclesService.assertOwner(id, req.user.id);
    return this.vehiclesService.findOne(id);
  }

  /**
   * PATCH /api/vehicles/:id
   * Mise à jour des informations d'un véhicule — vérifie ownership.
   */
  @Patch(':id')
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() data: Partial<Device>,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(req.user.id, 'live_tracking', id);
    await this.vehiclesService.assertOwner(id, req.user.id);
    return this.vehiclesService.update(id, data);
  }

  /** POST /api/vehicles/:id/sleep-mode — arme la veille antivol. */
  @Post(':id/sleep-mode')
  async enableSleepMode(
    @Param('id', ParseIntPipe) id: number,
    @Request() req: { user: { id: number } },
  ) {
    await this.vehiclesService.assertOwner(id, req.user.id);
    return this.vehiclesService.enableSleepMode(id, req.user.id);
  }

  /** DELETE /api/vehicles/:id/sleep-mode — désarme la veille antivol. */
  @Delete(':id/sleep-mode')
  async disableSleepMode(
    @Param('id', ParseIntPipe) id: number,
    @Request() req: { user: { id: number } },
  ) {
    await this.vehiclesService.assertOwner(id, req.user.id);
    await this.vehiclesService.disableSleepMode(id, req.user.id);
    return { active: false };
  }

  /**
   * GET /api/vehicles/:id/position
   * Dernière position — endpoint de polling Flutter (toutes les 10s).
   */
  @Get(':id/position')
  async getLastPosition(
    @Param('id', ParseIntPipe) id: number,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(req.user.id, 'live_tracking', id);
    await this.vehiclesService.assertOwner(id, req.user.id);
    const position = await this.vehiclesService.getLastPosition(id);
    if (!position) {
      throw new NotFoundException(
        `Aucune position trouvée pour le véhicule #${id}`,
      );
    }
    return position;
  }

  // ── Reports ──────────────────────────────────────────────────────────────

  private periodToDates(period: string): { from: Date; to: Date } {
    const now = new Date();
    let from: Date;
    if (period === 'today') {
      from = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    } else if (period === '30d') {
      from = new Date(now.getTime() - 30 * 24 * 3600 * 1000);
    } else {
      from = new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    }
    return { from, to: now };
  }

  /**
   * GET /api/vehicles/:id/reports/activity?period=today|7d|30d
   * Résumé activité : distance, trajets, idle, vitesse max, violations.
   */
  @Get(':id/reports/activity')
  async getActivitySummary(
    @Param('id', ParseIntPipe) id: number,
    @Query('period') period = '7d',
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(
      req.user.id,
      'activity_reports',
      id,
    );
    await this.vehiclesService.assertOwner(id, req.user.id);
    const { from, to } = this.periodToDates(period);
    const summary = await this.positionsService
      .getActivitySummary(id, from, to)
      .catch(() => ({
        distanceKm: 0,
        drivingMinutes: 0,
        idleMinutes: 0,
        maxSpeedKmh: 0,
        tripCount: 0,
        speedViolationCount: 0,
        pointCount: 0,
      }));
    return { deviceId: id, period, from, to, ...summary };
  }

  /**
   * GET /api/vehicles/:id/reports/trip-log?from=ISO&to=ISO
   * Trajets reconstitués (segmentation gap > 10 min).
   */
  @Get(':id/reports/trip-log')
  async getTripLog(
    @Param('id', ParseIntPipe) id: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(req.user.id, 'trip_reports', id);
    await this.vehiclesService.assertOwner(id, req.user.id);
    const now = new Date();
    const fromDate = from
      ? new Date(from)
      : new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    const toDate = to ? new Date(to) : now;
    const trips = await this.positionsService
      .getTripLog(id, fromDate, toDate)
      .catch(() => []);
    return { deviceId: id, from: fromDate, to: toDate, trips };
  }

  /**
   * GET /api/vehicles/:id/reports/speed-violations?from=ISO&to=ISO&threshold=120
   * Épisodes de vitesse excessive.
   */
  @Get(':id/reports/speed-violations')
  async getSpeedViolations(
    @Param('id', ParseIntPipe) id: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Query('threshold') threshold: string | undefined,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(req.user.id, 'speed_reports', id);
    await this.vehiclesService.assertOwner(id, req.user.id);
    const now = new Date();
    const fromDate = from
      ? new Date(from)
      : new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    const toDate = to ? new Date(to) : now;
    const thresholdKmh = threshold ? parseInt(threshold, 10) : 120;
    const violations = await this.positionsService
      .getSpeedViolations(id, fromDate, toDate, thresholdKmh)
      .catch(() => []);
    return {
      deviceId: id,
      from: fromDate,
      to: toDate,
      thresholdKmh,
      violations,
    };
  }

  /**
   * GET /api/vehicles/:id/reports/idle?from=ISO&to=ISO
   * Épisodes d'immobilisation prolongée.
   */
  @Get(':id/reports/idle')
  async getIdleTime(
    @Param('id', ParseIntPipe) id: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(req.user.id, 'idle_reports', id);
    await this.vehiclesService.assertOwner(id, req.user.id);
    const now = new Date();
    const fromDate = from
      ? new Date(from)
      : new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    const toDate = to ? new Date(to) : now;
    const episodes = await this.positionsService
      .getIdleTime(id, fromDate, toDate)
      .catch(
        (): Awaited<ReturnType<typeof this.positionsService.getIdleTime>> => [],
      );
    const totalIdleMinutes = episodes.reduce((s, e) => s + e.durationMin, 0);
    return {
      deviceId: id,
      from: fromDate,
      to: toDate,
      totalIdleMinutes,
      episodes,
    };
  }

  /**
   * GET /api/vehicles/:id/reports/geofence-activity?period=today|7d|30d
   * Activité geofence : entrées/sorties par zone sur la période.
   */
  @Get(':id/reports/geofence-activity')
  async getGeofenceActivity(
    @Param('id', ParseIntPipe) id: number,
    @Query('period') period = '7d',
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(
      req.user.id,
      'geofence_reports',
      id,
    );
    await this.vehiclesService.assertOwner(id, req.user.id);
    const { from, to } = this.periodToDates(period);
    const geofences = await this.alertsService
      .getGeofenceActivity(id, from, to)
      .catch(() => []);
    return { deviceId: id, period, from, to, geofences };
  }

  // ── History ───────────────────────────────────────────────────────────────

  /**
   * GET /api/vehicles/:id/history/active-days?from=ISO&to=ISO
   * Activité jour par jour (distance + nb points) pour le calendrier d'activité.
   * Permet à l'utilisateur de voir quels jours ont eu du mouvement avant de
   * choisir une date. Défaut : 31 derniers jours.
   */
  @Get(':id/history/active-days')
  async getActiveDays(
    @Param('id', ParseIntPipe) id: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlementsService.assertFeature(req.user.id, 'history', id);
    await this.vehiclesService.assertOwner(id, req.user.id);
    const now = new Date();
    const requestedFrom = from
      ? new Date(from)
      : new Date(now.getTime() - 31 * 24 * 3600 * 1000);
    const toDate = to ? new Date(to) : now;
    if (isNaN(requestedFrom.getTime()) || isNaN(toDate.getTime())) {
      throw new BadRequestException(
        'Format de date invalide — utiliser ISO 8601',
      );
    }
    const retentionDays = await this.entitlementsService.getNumber(
      req.user.id,
      'history_retention_days',
      id,
    );
    const earliest = new Date(Date.now() - retentionDays * 24 * 3600 * 1000);
    const fromDate = requestedFrom < earliest ? earliest : requestedFrom;
    const days = await this.positionsService
      .getActiveDays(id, fromDate, toDate)
      .catch(() => []);
    return { deviceId: id, from: fromDate, to: toDate, days };
  }

  /**
   * GET /api/vehicles/:id/history?from=ISO&to=ISO&limit=1000
   * Historique des positions pour tracer le trajet (polyligne Flutter).
   */
  @Get(':id/history')
  async getHistory(
    @Param('id', ParseIntPipe) id: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Query('limit') limit: string | undefined,
    @Request() req: { user: { id: number } },
  ) {
    await this.vehiclesService.assertOwner(id, req.user.id);

    if (!from || !to) {
      throw new BadRequestException(
        'Les paramètres "from" et "to" sont requis (ISO 8601)',
      );
    }

    const fromDate = new Date(from);
    const toDate = new Date(to);

    if (isNaN(fromDate.getTime()) || isNaN(toDate.getTime())) {
      throw new BadRequestException(
        'Format de date invalide — utiliser ISO 8601 (ex: 2024-01-01T00:00:00Z)',
      );
    }

    if (fromDate >= toDate) {
      throw new BadRequestException('"from" doit être antérieur à "to"');
    }

    await this.entitlementsService.assertFeature(req.user.id, 'history', id);
    await this.entitlementsService.assertHistoryRange(req.user.id, fromDate, id);

    const limitNum = limit ? Math.min(parseInt(limit, 10), 5000) : 1000;

    return this.positionsService.getHistory(id, fromDate, toDate, limitNum);
  }
}
