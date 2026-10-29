import { TypeOrmModuleOptions } from '@nestjs/typeorm';
import { Device } from '../devices/device.entity';
import { Position } from '../positions/position.entity';
import { User } from '../users/user.entity';
import { DeviceAssignment } from '../admin/device-assignment.entity';
import { Subscription } from '../admin/subscription.entity';
import { VehicleSubscription } from '../entitlements/vehicle-subscription.entity';
import { Geofence } from '../geofences/entities/geofence.entity';
import { Alert } from '../alerts/entities/alert.entity';
import { VehicleSleepMode } from '../vehicles/vehicle-sleep-mode.entity';
import { WaitlistSubscriber } from '../waitlist/waitlist-subscriber.entity';
import { Feature } from '../entitlements/feature.entity';
import { Plan } from '../entitlements/plan.entity';
import { PlanFeature } from '../entitlements/plan-feature.entity';
import { SecurityIncident } from '../security/incident.entity';
import { IncidentEvent } from '../security/incident-event.entity';
import { PublicTrackingLink } from '../security/tracking-link.entity';
import { Payment } from '../payments/payment.entity';
import { Trip } from '../trips/trip.entity';
import { Coupon } from '../promotions/entities/coupon.entity';
import { Referral } from '../promotions/entities/referral.entity';
import { CouponRedemption } from '../promotions/entities/coupon-redemption.entity';
import { SystemSetting } from '../admin/system-setting.entity';
import * as pg from 'pg';

// Force parsing of 'timestamp without time zone' (OID 1114) as UTC.
pg.types.setTypeParser(1114, (str) => new Date(str + 'Z'));

export default (): TypeOrmModuleOptions => ({
  type: 'postgres',
  host: process.env.DB_HOST ?? 'localhost',
  port: parseInt(process.env.DB_PORT ?? '5432', 10),
  username: process.env.DB_USER ?? 'trackeo',
  password: process.env.DB_PASS ?? 'Password_1234',
  database: process.env.DB_NAME ?? 'traccar_db',
  entities: [
    Device,
    Position,
    User,
    DeviceAssignment,
    Subscription,
    VehicleSubscription,
    Geofence,
    Alert,
    VehicleSleepMode,
    WaitlistSubscriber,
    Feature,
    Plan,
    PlanFeature,
    SecurityIncident,
    IncidentEvent,
    PublicTrackingLink,
    Payment,
    Trip,
    Coupon,
    Referral,
    CouponRedemption,
    SystemSetting,
  ],
  // migrations exclues du runtime — lancées manuellement via `npm run migration:run`
  synchronize: false,
  logging: ['error'],
  // Force UTC pour éviter les décalages de timezone (ex: UTC+3 local)
  extra: { options: '-c timezone=UTC' },
});
