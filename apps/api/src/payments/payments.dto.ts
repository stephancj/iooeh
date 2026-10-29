import {
  IsEnum,
  IsNumber,
  IsInt,
  Min,
  IsOptional,
  IsString,
  IsUUID,
} from 'class-validator';

export enum PapiProvider {
  MVOLA = 'MVOLA',
  AIRTEL_MONEY = 'ARTEL_MONEY',
  ORANGE_MONEY = 'ORANGE_MONEY',
  BRED = 'BRED',
}
export class CreatePaymentDto {
  @IsUUID() planId: string;
  @IsInt() @Min(1) deviceId: number;
  @IsOptional() @IsInt() @Min(0) expectedAmount?: number;
  @IsOptional() @IsEnum(PapiProvider) provider?: PapiProvider;
  @IsOptional() @IsString() couponCode?: string;
}
export class PapiNotificationDto {
  @IsString() paymentStatus: string;
  @IsOptional() @IsString() paymentMethod?: string;
  @IsString() currency: string;
  @IsNumber() amount: number;
  @IsOptional() @IsNumber() fee?: number;
  @IsOptional() @IsString() clientName?: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsString() merchantPaymentReference?: string;
  @IsString() paymentReference: string;
  @IsString() notificationToken: string;
  @IsOptional() @IsString() message?: string;
  @IsOptional() @IsString() payerEmail?: string;
  @IsOptional() @IsString() payerPhone?: string;
}
