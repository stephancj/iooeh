import {
  Controller,
  Get,
  Param,
  Query,
  ParseIntPipe,
  UseGuards,
  BadRequestException,
  Request,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PositionsService } from './positions.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { DeviceAssignment } from '../admin/device-assignment.entity';
import { EntitlementsService } from '../entitlements/entitlements.service';

@Controller('positions')
@UseGuards(JwtAuthGuard)
export class PositionsController {
  constructor(
    private readonly positionsService: PositionsService,
    private readonly entitlementsService: EntitlementsService,
    @InjectRepository(DeviceAssignment)
    private readonly assignmentRepo: Repository<DeviceAssignment>,
  ) {}

  private async assertOwner(deviceId: number, userId: number): Promise<void> {
    const assignment = await this.assignmentRepo.findOne({
      where: { deviceId, userId },
    });
    if (!assignment)
      throw new NotFoundException(`Vehicle #${deviceId} not found`);
  }

  /**
   * GET /api/positions/last/:deviceId
   * Dernière position connue du device.
   */
  @Get('last/:deviceId')
  async getLastPosition(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Request() req: { user: { id: number } },
  ) {
    await this.assertOwner(deviceId, req.user.id);
    await this.entitlementsService.assertFeature(req.user.id, 'live_tracking', deviceId);
    return this.positionsService.getLastPosition(deviceId);
  }

  /**
   * GET /api/positions/history/:deviceId?from=ISO&to=ISO&limit=500
   * Historique sur une plage de dates.
   *
   * Exemple :
   *   /api/positions/history/1?from=2024-01-01T00:00:00Z&to=2024-01-01T23:59:59Z
   */
  @Get('history/:deviceId')
  async getHistory(
    @Param('deviceId', ParseIntPipe) deviceId: number,
    @Query('from') from: string,
    @Query('to') to: string,
    @Query('limit') limit?: string,
    @Request() req?: { user: { id: number } },
  ) {
    await this.assertOwner(deviceId, req!.user.id);
    if (!from || !to) {
      throw new BadRequestException(
        'Les paramètres "from" et "to" sont requis',
      );
    }

    const fromDate = new Date(from);
    const toDate = new Date(to);

    if (isNaN(fromDate.getTime()) || isNaN(toDate.getTime())) {
      throw new BadRequestException(
        'Format de date invalide (ISO 8601 requis)',
      );
    }

    if (fromDate >= toDate) {
      throw new BadRequestException('"from" doit être antérieur à "to"');
    }

    await this.entitlementsService.assertFeature(req!.user.id, 'history', deviceId);
    await this.entitlementsService.assertHistoryRange(req!.user.id, fromDate, deviceId);

    const limitNum = limit ? parseInt(limit, 10) : 1000;

    return this.positionsService.getHistory(
      deviceId,
      fromDate,
      toDate,
      limitNum,
    );
  }
}
