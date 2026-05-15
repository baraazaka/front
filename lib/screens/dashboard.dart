import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart'; // 🟢 حزمة المشاركة الجديدة

import 'result_page.dart';
import 'fabric_view_page.dart';

class FabricDashboard extends StatefulWidget {
  const FabricDashboard({super.key});

  @override
  State<FabricDashboard> createState() => _FabricDashboardState();
}

class _FabricDashboardState extends State<FabricDashboard> {
  int totalScans = 0;
  int defective = 0;
  int reportedMistakes = 0;
  Map<String, int> defectsFrequency = {};

  List<Map<String, dynamic>> scanHistory = [];
  bool isLoadingData = true;
  late Box _myBox;

  @override
  void initState() {
    super.initState();
    try {
      _myBox = Hive.box('fabricBox');
      _loadData();
    } catch (e) {
      setState(() => isLoadingData = false);
    }
  }

  Future<void> _loadData() async {
    setState(() {
      List<dynamic> savedHistory = _myBox.get('scanHistory', defaultValue: []);

      int tScans = savedHistory.length;
      int defCount = 0;
      int mistCount = 0;
      Map<String, int> dFreq = {};

      scanHistory = savedHistory.map((item) {
        final mapItem = Map<String, dynamic>.from(item as Map);

        bool isDef = mapItem['isDefective'] ?? false;
        bool isMis = mapItem['isMistake'] ?? false;
        List detailed = mapItem['detailedDefects'] ?? [];

        if (isDef) {
          defCount++;
          for (var d in detailed) {
            String name = d['name'].toString();
            dFreq[name] = (dFreq[name] ?? 0) + 1;
          }
        }
        if (isMis) mistCount++;

        return {
          'isDefective': isDef,
          'image': File(mapItem['imagePath']),
          'defects': mapItem['defects'],
          'detailedDefects': detailed,
          'time': DateTime.parse(mapItem['time']),
          'fabricName': mapItem['fabricName'] ?? 'Unnamed Fabric',
          'isMistake': isMis,
          'mistakeNote': mapItem['mistakeNote'] ?? '',
        };
      }).toList();

      var sortedDefects = dFreq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      defectsFrequency = Map.fromEntries(sortedDefects);

      totalScans = tScans;
      defective = defCount;
      reportedMistakes = mistCount;
      isLoadingData = false;
    });
  }

  Future<void> _saveData() async {
    List<Map<String, dynamic>> historyToSave = scanHistory.map((item) {
      return {
        'isDefective': item['isDefective'],
        'imagePath': (item['image'] as File).path,
        'defects': item['defects'],
        'detailedDefects': item['detailedDefects'],
        'time': (item['time'] as DateTime).toIso8601String(),
        'fabricName': item['fabricName'],
        'isMistake': item['isMistake'] ?? false,
        'mistakeNote': item['mistakeNote'] ?? '',
      };
    }).toList();

    await _myBox.put('scanHistory', historyToSave);
    await _myBox.put('totalScans', totalScans);
    await _myBox.put('defective', defective);
  }

