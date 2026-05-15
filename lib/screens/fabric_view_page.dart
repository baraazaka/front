import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

// حزم الطباعة
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class FabricViewPage extends StatefulWidget {
  const FabricViewPage({super.key});

  @override
  State<FabricViewPage> createState() => _FabricViewPageState();
}

class _FabricViewPageState extends State<FabricViewPage> {
  List<Map<String, dynamic>> allFabrics = [];
  List<Map<String, dynamic>> filteredFabrics = []; // 🟢 قائمة مخصصة للبحث
  bool isLoading = true;
  late Box _myBox;

  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _myBox = Hive.box('fabricBox');
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    List<dynamic> savedHistory = _myBox.get('scanHistory', defaultValue: []);

    setState(() {
      allFabrics = savedHistory.map((item) {
        final mapItem = Map<String, dynamic>.from(item as Map);
        return {
          'isDefective': mapItem['isDefective'],
          'image': File(mapItem['imagePath']),
          'imagePath': mapItem['imagePath'],
          'defects': mapItem['defects'],
          'detailedDefects': mapItem['detailedDefects'] ?? [],
          'time': DateTime.parse(mapItem['time']),
          'fabricName': mapItem['fabricName'] ?? 'Unnamed Fabric',
          'isMistake': mapItem['isMistake'] ?? false,
          'mistakeNote': mapItem['mistakeNote'] ?? '',
        };
      }).toList();
      filteredFabrics = List.from(allFabrics);
      isLoading = false;
    });
  }

  void _runFilter(String enteredKeyword) {
    List<Map<String, dynamic>> results = [];
    if (enteredKeyword.isEmpty) {
      results = List.from(allFabrics);
    } else {
      results = allFabrics
          .where(
            (item) =>
                item['fabricName'].toString().toLowerCase().contains(
                  enteredKeyword.toLowerCase(),
                ) ||
                item['defects'].toString().toLowerCase().contains(
                  enteredKeyword.toLowerCase(),
                ),
          )
          .toList();
    }
    setState(() {
      filteredFabrics = results;
    });
  }

  Future<void> _deleteItem(int index) async {
    setState(() {
      var itemToRemove = filteredFabrics[index];
      allFabrics.remove(itemToRemove);
      filteredFabrics.removeAt(index);
    });

    List<Map<String, dynamic>> historyToSave = allFabrics.map((item) {
      return {
        'isDefective': item['isDefective'],
        'imagePath': item['imagePath'],
        'defects': item['defects'],
        'detailedDefects': item['detailedDefects'],
        'time': (item['time'] as DateTime).toIso8601String(),
        'fabricName': item['fabricName'],
        'isMistake': item['isMistake'],
        'mistakeNote': item['mistakeNote'],
      };
    }).toList();

    await _myBox.put('scanHistory', historyToSave);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Record deleted successfully'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showImageDialog(File imageFile) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(imageFile, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  // ==========================================
  // دالة الـ PDF الاحترافية (مربوطة بالإعدادات)
  // ==========================================
  Future<void> _generateAndPrintPdf(Map<String, dynamic> item) async {
    final pdf = pw.Document();

    // 🟢 قراءة اسم المصنع واسم المفتش من الإعدادات
    String compName = Hive.box(
      'fabricBox',
    ).get('factoryName', defaultValue: 'Fabric AI System');
    String inspName = Hive.box(
      'fabricBox',
    ).get('inspectorName', defaultValue: 'Unknown Inspector');

    File imageFile = item['image'] as File;
    final imageBytes = await imageFile.readAsBytes();
    final pdfImage = pw.MemoryImage(imageBytes);

    String fabricName = item['fabricName'];
    bool isDefective = item['isDefective'];
    bool isMistake = item['isMistake'];
    String mistakeNote = item['mistakeNote'];

    String statusText = isDefective ? 'DEFECTIVE' : 'PASSED';
    String formattedDate = _formatDate(item['time'] as DateTime);
    List detailedDefects = item['detailedDefects'];

    final PdfColor primaryColor = PdfColor.fromHex('#E91E63');
    final PdfColor statusColor = isDefective
        ? PdfColor.fromHex('#D32F2F')
        : PdfColor.fromHex('#388E3C');
    final PdfColor lightGrey = PdfColor.fromHex('#F5F5F5');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    compName, // 🟢 طباعة اسم المصنع هنا
                    style: pw.TextStyle(
                      color: primaryColor,
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Official Report',
                    style: pw.TextStyle(color: PdfColors.grey700, fontSize: 16),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: primaryColor, thickness: 2),
              pw.SizedBox(height: 20),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated by $compName', // 🟢 طباعة اسم المصنع في الأسفل
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: lightGrey,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Roll ID / Name:',
                        style: pw.TextStyle(
                          fontSize: 14,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        fabricName,
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Date & Time:',
                        style: pw.TextStyle(
                          fontSize: 14,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        formattedDate,
                        style: const pw.TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Divider(color: PdfColors.grey400),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Final Quality Status:',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: pw.BoxDecoration(
                          color: statusColor,
                          borderRadius: pw.BorderRadius.circular(20),
                        ),
                        child: pw.Text(
                          statusText,
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (isMistake) ...[
              pw.SizedBox(height: 15),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FFF3E0'),
                  border: pw.Border.all(color: PdfColor.fromHex('#FF9800')),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '⚠️ AI ACCURACY FLAG:',
                      style: pw.TextStyle(
                        color: PdfColor.fromHex('#E65100'),
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Inspector noted a discrepancy: "$mistakeNote"',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],

            pw.SizedBox(height: 30),
            pw.Text(
              'Scanned Image:',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Container(
                height: 250,
                width: double.infinity,
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: PdfColors.grey400, width: 2),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 10,
                  verticalRadius: 10,
                  child: pw.Image(pdfImage, fit: pw.BoxFit.cover),
                ),
              ),
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              'Inspection Findings:',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
              ),
            ),
            pw.SizedBox(height: 10),

            if (detailedDefects.isEmpty && !isDefective)
              pw.Text(
                'No defects found. Fabric is perfect.',
                style: const pw.TextStyle(fontSize: 14),
              )
            else
              pw.TableHelper.fromTextArray(
                context: context,
                cellAlignment: pw.Alignment.centerLeft,
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
                cellStyle: const pw.TextStyle(fontSize: 12),
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
                  ),
                ),
                headers: [
                  '#',
                  'Finding / Defect Type',
                  'Confidence Level',
                  'Severity',
                ],
                data: List<List<String>>.generate(detailedDefects.length, (
                  index,
                ) {
                  var def = detailedDefects[index];
                  return [
                    (index + 1).toString(),
                    def['name'],
                    '${(def['confidence'] * 100).toInt()}%',
                    'High (Defect)',
                  ];
                }),
              ),

            pw.SizedBox(height: 40),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Inspector: $inspName',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey600,
                      ),
                    ), // 🟢 طباعة اسم المفتش هنا
                    pw.SizedBox(height: 5),
                    pw.Container(width: 150, height: 1, color: PdfColors.black),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Inspection_Report_$fabricName.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'All Inspections',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: searchController,
                    onChanged: (value) => _runFilter(value),
                    decoration: InputDecoration(
                      hintText: 'Search by Roll ID or Defect...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                Expanded(
                  child: filteredFabrics.isEmpty
                      ? const Center(
                          child: Text(
                            "No history matches your search.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredFabrics.length,
                          itemBuilder: (context, index) {
                            var item = filteredFabrics[index];
                            bool isDefective = item['isDefective'];
                            bool isMistake = item['isMistake'];

                            return Dismissible(
                              key: Key(
                                item['time'].toString() + index.toString(),
                              ),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                              confirmDismiss: (direction) async {
                                return await showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Delete Record?"),
                                    content: const Text(
                                      "Are you sure you want to delete this inspection permanently?",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text("Cancel"),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text(
                                          "Delete",
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              onDismissed: (direction) => _deleteItem(index),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 16),
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
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => _showImageDialog(
                                          item['image'] as File,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.file(
                                            item['image'] as File,
                                            width: 80,
                                            height: 80,
                                            fit: BoxFit.cover,
                                            errorBuilder: (ctx, err, stack) =>
                                                Container(
                                                  width: 80,
                                                  height: 80,
                                                  color: Colors.grey[200],
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item['fabricName'],
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isMistake)
                                                  const Icon(
                                                    Icons.report_problem,
                                                    color: Colors.orange,
                                                    size: 20,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              isDefective
                                                  ? 'Defect: ${item['defects']}'
                                                  : 'Status: Perfect',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: isDefective
                                                    ? Colors.red[700]
                                                    : Colors.green[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.calendar_today,
                                                  size: 12,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _formatDate(
                                                    item['time'] as DateTime,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.print,
                                          color: Colors.blue,
                                        ),
                                        onPressed: () =>
                                            _generateAndPrintPdf(item),
                                        tooltip: 'Print Report',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
