// lib/app/presentation/screens/seller/store_detail_screen.dart
import 'package:flutter/material.dart';

class StoreDetailScreen extends StatelessWidget {
  const StoreDetailScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etalase Toko'),
      ),
      body: const Center(
        child: Text(
            'Halaman detail toko, menampilkan semua produk dari toko tertentu.'),
      ),
    );
  }
}
