import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapPickResult {
  final double lat;
  final double lng;
  final String? address;
  MapPickResult({required this.lat, required this.lng, this.address});
}

class MapPickPage extends StatefulWidget {
  const MapPickPage({super.key});

  @override
  State<MapPickPage> createState() => _MapPickPageState();
}

class _MapPickPageState extends State<MapPickPage> {
  final Completer<GoogleMapController> _controller = Completer();
  LatLng? _center;
  Marker? _marker;
  final TextEditingController _addrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      perm = await Geolocator.requestPermission();
    }
    LatLng fallback = const LatLng(-6.200000, 106.816666); // Jakarta fallback
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      _center = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      _center = fallback;
    }
    _marker = Marker(
      markerId: const MarkerId('pick'),
      position: _center!,
      draggable: true,
      onDragEnd: (p) => setState(() => _marker = _marker!.copyWith(positionParam: p)),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Lokasi di Peta')),
      body: _center == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _center!, zoom: 15),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  markers: _marker != null ? {_marker!} : {},
                  onMapCreated: (c) => _controller.complete(c),
                  onTap: (p) => setState(() { _marker = _marker!.copyWith(positionParam: p); }),
                ),
                Positioned(
                  left: 12, right: 12, bottom: 16,
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _addrCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Detail alamat (opsional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity, height: 44,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check),
                              label: const Text('Pakai Titik Ini'),
                              onPressed: () {
                                final p = _marker!.position;
                                Navigator.pop(context, MapPickResult(lat: p.latitude, lng: p.longitude, address: _addrCtrl.text));
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
