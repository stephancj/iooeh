import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { DevicesService } from '../devices/devices.service';
import { PositionsService, PositionDto } from '../positions/positions.service';
import { VehicleDto, VehiclePositionDto, VehicleStatus } from './vehicle.dto';
import { Device } from '../devices/device.entity';
import { DeviceAssignment } from '../admin/device-assignment.entity';
import { ClaimVehicleDto } from './dto/claim-vehicle.dto';
import { VehicleSleepMode } from './vehicle-sleep-mode.entity';
import { EntitlementsService } from '../entitlements/entitlements.service';

@Injectable()
export class VehiclesService {
  constructor(
    private readonly devicesService: DevicesService,
    private readonly positionsService: PositionsService,
    @InjectRepository(DeviceAssignment)
    private readonly assignmentRepo: Repository<DeviceAssignment>,
    @InjectRepository(VehicleSleepMode)
    private readonly sleepModeRepo: Repository<VehicleSleepMode>,
    private readonly entitlementsService: EntitlementsService,
  ) {}

  /**
   * Retourne tous les véhicules enrichis avec leur dernière position.
   * Sans filtre utilisateur — utilisé par l'admin.
   */
  async findAll(): Promise<VehicleDto[]> {
    const devices = await this.devicesService.findAll();

    const results = await Promise.allSettled(
      devices.map((device) => this.buildVehicleDto(device)),
    );

    return results
      .filter(
        (r): r is PromiseFulfilledResult<VehicleDto> =>
          r.status === 'fulfilled',
      )
      .map((r) => r.value);
  }

  /**
   * Retourne tous les véhicules enrichis avec leur dernière position, paginés.
   */
  async findAllPaginated(page: number, limit: number): Promise<[VehicleDto[], number]> {
    const [devices, total] = await this.devicesService.findAllPaginated(page, limit);

    const results = await Promise.allSettled(
      devices.map((device) => this.buildVehicleDto(device)),
    );

    const vehicles = results
      .filter(
        (r): r is PromiseFulfilledResult<VehicleDto> =>
          r.status === 'fulfilled',
      )
      .map((r) => r.value);
      
    return [vehicles, total];
  }

  /**
   * Retourne uniquement les véhicules assignés à cet utilisateur.
   * Utilisé par les endpoints mobiles (fleet list, carte).
   */
  async findAllForUser(userId: number): Promise<VehicleDto[]> {
    const assignments = await this.assignmentRepo.find({ where: { userId } });
    if (assignments.length === 0) return [];

    const deviceIds = new Set(assignments.map((a) => a.deviceId));
    const all = await this.findAll();
    return all.filter((v) => deviceIds.has(v.id));
  }

  /** Active si nécessaire puis associe un traceur au compte utilisateur. */
  async claimVehicle(
    userId: number,
    dto: ClaimVehicleDto,
  ): Promise<VehicleDto> {
    const serialNumber = dto.serialNumber.replace(/\s/g, '').trim();
    let device = await this.devicesService.findByUniqueId(serialNumber);

    if (device) {
      if (device.disabled) {
        throw new ForbiddenException('Cet appareil est désactivé.');
      }
      const existingAssignment = await this.assignmentRepo.findOne({
        where: { deviceId: device.id },
      });
      if (existingAssignment) {
        if (existingAssignment.userId !== userId) {
          throw new ConflictException(
            'Cet appareil est déjà associé à un autre compte.',
          );
        }
        return this.buildVehicleDto(device);
      }
    }

    if (!device) {
      if (!/^\d{15}$/.test(serialNumber)) {
        throw new BadRequestException(
          'Pour un nouveau traceur, saisissez son IMEI à 15 chiffres.',
        );
      }
      device = await this.devicesService.provision({
        uniqueId: serialNumber,
        name: dto.name?.trim() || `Véhicule ${serialNumber.slice(-6)}`,
        plate: dto.plate?.trim().toUpperCase(),
      });
    }

    try {
      await this.assignmentRepo.save(
        this.assignmentRepo.create({ deviceId: device.id, userId }),
      );
    } catch {
      throw new ConflictException(
        'Cet appareil vient d’être associé à un autre compte.',
      );
    }

    if (dto.name?.trim() || dto.plate?.trim()) {
      const updated = await this.devicesService.update(device.id, {
        name: dto.name?.trim() || device.name,
        attributes: dto.plate?.trim()
          ? { plate: dto.plate.trim().toUpperCase() }
          : undefined,
      });
      return this.buildVehicleDto(updated);
    }

    return this.buildVehicleDto(device);
  }

