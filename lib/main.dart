import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 營養顧問',
      theme: ThemeData(primarySwatch: Colors.green, useMaterial3: false),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(onGoToSettings: () => setState(() => _currentIndex = 3)),
      const RecordsPage(),
      const CalculatorPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'AI 食物分析' : _currentIndex == 1 ? '營養紀錄清單' : _currentIndex == 2 ? '熱量計算' : '設定'),
        backgroundColor: Colors.green,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: '分析'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '紀錄'),
          BottomNavigationBarItem(icon: Icon(Icons.calculate), label: '計算'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
}

// ==========================================
// 全域共用工具與常數
// ==========================================
final Map<String, String> nutrientDisplayNames = {
  'calories_kcal': '熱量 (kcal)', 'protein_g': '蛋白質 (g)', 'fat_g': '脂肪 (g)', 'carbs_g': '碳水化合物 (g)',
  'sugar_g': '糖分 (g)', 'sodium_mg': '鈉 (mg)', 'dietary_fiber_g': '膳食纖維 (g)', 'trans_fat_g': '反式脂肪 (g)',
  'cholesterol_mg': '膽固醇 (mg)', 'calcium_mg': '鈣 (mg)',
  'vitamin_A_ug': '維生素A (ug)', 'vitamin_B1_mg': '維生素B1 (mg)', 'vitamin_B2_mg': '維生素B2 (mg)',
  'vitamin_B6_mg': '維生素B6 (mg)', 'vitamin_B12_ug': '維生素B12 (ug)', 'vitamin_C_mg': '維生素C (mg)',
  'vitamin_D_ug': '維生素D (ug)', 'vitamin_E_mg': '維生素E (mg)', 'niacin_mg': '煙酸 (mg)',
  'phosphorus_mg': '磷 (mg)', 'potassium_mg': '鉀 (mg)', 'magnesium_mg': '鎂 (mg)',
  'iron_mg': '鐵 (mg)', 'zinc_mg': '鋅 (mg)', 'saturated_fat_g': '飽和脂肪 (g)',
  'selenium_ug': '硒 (ug)', 'copper_ug': '銅 (ug)', 'manganese_mg': '錳 (mg)',
};

Widget _buildEvalRow(String title, dynamic evalData) {
  if (evalData == null) return const SizedBox.shrink();
  String score = '?';
  String reason = '';
  if (evalData is Map) {
    score = evalData['score']?.toString() ?? '?';
    reason = evalData['reason']?.toString() ?? '';
  } else {
    score = '-';
    reason = evalData.toString();
  }

  Color scoreColor = Colors.grey;
  if (score == 'A') scoreColor = Colors.green;
  if (score == 'B') scoreColor = Colors.blue;
  if (score == 'C') scoreColor = Colors.orange;
  if (score == 'D') scoreColor = Colors.red;

  return Padding(
    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: scoreColor.withOpacity(0.2), border: Border.all(color: scoreColor), borderRadius: BorderRadius.circular(4)),
              child: Text(score, style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(reason, style: const TextStyle(color: Colors.black87)),
      ],
    ),
  );
}

num safeParseNum(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value;
  if (value is String) {
    String cleanStr = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return num.tryParse(cleanStr) ?? 0;
  }
  return 0;
}

Future<String> _generateDbThumbnail(Uint8List originalBytes) async {
  try {
    final ui.Codec codec = await ui.instantiateImageCodec(originalBytes, targetWidth: 400);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData? byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) return base64Encode(byteData.buffer.asUint8List());
  } catch (_) {}
  return base64Encode(originalBytes); 
}

