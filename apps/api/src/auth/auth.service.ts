import {
  BadRequestException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { UsersService } from '../users/users.service';
import { User, UserRole } from '../users/user.entity';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { JwtPayload } from './jwt.strategy';
import { EntitlementsService } from '../entitlements/entitlements.service';
import { PromotionsService } from '../promotions/promotions.service';
import { BrevoEmailService } from '../notifications/brevo-email.service';

export interface AuthResponse {
  access_token: string;
  user: {
    id: number;
    email: string;
    name: string | null;
    phone: string | null;
    role: string;
  };
}

export interface RegistrationResponse {
  ok: true;
  verificationRequired: true;
  email: string;
}

interface LoginContext {
  ip?: string;
  userAgent?: string;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly tokenTtlMs = 30 * 60_000;
  private readonly resendCooldownMs = 2 * 60_000;

  constructor(
    private readonly usersService: UsersService,
    private readonly jwtService: JwtService,
    private readonly entitlementsService: EntitlementsService,
    private readonly promotionsService: PromotionsService,
    private readonly emails: BrevoEmailService,
  ) {}

  async login(dto: LoginDto, context: LoginContext = {}): Promise<AuthResponse> {
    const user = await this.usersService.findByIdentifierWithPassword(
      dto.identifier ?? dto.email!,
    );

    if (!user) {
      throw new UnauthorizedException('Identifiant ou mot de passe incorrect');
    }

    const isPasswordValid = await bcrypt.compare(dto.password, user.password);
    if (!isPasswordValid) {
      throw new UnauthorizedException('Identifiant ou mot de passe incorrect');
    }

    if (!user.emailVerifiedAt) {
      throw new UnauthorizedException(
        'Adresse email non vérifiée. Consultez votre boîte de réception.',
      );
    }

    await this.usersService.markLogin(user.id);
    await this.sendLoginEmail(user, context);

    return this.buildResponse(user);
  }

  async register(dto: RegisterDto): Promise<RegistrationResponse> {
    const user = await this.usersService.create({
      email: dto.email,
      password: dto.password,
      name: dto.name,
      phone: dto.phone,
      role: UserRole.USER,
    });

    if (dto.referralCode) {
      await this.promotionsService.processRegistrationReferral(
        user.id,
        dto.referralCode,
      );
    }

    await this.sendVerificationEmail(user);
    return {
      ok: true,
      verificationRequired: true,
      email: user.email,
    };
  }

  async verifyEmail(token: string): Promise<{ ok: true }> {
    const user = await this.usersService.findByEmailVerificationToken(
      this.hashToken(token),
    );
    if (!user) {
      throw new BadRequestException('Ce lien est invalide ou a expiré.');
    }
    await this.usersService.markEmailVerified(user.id);
    await this.safeSend({
      to: user.email,
      toName: user.name ?? undefined,
      subject: 'Votre compte iooeh est prêt',
      tag: 'account-verified',
      content: {
        eyebrow: 'Compte activé',
        title: 'Bienvenue chez iooeh.',
        intro:
          'Votre adresse email est confirmée. Vous pouvez maintenant vous connecter et commencer à protéger votre véhicule.',
        actionLabel: 'Se connecter',
        actionUrl: this.appUrl(),
      },
    });
    return { ok: true };
  }

  async resendVerification(email: string): Promise<{ ok: true }> {
    const user = await this.usersService.findByEmailForEmailFlow(email);
    if (
      user &&
      !user.emailVerifiedAt &&
      (!user.emailVerificationSentAt ||
        Date.now() - user.emailVerificationSentAt.getTime() >=
          this.resendCooldownMs)
    ) {
      await this.sendVerificationEmail(user);
    }
    return { ok: true };
  }

  async forgotPassword(email: string): Promise<{ ok: true }> {
    const user = await this.usersService.findByEmailForEmailFlow(email);
    if (
      user?.emailVerifiedAt &&
      (!user.passwordResetSentAt ||
        Date.now() - user.passwordResetSentAt.getTime() >=
          this.resendCooldownMs)
    ) {
      const token = randomBytes(32).toString('base64url');
      await this.usersService.setPasswordResetToken(
        user.id,
        this.hashToken(token),
        new Date(Date.now() + this.tokenTtlMs),
      );
      const resetUrl = `${this.landingUrl()}/account/reset-password#token=${encodeURIComponent(token)}`;
      const content = this.emails.renderBranded({
        eyebrow: 'Sécurité du compte',
        title: 'Réinitialisez votre mot de passe.',
        intro:
          'Une demande de nouveau mot de passe a été reçue pour votre compte iooeh.',
        actionLabel: 'Choisir un nouveau mot de passe',
        actionUrl: resetUrl,
        notice:
          'Ce lien expire dans 30 minutes et ne fonctionne qu’une fois. Si vous n’avez rien demandé, ignorez cet email.',
      });
      await this.emails.send({
        to: user.email,
        toName: user.name ?? undefined,
        subject: 'Réinitialisez votre mot de passe iooeh',
        tag: 'password-reset',
        idempotencyKey: randomUUID(),
        ...content,
      });
    }
    return { ok: true };
  }

  async resetPassword(token: string, password: string): Promise<{ ok: true }> {
    const user = await this.usersService.findByPasswordResetToken(
      this.hashToken(token),
    );
    if (!user) {
      throw new BadRequestException('Ce lien est invalide ou a expiré.');
    }
    await this.usersService.resetPassword(user.id, password);
    await this.safeSend({
      to: user.email,
      toName: user.name ?? undefined,
      subject: 'Votre mot de passe iooeh a été modifié',
      tag: 'password-changed',
      content: {
        eyebrow: 'Sécurité du compte',
        title: 'Mot de passe modifié.',
        intro:
          'Votre nouveau mot de passe est actif. Si vous n’êtes pas à l’origine de cette modification, contactez immédiatement le support iooeh.',
        actionLabel: 'Se connecter',
        actionUrl: this.appUrl(),
      },
    });
    return { ok: true };
  }

  async deleteAccount(userId: number, password: string): Promise<void> {
    await this.usersService.deleteAccount(userId, password);
  }

  private async sendVerificationEmail(user: User): Promise<void> {
    const token = randomBytes(32).toString('base64url');
    await this.usersService.setEmailVerificationToken(
      user.id,
      this.hashToken(token),
      new Date(Date.now() + this.tokenTtlMs),
    );
    const verificationUrl = `${this.landingUrl()}/account/verify#token=${encodeURIComponent(token)}`;
    const content = this.emails.renderBranded({
      eyebrow: 'Activation du compte',
      title: 'Confirmez votre adresse email.',
      intro:
        'Ce dernier clic sécurise votre inscription et confirme que cette adresse vous appartient.',
      actionLabel: 'Activer mon compte',
      actionUrl: verificationUrl,
      notice:
        'Ce lien expire dans 30 minutes. Si vous n’êtes pas à l’origine de cette inscription, ignorez cet email.',
    });
    await this.emails.send({
      to: user.email,
      toName: user.name ?? undefined,
      subject: 'Activez votre compte iooeh',
      tag: 'account-verification',
      idempotencyKey: randomUUID(),
      ...content,
    });
  }

  private async sendLoginEmail(
    user: User,
    context: LoginContext,
  ): Promise<void> {
    const details = [
      {
        label: 'Date',
        value: new Intl.DateTimeFormat('fr-FR', {
          dateStyle: 'long',
          timeStyle: 'short',
          timeZone: 'Indian/Antananarivo',
        }).format(new Date()),
      },
    ];
    if (context.ip) details.push({ label: 'Adresse IP', value: context.ip });
    if (context.userAgent) {
      details.push({
        label: 'Appareil',
        value: context.userAgent.slice(0, 100),
      });
    }
    await this.safeSend({
      to: user.email,
      toName: user.name ?? undefined,
      subject: 'Nouvelle connexion à votre compte iooeh',
      tag: 'account-login',
      content: {
        eyebrow: 'Sécurité du compte',
        title: 'Nouvelle connexion détectée.',
        intro:
          'Une connexion réussie vient d’avoir lieu sur votre compte iooeh.',
        details,
        notice:
          'Si vous ne reconnaissez pas cette activité, réinitialisez immédiatement votre mot de passe.',
      },
    });
  }

  private async safeSend(input: {
    to: string;
    toName?: string;
    subject: string;
    tag: string;
    content: Parameters<BrevoEmailService['renderBranded']>[0];
  }): Promise<void> {
    try {
      await this.emails.send({
        to: input.to,
        toName: input.toName,
        subject: input.subject,
        tag: input.tag,
        idempotencyKey: randomUUID(),
        ...this.emails.renderBranded(input.content),
      });
    } catch (error) {
      this.logger.error(
        `Email ${input.tag} non envoyé à ${input.to}`,
        error instanceof Error ? error.stack : undefined,
      );
    }
  }

  private hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private landingUrl(): string {
    return (process.env.PUBLIC_LANDING_URL ?? 'https://iooeh.com').replace(
      /\/$/,
      '',
    );
  }

  private appUrl(): string {
    return (process.env.PUBLIC_APP_URL ?? 'https://app.iooeh.com').replace(
      /\/$/,
      '',
    );
  }

  private buildResponse(user: User): AuthResponse {
    const payload: JwtPayload = {
      sub: user.id,
      email: user.email,
      role: user.role,
    };

    return {
      access_token: this.jwtService.sign(payload),
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phone: user.phone,
        role: user.role,
      },
    };
  }
}
