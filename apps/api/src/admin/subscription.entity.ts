import {
  Entity,
  Column,
  PrimaryGeneratedColumn,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

export enum SubscriptionPlan {
  FREE = 'free',
  BASIC = 'basic',
  PREMIUM = 'premium',
}

export enum SubscriptionStatus {
  TRIAL = 'trial',
  ACTIVE = 'active',
  SUSPENDED = 'suspended',
  CANCELLED = 'cancelled',
}

@Entity({ name: 'subscriptions' })
export class Subscription {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /** Référence vers la table `users` — unique : 1 abonnement par user */
  @Column({ name: 'user_id', unique: true })
  userId: number;

  /** Relation normalisée vers `plans`; `plan` reste durant la transition. */
  @Column({ name: 'plan_id', type: 'uuid', nullable: true })
  planId: string | null;

  @Column({
    type: 'varchar',
    length: 50,
    default: SubscriptionPlan.FREE,
  })
  plan: SubscriptionPlan | string;

  @Column({
    type: 'varchar',
    length: 50,
    default: SubscriptionStatus.TRIAL,
  })
  status: SubscriptionStatus;

  /** Prochain échéance de facturation */
  @Column({ name: 'next_billing_date', type: 'timestamptz', nullable: true })
  nextBillingDate: Date | null;

  /** Fin de la période d'essai */
  @Column({ name: 'trial_ends_at', type: 'timestamptz', nullable: true })
  trialEndsAt: Date | null;

  /** Notes admin libres */
  @Column({ type: 'text', nullable: true })
  notes: string | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
