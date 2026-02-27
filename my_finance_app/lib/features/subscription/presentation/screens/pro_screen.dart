import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/subscription_provider.dart';
import '../widgets/pro_badge_widget.dart';

const _kGreen = Color(0xFF00D887);
const _kGreenDark = Color(0xFF00A86B);

class ProScreen extends ConsumerWidget {
  const ProScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    final subscription = ref.watch(subscriptionStreamProvider).value;
    final iapState = ref.watch(iapNotifierProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // ── AppBar ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: _kGreenDark,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kGreen, _kGreenDark],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'My Finance Pro',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Desbloqueie todo o potencial',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
            sliver: SliverList.list(
              children: [
                // ── Plano ativo ──────────────────────────────────────────
                if (isPro && subscription != null) ...[
                  _ActivePlanCard(subscription: subscription),
                  const SizedBox(height: 16),
                ],

                // ── Funcionalidades Pro ──────────────────────────────────
                const _FeaturesCard(),
                const SizedBox(height: 20),

                // ── Planos de preço ──────────────────────────────────────
                if (!isPro) ...[
                  Text(
                    'Escolha seu plano',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  // Mensal
                  _PriceCard(
                    planName: 'Mensal',
                    price: 'R\$ 5,00',
                    period: '/mês',
                    detail: 'Renovação automática mensal',
                    isHighlighted: false,
                    isLoading: iapState.isLoading,
                    onTap: () =>
                        ref.read(iapNotifierProvider.notifier).buyMonthly(),
                  ),
                  const SizedBox(height: 10),

                  // Anual (destaque)
                  _PriceCard(
                    planName: 'Anual',
                    price: 'R\$ 50,00',
                    period: '/ano',
                    detail: '≈ R\$ 4,17/mês · Economize R\$ 10',
                    savings: 'MAIS POPULAR',
                    isHighlighted: true,
                    isLoading: iapState.isLoading,
                    onTap: () =>
                        ref.read(iapNotifierProvider.notifier).buyAnnual(),
                  ),
                  const SizedBox(height: 10),

                  // Vitalício
                  _PriceCard(
                    planName: 'Vitalício',
                    price: 'R\$ 120,00',
                    period: '',
                    detail: 'Pagamento único · Acesso para sempre',
                    isHighlighted: false,
                    isLoading: iapState.isLoading,
                    buttonLabel: 'Comprar',
                    onTap: () =>
                        ref.read(iapNotifierProvider.notifier).buyLifetime(),
                  ),
                  const SizedBox(height: 20),

                  // Erro do IAP
                  if (iapState.errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              iapState.errorMessage!,
                              style: TextStyle(
                                  color: Colors.red.shade700, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (iapState.errorMessage != null)
                    const SizedBox(height: 12),

                  // Restaurar compras
                  Center(
                    child: TextButton.icon(
                      onPressed: iapState.isLoading
                          ? null
                          : () => ref
                              .read(iapNotifierProvider.notifier)
                              .restorePurchases(),
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text('Restaurar compras anteriores'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Nota legal
                  Text(
                    'O pagamento é processado pela Google Play Store / App Store. '
                    'As assinaturas renovam automaticamente. '
                    'Cancele a qualquer momento nas configurações da loja.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                // ── Já é pro ─────────────────────────────────────────────
                if (isPro) ...[
                  Center(
                    child: Column(
                      children: [
                        const ProBadgeWidget(),
                        const SizedBox(height: 8),
                        Text(
                          'Você tem acesso completo a todos os recursos!',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de plano ativo
// ─────────────────────────────────────────────────────────────────────────────

class _ActivePlanCard extends StatelessWidget {
  final dynamic subscription;
  const _ActivePlanCard({required this.subscription});

  String _planName() {
    switch (subscription.type.name) {
      case 'monthly':
        return 'Pro Mensal';
      case 'annual':
        return 'Pro Anual';
      case 'lifetime':
        return 'Pro Vitalício';
      default:
        return 'Pro';
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiry = subscription.expiryDate as DateTime?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: _kGreen, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Plano ativo: ',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      _planName(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _kGreenDark,
                          ),
                    ),
                  ],
                ),
                if (expiry != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Renova em ${DateFormat('dd/MM/yyyy').format(expiry)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                        ),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    'Acesso vitalício',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _kGreen,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de funcionalidades
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturesCard extends StatelessWidget {
  const _FeaturesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'O que você ganha com o Pro:',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            const _FeatureRow(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Múltiplas carteiras',
              description: 'Crie quantas carteiras quiser',
            ),
            const _FeatureRow(
              icon: Icons.category_rounded,
              title: 'Categorias personalizadas',
              description: 'Categorias ilimitadas do seu jeito',
            ),
            const _FeatureRow(
              icon: Icons.calendar_month_rounded,
              title: 'Visão anual',
              description: 'Analise o ano inteiro de uma vez',
            ),
            const _FeatureRow(
              icon: Icons.people_rounded,
              title: 'Compartilhamento',
              description: 'Convide colaboradores para gerenciar juntos',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isLast;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: _kGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, size: 18, color: _kGreen),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de preço
// ─────────────────────────────────────────────────────────────────────────────

class _PriceCard extends StatelessWidget {
  final String planName;
  final String price;
  final String period;
  final String detail;
  final String? savings;
  final bool isHighlighted;
  final bool isLoading;
  final String buttonLabel;
  final VoidCallback onTap;

  const _PriceCard({
    required this.planName,
    required this.price,
    required this.period,
    required this.detail,
    this.savings,
    required this.isHighlighted,
    required this.isLoading,
    this.buttonLabel = 'Assinar',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Card(
          margin: EdgeInsets.zero,
          elevation: isHighlighted ? 3 : 0,
          color: isHighlighted
              ? _kGreen.withValues(alpha: 0.07)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isHighlighted
                ? const BorderSide(color: _kGreen, width: 1.5)
                : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              children: [
                // Conteúdo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        planName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isHighlighted
                              ? _kGreenDark
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: price,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: isHighlighted
                                    ? _kGreenDark
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (period.isNotEmpty)
                              TextSpan(
                                text: period,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Botão
                FilledButton(
                  onPressed: isLoading ? null : onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(buttonLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),

        // Banner "MAIS POPULAR"
        if (savings != null)
          Positioned(
            top: -10,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                savings!,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
