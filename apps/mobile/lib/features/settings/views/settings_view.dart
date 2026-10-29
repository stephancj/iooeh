import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_version.dart';
import '../../../core/navigation/trackeo_route.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/product_ui.dart';
import '../../auth/providers/auth_provider.dart';
import '../../entitlements/models/entitlements_model.dart';
import '../../entitlements/providers/entitlements_provider.dart';
import '../../payments/views/payments_view.dart';
import '../../vehicles/providers/vehicles_provider.dart';
import '../../vehicles/views/add_vehicle_view.dart';
import '../../promotions/redeem_dialog.dart';
import '../../promotions/referral_view.dart';
import 'alert_settings_view.dart';
import 'delete_account_view.dart';
import '../../../core/layout/responsive_layout.dart';

enum SettingsSection { profile, alerts, payments, referral, deleteAccount }

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _isEditing = false;
  bool _isSaving = false;
  SettingsSection _activeSection = SettingsSection.profile;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _cancelEdit() {
    final user = ref.read(authProvider).user;
    _nameController.text = user?.name ?? '';
    _phoneController.text = user?.phone ?? '';
    setState(() => _isEditing = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(authProvider.notifier).updateProfile(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );
      if (!mounted) return;
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Profil mis à jour.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de sauvegarder. Réessayez.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.statusAlert,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildProfileContent(BuildContext context, {required bool isDesktop}) {
    final user = ref.watch(authProvider).user;
    final displayName = user?.displayName ?? '';
    final rightsAsync = ref.watch(entitlementsProvider);
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final rights = rightsAsync.valueOrNull;
    final disabledAlerts = user == null ||
            !ref.watch(authProvider).userDetailsLoaded ||
            rights == null ||
            !user.alertsEnabled
        ? null
        : <bool>[
            if (rights.has('low_battery_alerts')) user.alertLowBattery,
            if (rights.has('speed_alerts')) user.alertSpeedLimit,
            if (rights.has('push_notifications')) user.alertViaPush,
            if (rights.has('whatsapp_notifications')) user.alertViaWhatsapp,
            user.alertViaEmail,
          ].where((enabled) => !enabled).length;

    return SingleChildScrollView(
      child: ProductPage(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileSurface(
                displayName: displayName,
                email: user?.email ?? '',
                phone: user?.phone,
                editing: _isEditing,
                saving: _isSaving,
                nameController: _nameController,
                phoneController: _phoneController,
                onSave: _saveProfile,
              ),
              const SizedBox(height: 24),
              const ProductSectionHeader(
                title: 'Votre protection',
                subtitle: 'Plan actuel et services essentiels.',
              ),
              const SizedBox(height: 10),
              vehiclesAsync.when(
                data: (vehicles) => vehicles.isEmpty
                    ? ProductSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Votre véhicule n’est pas encore protégé',
                                style: AppTextStyles.cardTitle),
                            const SizedBox(height: 8),
                            Text('Ajoutez votre véhicule pour commencer.',
                                style: AppTextStyles.bodySecondary),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => Navigator.push(
                                  context,
                                  TrackeoRoute(
                                      builder: (_) => const AddVehicleView())),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Ajouter mon véhicule'),
                            ),
                          ],
                        ),
                      )
                    : rightsAsync.when(
                        data: (rights) => _PlanSurface(
                          rights: rights,
                          onTap: () => Navigator.push(
                            context,
                            TrackeoRoute(builder: (_) => const PaymentsView()),
                          ),
                        ),
                        loading: () => const ProductSurface(
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                        error: (_, __) => _SettingsTile(
                          icon: Icons.workspace_premium_outlined,
                          title: 'Abonnement',
                          subtitle: 'Consulter les plans disponibles',
                          onTap: () => Navigator.push(
                            context,
                            TrackeoRoute(builder: (_) => const PaymentsView()),
                          ),
                        ),
                      ),
                loading: () => const ProductSurface(
                    child: LinearProgressIndicator(minHeight: 2)),
                error: (_, __) => _SettingsTile(
                  icon: Icons.cloud_off_outlined,
                  title: 'Véhicules indisponibles',
                  subtitle: 'Appuyez pour réessayer',
                  onTap: () => ref.invalidate(vehiclesProvider),
                ),
              ),
              const SizedBox(height: 24),
              if ((rightsAsync.valueOrNull?.has('referral_program') ?? true) ||
                  (rightsAsync.valueOrNull?.has('coupon_redemption') ??
                      true)) ...[
                const ProductSectionHeader(
                  title: 'Promotions & Avantages',
                  subtitle: 'Parrainez des amis ou utilisez un code promo.',
                ),
                const SizedBox(height: 10),
                ProductSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (rightsAsync.valueOrNull?.has('referral_program') ??
                          true)
                        _SettingsTile(
                          icon: Icons.card_giftcard_rounded,
                          title: 'Parrainer un ami',
                          subtitle: 'Offrez 20% & gagnez 1 mois gratuit',
                          onTap: () => ReferralView.navigateTo(context),
                        ),
                      if ((rightsAsync.valueOrNull?.has('referral_program') ??
                              true) &&
                          (rightsAsync.valueOrNull?.has('coupon_redemption') ??
                              true))
                        const Divider(height: 1, indent: 68),
                      if (rightsAsync.valueOrNull?.has('coupon_redemption') ??
                          true)
                        _SettingsTile(
                          icon: Icons.confirmation_number_outlined,
                          title: 'Utiliser un code promo',
                          subtitle: 'Débloquez vos réductions et avantages',
                          onTap: () => RedeemDialog.show(context),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const ProductSectionHeader(
                title: 'Préférences',
                subtitle: 'Contrôlez la façon dont ioeh vous prévient.',
              ),
              const SizedBox(height: 10),
              ProductSurface(
                padding: EdgeInsets.zero,
                child: _SettingsTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notifications et alertes',
                  subtitle: user != null &&
                          ref.watch(authProvider).userDetailsLoaded &&
                          !user.alertsEnabled
                      ? 'Alertes désactivées'
                      : 'Push, WhatsApp et sécurité',
                  badge: user != null &&
                          ref.watch(authProvider).userDetailsLoaded &&
                          !user.alertsEnabled
                      ? 'Désactivées'
                      : disabledAlerts != null && disabledAlerts > 0
                          ? '$disabledAlerts désactivée${disabledAlerts > 1 ? 's' : ''}'
                          : null,
                  onTap: () => Navigator.push(
                    context,
                    TrackeoRoute(builder: (_) => const AlertSettingsView()),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const ProductSectionHeader(title: 'Aide'),
              const SizedBox(height: 10),
              ProductSurface(
                padding: EdgeInsets.zero,
                child: _SettingsTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Besoin d’aide ?',
                  subtitle: 'Écrivez-nous',
                  onTap: () async {
                    final opened = await launchUrl(
                        Uri(scheme: 'mailto', path: 'contact@iooeh.com'));
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Écrivez-nous à contact@iooeh.com')));
                    }
                  },
                ),
              ),
              const SizedBox(height: 24),
              const ProductSectionHeader(title: 'Compte'),
              const SizedBox(height: 10),
              ProductSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.delete_outline_rounded,
                      iconColor: AppColors.statusAlert,
                      iconBackground: AppColors.pastelRed,
                      title: 'Supprimer mon compte',
                      subtitle:
                          'Effacer définitivement le compte et ses données',
                      onTap: () => Navigator.push(
                        context,
                        TrackeoRoute(builder: (_) => const DeleteAccountView()),
                      ),
                    ),
                    const Divider(height: 1, indent: 68),
                    _SettingsTile(
                      icon: Icons.logout_rounded,
                      iconColor: AppColors.statusAlert,
                      iconBackground: AppColors.pastelRed,
                      title: 'Se déconnecter',
                      onTap: _showLogoutDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Text(
                  'iooeh · Version $kAppVersion',
                  style: AppTextStyles.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobileLayout = Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Réglages'),
        actions: [
          TextButton(
            onPressed: _isEditing
                ? _cancelEdit
                : () => setState(() => _isEditing = true),
            child: Text(_isEditing ? 'Annuler' : 'Modifier'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildProfileContent(context, isDesktop: false),
    );

    Widget activePanel;
    switch (_activeSection) {
      case SettingsSection.profile:
        activePanel = _buildProfileContent(context, isDesktop: true);
        break;
      case SettingsSection.alerts:
        activePanel = const AlertSettingsView(isDesktopPanel: true);
        break;
      case SettingsSection.payments:
        activePanel = const PaymentsView(isDesktopPanel: true);
        break;
      case SettingsSection.referral:
        activePanel = const ReferralView(isDesktopPanel: true);
        break;
      case SettingsSection.deleteAccount:
        activePanel = const DeleteAccountView(isDesktopPanel: true);
        break;
    }

    final desktopLayout = Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320,
            child: _SettingsSidebar(
              activeSection: _activeSection,
              onSectionChanged: (s) => setState(() {
                _activeSection = s;
                _isEditing = false;
              }),
            ),
          ),
          const VerticalDivider(
              width: 1, thickness: 1, color: AppColors.divider),
          Expanded(child: activePanel),
        ],
      ),
    );

    return ResponsiveLayout(
      mobile: mobileLayout,
      desktop: desktopLayout,
    );
  }

  void _showLogoutDialog() {
    showAdaptiveDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Vous devrez saisir vos identifiants pour accéder à nouveau à vos véhicules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Rester connecté'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await ref.read(authProvider.notifier).logout();
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Impossible de se déconnecter. Réessayez.'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.statusAlert,
                ));
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.statusAlert),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
  }
}

