import {
  Controller,
  Get,
  Post,
  Patch,
  Put,
  Delete,
  Param,
  Body,
  Query,
  UseGuards,
  ParseIntPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { AdminService } from './admin.service';
import {
  CreateFeatureDto,
  CreatePlanDto,
  CreateUserDto,
  ReplacePlanFeaturesDto,
  UpdateFeatureDto,
  UpdatePlanDto,
  UpdateSubscriptionDto,
  UpdateUserDto,
} from './admin.dto';

/**
 * Routes admin — accessibles uniquement aux users avec role = 'admin'.
 * Toutes les routes sont protégées par JwtAuthGuard + RolesGuard.
 *
 *   GET    /api/admin/users
 *   POST   /api/admin/users
 *   PATCH  /api/admin/users/:id
 *   DELETE /api/admin/users/:id        (désactivation)
 *   GET    /api/admin/vehicles
 *   POST   /api/admin/devices/:deviceId/assign/:userId
 *   DELETE /api/admin/devices/:deviceId/assign
 *   GET    /api/admin/geofences
 *   DELETE /api/admin/geofences/:id
 *   GET    /api/admin/alerts
 *   PATCH  /api/admin/alerts/:id       (ack)
 */
import { PaymentsService } from '../payments/payments.service';

@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('admin')
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly paymentsService: PaymentsService,
  ) {}

  @Get('payments')
  listPayments(
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = page ? parseInt(page, 10) : 1;
    const l = limit ? parseInt(limit, 10) : 50;
    return this.paymentsService.listAdminPayments(p, l);
  }

  // ── System Config ────────────────────────────────────────────────────────

  @Get('config')
  getConfig() {
    return this.adminService.getConfig();
  }

  @Patch('config')
  updateConfig(@Body() body: { key: string; value: any }) {
    return this.adminService.updateConfig(body.key, body.value);
  }

  // ── Commercial catalogue ────────────────────────────────────────────────

  @Get('features')
  listFeatures() {
    return this.adminService.listFeatures();
  }

  @Post('features')
  createFeature(@Body() body: CreateFeatureDto) {
    return this.adminService.createFeature(body);
  }

  @Patch('features/:id')
  updateFeature(@Param('id') id: string, @Body() body: UpdateFeatureDto) {
    return this.adminService.updateFeature(id, body);
  }

  @Delete('features/:id')
  deactivateFeature(@Param('id') id: string) {
    return this.adminService.deactivateFeature(id);
  }

  @Get('plans')
  listPlans() {
    return this.adminService.listPlans();
  }

  @Get('plans/:id')
  getPlan(@Param('id') id: string) {
    return this.adminService.getPlan(id);
  }

  @Post('plans')
  createPlan(@Body() body: CreatePlanDto) {
    return this.adminService.createPlan({
      ...body,
      priceMonthly: String(body.priceMonthly),
    });
  }

  @Patch('plans/:id')
  updatePlan(@Param('id') id: string, @Body() body: UpdatePlanDto) {
    const { priceMonthly, ...rest } = body;
    return this.adminService.updatePlan(id, {
      ...rest,
      ...(priceMonthly !== undefined
        ? { priceMonthly: String(priceMonthly) }
        : {}),
    });
  }

  @Delete('plans/:id')
  deactivatePlan(@Param('id') id: string) {
    return this.adminService.deactivatePlan(id);
  }

  @Put('plans/:id/features')
  replacePlanFeatures(
    @Param('id') id: string,
    @Body() body: ReplacePlanFeaturesDto,
  ) {
    return this.adminService.replacePlanFeatures(id, body.features);
  }

  // ── Users ────────────────────────────────────────────────────────────────

  @Get('users')
  listUsers(
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = page ? parseInt(page, 10) : 1;
    const l = limit ? parseInt(limit, 10) : 50;
    return this.adminService.listUsers(p, l);
  }

  @Get('users/:id')
  getUserDetail(@Param('id', ParseIntPipe) id: number) {
    return this.adminService.getUserDetail(id);
  }

  @Post('users')
  createUser(@Body() dto: CreateUserDto) {
    return this.adminService.createUser(dto);
  }

  @Patch('users/:id')
  updateUser(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
  ) {
    return this.adminService.updateUser(id, dto);
  }

  /** Désactivation douce — ne supprime pas le compte */
  @Delete('users/:id')
  @HttpCode(HttpStatus.OK)
  deactivateUser(@Param('id', ParseIntPipe) id: number) {
    return this.adminService.deactivateUser(id);
  }

  // ── Vehicles (enriched view — replaces raw devices list) ─────────────────

  @Get('vehicles')
  listVehicles(
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = page ? parseInt(page, 10) : 1;
    const l = limit ? parseInt(limit, 10) : 50;
    return this.adminService.listVehicles(p, l);
  }

  @Get('vehicles/:id')
  getVehicleDetail(@Param('id', ParseIntPipe) id: number) {
    return this.adminService.getVehicleDetail(id);
  }

  // ── Device assignments ────────────────────────────────────────────────────

  @Post('devices/:deviceId/assign/:userId')
  @HttpCode(HttpStatus.OK)
  assignDevice(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Param('userId', ParseIntPipe) userId: number,
  ) {
    return this.adminService.assignDevice(deviceId, userId);
  }

  @Delete('devices/:deviceId/assign')
  @HttpCode(HttpStatus.NO_CONTENT)
  unassignDevice(@Param('deviceId', ParseIntPipe) deviceId: number) {
    return this.adminService.unassignDevice(deviceId);
  }

  // ── Geofences ────────────────────────────────────────────────────────────

  @Get('geofences')
  listGeofences() {
    return this.adminService.listGeofences();
  }

  @Delete('geofences/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  removeGeofence(@Param('id') id: string) {
    return this.adminService.removeGeofence(id);
  }

  // ── Alerts ───────────────────────────────────────────────────────────────

  @Get('alerts')
  listAlerts(
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = page ? parseInt(page, 10) : 1;
    const l = limit ? parseInt(limit, 10) : 50;
    return this.adminService.listAlerts(p, l);
  }

  @Patch('alerts/:id')
  @HttpCode(HttpStatus.OK)
  ackAlert(@Param('id') id: string) {
    return this.adminService.ackAlert(id);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  @Get('reports/overview')
  getReportsOverview() {
    return this.adminService.getReportsOverview();
  }

  @Get('reports/vehicles')
  getVehicleReports(@Query('period') period: 'today' | '7d' | '30d' = '7d') {
    return this.adminService.getVehicleReports(period);
  }

  /** Résumé d'activité pour un véhicule donné */
  @Get('reports/vehicle/:deviceId/activity')
  getVehicleActivitySummary(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('period') period: 'today' | '7d' | '30d' = '7d',
  ) {
    return this.adminService.getVehicleActivitySummary(deviceId, period);
  }

  /** Trip log pour un véhicule */
  @Get('reports/vehicle/:deviceId/trip-log')
  getVehicleTripLog(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('from') from: string,
    @Query('to') to: string,
  ) {
    const now = new Date();
    const fromDate = from
      ? new Date(from)
      : new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    const toDate = to ? new Date(to) : now;
    return this.adminService.getVehicleTripLog(deviceId, fromDate, toDate);
  }

  /** Violations de vitesse pour un véhicule */
  @Get('reports/vehicle/:deviceId/speed-violations')
  getVehicleSpeedViolations(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Query('threshold') threshold?: string,
  ) {
    const now = new Date();
    const fromDate = from
      ? new Date(from)
      : new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    const toDate = to ? new Date(to) : now;
    const thresholdKmh = threshold ? parseInt(threshold, 10) : 120;
    return this.adminService.getVehicleSpeedViolations(
      deviceId,
      fromDate,
      toDate,
      thresholdKmh,
    );
  }

  /** Temps d'immobilisation moteur allumé pour un véhicule */
  @Get('reports/vehicle/:deviceId/idle')
  getVehicleIdleTime(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('from') from: string,
    @Query('to') to: string,
  ) {
    const now = new Date();
    const fromDate = from
      ? new Date(from)
      : new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    const toDate = to ? new Date(to) : now;
    return this.adminService.getVehicleIdleTime(deviceId, fromDate, toDate);
  }

  /** Activité geofence (entrées/sorties par zone) pour un véhicule */
  @Get('reports/vehicle/:deviceId/geofence-activity')
  getVehicleGeofenceActivity(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('from') from: string,
    @Query('to') to: string,
  ) {
    const now = new Date();
    const fromDate = from
      ? new Date(from)
      : new Date(now.getTime() - 7 * 24 * 3600 * 1000);
    const toDate = to ? new Date(to) : now;
    return this.adminService.getVehicleGeofenceActivity(
      deviceId,
      fromDate,
      toDate,
    );
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────

  @Get('subscriptions')
  listSubscriptions(
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = page ? parseInt(page, 10) : 1;
    const l = limit ? parseInt(limit, 10) : 50;
    return this.adminService.listSubscriptions(p, l);
  }

  @Patch('subscriptions/:deviceId')
  @HttpCode(HttpStatus.OK)
  upsertSubscription(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Body() body: UpdateSubscriptionDto,
  ) {
    return this.adminService.upsertSubscription(deviceId, body);
  }
}
