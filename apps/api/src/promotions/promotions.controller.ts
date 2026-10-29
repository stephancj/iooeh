import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { ClaimReferralRewardDto, CreateCouponDto, RedeemCouponDto, ValidateCouponDto } from './promotions.dto';
import { PromotionsService } from './promotions.service';

@Controller('promotions')
export class PromotionsController {
  constructor(
    private readonly promotionsService: PromotionsService,
    private readonly entitlementsService: EntitlementsService,
  ) {}

  @Post('redeem')
  @UseGuards(JwtAuthGuard)
  async redeem(
    @Body() dto: RedeemCouponDto,
    @Request() req: { user: { id: number } },
  ) {
    return this.promotionsService.redeemCode(req.user.id, dto.code, dto.deviceId);
  }

  @Post('preview')
  @UseGuards(JwtAuthGuard)
  preview(@Body() dto: RedeemCouponDto, @Request() req: { user: { id: number } }) {
    return this.promotionsService.previewCode(req.user.id, dto.code, dto.deviceId);
  }

  @Post('validate')
  @UseGuards(JwtAuthGuard)
  async validate(
    @Body() dto: ValidateCouponDto,
    @Request() req: { user: { id: number } },
  ) {
    return this.promotionsService.validateCouponForCheckout(
      dto.code,
      dto.planId,
      req.user.id,
    );
  }

  @Get('referral-info')
  @UseGuards(JwtAuthGuard)
  async getReferralInfo(@Request() req: { user: { id: number } }) {
    return this.promotionsService.getReferralInfo(req.user.id);
  }

  @Post('referrals/:id/claim')
  @UseGuards(JwtAuthGuard)
  claimReferralReward(@Param('id') id: string, @Body() dto: ClaimReferralRewardDto, @Request() req: { user: { id: number } }) {
    return this.promotionsService.claimReferralReward(req.user.id, id, dto.deviceId);
  }

  // ── Admin Endpoints ────────────────────────────────────────────────────────
  @Get('admin/coupons')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  listCoupons() {
    return this.promotionsService.listCoupons();
  }

  @Post('admin/coupons')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  createCoupon(@Body() dto: CreateCouponDto) {
    return this.promotionsService.createCoupon(dto);
  }

  @Delete('admin/coupons/:id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  deleteCoupon(@Param('id') id: string) {
    return this.promotionsService.deleteCoupon(id);
  }
}