// ==========================================
// 1. 主頁面：拍照與 AI 分析
// ==========================================
class HomePage extends StatefulWidget {
  final VoidCallback onGoToSettings;
  const HomePage({super.key, required this.onGoToSettings});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Uint8List? _imageBytes;
  final _noteController = TextEditingController();
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    final prefs = await SharedPreferences.getInstance();
    final uploadOriginal = prefs.getBool('upload_original') ?? false;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: uploadOriginal ? 1920 : 800,
      maxHeight: uploadOriginal ? 1920 : 800,
      imageQuality: uploadOriginal ? 100 : 70,
    );
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() { _imageBytes = bytes; });
    }
  }

  Future<void> _analyzeFood() async {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先拍照或從相簿選取食物照片')));
      return;
    }
    setState(() { _isLoading = true; });
    bool isRetrying = false;
    bool isCancelled = false;
    BuildContext? dialogContext;

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = (prefs.getString('gemini_api_key') ?? '').trim();
      final modelName = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';

      if (apiKey.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先切換至「設定」頁面輸入 API Key')));
        setState(() { _isLoading = false; });
        return;
      }

      final base64Image = base64Encode(_imageBytes!);
      
      final prompt = '''
你是一位專業的 AI 營養顧問。請分析照片中的食物，並參考備註：「${_noteController.text.trim()}」。
請務必只輸出純 JSON 格式，不要加入 ```json 標籤或任何說明文字。
請嚴格依照以下 JSON 結構輸出，不要改變欄位層級：
{
  "food_name": "你判斷的食物名稱",
  "total_weight_g": 250,
  "nutrients_per_100g": {
    "calories_kcal": 150,
    "protein_g": 10,
    "fat_g": 5.5,
    "carbs_g": 20,
    "sugar_g": 5,
    "sodium_mg": 300,
    "dietary_fiber_g": 2.5,
    "trans_fat_g": 0.0
  },
  "breakdown": [
    {"name": "食材1", "weight_g": 100, "calories_kcal": 150}
  ],
  "evaluation": {
    "fitness": {"score": "A", "reason": "說明..."},
    "weight_loss": {"score": "B", "reason": "說明..."},
    "diversity": {"score": "C", "reason": "說明..."},
    "overall": {"score": "A", "reason": "說明..."}
  }
}
''';

      final url = Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$modelName:generateContent', {'key': apiKey});
      final requestBody = jsonEncode({
        "contents": [{"parts": [{"text": prompt}, {"inline_data": {"mime_type": "image/jpeg", "data": base64Image}}]}],
        "generationConfig": {"response_mime_type": "application/json"}
      });

      while (!isCancelled) {
        final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: requestBody);
        if (response.statusCode == 200) {
          if (isRetrying && dialogContext != null && mounted) { Navigator.pop(dialogContext!); isRetrying = false; }
          final data = jsonDecode(response.body);
          String rawText = data['candidates'][0]['content']['parts'][0]['text'];
          int startIndex = rawText.indexOf('{');
          int endIndex = rawText.lastIndexOf('}');
          if (startIndex != -1 && endIndex != -1) rawText = rawText.substring(startIndex, endIndex + 1);
          final dbThumbnailBase64 = await _generateDbThumbnail(_imageBytes!);
          if (!mounted) return;
          _showResultAndSaveDialog(jsonDecode(rawText), dbThumbnailBase64);
          break; 
        } else if (response.statusCode == 503) {
          if (!isRetrying) {
            isRetrying = true;
            if (!mounted) return;
            // 完美還原原本 100% 的伺服器擁擠提示與設定跳轉按鈕
            showDialog(context: context, barrierDismissible: false, builder: (ctx) {
                dialogContext = ctx;
                return AlertDialog(title: const Text('伺服器滿載中'), content: const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.green), SizedBox(height: 16), Text('排隊等待模型中，請稍後。\n如等待過久，請至設定中嘗試其他模型。', textAlign: TextAlign.center)]), actions: [TextButton(onPressed: () { isCancelled = true; Navigator.pop(ctx); }, child: const Text('取消', style: TextStyle(color: Colors.grey))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), onPressed: () { isCancelled = true; Navigator.pop(ctx); widget.onGoToSettings(); }, child: const Text('選擇其他模型', style: TextStyle(color: Colors.white)))]);
            });
          }
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        } else {
          if (isRetrying && dialogContext != null && mounted) { Navigator.pop(dialogContext!); isRetrying = false; }
          String msg = '未知錯誤';
          try { msg = jsonDecode(response.body)['error']['message'] ?? response.body; } catch (_) { msg = response.body; }
          if (!mounted) return;
          showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('API 連線失敗 (${response.statusCode})'), content: SingleChildScrollView(child: Text('伺服器訊息:\n$msg')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))]));
          break;
        }
      }
    } catch (e) {
      if (isRetrying && dialogContext != null && mounted) Navigator.pop(dialogContext!);
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('發生錯誤'), content: SingleChildScrollView(child: Text('$e')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))]));
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _showResultAndSaveDialog(Map<String, dynamic> data, String dbBase64Img) {
    final nameCtrl = TextEditingController(text: data['food_name']?.toString() ?? '未命名食物');
    final num totalWeight = safeParseNum(data['total_weight_g']);
    final Map<String, dynamic> nutrients = data['nutrients_per_100g'] is Map ? data['nutrients_per_100g'] : {};
    final num caloriesPer100g = safeParseNum(nutrients['calories_kcal']);
    final num totalCalories = (caloriesPer100g / 100) * totalWeight;
    final dynamic breakdownData = data['breakdown'];
    final dynamic evaluation = data['evaluation'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 分析完成'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '食物名稱', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [const Text('預估總重', style: TextStyle(color: Colors.green)), Text('$totalWeight g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                      Column(children: [const Text('預估總熱量', style: TextStyle(color: Colors.green)), Text('${totalCalories.toStringAsFixed(1)} kcal', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                    ],
                  ),
                ),
                const Divider(height: 24),
                if (breakdownData is List && breakdownData.isNotEmpty) ...[
                  const Text('🍔 食物組成拆解：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ...breakdownData.whereType<Map>().map((item) {
                     num bWeight = safeParseNum(item['weight_g']);
                     num bKcal = safeParseNum(item['calories_kcal']);
                     return Padding(padding: const EdgeInsets.only(bottom: 4.0), child: Text('• ${item['name']} (${bWeight}g, ${bKcal}大卡)'));
                  }),
                  const Divider(height: 24),
                ],
                if (evaluation is Map) ...[
                  const Text('🤖 AI 專業評價：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  _buildEvalRow('健身', evaluation['fitness']),
                  _buildEvalRow('瘦身', evaluation['weight_loss']),
                  _buildEvalRow('多樣性', evaluation['diversity']),
                  _buildEvalRow('綜合', evaluation['overall']),
                  const Divider(height: 24),
                ],
                const Text('📊 每 100g 營養素含量：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ...nutrients.entries.where((e) => e.value != null && e.value.toString().toLowerCase() != 'null').map((e) {
                  num val = safeParseNum(e.value);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0), 
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(nutrientDisplayNames[e.key] ?? e.key), Text('$val', style: const TextStyle(fontWeight: FontWeight.bold))]),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('捨棄')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              data['food_name'] = nameCtrl.text.trim();
              data['record_date'] = DateTime.now().toString().substring(0, 16);
              data['calculated_total_calories'] = totalCalories;
              data['image_base64'] = dbBase64Img; 
              final prefs = await SharedPreferences.getInstance();
              final List list = jsonDecode(prefs.getString('food_records') ?? '[]');
              list.insert(0, data);
              await prefs.setString('food_records', jsonEncode(list));
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已儲存紀錄！')));
            },
            child: const Text('儲存紀錄', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
              child: _imageBytes == null
                  ? const Center(child: Text('請點選下方按鈕拍照或選圖', style: TextStyle(color: Colors.grey)))
                  : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('拍照'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
              ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('相簿'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: '文字備註 (例如：微糖微冰、半份、去皮)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.edit_note))),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: _isLoading ? null : _analyzeFood,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('送出 AI 分析', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. 紀錄頁面 (檢視詳細與跳轉編輯)
// ==========================================
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final List decoded = jsonDecode(prefs.getString('food_records') ?? '[]');
    setState(() { _records = decoded.map((e) => Map<String, dynamic>.from(e)).toList(); });
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('food_records', jsonEncode(_records));
  }

  void _exportJsonFile() {
    final lightweightRecords = _records.map((item) {
      var copy = Map<String, dynamic>.from(item);
      copy.remove('image_base64');
      return copy;
    }).toList();
    
    final jsonStr = jsonEncode(lightweightRecords);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('備份匯出 (純文字無圖)'),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(jsonStr, style: const TextStyle(fontSize: 10, color: Colors.grey)))),
        actions: [
          TextButton(
            onPressed: () { Clipboard.setData(ClipboardData(text: jsonStr)); Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已複製極輕量紀錄到剪貼簿！'))); },
            child: const Text('複製全部資料', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
        ],
      ),
    );
  }

  void _importJsonFile() {
    final inputCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('備份匯入 (純文字)'),
        content: TextField(controller: inputCtrl, maxLines: 8, decoration: const InputDecoration(hintText: '請貼上 JSON 資料...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              try {
                final List parsed = jsonDecode(inputCtrl.text.trim());
                setState(() { _records = parsed.map((e) => Map<String, dynamic>.from(e)).toList(); });
                await _saveRecords();
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('資料匯入成功！可點擊食物進行編輯或補上圖片。')));
              } catch (_) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('匯入失敗，格式錯誤'))); }
            },
            child: const Text('確定匯入'),
          ),
        ],
      ),
    );
  }

  void _showDetail(Map<String, dynamic> item, int index) {
    final Map<String, dynamic> nutrients = item['nutrients_per_100g'] is Map ? item['nutrients_per_100g'] : {};
    final dynamic breakdownData = item['breakdown'];
    final dynamic evaluation = item['evaluation'];
    final String? base64Img = item['image_base64'];
    
    num tWeight = safeParseNum(item['total_weight_g']);
    num cPer100 = safeParseNum(nutrients['calories_kcal']);
    num totalCalories = (cPer100 / 100) * tWeight;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(item['food_name']?.toString() ?? '詳細數據', overflow: TextOverflow.ellipsis)),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              tooltip: '編輯完整數值與圖片',
              onPressed: () async {
                Navigator.pop(ctx);
                final updated = await Navigator.push(context, MaterialPageRoute(builder: (_) => EditRecordPage(record: item)));
                if (updated != null) {
                  setState(() { _records[index] = updated; });
                  _saveRecords();
                }
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (base64Img != null && base64Img.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(base64Img), height: 180, width: double.infinity, fit: BoxFit.cover)),
                  ),
                Text('紀錄時間: ${item['record_date'] ?? '無'}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('總重: ${tWeight}g', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('總熱量: ${totalCalories.toStringAsFixed(1)} kcal', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Divider(height: 20),
                if (breakdownData is List && breakdownData.isNotEmpty) ...[
                  const Text('🍔 食物拆解：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ...breakdownData.whereType<Map>().map((b) {
                     num bWeight = safeParseNum(b['weight_g']);
                     num bKcal = safeParseNum(b['calories_kcal']);
                     return Text('• ${b['name']} (${bWeight}g, ${bKcal}大卡)');
                  }),
                  const Divider(height: 20),
                ],
                if (evaluation is Map) ...[
                  const Text('🤖 AI 專業評價：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  _buildEvalRow('健身', evaluation['fitness']),
                  _buildEvalRow('瘦身', evaluation['weight_loss']),
                  _buildEvalRow('多樣性', evaluation['diversity']),
                  _buildEvalRow('綜合', evaluation['overall']),
                  const Divider(height: 20),
                ],
                const Text('📊 每 100g 數值：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ...nutrients.entries.where((e) => e.value != null && e.value.toString().toLowerCase() != 'null').map((e) {
                  num val = safeParseNum(e.value);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(nutrientDisplayNames[e.key] ?? e.key), Text('$val', style: const TextStyle(fontWeight: FontWeight.bold))]),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () { setState(() { _records.removeAt(index); }); _saveRecords(); Navigator.pop(ctx); }, child: const Text('刪除此筆')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(onPressed: _exportJsonFile, icon: const Icon(Icons.copy), label: const Text('輕量匯出')),
              OutlinedButton.icon(onPressed: _importJsonFile, icon: const Icon(Icons.paste), label: const Text('貼上匯入')),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _records.isEmpty
              ? const Center(child: Text('目前尚無分析紀錄'))
              : ListView.builder(
                  itemCount: _records.length,
                  itemBuilder: (ctx, i) {
                    final item = _records[i];
                    final String? base64Img = item['image_base64'];
                    num tWeight = safeParseNum(item['total_weight_g']);
                    num cPer100 = safeParseNum(item['nutrients_per_100g']?['calories_kcal']);
                    num totalCalories = (cPer100 / 100) * tWeight;
                    
                    return ListTile(
                      leading: base64Img != null && base64Img.isNotEmpty
                          ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(base64Img), width: 50, height: 50, fit: BoxFit.cover))
                          : const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.restaurant, color: Colors.white)),
                      title: Text(item['food_name']?.toString() ?? '未命名食物', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item['record_date'] ?? ''}\n${tWeight}g · ${totalCalories.toStringAsFixed(0)} kcal'),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setState(() { _records.removeAt(i); }); _saveRecords(); }),
                      onTap: () => _showDetail(item, i),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ==========================================
