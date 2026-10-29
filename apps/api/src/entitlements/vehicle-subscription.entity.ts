import { Column, CreateDateColumn, Entity, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';
import { SubscriptionStatus } from '../admin/subscription.entity';

@Entity({ name: 'vehicle_subscriptions' })
export class VehicleSubscription {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column({ name: 'assignment_id', unique: true }) assignmentId: number;
  @Column({ name: 'plan_id', type: 'uuid', nullable: true }) planId: string | null;
  @Column({ type: 'varchar', length: 50 }) plan: string;
  @Column({ type: 'varchar', length: 50 }) status: SubscriptionStatus;
  @Column({ name: 'trial_ends_at', type: 'timestamptz', nullable: true }) trialEndsAt: Date | null;
  @Column({ name: 'next_billing_date', type: 'timestamptz', nullable: true }) nextBillingDate: Date | null;
  @Column({ type: 'text', nullable: true }) notes: string | null;
  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' }) createdAt: Date;
  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' }) updatedAt: Date;
}
