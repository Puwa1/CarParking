import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ParkingDashboard extends StatefulWidget {
  final int locationId;

  const ParkingDashboard({super.key, required this.locationId});

  @override
  State<ParkingDashboard> createState() => _ParkingDashboardState();
}

class _ParkingDashboardState extends State<ParkingDashboard> {
  final supabase = Supabase.instance.client;
  Stream<List<Map<String, dynamic>>>? _parkingSlotsStream;

  @override
  void initState() {
    super.initState();
    _parkingSlotsStream = supabase
        .from('parking_slots_status')
        .stream(primaryKey: ['slot_id'])
        .eq('location_id', widget.locationId)
        .order('slot_id');
  }

  Color statusColor(String status) =>
      status == 'F' ? const Color(0xFFE53935) : const Color(0xFF43A047);

  Map<int, Map<int, String>> groupByLane(List<Map<String, dynamic>> data) {
    final Map<int, Map<int, String>> grouped = {};
    for (var slot in data) {
      final lane = slot['lane'] as int;
      final slotId = slot['slot_id'] as int;
      final status = slot['status'] as String;
      grouped.putIfAbsent(lane, () => {});
      grouped[lane]![slotId] = status;
    }
    return grouped;
  }

  Map<String, dynamic> calculateSummary(Map<int, Map<int, String>> grouped) {
    int totalSlots = 0;
    int occupied = 0;
    int available = 0;
    final laneSummary = <int, Map<String, int>>{};

    grouped.forEach((lane, slots) {
      final laneTotal = slots.length;
      final laneOccupied = slots.values.where((s) => s == 'F').length;
      final laneAvailable = laneTotal - laneOccupied;

      totalSlots += laneTotal;
      occupied += laneOccupied;
      available += laneAvailable;

      laneSummary[lane] = {
        'total': laneTotal,
        'occupied': laneOccupied,
        'available': laneAvailable,
      };
    });

    final overallStatus = available > 0 ? 'ว่าง' : 'เต็ม';

    return {
      'totalSlots': totalSlots,
      'occupied': occupied,
      'available': available,
      'overallStatus': overallStatus,
      'laneSummary': laneSummary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'สถานะช่องจอดรถ',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _parkingSlotsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('ไม่พบข้อมูล.'));
          }

          final grouped = groupByLane(snapshot.data!);
          final summary = calculateSummary(grouped);

          // เรียงลานจากน้อย → มาก
          final sortedLanes = grouped.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                // สรุปด้านบน
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "รวมทั้งหมด: ",
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontSize: 18),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              return ScaleTransition(
                                  scale: animation, child: child);
                            },
                            child: Text(
                              "${summary['available']} / ${summary['totalSlots']} ช่อง",
                              key: ValueKey<int>(summary['available']),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: summary['available'] > 0
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: summary['overallStatus'] == 'ว่าง'
                              ? Colors.green[800]
                              : Colors.red[800],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "สถานะโดยรวม: ${summary['overallStatus']}",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                // ตารางแต่ละลาน (เรียงลานแล้ว)
                ...sortedLanes.map(
                  (laneEntry) => buildLaneGrid(
                    laneEntry.key,
                    laneEntry.value,
                    summary['laneSummary'][laneEntry.key]['available'],
                    summary['laneSummary'][laneEntry.key]['total'],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget buildLaneGrid(
      int lane, Map<int, String> slots, int available, int total) {
    final slotIds = slots.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'ลาน $lane',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16.0,
              runSpacing: 16.0,
              alignment: WrapAlignment.center,
              children: slotIds.map((num) {
                final status = slots[num] ?? 'E';
                return Material(
                  color: statusColor(status),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 6,
                  child: Container(
                    width: 130,
                    height: 60,
                    alignment: Alignment.center,
                    child: Text(
                      'ช่อง $num',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                "ว่าง $available / $total ช่อง",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
