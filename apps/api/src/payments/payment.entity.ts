import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

export enum PaymentStatus {
  CREATED = 'created',
  PENDING = 'pending',
  SUCCESS = 'success',
  FAILED = 'failed',
  EXPIRED = 'expired',
  REQUIRES_REVIEW = 'requires_review',
}

@Entity({ name: 'payments' })
export class Payment {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column({ name: 'user_id' }) userId: number;
  @Column({ name: 'assignment_id', type: 'integer', nullable: true }) assignmentId: number | null;
  @Column({ name: 'coupon_id', type: 'uuid', nullable: true }) couponId: string | null;
  @Column({ name: 'referral_id', type: 'uuid', nullable: true }) referralId: string | null;
  @Column({ name: 'plan_id', type: 'uuid' }) planId: string;
  @Column({ type: 'varchar', length: 80, unique: true }) reference: string;
  @Column({ type: 'integer' }) amount: number;
  @Column({ type: 'varchar', length: 3, default: 'MGA' }) currency: string;
  @Column({ type: 'varchar', length: 30, default: PaymentStatus.CREATED })
  status: PaymentStatus;
  @Column({ type: 'varchar', length: 30, nullable: true }) provider:
    | string
    | null;
  @Column({
    name: 'payment_method',
    type: 'varchar',
    length: 30,
    nullable: true,
  })
  paymentMethod: string | null;
  @Column({ name: 'payment_link', type: 'text', nullable: true }) paymentLink:
    | string
    | null;
  @Column({
    name: 'papi_notification_token',
    type: 'text',
    nullable: true,
    select: false,
  })
  papiNotificationToken: string | null;
  @Column({
    name: 'papi_merchant_reference',
    type: 'varchar',
    length: 100,
    nullable: true,
  })
  papiMerchantReference: string | null;
  @Column({
    name: 'papi_payment_reference',
    type: 'varchar',
    length: 100,
    nullable: true,
    unique: true,
  })
  papiPaymentReference: string | null;
  @Column({ name: 'failure_message', type: 'text', nullable: true })
  failureMessage: string | null;
  @Column({ name: 'paid_at', type: 'timestamptz', nullable: true })
  paidAt: Date | null;
  @Column({ name: 'expires_at', type: 'timestamptz', nullable: true })
  expiresAt: Date | null;
  @Column({ name: 'raw_notification', type: 'jsonb', nullable: true })
  rawNotification: Record<string, unknown> | null;
  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt: Date;
}