// 2-1. 全螢幕紀錄編輯頁面 (比例自動重算)
// ==========================================
class EditRecordPage extends StatefulWidget {
  final Map<String, dynamic> record;
  const EditRecordPage({super.key, required this.record});

  @override
  State<EditRecordPage> createState() => _EditRecordPageState();
}

class _EditRecordPageState extends State<EditRecordPage> {
  late TextEditingController nameCtrl;
  late TextEditingController weightCtrl;
  late TextEditingController kcalCtrl;
  late TextEditingController proteinCtrl;
  late TextEditingController fatCtrl;
  late TextEditingController carbsCtrl;
  late TextEditingController sugarCtrl;
  late TextEditingController sodiumCtrl;
  late TextEditingController fiberCtrl;
  late TextEditingController transFatCtrl;
  
  String? _currentBase64Img;
  late double _originalTotalWeight;
  late double _original100gKcal;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    final n = r['nutrients_per_100g'] is Map ? r['nutrients_per_100g'] : {};
    
    _currentBase64Img = r['image_base64'];
    _originalTotalWeight = safeParseNum(r['total_weight_g']).toDouble();
    _original100gKcal = safeParseNum(n['calories_kcal']).toDouble();

    nameCtrl = TextEditingController(text: r['food_name']?.toString() ?? '');
    weightCtrl = TextEditingController(text: _originalTotalWeight.toString());
    kcalCtrl = TextEditingController(text: _original100gKcal.toString());
    proteinCtrl = TextEditingController(text: safeParseNum(n['protein_g']).toString());
    fatCtrl = TextEditingController(text: safeParseNum(n['fat_g']).toString());
    carbsCtrl = TextEditingController(text: safeParseNum(n['carbs_g']).toString());
    sugarCtrl = TextEditingController(text: safeParseNum(n['sugar_g']).toString());
    sodiumCtrl = TextEditingController(text: safeParseNum(n['sodium_mg']).toString());
    fiberCtrl = TextEditingController(text: safeParseNum(n['dietary_fiber_g']).toString());
    transFatCtrl = TextEditingController(text: safeParseNum(n['trans_fat_g']).toString());
  }

  Future<void> _pickNewImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 70);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      final thumbBase64 = await _generateDbThumbnail(bytes);
      setState(() { _currentBase64Img = thumbBase64; });
    }
  }

  void _saveAndRecalculate() {
    Map<String, dynamic> updatedRecord = Map<String, dynamic>.from(widget.record);
    double newWeight = double.tryParse(weightCtrl.text) ?? 0;
    double newKcal = double.tryParse(kcalCtrl.text) ?? 0;

    double weightRatio = (_originalTotalWeight > 0) ? (newWeight / _originalTotalWeight) : 1.0;
    double kcalRatio = (_original100gKcal > 0) ? (newKcal / _original100gKcal) : 1.0;

    if (updatedRecord['breakdown'] is List) {
      List newBreakdown = [];
      for (var b in updatedRecord['breakdown']) {
        if (b is Map) {
          double bW = safeParseNum(b['weight_g']).toDouble();
          double bK = safeParseNum(b['calories_kcal']).toDouble();
          b['weight_g'] = double.parse((bW * weightRatio).toStringAsFixed(1));
          b['calories_kcal'] = double.parse((bK * weightRatio * kcalRatio).toStringAsFixed(1));
          newBreakdown.add(b);
        }
      }
      updatedRecord['breakdown'] = newBreakdown;
    }

    updatedRecord['food_name'] = nameCtrl.text.trim();
    updatedRecord['total_weight_g'] = newWeight;
    updatedRecord['image_base64'] = _currentBase64Img;
    
    Map<String, dynamic> newNutrients = updatedRecord['nutrients_per_100g'] is Map ? Map.from(updatedRecord['nutrients_per_100g']) : {};
    newNutrients['calories_kcal'] = newKcal;
    newNutrients['protein_g'] = double.tryParse(proteinCtrl.text) ?? 0;
    newNutrients['fat_g'] = double.tryParse(fatCtrl.text) ?? 0;
    newNutrients['carbs_g'] = double.tryParse(carbsCtrl.text) ?? 0;
    newNutrients['sugar_g'] = double.tryParse(sugarCtrl.text) ?? 0;
    newNutrients['sodium_mg'] = double.tryParse(sodiumCtrl.text) ?? 0;
    newNutrients['dietary_fiber_g'] = double.tryParse(fiberCtrl.text) ?? 0;
    newNutrients['trans_fat_g'] = double.tryParse(transFatCtrl.text) ?? 0;
    
    updatedRecord['nutrients_per_100g'] = newNutrients;
    Navigator.pop(context, updatedRecord);
  }

  Widget _buildTextField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('編輯詳細紀錄'), backgroundColor: Colors.green, actions: [IconButton(icon: const Icon(Icons.check), onPressed: _saveAndRecalculate)]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickNewImage,
                child: Container(
                  height: 180, width: double.infinity,
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400)),
                  child: (_currentBase64Img != null && _currentBase64Img!.isNotEmpty)
                      ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(_currentBase64Img!), fit: BoxFit.cover))
                      : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 40, color: Colors.grey), SizedBox(height: 8), Text('點擊補上/更換圖片', style: TextStyle(color: Colors.grey))]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('💡 修改總重或每 100g 熱量時，系統會自動等比例重算食材拆解數值。', style: TextStyle(color: Colors.blue, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '食物名稱', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 12),
            _buildTextField('總重量 (g)', weightCtrl),
            const Divider(height: 24),
            const Text('每 100g 營養素含量', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _buildTextField('熱量 (kcal)', kcalCtrl),
            Row(children: [Expanded(child: _buildTextField('碳水 (g)', carbsCtrl)), const SizedBox(width: 8), Expanded(child: _buildTextField('蛋白質 (g)', proteinCtrl)), const SizedBox(width: 8), Expanded(child: _buildTextField('脂肪 (g)', fatCtrl))]),
            Row(children: [Expanded(child: _buildTextField('糖分 (g)', sugarCtrl)), const SizedBox(width: 8), Expanded(child: _buildTextField('膳食纖維 (g)', fiberCtrl))]),
            Row(children: [Expanded(child: _buildTextField('鈉 (mg)', sodiumCtrl)), const SizedBox(width: 8), Expanded(child: _buildTextField('反式脂肪 (g)', transFatCtrl))]),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. 熱量計算頁面 (包含 AI 綜合評價)
// ==========================================
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});
  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  List<Map<String, dynamic>> _records = [];
  final List<Map<String, dynamic>> _selectedItems = [];
  int _targetCalories = 2000;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final List decoded = jsonDecode(prefs.getString('food_records') ?? '[]');
    setState(() {
      _records = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      _targetCalories = prefs.getInt('target_calories') ?? 2000;
    });
  }

  void _addToCalculator(Map<String, dynamic> record) {
    setState(() { _selectedItems.add({'record': record, 'multiplier': 1.0}); });
  }

  void _updateMultiplier(int index, double delta) {
    setState(() {
      double current = _selectedItems[index]['multiplier'];
      current += delta;
      if (current <= 0) _selectedItems.removeAt(index);
      else _selectedItems[index]['multiplier'] = current;
    });
  }

  void _showAIEvalDialog(double tKcal, double tPro, double tFat, double tCarbs, double tSugar, double tSodium, double tFiber, double tTransFat) {
    if (_selectedItems.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先加入食物！'))); return; }
    final questionCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('向 AI 營養顧問提問'),
        content: TextField(controller: questionCtrl, maxLines: 4, decoration: const InputDecoration(hintText: '（可選）你想問 AI 什麼？例如：今天飲食健康嗎？', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () { Navigator.pop(ctx); _submitAIEval(questionCtrl.text.trim(), tKcal, tPro, tFat, tCarbs, tSugar, tSodium, tFiber, tTransFat); }, child: const Text('送出評價', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Future<void> _submitAIEval(String question, double tKcal, double tPro, double tFat, double tCarbs, double tSugar, double tSodium, double tFiber, double tTransFat) async {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(content: Row(children: const [CircularProgressIndicator(), SizedBox(width: 20), Text('AI 評估中...')])));
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = (prefs.getString('gemini_api_key') ?? '').trim();
      final modelName = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';
      if (apiKey.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先至「設定」輸入 API Key'))); return; }

      StringBuffer foodListString = StringBuffer();
      for (int i = 0; i < _selectedItems.length; i++) {
        final item = _selectedItems[i]; final record = item['record']; final double multiplier = item['multiplier'];
        final double weight = safeParseNum(record['total_weight_g']).toDouble();
        final n = record['nutrients_per_100g'] is Map ? record['nutrients_per_100g'] : {};
        final kcal = (safeParseNum(n['calories_kcal']) / 100) * weight * multiplier;
        final name = record['food_name'] ?? '未命名';
        foodListString.writeln('${i + 1}. $name (${multiplier}份, 約${(weight * multiplier).toStringAsFixed(0)}g)：${kcal.toStringAsFixed(0)} kcal');
      }

      final prompt = '''
你是一位專業且溫暖的 AI 營養顧問。
【今日數據總結】
目標熱量：$_targetCalories kcal | 實際熱量：${tKcal.toStringAsFixed(1)} kcal
碳水：${tCarbs.toStringAsFixed(1)}g | 蛋白質：${tPro.toStringAsFixed(1)}g | 脂肪：${tFat.toStringAsFixed(1)}g
糖分：${tSugar.toStringAsFixed(1)}g | 鈉：${tSodium.toStringAsFixed(1)}mg | 纖維：${tFiber.toStringAsFixed(1)}g | 反式脂肪：${tTransFat.toStringAsFixed(1)}g
【飲食明細】
$foodListString
【使用者提問】
${question.isEmpty ? "無提問，請給予整體總結與建議。" : question}

請嚴格輸出純 JSON 格式：
{
  "health_score": 85, 
  "overall_review": "綜合評語(包含對糖、鈉、纖維的看法)...",
  "suggestions": ["建議1", "建議2"],
  "qa_answer": "回答提問或鼓勵..."
}
''';

      final url = Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$modelName:generateContent', {'key': apiKey});
      final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode({ "contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"response_mime_type": "application/json"} }));
      Navigator.pop(context);

      if (response.statusCode == 200) {
        String rawText = jsonDecode(response.body)['candidates'][0]['content']['parts'][0]['text'];
        int start = rawText.indexOf('{'); int end = rawText.lastIndexOf('}');
        if (start != -1 && end != -1) rawText = rawText.substring(start, end + 1);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (context) => AIEvaluationResultPage(
          selectedItems: List.from(_selectedItems), targetCalories: _targetCalories,
          totalKcal: tKcal, totalProtein: tPro, totalFat: tFat, totalCarbs: tCarbs,
          totalSugar: tSugar, totalSodium: tSodium, totalFiber: tFiber, totalTransFat: tTransFat,
          aiResponse: jsonDecode(rawText),
        )));
      } else {
        String msg = response.body;
        try { msg = jsonDecode(response.body)['error']['message'] ?? response.body; } catch (_) {}
        if (!mounted) return;
        showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('API 失敗 (${response.statusCode})'), content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))]));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('連線錯誤'), content: Text('$e'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))]));
    }
  }

  @override
  Widget build(BuildContext context) {
    double tKcal = 0, tPro = 0, tFat = 0, tCarbs = 0, tSugar = 0, tSodium = 0, tFiber = 0, tTransFat = 0;

    for (var item in _selectedItems) {
      final record = item['record']; final double m = item['multiplier'];
      final double w = safeParseNum(record['total_weight_g']).toDouble();
      final n = record['nutrients_per_100g'] is Map ? record['nutrients_per_100g'] : {};
      
      double calc(String key) => (safeParseNum(n[key]) / 100) * w * m;
      tKcal += calc('calories_kcal'); tPro += calc('protein_g'); tFat += calc('fat_g'); tCarbs += calc('carbs_g');
      tSugar += calc('sugar_g'); tSodium += calc('sodium_mg'); tFiber += calc('dietary_fiber_g'); tTransFat += calc('trans_fat_g');
    }
    double rem = _targetCalories - tKcal;

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  color: Colors.grey.shade100,
                  child: ListView.builder(
                    itemCount: _records.length,
                    itemBuilder: (ctx, i) {
                      final r = _records[i]; final String? b64 = r['image_base64'];
                      return InkWell(
                        onTap: () => _addToCalculator(r),
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Column(children: [
                                if (b64 != null && b64.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(b64), height: 40, width: double.infinity, fit: BoxFit.cover)) else const Icon(Icons.restaurant, color: Colors.green),
                                const SizedBox(height: 4), Text(r['food_name']?.toString() ?? '未命名', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                flex: 2,
                child: _selectedItems.isEmpty
                    ? const Center(child: Text('請從左側點選食物加入', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _selectedItems.length,
                        itemBuilder: (ctx, i) {
                          final item = _selectedItems[i]; final record = item['record']; final double m = item['multiplier'];
                          final double w = safeParseNum(record['total_weight_g']).toDouble();
                          final n = record['nutrients_per_100g'] is Map ? record['nutrients_per_100g'] : {};
                          final kcal = (safeParseNum(n['calories_kcal']) / 100) * w * m;
                          final String? b64 = record['image_base64'];

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  if (b64 != null && b64.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(b64), height: 50, width: 50, fit: BoxFit.cover)) else Container(width: 50, height: 50, color: Colors.green, child: const Icon(Icons.restaurant, color: Colors.white)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(record['food_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), Text('${(w * m).toStringAsFixed(0)}g | ${kcal.toStringAsFixed(0)} kcal', style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold))])),
                                  Column(children: [IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _updateMultiplier(i, 0.5)), Text('$m 份', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.do_not_disturb_on, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _updateMultiplier(i, -0.5))])
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))]),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('加總熱量: ${tKcal.toStringAsFixed(0)} kcal', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('目標: $_targetCalories | 剩餘: ${rem.toStringAsFixed(0)}', style: TextStyle(color: rem < 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Row(
                    children: [
                      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 12)), onPressed: () => _showAIEvalDialog(tKcal, tPro, tFat, tCarbs, tSugar, tSodium, tFiber, tTransFat), child: const Text('AI評價', style: TextStyle(color: Colors.white))),
                      const SizedBox(width: 8),
                      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 12)), onPressed: () => setState(() => _selectedItems.clear()), child: const Icon(Icons.delete_sweep, color: Colors.white)),
                    ],
                  )
                ],
              ),
              const Divider(),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text('碳水: ${tCarbs.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.orange)), const SizedBox(width: 12),
                    Text('蛋白: ${tPro.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.blue)), const SizedBox(width: 12),
                    Text('脂肪: ${tFat.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.redAccent)), const SizedBox(width: 12),
                    Text('糖: ${tSugar.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.pink)), const SizedBox(width: 12),
                    Text('鈉: ${tSodium.toStringAsFixed(0)}mg', style: const TextStyle(color: Colors.purple)),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}

// ==========================================
// 3-1. 全螢幕結果頁 (支援整體長截圖)
// ==========================================
class AIEvaluationResultPage extends StatelessWidget {
  final List<Map<String, dynamic>> selectedItems;
  final int targetCalories;
  final double totalKcal, totalProtein, totalFat, totalCarbs, totalSugar, totalSodium, totalFiber, totalTransFat;
  final Map<String, dynamic> aiResponse;

  const AIEvaluationResultPage({
    super.key, required this.selectedItems, required this.targetCalories,
    required this.totalKcal, required this.totalProtein, required this.totalFat, required this.totalCarbs,
    required this.totalSugar, required this.totalSodium, required this.totalFiber, required this.totalTransFat,
    required this.aiResponse,
  });

  @override
  Widget build(BuildContext context) {
    final int score = int.tryParse(aiResponse['health_score']?.toString() ?? '0') ?? 0;
    final String overallReview = aiResponse['overall_review']?.toString() ?? '無評語';
    final List suggestions = aiResponse['suggestions'] is List ? aiResponse['suggestions'] : [];
    final String qaAnswer = aiResponse['qa_answer']?.toString() ?? '';

    Color scoreColor = Colors.green; if (score < 60) scoreColor = Colors.red; else if (score < 80) scoreColor = Colors.orange;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 飲食診斷報告'), backgroundColor: Colors.blue),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📝 今日飲食明細', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.75),
                itemCount: selectedItems.length,
                itemBuilder: (ctx, i) {
                  final item = selectedItems[i]; final record = item['record']; final double m = item['multiplier'];
                  final double w = safeParseNum(record['total_weight_g']).toDouble();
                  final n = record['nutrients_per_100g'] is Map ? record['nutrients_per_100g'] : {};
                  final kcal = (safeParseNum(n['calories_kcal']) / 100) * w * m;
                  final String? b64 = record['image_base64'];
                  return Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: (b64 != null && b64.isNotEmpty) ? Image.memory(base64Decode(b64), fit: BoxFit.cover) : Container(color: Colors.grey[200], child: const Icon(Icons.restaurant, color: Colors.grey, size: 40)))),
                        Expanded(flex: 4, child: Padding(padding: const EdgeInsets.all(8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(record['food_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${m}份 (${(w * m).toStringAsFixed(0)}g)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const Spacer(),
                          Text('${kcal.toStringAsFixed(0)} kcal', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                        ]))),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('總熱量', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text('${totalKcal.toStringAsFixed(0)} / $targetCalories kcal', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 20, runSpacing: 16, alignment: WrapAlignment.center,
                      children: [
                        _buildMacroText('碳水', totalCarbs, 'g', Colors.orange),
                        _buildMacroText('蛋白質', totalProtein, 'g', Colors.blue),
                        _buildMacroText('脂肪', totalFat, 'g', Colors.redAccent),
                        _buildMacroText('糖分', totalSugar, 'g', Colors.pink),
                        _buildMacroText('膳食纖維', totalFiber, 'g', Colors.green),
                        _buildMacroText('鈉', totalSodium, 'mg', Colors.purple),
                        _buildMacroText('反式脂肪', totalTransFat, 'g', Colors.brown),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Row(children: [
                Stack(alignment: Alignment.center, children: [SizedBox(width: 70, height: 70, child: CircularProgressIndicator(value: score / 100, color: scoreColor, backgroundColor: Colors.grey[200], strokeWidth: 8)), Text('$score', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: scoreColor))]),
                const SizedBox(width: 16), const Expanded(child: Text('AI 健康評分', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 24),
              
              const Text('💡 綜合評語', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)), const SizedBox(height: 8), Text(overallReview, style: const TextStyle(fontSize: 15, height: 1.5)), const SizedBox(height: 24),
              if (suggestions.isNotEmpty) ...[const Text('✅ 改善建議', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)), const SizedBox(height: 8), ...suggestions.map((s) => Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Expanded(child: Text(s.toString(), style: const TextStyle(fontSize: 15, height: 1.5)))]))), const SizedBox(height: 24)],
              if (qaAnswer.isNotEmpty) ...[Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('💬 AI 顧問回覆', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber)), const SizedBox(height: 8), Text(qaAnswer, style: const TextStyle(fontSize: 15, height: 1.5))]))],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMacroText(String title, double value, String unit, Color color) {
    return Column(children: [Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text('${value.toStringAsFixed(1)}$unit', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))]);
  }
}

