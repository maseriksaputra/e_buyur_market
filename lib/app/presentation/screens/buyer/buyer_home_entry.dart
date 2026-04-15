// lib/app/presentation/screens/buyer/buyer_home_entry.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Provider & Colors
import '../../providers/product_provider.dart';
import '../../../core/theme/app_colors.dart';

// Body content (grid produk) — sesuai file yang kamu pakai
import 'home_screen.dart' show HomeScreen;

class BuyerHomeEntry extends StatelessWidget {
  const BuyerHomeEntry({super.key});

  @override
  Widget build(BuildContext context) {
    // JANGAN const supaya child tidak wajib konstanta
    final scaffold = Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      body: const HomeScreen(), // pakai HomeScreen (bukan BuyerHomeScreen)
    );

    // Kompatibel semua versi provider: cek keberadaan ProductProvider via try/catch
    try {
      Provider.of<ProductProvider>(context, listen: false);
      // Sudah ada provider di atas tree → pakai langsung
      return scaffold;
    } catch (_) {
      // Belum ada → bungkus dengan ChangeNotifierProvider
      return ChangeNotifierProvider<ProductProvider>(
        create: (_) => ProductProvider(),
        child: scaffold,
      );
    }
  }
}
