import {
  IsEnum,
  IsNotEmpty,
  IsNumber,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Min,
} from 'class-validator';
import { CouponRewardType } from './entities/coupon.entity';

export class CreateCouponDto {
  @IsString()
  @IsNotEmpty()
  code: string;

  @IsEnum(CouponRewardType)
  rewardType: CouponRewardType;

  @IsNumber()
  @Min(0)
  rewardValue: number;

  @IsOptional()
  @IsUUID()
  grantedPlanId?: string;

  @IsOptional()
  @IsUUID()
  targetPlanId?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  minPlanPrice?: number;

  @IsOptional()
  @IsNumber()
  maxRedemptions?: number;

  @IsOptional()
  @IsNumber()
  maxRedemptionsPerUser?: number;

  @IsOptional()
  expiresAt?: string;
}

export class RedeemCouponDto {
  @IsOptional() @IsInt() @Min(1) deviceId?: number;
  @IsString()
  @IsNotEmpty()
  code: string;
}

export class ValidateCouponDto {
  @IsString()
  @IsNotEmpty()
  code: string;

  @IsUUID()
  planId: string;
}

export class ClaimReferralRewardDto {
  @IsInt() @Min(1) deviceId: number;
}