// ==========================================
// 4. 教學與設定頁面 (已完全復原為原版模型清單)
// ==========================================
class ApiKeyHelpPage extends StatelessWidget {
  const ApiKeyHelpPage({super.key});
  @override Widget build(BuildContext context) { return Scaffold(appBar: AppBar(title: const Text('如何獲取免費 API Key'), backgroundColor: Colors.blue), body: ListView(padding: const EdgeInsets.all(16.0), children: const [ListTile(leading: CircleAvatar(child: Text('1')), title: Text('前往 Google AI Studio 網站'), subtitle: Text('[https://aistudio.google.com/](https://aistudio.google.com/)')), ListTile(leading: CircleAvatar(child: Text('2')), title: Text('點擊左側 Get API key'))])); }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyController = TextEditingController();
  final _targetCaloriesController = TextEditingController(); 
  String _selectedModel = 'gemini-3.8-flash';
  bool _uploadOriginal = false;

  final Map<String, String> _modelDescriptions = {
    'gemini-3.1-pro-preview': '【優點】最強大的模型，精準度極高，適合複雜食物與詳細微量元素分析。\n【缺點】處理速度較慢，免費 API 額度限制較嚴。',
    'gemini-3.8-flash': '【優點】最新推薦模型，聰明且速度快，適合日常快速分析。\n【缺點】無明顯缺點，強烈建議設為首選。',
    'gemini-3.5-flash-lite': '【優點】輕量極速版，回覆速度最快，幾乎不卡頓。\n【缺點】只適合簡單清晰的食物圖片，複雜的組合餐點容易誤判。',
  };