class _ProfileSurface extends StatelessWidget {
  final String displayName;
  final String email;
  final String? phone;
  final bool editing;
  final bool saving;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final VoidCallback onSave;

  const _ProfileSurface({
    required this.displayName,
    required this.email,
    required this.phone,
    required this.editing,
    required this.saving,
    required this.nameController,
    required this.phoneController,
    required this.onSave,
  });

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => ProductSurface(
        padding: const EdgeInsets.all(20),
        child: AnimatedSize(
          duration: AppMotion.base,
          curve: AppMotion.quint,
          child: editing ? _editForm() : _summary(),
        ),
      );

  Widget _summary() => Row(
        children: [
          CircleAvatar(
            radius: 29,
            backgroundColor: AppColors.primaryDark,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: AppTextStyles.sectionTitle),
                const SizedBox(height: 3),
                Text(email, style: AppTextStyles.bodySecondary),
                if (phone?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(phone!, style: AppTextStyles.label),
                ],
              ],
            ),
          ),
          const Icon(Icons.edit_outlined, color: AppColors.textHint, size: 18),
        ],
      );

  Widget _editForm() => Column(
        children: [
          TextFormField(
            controller: nameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nom affiché',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Téléphone WhatsApp',
              hintText: '+261 34 12 345 67',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (value) {
              if (value != null &&
                  value.isNotEmpty &&
                  !value.startsWith('+') &&
                  !value.startsWith('0')) {
                return 'Utilisez un numéro local ou le format +261.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(saving ? 'Enregistrement…' : 'Enregistrer'),
            ),
          ),
        ],
      );
}

