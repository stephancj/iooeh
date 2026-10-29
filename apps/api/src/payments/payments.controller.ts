import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { CreatePaymentDto, PapiNotificationDto } from './payments.dto';
import { PaymentsService } from './payments.service';

@Controller('payments')
export class PaymentsController {
  constructor(private readonly payments: PaymentsService) {}
  @Post('checkout') @UseGuards(JwtAuthGuard) checkout(
    @Body() dto: CreatePaymentDto,
    @Request() req: { user: { id: number } },
  ) {
    return this.payments.create(req.user.id, dto);
  }
  @Post('quote') @UseGuards(JwtAuthGuard) quote(
    @Body() dto: CreatePaymentDto,
    @Request() req: { user: { id: number } },
  ) {
    return this.payments.quote(req.user.id, dto);
  }
  @Get('plans') @UseGuards(JwtAuthGuard) plans() {
    return this.payments.listPlans();
  }
  @Get() @UseGuards(JwtAuthGuard) history(
    @Request() req: { user: { id: number } },
  ) {
    return this.payments.history(req.user.id);
  }
  @Get(':reference/status') @UseGuards(JwtAuthGuard) status(
    @Param('reference') reference: string,
    @Request() req: { user: { id: number } },
  ) {
    return this.payments.status(req.user.id, reference);
  }
  @Get('admin/all')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  listAdminPayments() {
    return this.payments.listAdminPayments();
  }

  @Post('papi/notification') @HttpCode(200) notification(
    @Body() dto: PapiNotificationDto,
  ) {
    return this.payments.handleNotification(dto);
  }
}
