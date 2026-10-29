import {
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Query,
  Request,
  StreamableFile,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { TripsService } from './trips.service';

@Controller('trips')
@UseGuards(JwtAuthGuard)
export class TripsController {
  constructor(
    private readonly trips: TripsService,
    private readonly entitlements: EntitlementsService,
  ) {}
  private dates(from?: string, to?: string) {
    const end = to ? new Date(to) : new Date();
    return {
      from: from ? new Date(from) : new Date(end.getTime() - 7 * 24 * 3600_000),
      to: end,
    };
  }
  @Get('device/:deviceId') async list(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlements.assertFeature(req.user.id, 'trip_reports', deviceId);
    const range = this.dates(from, to);
    await this.entitlements.assertHistoryRange(req.user.id, range.from, deviceId);
    return this.trips.listForUser(req.user.id, deviceId, range.from, range.to);
  }
  @Get(':id/playback') async playback(
    @Param('id') id: string,
    @Request() req: { user: { id: number } },
  ) {
    const trip = await this.trips.playback(req.user.id, id);
    await this.entitlements.assertFeature(req.user.id, 'trip_playback', trip.deviceId);
    return trip;
  }
  @Get('device/:deviceId/export.csv') async csv(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlements.assertFeature(req.user.id, 'report_exports', deviceId);
    const range = this.dates(from, to);
    const rows = await this.trips.listForUser(
      req.user.id,
      deviceId,
      range.from,
      range.to,
    );
    return new StreamableFile(this.trips.csv(rows), {
      type: 'text/csv; charset=utf-8',
      disposition: `attachment; filename="trajets-${deviceId}.csv"`,
    });
  }
  @Get('device/:deviceId/export.pdf') async pdf(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Request() req: { user: { id: number } },
  ) {
    await this.entitlements.assertFeature(req.user.id, 'report_exports', deviceId);
    const range = this.dates(from, to);
    const rows = await this.trips.listForUser(
      req.user.id,
      deviceId,
      range.from,
      range.to,
    );
    return new StreamableFile(
      this.trips.pdf(rows, `Rapport trajets — véhicule ${deviceId}`),
      {
        type: 'application/pdf',
        disposition: `attachment; filename="trajets-${deviceId}.pdf"`,
      },
    );
  }
}
