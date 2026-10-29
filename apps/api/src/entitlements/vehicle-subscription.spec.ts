import { NotFoundException } from '@nestjs/common';
import { EntitlementsService } from './entitlements.service';

describe('Vehicle subscriptions', () => {
  const makeService = (assignment: unknown, existing: unknown = null) => {
    const assignmentRepo = { findOne: jest.fn().mockResolvedValue(assignment) };
    const query = { insert: jest.fn().mockReturnThis(), values: jest.fn().mockReturnThis(), orIgnore: jest.fn().mockReturnThis(), execute: jest.fn().mockResolvedValue(undefined) };
    const vehicleRepo = { findOne: jest.fn().mockResolvedValue(existing), findOneOrFail: jest.fn().mockResolvedValue({ id: 'subscription' }), createQueryBuilder: jest.fn().mockReturnValue(query) };
    const plans = { findOne: jest.fn().mockResolvedValue({ id: 'free-plan', code: 'free' }) };
    const service = new EntitlementsService({} as never, plans as never, {} as never, {} as never, {} as never, assignmentRepo as never, vehicleRepo as never);
    return { service, query, vehicleRepo };
  };
  it('does not expose or create a subscription for a vehicle owned by another user', async () => {
    const { service, vehicleRepo } = makeService(null);
    await expect(service.ensureVehicleSubscription(4, 12)).rejects.toBeInstanceOf(NotFoundException);
    expect(vehicleRepo.createQueryBuilder).not.toHaveBeenCalled();
  });
  it('creates a seven-day trial from the assignment time and does not overwrite a concurrent insert', async () => {
    const { service, query } = makeService({ id: 20, createdAt: new Date('2026-01-01T00:00:00Z') });
    await service.ensureVehicleSubscription(4, 12);
    expect(query.values).toHaveBeenCalledWith(expect.objectContaining({ assignmentId: 20, trialEndsAt: new Date('2026-01-08T00:00:00Z') }));
    expect(query.orIgnore).toHaveBeenCalled();
  });
  it('preserves an existing subscription', async () => {
    const existing = { id: 'existing' };
    const { service, vehicleRepo } = makeService({ id: 20 }, existing);
    expect(await service.ensureVehicleSubscription(4, 12)).toBe(existing);
    expect(vehicleRepo.createQueryBuilder).not.toHaveBeenCalled();
  });
});

describe('Account-wide notification preferences', () => {
  it('combines available vehicle features without dropping the first vehicle', async () => {
    const assignmentRepo = { find: jest.fn().mockResolvedValue([{ deviceId: 1 }, { deviceId: 2 }]) };
    const service = new EntitlementsService({} as never, {} as never, {} as never, {} as never, {} as never, assignmentRepo as never, {} as never);
    const result = (features: Record<string, boolean | number>) => ({ subscription: { id: 's', status: 'active', trialEndsAt: null, nextBillingDate: null }, plan: { id: 'p', code: 'free', name: 'Free' }, accessAllowed: true, features });
    jest.spyOn(service, 'getForVehicle').mockResolvedValueOnce(result({ live_tracking: true, history_retention_days: 30 }) as never).mockResolvedValueOnce(result({ whatsapp_notifications: true, history_retention_days: 7 }) as never);
    jest.spyOn(service, 'ensureDefaultSubscription').mockResolvedValue({} as never);
    const rights = await service.getForUser(1);
    expect(rights.features).toMatchObject({ live_tracking: true, whatsapp_notifications: true, history_retention_days: 30 });
  });
});
