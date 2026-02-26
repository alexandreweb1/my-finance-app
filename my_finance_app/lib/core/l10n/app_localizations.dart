import 'package:flutter/material.dart';

/// Simple inline localizations for PT-BR, EN-US and ES-ES.
/// Access via: AppLocalizations.of(context).someKey
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('pt', 'BR'));
  }

  static const delegate = _AppLocalizationsDelegate();

  static const supportedLocales = [
    Locale('pt', 'BR'),
    Locale('en', 'US'),
    Locale('es', 'ES'),
  ];

  String _t(String pt, String en, String es) {
    switch (locale.languageCode) {
      case 'en':
        return en;
      case 'es':
        return es;
      default:
        return pt;
    }
  }

  // ── App ──────────────────────────────────────────────────────────────────
  String get appTitle => _t('My Finance App', 'My Finance App', 'My Finance App');

  // ── Navigation ───────────────────────────────────────────────────────────
  String get navHome => _t('Início', 'Home', 'Inicio');
  String get navStatement => _t('Extrato', 'Statement', 'Extracto');
  String get navPlanning => _t('Planejamento', 'Planning', 'Planificación');
  String get navProfile => _t('Perfil', 'Profile', 'Perfil');
  String get newTransaction => _t('Nova Transação', 'New Transaction', 'Nueva Transacción');

  // ── Dashboard ────────────────────────────────────────────────────────────
  String get dashboard => _t('Dashboard', 'Dashboard', 'Dashboard');
  String get totalBalance => _t('Saldo Total', 'Total Balance', 'Saldo Total');
  String get income => _t('Receitas', 'Income', 'Ingresos');
  String get expenses => _t('Despesas', 'Expenses', 'Gastos');
  String get budgets => _t('Orçamentos', 'Budgets', 'Presupuestos');
  String get thisMonth => _t('Este mês', 'This month', 'Este mes');
  String get hello => _t('Olá', 'Hello', 'Hola');
  String get goodMorning => _t('Bom dia', 'Good morning', 'Buenos días');
  String get goodAfternoon => _t('Boa tarde', 'Good afternoon', 'Buenas tardes');
  String get goodEvening => _t('Boa noite', 'Good evening', 'Buenas noches');
  String get yourFinances => _t('Suas Finanças', 'Your Finances', 'Tus Finanzas');
  String get noBudgets => _t('Sem orçamentos', 'No budgets', 'Sin presupuestos');
  String get seeAll => _t('Ver tudo', 'See all', 'Ver todo');
  String get recentTransactions => _t('Transações Recentes', 'Recent Transactions', 'Transacciones Recientes');

  // ── Transactions ─────────────────────────────────────────────────────────
  String get transactions => _t('Transações', 'Transactions', 'Transacciones');
  String get noTransactions => _t('Nenhuma transação encontrada', 'No transactions found', 'No se encontraron transacciones');
  String get titleField => _t('Título', 'Title', 'Título');
  String get amountField => _t('Valor (R\$)', 'Amount', 'Monto');
  String get categoryField => _t('Categoria', 'Category', 'Categoría');
  String get dateField => _t('Data', 'Date', 'Fecha');
  String get descriptionField => _t('Descrição (opcional)', 'Description (optional)', 'Descripción (opcional)');
  String get expense => _t('Despesa', 'Expense', 'Gasto');
  String get incomeType => _t('Receita', 'Income', 'Ingreso');
  String get save => _t('Salvar', 'Save', 'Guardar');
  String get cancel => _t('Cancelar', 'Cancel', 'Cancelar');
  String get delete => _t('Excluir', 'Delete', 'Eliminar');
  String get invalidAmount => _t('Valor inválido', 'Invalid amount', 'Monto inválido');
  String get enterTitle => _t('Informe o título', 'Enter a title', 'Ingrese un título');
  String get enterAmount => _t('Informe o valor', 'Enter the amount', 'Ingrese el monto');
  String get selectCategory => _t('Selecione uma categoria', 'Select a category', 'Seleccione una categoría');
  String get maxAmount => _t('Valor máximo: R\$ 1.000.000.000,00', 'Max: \$ 1,000,000,000.00', 'Máx: \$ 1.000.000.000,00');
  String get suggestCategory => _t('Sugestão', 'Suggestion', 'Sugerencia');
  String get use => _t('Usar', 'Use', 'Usar');
  String get newCategory => _t('Nova categoria...', 'New category...', 'Nueva categoría...');
  String get newCategoryTitle => _t('Nova Categoria', 'New Category', 'Nueva Categoría');
  String get categoryName => _t('Nome da categoria', 'Category name', 'Nombre de categoría');
  String get create => _t('Criar', 'Create', 'Crear');
  String get errorSavingTransaction => _t('Erro ao salvar transação.', 'Error saving transaction.', 'Error al guardar transacción.');
  String get errorCreatingCategory => _t('Erro ao criar categoria.', 'Error creating category.', 'Error al crear categoría.');
  String get editTransaction => _t('Editar Transação', 'Edit Transaction', 'Editar Transacción');
  String get editBudget => _t('Editar Orçamento', 'Edit Budget', 'Editar Presupuesto');
  String get selectMonth => _t('Selecionar mês', 'Select month', 'Seleccionar mes');
  String get annualView => _t('Visão anual', 'Annual view', 'Vista anual');
  String get monthlyView => _t('Visão mensal', 'Monthly view', 'Vista mensual');
  String get expenseByCategory => _t('Gastos por categoria', 'Expenses by category', 'Gastos por categoría');

  // ── Wallets ───────────────────────────────────────────────────────────────
  String get wallet => _t('Carteira', 'Wallet', 'Billetera');
  String get wallets => _t('Carteiras', 'Wallets', 'Billeteras');
  String get newWallet => _t('Nova carteira...', 'New wallet...', 'Nueva billetera...');
  String get walletField => _t('Carteira', 'Wallet', 'Billetera');
  String get walletName => _t('Nome da carteira', 'Wallet name', 'Nombre de la billetera');
  String get manageWallets => _t('Gerenciar carteiras', 'Manage wallets', 'Gestionar billeteras');
  String get noWallets => _t('Nenhuma carteira cadastrada.', 'No wallets found.', 'No hay billeteras.');
  String get errorCreatingWallet => _t('Erro ao criar carteira.', 'Error creating wallet.', 'Error al crear billetera.');
  String get appearance => _t('Aparência', 'Appearance', 'Apariencia');
  String get themeModeSystem => _t('Padrão do sistema', 'System default', 'Predeterminado del sistema');
  String get themeModeLight => _t('Claro', 'Light', 'Claro');
  String get themeModeDark => _t('Escuro', 'Dark', 'Oscuro');

  // ── Planning ─────────────────────────────────────────────────────────────
  String get planning => _t('Planejamento', 'Planning', 'Planificación');
  String get budget => _t('Orçamento', 'Budget', 'Presupuesto');
  String get noBudgetsForMonth => _t('Nenhum orçamento para', 'No budget for', 'Sin presupuesto para');
  String get tapToStart => _t('Toque em "+ Orçamento" para começar.', 'Tap "+ Budget" to get started.', 'Toque en "+ Presupuesto" para comenzar.');
  String get replicateFrom => _t('Replicar de', 'Copy from', 'Copiar de');
  String get replicateBudgets => _t('Replicar orçamentos', 'Copy budgets', 'Copiar presupuestos');
  String get replicateConfirm => _t('orçamento(s) de', 'budget(s) from', 'presupuesto(s) de');
  String get replicateConfirmTo => _t('para', 'to', 'a');
  String get replicate => _t('Replicar', 'Copy', 'Copiar');
  String get limit => _t('Limite (R\$)', 'Limit', 'Límite');
  String get spent => _t('Gasto', 'Spent', 'Gastado');
  String get limitLabel => _t('Limite', 'Limit', 'Límite');
  String get errorReplicating => _t('Erro ao replicar orçamentos.', 'Error copying budgets.', 'Error al copiar presupuestos.');

  // ── Settings ─────────────────────────────────────────────────────────────
  String get settings => _t('Configurações', 'Settings', 'Configuración');
  String get changePassword => _t('Alterar senha', 'Change password', 'Cambiar contraseña');
  String get expenseCategories => _t('Categorias de Despesa', 'Expense Categories', 'Categorías de Gastos');
  String get incomeCategories => _t('Categorias de Receita', 'Income Categories', 'Categorías de Ingresos');
  String get logout => _t('Sair', 'Logout', 'Cerrar sesión');
  String get editProfile => _t('Editar perfil', 'Edit profile', 'Editar perfil');
  String get noName => _t('Sem nome', 'No name', 'Sin nombre');
  String get nameField => _t('Nome', 'Name', 'Nombre');
  String get currentPassword => _t('Senha atual', 'Current password', 'Contraseña actual');
  String get newPassword => _t('Nova senha', 'New password', 'Nueva contraseña');
  String get enterCurrentPassword => _t('Informe a senha atual', 'Enter current password', 'Ingrese la contraseña actual');
  String get enterNewPassword => _t('Informe a nova senha', 'Enter new password', 'Ingrese la nueva contraseña');
  String get minChars => _t('Mínimo 6 caracteres', 'Minimum 6 characters', 'Mínimo 6 caracteres');
  String get passwordChanged => _t('Senha alterada com sucesso!', 'Password changed successfully!', '¡Contraseña cambiada con éxito!');
  String get defaultCategory => _t('Categoria padrão', 'Default category', 'Categoría predeterminada');
  String get addExpenseCategory => _t('Adicionar despesa', 'Add expense', 'Agregar gasto');
  String get addIncomeCategory => _t('Adicionar receita', 'Add income', 'Agregar ingreso');
  String get editCategory => _t('Editar categoria', 'Edit category', 'Editar categoría');
  String get editWallet => _t('Editar carteira', 'Edit wallet', 'Editar billetera');
  String get selectIcon => _t('Selecionar ícone', 'Select icon', 'Seleccionar ícono');
  String get selectColor => _t('Selecionar cor', 'Select color', 'Seleccionar color');
  String get defaultWallet => _t('Carteira padrão', 'Default wallet', 'Billetera predeterminada');
  String get currency => _t('Moeda', 'Currency', 'Moneda');
  String get language => _t('Idioma', 'Language', 'Idioma');
  String get currencyTitle => _t('Selecionar moeda', 'Select currency', 'Seleccionar moneda');
  String get languageTitle => _t('Selecionar idioma', 'Select language', 'Seleccionar idioma');
  String get newBudget => _t('Orçamento – ', 'Budget – ', 'Presupuesto – ');

  // ── Auth ─────────────────────────────────────────────────────────────────
  String get login => _t('Entrar', 'Login', 'Iniciar sesión');
  String get register => _t('Criar conta', 'Create account', 'Crear cuenta');

  // ── Common ───────────────────────────────────────────────────────────────
  String get errorGeneric => _t('Erro desconhecido.', 'Unknown error.', 'Error desconocido.');
  String get confirm => _t('Confirmar', 'Confirm', 'Confirmar');
}

// ─────────────────────────────────────────────────────────────────────────────
// Delegate
// ─────────────────────────────────────────────────────────────────────────────

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['pt', 'en', 'es'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
