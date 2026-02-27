import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/providers/effective_user_provider.dart';
import '../../../../core/utils/category_icons.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/presentation/providers/categories_provider.dart';
import '../../../sharing/presentation/providers/sharing_provider.dart';
import '../../../wallets/domain/entities/wallet_entity.dart';
import '../../../wallets/presentation/providers/wallets_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared palette & helpers
// ─────────────────────────────────────────────────────────────────────────────

const _kColorPalette = [
  0xFF1976D2, // blue
  0xFF303F9F, // indigo
  0xFF00796B, // teal
  0xFF388E3C, // green
  0xFF558B2F, // light green
  0xFFE64A19, // deep orange
  0xFFC62828, // red
  0xFFAD1457, // pink
  0xFF6A1B9A, // purple
  0xFF5D4037, // brown
  0xFF0288D1, // light blue
  0xFF616161, // grey
];

class _ColorDots extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _ColorDots({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _kColorPalette.map((c) {
        final isSelected = c == selected;
        return GestureDetector(
          onTap: () => onSelected(c),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 2.5)
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: Color(c).withValues(alpha: 0.5),
                          blurRadius: 6)
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

class _IconPickerGrid extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _IconPickerGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final entries = kCategoryIconMap.entries.toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final codePoint = entries[i].key;
        final iconData = entries[i].value;
        final isSelected = codePoint == selected;
        return GestureDetector(
          onTap: () => onSelected(codePoint),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary, width: 2)
                  : null,
            ),
            child: Icon(iconData,
                size: 22,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout helpers
// ─────────────────────────────────────────────────────────────────────────────

const _kBlue = Color(0xFF1E88E5);
const _kDarkBlue = Color(0xFF0D47A1);

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge(this.icon, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).value;
    final settings = ref.watch(appSettingsProvider);
    final incomeCategories = ref.watch(incomeCategoriesProvider);
    final expenseCategories = ref.watch(expenseCategoriesProvider);

    final displayName = user?.displayName ?? '';
    final email = user?.email ?? '';
    final initials = _initials(user?.displayName ?? user?.email ?? '?');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Gradient profile header ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 176,
            pinned: true,
            backgroundColor: _kDarkBlue,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                l10n.settings,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kDarkBlue, _kBlue],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 48),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.22),
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName.isNotEmpty
                                    ? displayName
                                    : l10n.noName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white),
                          tooltip: l10n.editProfile,
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) =>
                                _EditProfileDialog(currentName: displayName),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Settings body ────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            sliver: SliverList.list(
              children: [
                // Account
                _SettingsCard(children: [
                  ListTile(
                    leading: const _IconBadge(Icons.lock_outline,
                        color: Color(0xFF5C6BC0)),
                    title: Text(l10n.changePassword),
                    trailing:
                        const Icon(Icons.chevron_right, size: 20),
                    onTap: () =>
                        _showChangePasswordDialog(context, ref),
                  ),
                ]),
                const SizedBox(height: 12),

                // Preferences
                _SettingsCard(children: [
                  ListTile(
                    leading: const _IconBadge(Icons.currency_exchange_outlined,
                        color: Color(0xFF26A69A)),
                    title: Text(l10n.currency),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(settings.currency.label,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    onTap: () =>
                        _showCurrencyDialog(context, ref, l10n),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const _IconBadge(Icons.language_outlined,
                        color: Color(0xFF42A5F5)),
                    title: Text(l10n.language),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(settings.language.nativeLabel,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    onTap: () =>
                        _showLanguageDialog(context, ref, l10n),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const _IconBadge(Icons.brightness_6_outlined,
                        color: Color(0xFFFFA726)),
                    title: Text(l10n.appearance),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_themeModeLabel(settings.themeMode, l10n),
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    onTap: () =>
                        _showAppearanceDialog(context, ref, l10n),
                  ),
                ]),
                const SizedBox(height: 12),

                // Data
                _SettingsCard(children: [
                  const _WalletSection(),
                  const Divider(height: 1, indent: 16),
                  _CategorySection(
                    title: l10n.expenseCategories,
                    type: CategoryType.expense,
                    categories: expenseCategories,
                  ),
                  const Divider(height: 1, indent: 16),
                  _CategorySection(
                    title: l10n.incomeCategories,
                    type: CategoryType.income,
                    categories: incomeCategories,
                  ),
                ]),
                const SizedBox(height: 12),

                // Sharing
                const _SharingSection(),
                const SizedBox(height: 12),

                // Logout
                _SettingsCard(children: [
                  ListTile(
                    leading: _IconBadge(Icons.logout,
                        color: Colors.red.shade400),
                    title: Text(l10n.logout,
                        style:
                            TextStyle(color: Colors.red.shade600)),
                    onTap: () => ref
                        .read(authNotifierProvider.notifier)
                        .signOut(),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    showDialog(
        context: context, builder: (_) => const _ChangePasswordDialog());
  }

  void _showCurrencyDialog(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showDialog(
        context: context, builder: (ctx) => _CurrencyDialog(l10n: l10n));
  }

  void _showLanguageDialog(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showDialog(
        context: context, builder: (ctx) => _LanguageDialog(l10n: l10n));
  }

  void _showAppearanceDialog(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showDialog(
        context: context, builder: (ctx) => _AppearanceDialog(l10n: l10n));
  }

  String _themeModeLabel(AppThemeMode mode, AppLocalizations l10n) {
    switch (mode) {
      case AppThemeMode.system:
        return l10n.themeModeSystem;
      case AppThemeMode.light:
        return l10n.themeModeLight;
      case AppThemeMode.dark:
        return l10n.themeModeDark;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Currency Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CurrencyDialog extends ConsumerWidget {
  final AppLocalizations l10n;
  const _CurrencyDialog({required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appSettingsProvider).currency;
    return AlertDialog(
      title: Text(l10n.currencyTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 320,
        child: RadioGroup<AppCurrency>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) {
              ref.read(appSettingsProvider.notifier).setCurrency(v);
              Navigator.of(context).pop();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppCurrency.values
                .map((currency) => RadioListTile<AppCurrency>(
                      value: currency,
                      title: Text(currency.label),
                      subtitle: Text(currency.symbol,
                          style: TextStyle(color: Colors.grey.shade600)),
                    ))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Language Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _LanguageDialog extends ConsumerWidget {
  final AppLocalizations l10n;
  const _LanguageDialog({required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appSettingsProvider).language;
    return AlertDialog(
      title: Text(l10n.languageTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 320,
        child: RadioGroup<AppLanguage>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) {
              ref.read(appSettingsProvider.notifier).setLanguage(v);
              Navigator.of(context).pop();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppLanguage.values
                .map((lang) => RadioListTile<AppLanguage>(
                      value: lang,
                      title: Text(lang.nativeLabel),
                      subtitle: Text(lang.label,
                          style: TextStyle(color: Colors.grey.shade600)),
                    ))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Profile Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _EditProfileDialog extends ConsumerStatefulWidget {
  final String currentName;
  const _EditProfileDialog({required this.currentName});

  @override
  ConsumerState<_EditProfileDialog> createState() =>
      _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<_EditProfileDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final success = await ref
        .read(authNotifierProvider.notifier)
        .updateProfile(displayName: name);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      final err = ref.read(authNotifierProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? 'Erro ao atualizar perfil.'),
          backgroundColor: Colors.red.shade700));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(authNotifierProvider).isLoading;
    return AlertDialog(
      title: Text(l10n.editProfile),
      content: TextField(
        controller: _nameController,
        decoration: InputDecoration(
            labelText: l10n.nameField, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Change Password Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPwController = TextEditingController();
  final _newPwController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  @override
  void dispose() {
    _currentPwController.dispose();
    _newPwController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await ref
        .read(authNotifierProvider.notifier)
        .updatePassword(_currentPwController.text, _newPwController.text);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).passwordChanged)));
    } else {
      final err = ref.read(authNotifierProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? 'Erro ao alterar senha.'),
          backgroundColor: Colors.red.shade700));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(authNotifierProvider).isLoading;
    return AlertDialog(
      title: Text(l10n.changePassword),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentPwController,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: l10n.currentPassword,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureCurrent
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? l10n.enterCurrentPassword : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPwController,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: l10n.newPassword,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return l10n.enterNewPassword;
                  if (v.length < 6) return l10n.minChars;
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Section
// ─────────────────────────────────────────────────────────────────────────────

class _CategorySection extends ConsumerWidget {
  final String title;
  final CategoryType type;
  final List<CategoryEntity> categories;

  const _CategorySection({
    required this.title,
    required this.type,
    required this.categories,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ExpansionTile(
      title:
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      children: [
        ...categories.map(
          (cat) => ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(cat.colorValue).withValues(alpha: 0.15),
              child: Icon(categoryIcon(cat.iconCodePoint),
                  color: Color(cat.colorValue), size: 20),
            ),
            title: Text(cat.name),
            trailing: cat.isDefault
                ? Tooltip(
                    message: l10n.defaultCategory,
                    child: const Icon(Icons.lock_outline,
                        size: 16, color: Colors.grey),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) =>
                              _EditCategoryDialog(category: cat),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red.shade400, size: 20),
                        onPressed: () => ref
                            .read(categoriesNotifierProvider.notifier)
                            .delete(cat.id),
                      ),
                    ],
                  ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(type == CategoryType.expense
              ? l10n.addExpenseCategory
              : l10n.addIncomeCategory),
          onTap: () => showDialog(
            context: context,
            builder: (_) => _AddCategoryDialog(type: type),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Category Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddCategoryDialog extends ConsumerStatefulWidget {
  final CategoryType type;
  const _AddCategoryDialog({required this.type});

  @override
  ConsumerState<_AddCategoryDialog> createState() =>
      _AddCategoryDialogState();
}

class _AddCategoryDialogState extends ConsumerState<_AddCategoryDialog> {
  final _nameController = TextEditingController();
  int _iconCodePoint = 0xe574; // Icons.category
  int _colorValue = 0xFF616161;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    final success = await ref.read(categoriesNotifierProvider.notifier).add(
          userId: user.id,
          name: name,
          type: widget.type,
          iconCodePoint: _iconCodePoint,
          colorValue: _colorValue,
        );
    if (!mounted) return;
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(categoriesNotifierProvider).isLoading;
    final typeLabel =
        widget.type == CategoryType.expense ? l10n.expense : l10n.incomeType;
    return AlertDialog(
      title: Text('${l10n.newCategoryTitle} – $typeLabel'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                  labelText: l10n.categoryName,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text(l10n.selectIcon,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _IconPickerGrid(
                selected: _iconCodePoint,
                onSelected: (v) => setState(() => _iconCodePoint = v)),
            const SizedBox(height: 16),
            Text(l10n.selectColor,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _ColorDots(
                selected: _colorValue,
                onSelected: (v) => setState(() => _colorValue = v)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Category Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _EditCategoryDialog extends ConsumerStatefulWidget {
  final CategoryEntity category;
  const _EditCategoryDialog({required this.category});

  @override
  ConsumerState<_EditCategoryDialog> createState() =>
      _EditCategoryDialogState();
}

class _EditCategoryDialogState extends ConsumerState<_EditCategoryDialog> {
  late final TextEditingController _nameController;
  late int _iconCodePoint;
  late int _colorValue;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _iconCodePoint = widget.category.iconCodePoint;
    _colorValue = widget.category.colorValue;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final updated = CategoryEntity(
      id: widget.category.id,
      userId: widget.category.userId,
      name: name,
      type: widget.category.type,
      iconCodePoint: _iconCodePoint,
      colorValue: _colorValue,
      isDefault: widget.category.isDefault,
    );
    final success = await ref
        .read(categoriesNotifierProvider.notifier)
        .update(updated);
    if (!mounted) return;
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(categoriesNotifierProvider).isLoading;
    return AlertDialog(
      title: Text(l10n.editCategory),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                  labelText: l10n.categoryName,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text(l10n.selectIcon,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _IconPickerGrid(
                selected: _iconCodePoint,
                onSelected: (v) => setState(() => _iconCodePoint = v)),
            const SizedBox(height: 16),
            Text(l10n.selectColor,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _ColorDots(
                selected: _colorValue,
                onSelected: (v) => setState(() => _colorValue = v)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sharing Section
// ─────────────────────────────────────────────────────────────────────────────

class _SharingSection extends ConsumerStatefulWidget {
  const _SharingSection();

  @override
  ConsumerState<_SharingSection> createState() => _SharingSectionState();
}

class _SharingSectionState extends ConsumerState<_SharingSection> {
  final _emailCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendInvite() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _sending = true);
    final error = await ref
        .read(sharingNotifierProvider.notifier)
        .sendInvitation(email);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error == null) {
      _emailCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite enviado com sucesso!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sair da conta compartilhada'),
        content: const Text(
            'Você perderá acesso aos dados desta conta. Deseja continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await ref
        .read(sharingNotifierProvider.notifier)
        .leaveSharedAccount();
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMaster = ref.watch(isMasterProvider);
    final pendingAsync = ref.watch(pendingInvitationsProvider);
    final collaboratorsAsync = ref.watch(myCollaboratorsProvider);
    final pendingInvites = pendingAsync.value ?? [];
    final collaborators = collaboratorsAsync.value ?? [];
    final profileAsync = ref.watch(userProfileStreamProvider);
    final profile = profileAsync.value;

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Pending received invitations (amber banner) ──────────────────
        if (pendingInvites.isNotEmpty) ...[
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.amber.shade600.withValues(alpha: 0.6),
                  width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline,
                          color: Colors.amber.shade700, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Convites recebidos',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                ...pendingInvites.map((inv) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            colorScheme.primaryContainer,
                        child: Text(
                          (inv.masterName.isNotEmpty
                                  ? inv.masterName[0]
                                  : inv.masterEmail[0])
                              .toUpperCase(),
                          style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(inv.masterName.isNotEmpty
                          ? inv.masterName
                          : inv.masterEmail),
                      subtitle: Text(inv.masterEmail,
                          style: const TextStyle(fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade600),
                            onPressed: () => ref
                                .read(sharingNotifierProvider.notifier)
                                .declineInvitation(inv.id),
                            child: const Text('Recusar'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact),
                            onPressed: () => ref
                                .read(sharingNotifierProvider.notifier)
                                .acceptInvitation(inv),
                            child: const Text('Aceitar'),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Collaborator view: "you are on someone else's account" ───────
        if (!isMaster) ...[
          _SettingsCard(children: [
            ListTile(
              leading: const _IconBadge(Icons.people_alt_outlined,
                  color: Color(0xFF7E57C2)),
              title: const Text('Conta compartilhada'),
              subtitle: Text(
                profile?['masterUserId'] != null
                    ? 'Você está usando uma conta compartilhada'
                    : 'Conta compartilhada',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade700,
                ),
                onPressed: _confirmLeave,
                child: const Text('Sair da conta compartilhada'),
              ),
            ),
          ]),
        ],

        // ── Master view: invite + collaborator list ───────────────────────
        if (isMaster) ...[
          _SettingsCard(children: [
            ExpansionTile(
              leading: const _IconBadge(Icons.people_outline,
                  color: Color(0xFF7E57C2)),
              title: const Text('Compartilhamento',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              children: [
                // Invite field
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email do colaborador',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendInvite(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _sending ? null : _sendInvite,
                        child: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Text('Convidar'),
                      ),
                    ],
                  ),
                ),

                // Active collaborators
                if (collaborators.isNotEmpty) ...[
                  const Divider(height: 1, indent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Text('Colaboradores ativos',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant)),
                  ),
                  ...collaborators.map((inv) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              const Color(0xFF7E57C2).withValues(alpha: 0.15),
                          child: Text(
                            inv.inviteeEmail[0].toUpperCase(),
                            style: const TextStyle(
                                color: Color(0xFF7E57C2),
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                        title: Text(inv.inviteeEmail,
                            style: const TextStyle(fontSize: 13)),
                        trailing: IconButton(
                          icon: Icon(Icons.person_remove_outlined,
                              color: Colors.red.shade400, size: 20),
                          tooltip: 'Remover colaborador',
                          onPressed: inv.collaboratorUserId == null
                              ? null
                              : () => ref
                                  .read(sharingNotifierProvider.notifier)
                                  .removeCollaborator(
                                    invitationId: inv.id,
                                    collaboratorUserId:
                                        inv.collaboratorUserId!,
                                  ),
                        ),
                      )),
                ],

                const SizedBox(height: 8),
              ],
            ),
          ]),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wallet Section
// ─────────────────────────────────────────────────────────────────────────────

class _WalletSection extends ConsumerWidget {
  const _WalletSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final walletsAsync = ref.watch(walletsStreamProvider);
    final hiddenWalletIds = ref.watch(appSettingsProvider).hiddenWalletIds;

    final walletTiles = walletsAsync.when(
      data: (wallets) => wallets.map((w) {
        final isVisible = !hiddenWalletIds.contains(w.id);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(w.colorValue)
                .withValues(alpha: isVisible ? 0.15 : 0.06),
            child: Icon(
              categoryIcon(w.iconCodePoint),
              color: Color(w.colorValue)
                  .withValues(alpha: isVisible ? 1.0 : 0.35),
              size: 20,
            ),
          ),
          title: Text(
            w.name,
            style: TextStyle(
              color: isVisible
                  ? null
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: isVisible,
                onChanged: (_) => ref
                    .read(appSettingsProvider.notifier)
                    .toggleWalletVisibility(w.id),
              ),
              if (w.isDefault)
                Tooltip(
                  message: l10n.defaultWallet,
                  child: const Icon(Icons.lock_outline,
                      size: 16, color: Colors.grey),
                )
              else ...[
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _EditWalletDialog(wallet: w),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade400, size: 20),
                  onPressed: () => ref
                      .read(walletsNotifierProvider.notifier)
                      .delete(w.id),
                ),
              ],
            ],
          ),
        );
      }).toList(),
      loading: () => [
        const ListTile(title: Center(child: CircularProgressIndicator()))
      ],
      error: (e, _) => [ListTile(title: Text('Erro: $e'))],
    );

    return ExpansionTile(
      title: Text(l10n.wallets,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      children: [
        ...walletTiles,
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(l10n.newWallet),
          onTap: () => showDialog(
            context: context,
            builder: (_) => const _AddWalletDialog(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Wallet Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddWalletDialog extends ConsumerStatefulWidget {
  const _AddWalletDialog();

  @override
  ConsumerState<_AddWalletDialog> createState() => _AddWalletDialogState();
}

class _AddWalletDialogState extends ConsumerState<_AddWalletDialog> {
  final _nameController = TextEditingController();
  int _iconCodePoint = 0xe4c9; // account_balance_wallet
  int _colorValue = 0xFF1976D2;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    setState(() => _isLoading = true);
    final success = await ref.read(walletsNotifierProvider.notifier).add(
          userId: user.id,
          name: name,
          iconCodePoint: _iconCodePoint,
          colorValue: _colorValue,
        );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      Navigator.of(context).pop();
    } else {
      final err = ref.read(walletsNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err?.toString() ?? 'Erro ao criar carteira'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.newWallet),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                  labelText: l10n.walletName,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text(l10n.selectIcon,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _IconPickerGrid(
                selected: _iconCodePoint,
                onSelected: (v) => setState(() => _iconCodePoint = v)),
            const SizedBox(height: 16),
            Text(l10n.selectColor,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _ColorDots(
                selected: _colorValue,
                onSelected: (v) => setState(() => _colorValue = v)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Wallet Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _EditWalletDialog extends ConsumerStatefulWidget {
  final WalletEntity wallet;
  const _EditWalletDialog({required this.wallet});

  @override
  ConsumerState<_EditWalletDialog> createState() => _EditWalletDialogState();
}

class _EditWalletDialogState extends ConsumerState<_EditWalletDialog> {
  late final TextEditingController _nameController;
  late int _iconCodePoint;
  late int _colorValue;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.wallet.name);
    _iconCodePoint = widget.wallet.iconCodePoint;
    _colorValue = widget.wallet.colorValue;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final updated = WalletEntity(
      id: widget.wallet.id,
      userId: widget.wallet.userId,
      name: name,
      iconCodePoint: _iconCodePoint,
      colorValue: _colorValue,
      isDefault: widget.wallet.isDefault,
    );
    setState(() => _isLoading = true);
    final success =
        await ref.read(walletsNotifierProvider.notifier).update(updated);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      Navigator.of(context).pop();
    } else {
      final err = ref.read(walletsNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err?.toString() ?? 'Erro ao editar carteira'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.editWallet),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                  labelText: l10n.walletName,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text(l10n.selectIcon,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _IconPickerGrid(
                selected: _iconCodePoint,
                onSelected: (v) => setState(() => _iconCodePoint = v)),
            const SizedBox(height: 16),
            Text(l10n.selectColor,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _ColorDots(
                selected: _colorValue,
                onSelected: (v) => setState(() => _colorValue = v)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appearance Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AppearanceDialog extends ConsumerWidget {
  final AppLocalizations l10n;
  const _AppearanceDialog({required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appSettingsProvider).themeMode;
    return AlertDialog(
      title: Text(l10n.appearance),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 320,
        child: RadioGroup<AppThemeMode>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) {
              ref.read(appSettingsProvider.notifier).setThemeMode(v);
              Navigator.of(context).pop();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<AppThemeMode>(
                  value: AppThemeMode.system,
                  title: Text(l10n.themeModeSystem)),
              RadioListTile<AppThemeMode>(
                  value: AppThemeMode.light,
                  title: Text(l10n.themeModeLight)),
              RadioListTile<AppThemeMode>(
                  value: AppThemeMode.dark,
                  title: Text(l10n.themeModeDark)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
      ],
    );
  }
}