  /**
   * Vérifie que le device appartient à cet utilisateur.
   * Lève NotFoundException si non (ne révèle pas l'existence du device à d'autres users).
   */
  async assertOwner(deviceId: number, userId: number): Promise<void> {
    const assignment = await this.assignmentRepo.findOne({
      where: { deviceId, userId },
    });
    if (!assignment) {
      throw new NotFoundException(`Vehicle #${deviceId} not found`);
    }
  }

  /**
   * Retourne un véhicule enrichi par son ID.
   */
  async findOne(id: number): Promise<VehicleDto> {
    const device = await this.devicesService.findOne(id);
    return this.buildVehicleDto(device);
  }

  async update(id: number, data: Partial<Device>): Promise<VehicleDto> {
    const device = await this.devicesService.update(id, data);
    return this.buildVehicleDto(device);
  }

  /** Arme la veille depuis la position actuelle, uniquement véhicule arrêté. */
  async enableSleepMode(
    deviceId: number,
    ownerId: number,
  ): Promise<VehicleSleepMode> {
    await this.entitlementsService.assertFeature(ownerId, 'sleep_mode', deviceId);
    const vehicle = await this.findOne(deviceId);
    if (!vehicle.position || vehicle.status === 'offline') {
      throw new BadRequestException(
        'Le véhicule doit transmettre une position récente pour activer la veille.',
      );
    }
    if (vehicle.status !== 'idle' || vehicle.position.speedKmh > 2) {
      throw new BadRequestException(
        'La veille peut être activée uniquement lorsque le véhicule est à l’arrêt.',
      );
    }

    const existing = await this.sleepModeRepo.findOne({
      where: { deviceId },
    });
    const mode = this.sleepModeRepo.create({
      ...(existing ?? {}),
      deviceId,
      ownerId,
      active: true,
      armedLat: vehicle.position.lat,
      armedLon: vehicle.position.lon,
      movementThresholdM: 100,
      triggeredAt: null,
      lastDistanceM: 0,
      armedAt: new Date(),
    });
    return this.sleepModeRepo.save(mode);
  }

  /** Désarme la veille. Le record est conservé pour le diagnostic. */
  async disableSleepMode(
    deviceId: number,
    ownerId: number,
  ): Promise<VehicleSleepMode | null> {
    const mode = await this.sleepModeRepo.findOne({
      where: { deviceId, ownerId },
    });
    if (!mode) return null;
    mode.active = false;
    return this.sleepModeRepo.save(mode);
  }

