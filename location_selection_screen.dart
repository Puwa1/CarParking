import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'parking_dashboard.dart';

class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({super.key});

  @override
  State<LocationSelectionScreen> createState() => _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> {
  final supabase = Supabase.instance.client;
  Stream<List<Map<String, dynamic>>>? _locationsStream;

  @override
  void initState() {
    super.initState();
    // ดึงข้อมูลสถานที่จากตาราง locations
    _locationsStream = supabase.from('locations').stream(primaryKey: ['id']).order('id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกสถานที่',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            )),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _locationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('ไม่พบข้อมูลสถานที่.'));
          }

          final locations = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: locations.length,
            itemBuilder: (context, index) {
              final location = locations[index];
              return Card(
                color: const Color(0xFF1E1E1E),
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  title: Text(
                    location['location_name'] ?? 'ไม่มีชื่อ',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                  onTap: () {
                    // นำทางไปหน้า ParkingDashboard พร้อมส่ง id ไปด้วย
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ParkingDashboard(locationId: location['id']),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}