  @override void initState() { super.initState(); _loadSettings(); }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      _targetCaloriesController.text = (prefs.getInt('target_calories') ?? 2000).toString(); 
      String savedModel = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';
      // 確保如果存到舊代碼，預設會切回 3.8-flash
      if (!_modelDescriptions.containsKey(savedModel)) savedModel = 'gemini-3.8-flash';
      _selectedModel = savedModel;
      _uploadOriginal = prefs.getBool('upload_original') ?? false;
    });
  }

  Future<void> _autoSaveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKeyController.text.trim());
    await prefs.setInt('target_calories', int.tryParse(_targetCaloriesController.text.trim()) ?? 2000); 
    await prefs.setString('gemini_model', _selectedModel);
    await prefs.setBool('upload_original', _uploadOriginal);
  }

  @override Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每日目標熱量 (kcal)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
          TextField(controller: _targetCaloriesController, keyboardType: TextInputType.number, onChanged: (val) => _autoSaveSettings(), decoration: const InputDecoration(hintText: '預設 2000', border: OutlineInputBorder(), prefixIcon: Icon(Icons.local_fire_department, color: Colors.orange))), const SizedBox(height: 16),
          const Text('Gemini API 金鑰', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
          TextField(controller: _apiKeyController, onChanged: (val) => _autoSaveSettings(), decoration: const InputDecoration(hintText: '請輸入你的 API Key', border: OutlineInputBorder(), prefixIcon: Icon(Icons.vpn_key)), obscureText: true),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiKeyHelpPage())); }, child: const Text('如何免費申請 API Key？', style: TextStyle(decoration: TextDecoration.underline, fontSize: 13, color: Colors.blue)))), const SizedBox(height: 12),
          const Text('選擇 AI 分析模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gemini-3.1-pro-preview', child: Text('Gemini 3.1 Pro (最強)')),
              DropdownMenuItem(value: 'gemini-3.8-flash', child: Text('Gemini 3.8 Flash (推薦)')),
              DropdownMenuItem(value: 'gemini-3.5-flash-lite', child: Text('Gemini 3.5 Flash-Lite (極速)')),
            ],
            onChanged: (val) { if (val != null) { setState(() => _selectedModel = val); _autoSaveSettings(); } },
          ),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Text(_modelDescriptions[_selectedModel] ?? '', style: const TextStyle(color: Colors.black87, height: 1.4))), const SizedBox(height: 24),
          const Text('進階設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
          Container(decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)), child: SwitchListTile(title: const Text('上傳原圖給 AI 分析', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('【開啟】AI 辨識更精準，但消耗網路流量。\n【關閉】上傳前自動壓縮圖片，省流量速度快。', style: TextStyle(fontSize: 12, height: 1.3)), value: _uploadOriginal, activeColor: Colors.green, onChanged: (val) { setState(() => _uploadOriginal = val); _autoSaveSettings(); })),
        ],
      ),
    );
  }
}