  Future<File> _saveImagePermanently(File tempImage) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'fabric_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return await tempImage.copy('${directory.path}/$fileName');
  }

  int get qualityRate {
    if (totalScans == 0) return 100;
    return (((totalScans - defective) / totalScans) * 100).round();
  }

  // ==========================================
  // 🟢 دالة تحويل البيانات إلى Excel (CSV) ومشاركتها
  // ==========================================
  Future<void> _exportDataToExcel() async {
    if (scanHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available to export.')),
      );
      return;
    }

    try {
      // 1. إنشاء رأس الجدول (الأعمدة)
      String csvData =
          "Date & Time,Roll ID / Fabric Name,Quality Status,Defects Found,AI Mistake Reported?,Mistake Note\n";

      // 2. تعبئة البيانات صفاً صفاً
      for (var item in scanHistory) {
        DateTime t = item['time'] as DateTime;
        String date = '${t.year}-${t.month}-${t.day} ${t.hour}:${t.minute}';

        // استبدال الفواصل بمسافات حتى لا ينهار ترتيب ملف الإكسل
        String name = item['fabricName'].toString().replaceAll(',', ' ');
        String status = item['isDefective'] ? "DEFECTIVE" : "PERFECT";
        String defects = item['defects'].toString().replaceAll(',', ' | ');
        String isMistake = item['isMistake'] ? "YES" : "NO";
        String note = item['mistakeNote'].toString().replaceAll(',', ' ');

        csvData += "$date,$name,$status,$defects,$isMistake,$note\n";
      }

      // 3. حفظ الملف مؤقتاً في الهاتف
      final directory = await getApplicationDocumentsDirectory();
      final path = "${directory.path}/Fabric_Inspection_Report.csv";
      final file = File(path);
      await file.writeAsString(csvData);

      // 4. فتح نافذة المشاركة (لمشاركته عبر واتساب، ايميل، الخ)
      await Share.shareXFiles([
        XFile(path),
      ], text: 'Fabric AI Inspection - Official Report');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingData) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE91E63)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Quality Dashboard',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 🟢 زر التصدير الجديد في الـ AppBar
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(
                Icons.file_download,
                color: Colors.green,
                size: 28,
              ),
              tooltip: 'Export to Excel',
              onPressed: _exportDataToExcel,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. زر التصوير الرئيسي
            GestureDetector(
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ResultPage()),
                );
                if (result != null && result is Map) {
                  File savedImage = await _saveImagePermanently(
                    result['image'],
                  );
                  setState(() {
                    scanHistory.insert(0, {
                      'isDefective': result['isDefective'],
                      'image': savedImage,
                      'defects': result['defects'],
                      'detailedDefects': result['detailedDefects'],
                      'time': result['time'],
                      'fabricName': result['fabricName'],
                      'isMistake': result['isMistake'] ?? false,
                      'mistakeNote': result['mistakeNote'] ?? '',
                    });
                  });
                  await _saveData();
                  _loadData();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE91E63),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE91E63).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: const [
                    Icon(Icons.qr_code_scanner, color: Colors.white, size: 40),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Start New Inspection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. شبكة الكروت الإحصائية (2x2)
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total Scans',
                    totalScans.toString(),
                    Icons.analytics,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Quality',
                    '$qualityRate%',
                    Icons.verified,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Defective',
                    defective.toString(),
                    Icons.error,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'AI Mistakes',
                    reportedMistakes.toString(),
                    Icons.warning,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),

            // 3. الرسم البياني (Pie Chart)
            if (totalScans > 0) ...[
              const Text(
                'Quality Distribution',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                height: 200,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 35,
                          sections: [
                            PieChartSectionData(
                              color: Colors.green,
                              value: (totalScans - defective).toDouble(),
                              title: '$qualityRate%',
                              radius: 45,
                              titleStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              color: Colors.redAccent,
                              value: defective.toDouble(),
                              title: '${100 - qualityRate}%',
                              radius: 45,
                              titleStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLegendItem('Perfect', Colors.green),
                        const SizedBox(height: 10),
                        _buildLegendItem('Defective', Colors.redAccent),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
            ],

            // 4. أكثر العيوب شيوعاً
            if (defectsFrequency.isNotEmpty) ...[
              const Text(
                'Most Common Defects',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: defectsFrequency.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.bug_report,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${entry.value} times',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 25),
            ],

            // 5. الفحوصات الأخيرة
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Scans',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FabricViewPage(),
                      ),
                    );
                    _loadData();
                  },
                  child: const Text(
                    'View All',
                    style: TextStyle(color: Color(0xFFE91E63)),
                  ),
                ),
              ],
            ),
            if (scanHistory.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text("No scans yet."),
                ),
              )
            else
              ...scanHistory.take(5).map((item) {
                bool isMistake = item['isMistake'] ?? false;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        item['image'] as File,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['fabricName'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMistake)
                          const Icon(
                            Icons.warning,
                            color: Colors.orange,
                            size: 18,
                          ),
                      ],
                    ),
                    subtitle: Text(
                      item['isDefective']
                          ? 'Defect: ${item['defects']}'
                          : 'Perfect',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      item['isDefective'] ? Icons.cancel : Icons.check_circle,
                      color: item['isDefective'] ? Colors.red : Colors.green,
                    ),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