class _PlanSurface extends StatelessWidget {
  final Entitlements rights;
  final VoidCallback onTap;

  const _PlanSurface({required this.rights, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final remaining = rights.trialEndsAt?.difference(DateTime.now());
    final days =
        remaining == null ? null : (remaining.inSeconds / 86400).ceil();
    final trial = rights.status == 'trial' && days != null
        ? days > 0
            ? 'Essai gratuit · $days jour${days > 1 ? 's' : ''} restant${days > 1 ? 's' : ''}'
            : 'Essai expiré'
        : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ProductSurface(
        borderColor: AppColors.primary.withValues(alpha: .35),
        child: Row(
          children: [
            const ProductIcon(icon: Icons.workspace_premium_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Abonnement du compte',
                          style: AppTextStyles.cardTitle,
                        ),
                      ),
                      _StatusPill(
                        status: rights.status == 'trial' &&
                                days != null &&
                                days <= 0
                            ? 'expired'
                            : rights.status,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    trial ?? 'Plan ${rights.planName}',
                    style: AppTextStyles.bodySecondary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'active' => 'Actif',
      'trial' => 'Essai',
      'suspended' => 'Suspendu',
      'expired' => 'Expiré',
      'cancelled' => 'Annulé',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.pastelGreen,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    this.iconColor = AppColors.primaryDark,
    this.iconBackground = AppColors.pastelGreen,
    required this.title,
    this.subtitle,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              ProductIcon(
                icon: icon,
                color: iconColor,
                background: iconBackground,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(title, style: AppTextStyles.cardTitle),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.statusAlert.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Text(badge!,
                                style: AppTextStyles.label.copyWith(
                                    color: AppColors.statusAlert,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: AppTextStyles.bodySecondary),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textHint),
            ],
          ),
        ),
      );
}

class _SettingsSidebar extends StatelessWidget {
  final SettingsSection activeSection;
  final ValueChanged<SettingsSection> onSectionChanged;

  const _SettingsSidebar({
    required this.activeSection,
    required this.onSectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, bottom: 24),
          child: Text('Réglages', style: AppTextStyles.pageTitleLarge),
        ),
        _SidebarItem(
          icon: Icons.person_outline,
          activeIcon: Icons.person,
          label: 'Profil',
          isActive: activeSection == SettingsSection.profile,
          onTap: () => onSectionChanged(SettingsSection.profile),
        ),
        _SidebarItem(
          icon: Icons.notifications_none,
          activeIcon: Icons.notifications,
          label: 'Alertes',
          isActive: activeSection == SettingsSection.alerts,
          onTap: () => onSectionChanged(SettingsSection.alerts),
        ),
        _SidebarItem(
          icon: Icons.workspace_premium_outlined,
          activeIcon: Icons.workspace_premium,
          label: 'Abonnement',
          isActive: activeSection == SettingsSection.payments,
          onTap: () => onSectionChanged(SettingsSection.payments),
        ),
        _SidebarItem(
          icon: Icons.card_giftcard_outlined,
          activeIcon: Icons.card_giftcard,
          label: 'Parrainage',
          isActive: activeSection == SettingsSection.referral,
          onTap: () => onSectionChanged(SettingsSection.referral),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(),
        ),
        _SidebarItem(
          icon: Icons.delete_outline,
          activeIcon: Icons.delete,
          label: 'Supprimer mon compte',
          isActive: activeSection == SettingsSection.deleteAccount,
          onTap: () => onSectionChanged(SettingsSection.deleteAccount),
          isDestructive: true,
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SidebarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? AppColors.statusAlert
        : (isActive ? AppColors.primaryDark : AppColors.textPrimary);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? (isDestructive
                    ? AppColors.statusAlert.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.1))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isDestructive
                    ? AppColors.statusAlert
                    : (isActive ? AppColors.primaryDark : AppColors.textHint),
                size: 22,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
