import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/utils/category_icons.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/presentation/providers/categories_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).value;
    final settings = ref.watch(appSettingsProvider);
    final incomeCategories = ref.watch(incomeCategoriesProvider);
    final expenseCategories = ref.watch(expenseCategoriesProvider);

    final initials = _initials(user?.displayName ?? user?.email ?? '?');

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // Profile section
          _ProfileCard(
            initials: initials,
            displayName: user?.displayName ?? '',
            email: user?.email ?? '',
          ),

          const Divider(height: 1),

          // Change password
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.changePassword),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChangePasswordDialog(context, ref),
          ),

          const Divider(height: 1),

          // Currency
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: Text(l10n.currency),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  settings.currency.label,
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _showCurrencyDialog(context, ref, l10n),
          ),

          const Divider(height: 1),

          // Language
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.language),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  settings.language.nativeLabel,
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _showLanguageDialog(context, ref, l10n),
          ),

          const Divider(height: 1),

          // Expense categories
          _CategorySection(
            title: l10n.expenseCategories,
            type: CategoryType.expense,
            categories: expenseCategories,
          ),

          const Divider(height: 1),

          // Income categories
          _CategorySection(
            title: l10n.incomeCategories,
            type: CategoryType.income,
            categories: incomeCategories,
          ),

          const Divider(height: 1),

          // Logout
          ListTile(
            leading: Icon(Icons.logout, color: Colors.red.shade600),
            title: Text(l10n.logout,
                style: TextStyle(color: Colors.red.shade600)),
            onTap: () =>
                ref.read(authNotifierProvider.notifier).signOut(),
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
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
  }

  void _showCurrencyDialog(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (ctx) => _CurrencyDialog(l10n: l10n),
    );
  }

  void _showLanguageDialog(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (ctx) => _LanguageDialog(l10n: l10n),
    );
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
                          style:
                              TextStyle(color: Colors.grey.shade600)),
                    ))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
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
                          style:
                              TextStyle(color: Colors.grey.shade600)),
                    ))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Card
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCard extends ConsumerWidget {
  final String initials;
  final String displayName;
  final String email;

  const _ProfileCard({
    required this.initials,
    required this.displayName,
    required this.email,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor:
                Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isNotEmpty ? displayName : l10n.noName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(email,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.editProfile,
            onPressed: () => _showEditProfileDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _EditProfileDialog(currentName: displayName),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(err ?? 'Erro ao atualizar perfil.'),
            backgroundColor: Colors.red.shade700),
      );
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
          labelText: l10n.nameField,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
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

class _ChangePasswordDialogState
    extends ConsumerState<_ChangePasswordDialog> {
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
        .updatePassword(
          _currentPwController.text,
          _newPwController.text,
        );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).passwordChanged)),
      );
    } else {
      final err = ref.read(authNotifierProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(err ?? 'Erro ao alterar senha.'),
            backgroundColor: Colors.red.shade700),
      );
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
                    icon: Icon(_obscureNew
                        ? Icons.visibility_off
                        : Icons.visibility),
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
          child: Text(l10n.cancel),
        ),
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
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      children: [
        ...categories.map(
          (cat) => ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(cat.colorValue).withValues(alpha: 0.15),
              child: Icon(
                categoryIcon(cat.iconCodePoint),
                color: Color(cat.colorValue),
                size: 20,
              ),
            ),
            title: Text(cat.name),
            trailing: cat.isDefault
                ? Tooltip(
                    message: l10n.defaultCategory,
                    child: const Icon(Icons.lock_outline,
                        size: 16, color: Colors.grey),
                  )
                : IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Colors.red.shade400, size: 20),
                    onPressed: () => ref
                        .read(categoriesNotifierProvider.notifier)
                        .delete(cat.id),
                  ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(
              type == CategoryType.expense
                  ? l10n.addExpenseCategory
                  : l10n.addIncomeCategory),
          onTap: () => _showAddCategoryDialog(context, ref),
        ),
      ],
    );
  }

  void _showAddCategoryDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _AddCategoryDialog(type: type),
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

    final success =
        await ref.read(categoriesNotifierProvider.notifier).add(
              userId: user.id,
              name: name,
              type: widget.type,
              iconCodePoint: 0xe574,
              colorValue: 0xFF616161,
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
      content: TextField(
        controller: _nameController,
        decoration: InputDecoration(
          labelText: l10n.categoryName,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
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
