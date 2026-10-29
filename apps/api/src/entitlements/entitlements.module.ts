import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Subscription } from '../admin/subscription.entity';
import { VehicleSubscription } from './vehicle-subscription.entity';
import { DeviceAssignment } from '../admin/device-assignment.entity';
import { Geofence } from '../geofences/entities/geofence.entity';
import { Feature } from './feature.entity';
import { Plan } from './plan.entity';
import { PlanFeature } from './plan-feature.entity';
import { EntitlementsService } from './entitlements.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Subscription,
      VehicleSubscription,
      Plan,
      Feature,
      PlanFeature,
      DeviceAssignment,
      Geofence,
    ]),
  ],
  providers: [EntitlementsService],
  exports: [EntitlementsService, TypeOrmModule],
})
export class EntitlementsModule {}
