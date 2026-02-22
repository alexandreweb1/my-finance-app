import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _usd = NumberFormat.currency(locale: 'en_US', symbol: '\$');

  static String formatBRL(double amount) => _brl.format(amount);
  static String formatUSD(double amount) => _usd.format(amount);

  static String formatDate(DateTime date) =>
      DateFormat('dd/MM/yyyy', 'pt_BR').format(date);

  static String formatMonthYear(DateTime date) =>
      DateFormat('MMMM yyyy', 'pt_BR').format(date);
}
