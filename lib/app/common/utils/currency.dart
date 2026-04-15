import 'package:intl/intl.dart';

class Rp {
  static final _fmt =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static String format(num n) => _fmt.format(n);
}
