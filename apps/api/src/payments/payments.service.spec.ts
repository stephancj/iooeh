import { PaymentsService } from './payments.service';
import { Payment, PaymentStatus } from './payment.entity';

describe('PaymentsService PAPI notifications', () => {
  it('looks up the local payment with merchantPaymentReference', async () => {
    const payment = {
      reference: 'IOOEH-60f4db35-3d1f-416a-be79-d460f10422e0',
      amount: 29000,
      currency: 'MGA',
      status: PaymentStatus.PENDING,
      papiNotificationToken: 'notification-secret',
    } as Payment;
    const queryBuilder = {
      addSelect: jest.fn().mockReturnThis(),
      setLock: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      getOne: jest.fn().mockResolvedValue(payment),
    };
    const paymentRepo = {
      createQueryBuilder: jest.fn().mockReturnValue(queryBuilder),
      save: jest.fn().mockResolvedValue(payment),
      manager: { transaction: jest.fn(async (work) => work({ getRepository: () => paymentRepo })) },
    };
    const service = new PaymentsService(
      paymentRepo as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
    );

    await service.handleNotification({
      paymentStatus: 'PENDING',
      currency: 'MGA',
      amount: 29000,
      merchantPaymentReference: payment.reference,
      paymentReference: '60f4db35-3d1f-416a-be79-d460f10422e0',
      notificationToken: 'notification-secret',
    });

    expect(queryBuilder.where).toHaveBeenCalledWith(
      'payment.reference = :reference',
      { reference: payment.reference },
    );
    expect(payment.papiMerchantReference).toBe(payment.reference);
    expect(payment.papiPaymentReference).toBe(
      '60f4db35-3d1f-416a-be79-d460f10422e0',
    );
  });
});

describe('Vehicle payment notifications', () => {
  function setup(assignment: unknown = { id: 42, userId: 7 }) {
    const payment = { id: 'payment', reference: 'IOOEH-test', userId: 7, assignmentId: 42, planId: 'p', amount: 29000, currency: 'MGA', status: PaymentStatus.PENDING, papiNotificationToken: 'secret' } as Payment;
    const sub = { assignmentId: 42, planId: 'old', status: 'trial', nextBillingDate: null };
    const qb = { addSelect: jest.fn().mockReturnThis(), setLock: jest.fn().mockReturnThis(), where: jest.fn().mockReturnThis(), getOne: jest.fn().mockResolvedValue(payment) };
    const payments = { createQueryBuilder: () => qb, save: jest.fn().mockResolvedValue(payment) };
    const assignments = { findOne: jest.fn().mockResolvedValue(assignment) };
    const subscriptions = { findOne: jest.fn().mockResolvedValue(sub), save: jest.fn().mockResolvedValue(sub) };
    const plans = { findOneByOrFail: jest.fn().mockResolvedValue({ id: 'p', code: 'basic' }) };
    const manager = { getRepository: (entity: { name: string }) => ({ Payment: payments, DeviceAssignment: assignments, VehicleSubscription: subscriptions, Plan: plans }[entity.name]) };
    const repo = { manager: { transaction: (fn: (manager: unknown) => unknown) => fn(manager) } };
    const entitlements = { invalidate: jest.fn() };
    const promotions = { qualifyReferralOnPayment: jest.fn().mockResolvedValue(undefined) };
    const service = new PaymentsService(repo as never, {} as never, {} as never, {} as never, entitlements as never, promotions as never);
    const dto = { paymentStatus: 'SUCCESS', currency: 'MGA', amount: 29000, merchantPaymentReference: 'IOOEH-test', paymentReference: 'provider-ref', notificationToken: 'secret' };
    return { service, dto, payment, sub, subscriptions };
  }
  it('activates only the subscription linked to the paid assignment', async () => {
    const { service, dto, sub, subscriptions } = setup();
    await service.handleNotification(dto);
    expect(subscriptions.save).toHaveBeenCalledTimes(1);
    expect(sub).toMatchObject({ assignmentId: 42, planId: 'p', status: 'active' });
  });
  it('does not activate a reassigned or removed vehicle', async () => {
    const { service, dto, subscriptions } = setup(null);
    await service.handleNotification(dto);
    expect(subscriptions.save).not.toHaveBeenCalled();
  });
  it('does not apply a successful notification twice', async () => {
    const { service, dto, payment, subscriptions } = setup();
    payment.status = PaymentStatus.SUCCESS;
    await service.handleNotification(dto);
    expect(subscriptions.save).not.toHaveBeenCalled();
  });
});