  /**
   * Dernière position d'un véhicule — endpoint de polling (toutes les 10s).
   */
  async getLastPosition(deviceId: number): Promise<VehiclePositionDto | null> {
    try {
      const pos = await this.positionsService.getLastPosition(deviceId);
      return {
        lat: pos.lat,
        lon: pos.lon,
        speedKmh: pos.speedKmh,
        course: pos.course,
        address: pos.address,
        battery: this.extractBattery(pos.attributes),
        charging: this.extractCharging(pos.attributes),
        ignition: this.extractIgnition(pos.attributes),
        rssi: this.extractRssi(pos.attributes),
        deviceTime: pos.deviceTime,
      };
    } catch {
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers privés
  // ──────────────────────────────────────────────────────────────────────────

  private async buildVehicleDto(device: Device): Promise<VehicleDto> {
    let position: VehiclePositionDto | null = null;
    let lastSeen: Date | null = device.lastUpdate;

    if (device.positionid) {
      const pos = await this.positionsService.getPositionById(
        device.positionid,
      );
      if (pos) {
        position = this.toVehiclePosition(pos);
        if (!lastSeen) lastSeen = pos.serverTime ?? pos.deviceTime;
      }
    } else {
      try {
        const pos = await this.positionsService.getLastPosition(device.id);
        position = this.toVehiclePosition(pos);
        if (!lastSeen) lastSeen = pos.serverTime ?? pos.deviceTime;
      } catch {
        // offline
      }
    }

    const sleepMode = await this.sleepModeRepo.findOne({
      where: { deviceId: device.id, active: true },
    });

    return {
      id: device.id,
      name: device.name,
      serialNumber: device.uniqueId,
      plate: (device.attributes as any)?.plate || null,
      imageUrl: this.extractImageUrl(device),
      status: this.computeStatus(
        position?.speedKmh ?? 0,
        lastSeen,
        device.status,
      ),
      lastUpdate: device.lastUpdate,
      position,
      sleepMode: sleepMode
        ? {
            active: sleepMode.active,
            triggered: sleepMode.triggeredAt != null,
            armedAt: sleepMode.armedAt,
            triggeredAt: sleepMode.triggeredAt,
            movementThresholdM: sleepMode.movementThresholdM,
            lastDistanceM: sleepMode.lastDistanceM,
          }
        : null,
    };
  }

  private toVehiclePosition(pos: PositionDto): VehiclePositionDto {
    return {
      lat: pos.lat,
      lon: pos.lon,
      speedKmh: pos.speedKmh,
      course: pos.course,
      address: pos.address,
      battery: this.extractBattery(pos.attributes),
      charging: this.extractCharging(pos.attributes),
      ignition: this.extractIgnition(pos.attributes),
      rssi: this.extractRssi(pos.attributes),
      deviceTime: pos.deviceTime,
    };
  }

  private extractImageUrl(device: Device): string | null {
    if (device.attributes?.imageUrl) {
      return device.attributes.imageUrl as string;
    }

    const n = device.name.toLowerCase();
    if (n.includes('rav4'))
      return 'https://images.info-auto.fr/toyota-rav4-2019-1.jpg';
    if (n.includes('hilux'))
      return 'https://images.info-auto.fr/toyota-hilux-2021.jpg';
    return 'https://images.info-auto.fr/vehicule-generique.jpg';
  }

  private computeStatus(
    speedKmh: number,
    lastUpdate: Date | null,
    traccarStatus?: string | null,
  ): VehicleStatus {
    const OFFLINE_THRESHOLD_S = 600;
    if (!lastUpdate) return 'offline';
    const secondsAgo = (Date.now() - new Date(lastUpdate).getTime()) / 1000;
    if (secondsAgo > OFFLINE_THRESHOLD_S) return 'offline';
    if (traccarStatus === 'offline') return 'offline';
    return speedKmh > 1 ? 'online' : 'idle';
  }

  private extractBattery(
    attributes: Record<string, unknown> | null,
  ): number | null {
    if (!attributes) return null;
    const raw =
      attributes['battery'] ??
      attributes['batteryLevel'] ??
      attributes['io113'];
    if (typeof raw !== 'number') return null;
    // Fraction [0,1] → percentage
    if (raw <= 1) return Math.round(raw * 100);
    // Already a percentage [2,100]
    if (raw >= 2 && raw <= 100) return Math.round(raw);
    // GT06 / Li-Ion voltage [3.0V, 4.5V] → percentage
    if (raw >= 3.0 && raw <= 4.5) {
      return Math.max(0, Math.min(100, Math.round(((raw - 3.5) / 0.7) * 100)));
    }
    return null;
  }

  private extractCharging(
    attributes: Record<string, unknown> | null,
  ): boolean | null {
    if (!attributes) return null;
    // GT06: 'charge' boolean
    const charge = attributes['charge'] ?? attributes['externalPower'];
    if (typeof charge === 'boolean') return charge;
    if (typeof charge === 'number') return charge > 0;
    return null;
  }

  private extractIgnition(
    attributes: Record<string, unknown> | null,
  ): boolean | null {
    if (!attributes) return null;
    const raw = attributes['ignition'] ?? attributes['acc'];
    if (typeof raw === 'boolean') return raw;
    if (typeof raw === 'number') return raw === 1;
    return null;
  }

  private extractRssi(
    attributes: Record<string, unknown> | null,
  ): number | null {
    if (!attributes) return null;
    const raw = attributes['rssi'] ?? attributes['signal'];
    if (typeof raw === 'number') return raw;
    return null;
  }
}
