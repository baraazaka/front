import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

// 🟢 المكتبة السحرية الجديدة (تعمل بدون إنترنت)
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

// 🟢 تحديد وضع الفحص
enum ScanMode { defect, fabricType }

class ResultPage extends StatefulWidget {
  const ResultPage({super.key});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  bool isLoading = false;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  List predictionsList = [];
  double? imgWidth;
  double? imgHeight;

  bool _showBoundingBoxes = false;
  bool _isMistakeReported = false;

  ScanMode _currentMode = ScanMode.defect;

  List<FabricItem> fabricItems = [];
  Map<String, dynamic>? finalResultToReturn;

  final TextEditingController _nameController = TextEditingController();

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _currentMode == ScanMode.defect
                      ? 'Scan for Defects'
                      : 'Identify Fabric Type',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFFE91E63)),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _scanImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _scanImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<File?> _cropImage(String imagePath) async {
    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: imagePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Fabric',
          toolbarColor: const Color(0xFFE91E63),
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Crop Fabric'),
      ],
    );
    if (croppedFile != null) return File(croppedFile.path);
    return null;
  }

  Future<void> _scanImage(ImageSource sourceOption) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: sourceOption,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (pickedFile == null) return;

      File? croppedImage = await _cropImage(pickedFile.path);
      if (croppedImage == null) return;

      setState(() {
        _selectedImage = croppedImage;
        isLoading = true;
        fabricItems.clear();
        predictionsList.clear();
        finalResultToReturn = null;
        _nameController.clear();
        _showBoundingBoxes = false;
        _isMistakeReported = false;
      });

      // =========================================================
      // 🟢 وضع "كشف العيوب" (Roboflow)
      // =========================================================
      if (_currentMode == ScanMode.defect) {
        List<int> imageBytes = await _selectedImage!.readAsBytes();
        String base64Image = base64Encode(imageBytes);

        String apiKey = "23FkvKnUQBHppJDcPvVF";
        String modelName = "garment-defects-o1agi";
        String version = "1";

        int userConfidence = Hive.box(
          'fabricBox',
        ).get('aiConfidence', defaultValue: 35.0).toInt();

        String url =
            "https://detect.roboflow.com/$modelName/$version?api_key=$apiKey&confidence=$userConfidence";

        var response = await http
            .post(
              Uri.parse(url),
              headers: {"Content-Type": "application/x-www-form-urlencoded"},
              body: base64Image,
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode == 200) {
          var jsonResponse = jsonDecode(response.body);

          if (jsonResponse['image'] != null) {
            imgWidth = jsonResponse['image']['width']?.toDouble();
            imgHeight = jsonResponse['image']['height']?.toDouble();
          }

          List predictions = jsonResponse['predictions'] ?? [];

          setState(() {
            predictionsList = predictions;
            List<Map<String, dynamic>> detailedDefects = [];

            if (predictions.isNotEmpty) {
              HapticFeedback.heavyImpact();
              List<String> defectNames = [];

              for (var pred in predictions) {
                String defName = pred['class'].toString().toUpperCase();
                double conf = pred['confidence'] as double;

                defectNames.add(defName);
                fabricItems.add(
                  FabricItem(name: defName, confidence: conf, isDefect: true),
                );
                detailedDefects.add({'name': defName, 'confidence': conf});
              }

              finalResultToReturn = {
                'isDefective': true,
                'image': _selectedImage,
                'defects': defectNames.toSet().toList().join(', '),
                'detailedDefects': detailedDefects,
                'time': DateTime.now(),
                'isMistake': false,
                'mistakeNote': '',
              };

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '⚠️ Alert: Detected defects (${defectNames.toSet().toList().join(', ')})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.redAccent,
                  duration: const Duration(seconds: 4),
                ),
              );
            } else {
              _setPerfectFabric();
            }
          });
        } else {
          throw Exception('Roboflow Server Error: ${response.statusCode}');
        }
      }
      // =========================================================
      // 🔵 وضع "نوع القماش" (Google ML Kit Offline) - مجاني وسريع جداً ومضمون
      // =========================================================
      else {
        // 1. تحويل الصورة لصيغة يقبلها ML Kit
        final inputImage = InputImage.fromFile(_selectedImage!);

        // 2. تجهيز الموديل
        final imageLabeler = ImageLabeler(options: ImageLabelerOptions());

        // 3. تحليل الصورة في جزء من الثانية (بدون إنترنت!)
        final List<ImageLabel> labels = await imageLabeler.processImage(
          inputImage,
        );

        // 4. إغلاق الموديل لتوفير الذاكرة
        imageLabeler.close();

        // 5. فلترة النتائج للبحث عن الكلمات المتعلقة بالأقمشة
        List<String> fabricKeywords = [
          'textile',
          'fabric',
          'cotton',
          'denim',
          'jeans',
          'silk',
          'wool',
          'linen',
          'leather',
          'clothing',
          'pattern',
          'knit',
          'woven',
        ];

        String bestMatch = "UNKNOWN FABRIC";
        double accuracy = 0.0;

        for (ImageLabel label in labels) {
          String name = label.label.toLowerCase();
          if (fabricKeywords.any((keyword) => name.contains(keyword))) {
            bestMatch = name.toUpperCase();
            accuracy = label.confidence;
            break; // نأخذ أول نتيجة صحيحة لأن القائمة مرتبة حسب الدقة
          }
        }

        // إذا لم يجد كلمة دقيقة، نأخذ أعلى نتيجة وجدها الموديل في الصورة
        if (bestMatch == "UNKNOWN FABRIC" && labels.isNotEmpty) {
          bestMatch = labels.first.label.toUpperCase();
          accuracy = labels.first.confidence;
        }

        HapticFeedback.lightImpact();
        setState(() {
          fabricItems.add(
            FabricItem(
              name: "MATERIAL: $bestMatch",
              confidence: accuracy,
              isDefect: false,
            ),
          );

          finalResultToReturn = {
            'isDefective': false,
            'image': _selectedImage,
            'defects': "Type: $bestMatch",
            'detailedDefects': [
              {'name': 'Identified as $bestMatch', 'confidence': accuracy},
            ],
            'time': DateTime.now(),
            'isMistake': false,
            'mistakeNote': '',
          };
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🧵 Fabric identified as: $bestMatch',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.blueAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print("SCAN ERROR: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _setPerfectFabric() {
    HapticFeedback.lightImpact();
    fabricItems.add(
      FabricItem(name: 'PERFECT FABRIC', confidence: 1.0, isDefect: false),
    );
    finalResultToReturn = {
      'isDefective': false,
      'image': _selectedImage,
      'defects': 'None',
      'detailedDefects': [],
      'time': DateTime.now(),
      'isMistake': false,
      'mistakeNote': '',
    };

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '✅ Success: Fabric is perfect! No defects found.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showReportMistakeDialog() {
    TextEditingController noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.report_problem, color: Colors.orange),
            SizedBox(width: 8),
            Text('Report AI Mistake', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Did the AI miss a defect or guess wrong? Please describe what it actually is.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                hintText: 'e.g., Missed a small hole',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(ctx);
              _submitMistake(noteController.text);
            },
            child: const Text(
              'Submit Flag',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _submitMistake(String note) {
    setState(() {
      _isMistakeReported = true;
      if (finalResultToReturn != null) {
        finalResultToReturn!['isMistake'] = true;
        finalResultToReturn!['mistakeNote'] = note.isNotEmpty
            ? note
            : 'User flagged an error';
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Thank you! This image is flagged.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Widget _buildImageWithBoundingBoxes() {
    if (_selectedImage == null) return const SizedBox();

    if (!_showBoundingBoxes ||
        predictionsList.isEmpty ||
        imgWidth == null ||
        imgHeight == null ||
        _currentMode == ScanMode.fabricType) {
      return Container(
        constraints: const BoxConstraints(maxHeight: 350),
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(_selectedImage!, fit: BoxFit.contain),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double maxWidth = constraints.maxWidth;
        double maxHeight = 350;

        double imgRatio = imgWidth! / imgHeight!;
        double containerRatio = maxWidth / maxHeight;

        double displayWidth, displayHeight;

        if (imgRatio > containerRatio) {
          displayWidth = maxWidth;
          displayHeight = maxWidth / imgRatio;
        } else {
          displayHeight = maxHeight;
          displayWidth = maxHeight * imgRatio;
        }

        double scaleX = displayWidth / imgWidth!;
        double scaleY = displayHeight / imgHeight!;

        List<Widget> boxes = predictionsList.map((pred) {
          double x = pred['x'].toDouble();
          double y = pred['y'].toDouble();
          double w = pred['width'].toDouble();
          double h = pred['height'].toDouble();

          double left = (x - w / 2) * scaleX;
          double top = (y - h / 2) * scaleY;

          return Positioned(
            left: left,
            top: top,
            width: w * scaleX,
            height: h * scaleY,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.redAccent, width: 2.5),
                borderRadius: BorderRadius.circular(4),
                color: Colors.redAccent.withOpacity(0.25),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(2),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Text(
                    '${pred['class']} ${(pred['confidence'] * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList();

        return Container(
          constraints: const BoxConstraints(maxHeight: 350),
          width: double.infinity,
          alignment: Alignment.center,
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    _selectedImage!,
                    width: displayWidth,
                    height: displayHeight,
                    fit: BoxFit.fill,
                  ),
                ),
                ...boxes,
              ],
            ),
          ),
        );
      },
    );
  }

  void _returnWithData() {
    if (finalResultToReturn != null) {
      finalResultToReturn!['fabricName'] = _nameController.text.isNotEmpty
          ? _nameController.text
          : 'Unknown Fabric';
    }
    Navigator.of(context).pop(finalResultToReturn);
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
          onPressed: () => Navigator.pop(context, null),
        ),
        title: const Text(
          'Scan Fabric',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🟢 الأزرار لاختيار وضع الفحص
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!isLoading)
                          setState(() => _currentMode = ScanMode.defect);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _currentMode == ScanMode.defect
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _currentMode == ScanMode.defect
                              ? [
                                  const BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                  ),
                                ]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search,
                              size: 18,
                              color: _currentMode == ScanMode.defect
                                  ? const Color(0xFFE91E63)
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Detect Defects',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _currentMode == ScanMode.defect
                                    ? const Color(0xFFE91E63)
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!isLoading)
                          setState(() => _currentMode = ScanMode.fabricType);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _currentMode == ScanMode.fabricType
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _currentMode == ScanMode.fabricType
                              ? [
                                  const BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                  ),
                                ]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.category,
                              size: 18,
                              color: _currentMode == ScanMode.fabricType
                                  ? Colors.blue
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Fabric Type',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _currentMode == ScanMode.fabricType
                                    ? Colors.blue
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentMode == ScanMode.defect
                        ? 'Defect Analysis'
                        : 'Material Analysis',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildImageWithBoundingBoxes(),
                  const SizedBox(height: 16),

                  if (finalResultToReturn != null &&
                      predictionsList.isNotEmpty &&
                      _currentMode == ScanMode.defect)
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(
                          () => _showBoundingBoxes = !_showBoundingBoxes,
                        ),
                        icon: Icon(
                          _showBoundingBoxes
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.blue,
                        ),
                        label: Text(
                          _showBoundingBoxes
                              ? 'Hide Defect Locations'
                              : 'Show Defect Locations',
                          style: const TextStyle(color: Colors.blue),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.blue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),

                  if (finalResultToReturn != null &&
                      predictionsList.isNotEmpty &&
                      _currentMode == ScanMode.defect)
                    const SizedBox(height: 16),

                  if (finalResultToReturn != null) ...[
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Enter Fabric Name / Roll ID',
                        prefixIcon: const Icon(
                          Icons.label,
                          color: Color(0xFFE91E63),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE91E63),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : _showImageSourceDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: finalResultToReturn == null
                                ? (_currentMode == ScanMode.defect
                                      ? const Color(0xFFE91E63)
                                      : Colors.blue)
                                : Colors.grey[300],
                            foregroundColor: finalResultToReturn == null
                                ? Colors.white
                                : Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: isLoading
                              ? const SizedBox()
                              : const Icon(Icons.camera_alt),
                          label: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  finalResultToReturn == null
                                      ? 'Scan Image'
                                      : 'Retake',
                                ),
                        ),
                      ),
                      if (finalResultToReturn != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _returnWithData,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text(
                              'Save & View History',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  if (finalResultToReturn != null &&
                      !_isMistakeReported &&
                      _currentMode == ScanMode.defect) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showReportMistakeDialog,
                        icon: const Icon(
                          Icons.report_problem_outlined,
                          color: Colors.orange,
                        ),
                        label: const Text(
                          'AI is wrong? Report Mistake',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Colors.orange,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (fabricItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(
                  child: Text(
                    "No scan results yet.\nPlease add an image.",
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                itemCount: fabricItems.length,
                itemBuilder: (context, index) {
                  var item = fabricItems[index];
                  Color iconColor = _currentMode == ScanMode.fabricType
                      ? Colors.blue
                      : (item.isDefect ? Colors.red : Colors.green);
                  IconData iconType = _currentMode == ScanMode.fabricType
                      ? Icons.info
                      : (item.isDefect ? Icons.warning : Icons.check_circle);

                  return Card(
                    child: ListTile(
                      leading: Icon(iconType, color: iconColor),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        _currentMode == ScanMode.fabricType
                            ? 'AI Analysis'
                            : 'Confidence: ${(item.confidence * 100).toInt()}%',
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class FabricItem {
  final String name;
  final double confidence;
  final bool isDefect;
  FabricItem({
    required this.name,
    required this.confidence,
    required this.isDefect,
  });
}
