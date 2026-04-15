import 'package:intl/intl.dart';

class Format {
  static String rupiah(double v) {
    final f = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    return f.format(v);
  }
}
