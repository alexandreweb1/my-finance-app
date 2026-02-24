import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/presentation/providers/categories_provider.dart';
import '../../domain/entities/transaction_entity.dart';
import '../providers/transactions_provider.dart';

const _kNewCategory = '__new__';
const _kNavy = Color(0xFF1A2B4A);
const _kGreen = Color(0xFF00D887);

class AddTransactionDialog extends ConsumerStatefulWidget {
  /// If provided, the dialog opens in edit mode pre-filled with this transaction.
  final TransactionEntity? transaction;

  const AddTransactionDialog({super.key, this.transaction});

  @override
  ConsumerState<AddTransactionDialog> createState() =>
      _AddTransactionDialogState();
}

class _AddTransactionDialogState extends ConsumerState<AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  String? _category;
  DateTime _date = DateTime.now();
  String? _suggestedCategory;

  bool get _isEditing => widget.transaction != null;

  // Fallback static lists when Firestore categories haven't loaded yet.
  static const _staticIncomeCategories = [
    'Salário', 'Freelance', 'Investimentos', 'Outros',
  ];
  static const _staticExpenseCategories = [
    'Alimentação', 'Moradia', 'Transporte', 'Saúde',
    'Educação', 'Lazer', 'Vestuário', 'Outros',
  ];

  List<String> _categoryNames() {
    if (_type == TransactionType.income) {
      final cats = ref.watch(incomeCategoriesProvider);
      return cats.isNotEmpty
          ? cats.map((c) => c.name).toList()
          : _staticIncomeCategories;
    } else {
      final cats = ref.watch(expenseCategoriesProvider);
      return cats.isNotEmpty
          ? cats.map((c) => c.name).toList()
          : _staticExpenseCategories;
    }
  }

  // --- Auto-suggest by title similarity ---

  String? _computeSuggestion(String input) {
    if (_isEditing) return null; // no suggestion in edit mode
    final query = input.toLowerCase().trim();
    if (query.length < 3) return null;
    final transactions = ref.read(transactionsStreamProvider).value ?? [];
    if (transactions.isEmpty) return null;

    final queryWords = query
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();

    String? bestCategory;
    int bestScore = 0;

    for (final t in transactions) {
      final titleLower = t.title.toLowerCase();
      final titleWords = titleLower
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 3)
          .toSet();

      final wordOverlap = queryWords.intersection(titleWords).length;
      final substringMatch =
          (titleLower.contains(query) || query.contains(titleLower)) ? 1 : 0;
      final score = wordOverlap + substringMatch;

      if (score > bestScore) {
        bestScore = score;
        bestCategory = t.category;
      }
    }

    return bestScore > 0 ? bestCategory : null;
  }

  void _onTitleChanged(String value) {
    final suggestion = _computeSuggestion(value);
    if (suggestion != _suggestedCategory) {
      setState(() => _suggestedCategory = suggestion);
    }
  }

  void _acceptSuggestion() {
    if (_suggestedCategory == null) return;
    final categories = _categoryNames();
    if (categories.contains(_suggestedCategory)) {
      setState(() {
        _category = _suggestedCategory;
        _suggestedCategory = null;
      });
    }
  }

  void _dismissSuggestion() => setState(() => _suggestedCategory = null);

  // --- New category dialog ---

  Future<void> _showNewCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    final created = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova Categoria'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome da categoria',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    if (created == null || created.isEmpty) return;
    if (!mounted) return;

    final categoryType = _type == TransactionType.income
        ? CategoryType.income
        : CategoryType.expense;

    final success = await ref.read(categoriesNotifierProvider.notifier).add(
          userId: user.id,
          name: created,
          type: categoryType,
          iconCodePoint: Icons.label_outline_rounded.codePoint,
          colorValue: 0xFF607D8B,
        );

    if (!mounted) return;

    if (success) {
      setState(() => _category = created);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao criar categoria.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Pre-fill fields when editing an existing transaction.
    if (_isEditing) {
      final t = widget.transaction!;
      _titleController.text = t.title;
      _amountController.text = t.amount.toString();
      _descriptionController.text = t.description ?? '';
      _type = t.type;
      _category = t.category;
      _date = t.date;
    }
    _titleController.addListener(() => _onTitleChanged(_titleController.text));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valor inválido')),
      );
      return;
    }

    final notifier = ref.read(transactionsNotifierProvider.notifier);
    final bool success;

    if (_isEditing) {
      final updated = TransactionEntity(
        id: widget.transaction!.id,
        userId: widget.transaction!.userId,
        title: _titleController.text.trim(),
        amount: amount,
        type: _type,
        category: _category!,
        date: _date,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );
      success = await notifier.update(updated);
    } else {
      success = await notifier.add(
        title: _titleController.text.trim(),
        amount: amount,
        type: _type,
        category: _category!,
        date: _date,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
      final errorMsg = ref.read(transactionsNotifierProvider).error?.toString()
          ?? 'Erro ao salvar transação. Verifique se o Firestore está habilitado.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(transactionsNotifierProvider).isLoading;
    final categories = _categoryNames();

    // Auto-reset only when null (type changes set _category = null explicitly).
    _category ??= categories.isNotEmpty ? categories.first : null;

    // Only show suggestion when it's a valid category and not already selected.
    final showSuggestion = _suggestedCategory != null &&
        categories.contains(_suggestedCategory) &&
        _suggestedCategory != _category;

    return AlertDialog(
      title: Text(_isEditing ? l10n.editTransaction : l10n.newTransaction),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<TransactionType>(
                  segments: [
                    ButtonSegment(
                      value: TransactionType.expense,
                      label: Text(l10n.expense),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    ButtonSegment(
                      value: TransactionType.income,
                      label: Text(l10n.incomeType),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) => setState(() {
                    _type = v.first;
                    _category = null;
                    _suggestedCategory = null;
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: l10n.titleField,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? l10n.enterTitle : null,
                ),

                // Auto-suggest banner (only in create mode)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: showSuggestion
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8FBF3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _kGreen.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome,
                                    size: 16, color: _kGreen),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${l10n.suggestCategory}: $_suggestedCategory',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _kNavy,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _acceptSuggestion,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      l10n.use,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _kGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _dismissSuggestion,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(Icons.close,
                                        size: 16, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l10n.amountField,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.enterAmount;
                    final n = double.tryParse(v.replaceAll(',', '.'));
                    if (n == null || n <= 0) return l10n.invalidAmount;
                    if (n > 1000000000) return l10n.maxAmount;
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(_category),
                  initialValue: categories.contains(_category) ? _category : null,
                  decoration: InputDecoration(
                    labelText: l10n.categoryField,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v == _kNewCategory)
                      ? l10n.selectCategory
                      : null,
                  items: [
                    ...categories.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                    DropdownMenuItem(
                      value: _kNewCategory,
                      child: Row(
                        children: [
                          const Icon(Icons.add_circle_outline,
                              size: 18, color: _kGreen),
                          const SizedBox(width: 8),
                          Text(
                            l10n.newCategory,
                            style: const TextStyle(
                              color: _kGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == _kNewCategory) {
                      _showNewCategoryDialog();
                    } else {
                      setState(() => _category = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _selectDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.dateField,
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      '${_date.day.toString().padLeft(2, '0')}/'
                      '${_date.month.toString().padLeft(2, '0')}/'
                      '${_date.year}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: l10n.descriptionField,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }
}
