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
// 全域共用工具與常數 (終極防呆機制)
// ==========================================
final Map<String, String> nutrientDisplayNames = {
  'calories_kcal': '熱量 (kcal)', 'protein_g': '蛋白質 (g)', 'fat_g': '脂肪 (g)', 'carbs_g': '碳水化合物 (g)',
  'dietary_fiber_g': '膳食纖維 (g)', 'cholesterol_mg': '膽固醇 (mg)', 'calcium_mg': '鈣 (mg)',
  'vitamin_A_ug': '維生素A (ug)', 'vitamin_B1_mg': '維生素B1 (mg)', 'vitamin_B2_mg': '維生素B2 (mg)',
  'vitamin_B6_mg': '維生素B6 (mg)', 'vitamin_B12_ug': '維生素B12 (ug)', 'vitamin_C_mg': '維生素C (mg)',
  'vitamin_D_ug': '維生素D (ug)', 'vitamin_E_mg': '維生素E (mg)', 'niacin_mg': '煙酸 (mg)',
  'phosphorus_mg': '磷 (mg)', 'potassium_mg': '鉀 (mg)', 'sodium_mg': '鈉 (mg)', 'magnesium_mg': '鎂 (mg)',
  'iron_mg': '鐵 (mg)', 'zinc_mg': '鋅 (mg)', 'trans_fat_g': '反式脂肪 (g)', 'saturated_fat_g': '飽和脂肪 (g)',
  'sugar_g': '糖 (g)', 'selenium_ug': '硒 (ug)', 'copper_ug': '銅 (ug)', 'manganese_mg': '錳 (mg)',
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
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: scoreColor.withOpacity(0.2), border: Border.all(color: scoreColor), borderRadius: BorderRadius.circular(4)), child: Text(score, style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold))),
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
    final pickedFile = await picker.pickImage(source: source, maxWidth: uploadOriginal ? 1920 : 800, maxHeight: uploadOriginal ? 1920 : 800, imageQuality: uploadOriginal ? 100 : 70);
    if (pickedFile != null) { final bytes = await pickedFile.readAsBytes(); setState(() { _imageBytes = bytes; }); }
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

  Future<void> _analyzeFood() async {
    if (_imageBytes == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先拍照或從相簿選取食物照片'))); return; }
    setState(() { _isLoading = true; });
    bool isRetrying = false; bool isCancelled = false; BuildContext? dialogContext;

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = (prefs.getString('gemini_api_key') ?? '').trim();
      final modelName = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';

      if (apiKey.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先切換至「設定」頁面輸入 API Key')));
        setState(() { _isLoading = false; }); return;
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
    "carbs_g": 20
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
（若有微量元素可自行加在 nutrients_per_100g 中，無則省略，數值請務必只填寫數字）
''';

      // 🛡️ 這裡改用安全的 Uri.https，徹底避免複製貼上帶來的隱藏符號與括號錯誤
      final url = Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/$modelName:generateContent',
        {'key': apiKey}
      );

      final requestBody = jsonEncode({ "contents": [{"parts": [{"text": prompt}, {"inline_data": {"mime_type": "image/jpeg", "data": base64Image}}]}], "generationConfig": {"response_mime_type": "application/json"} });

      while (!isCancelled) {
        final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: requestBody);
        if (response.statusCode == 200) {
          if (isRetrying && dialogContext != null && mounted) { Navigator.pop(dialogContext!); isRetrying = false; }
          final data = jsonDecode(response.body);
          String rawText = data['candidates'][0]['content']['parts'][0]['text'];
          int startIndex = rawText.indexOf('{'); int endIndex = rawText.lastIndexOf('}');
          if (startIndex != -1 && endIndex != -1) rawText = rawText.substring(startIndex, endIndex + 1);
          final dbThumbnailBase64 = await _generateDbThumbnail(_imageBytes!);
          if (!mounted) return;
          _showResultAndSaveDialog(jsonDecode(rawText), dbThumbnailBase64);
          break; 
        } else if (response.statusCode == 503) {
          if (!isRetrying) {
            isRetrying = true;
            if (!mounted) return;
            showDialog(context: context, barrierDismissible: false, builder: (ctx) {
                dialogContext = ctx;
                return AlertDialog(title: const Text('伺服器滿載中'), content: const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.green), SizedBox(height: 16), Text('排隊等待模型中，請稍後。\n如等待過久，請至設定中嘗試其他模型。', textAlign: TextAlign.center)]), actions: [TextButton(onPressed: () { isCancelled = true; Navigator.pop(ctx); }, child: const Text('取消', style: TextStyle(color: Colors.grey))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), onPressed: () { isCancelled = true; Navigator.pop(ctx); widget.onGoToSettings(); }, child: const Text('選擇其他模型', style: TextStyle(color: Colors.white)))]);
            });
          }
          await Future.delayed(const Duration(milliseconds: 500)); continue;
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
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('發生錯誤'), content: SingleChildScrollView(child: Text('無法解析資料或連線異常。\n\n詳細錯誤：\n$e')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確定'))]));
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
      context: context, barrierDismissible: false,
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
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Column(children: [const Text('預估總重量', style: TextStyle(color: Colors.green)), Text('$totalWeight g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]), Column(children: [const Text('預估總熱量', style: TextStyle(color: Colors.green)), Text('${totalCalories.toStringAsFixed(1)} kcal', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))])])),
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
                  _buildEvalRow('健身', evaluation['fitness']), _buildEvalRow('瘦身', evaluation['weight_loss']),
                  _buildEvalRow('多樣性', evaluation['diversity']), _buildEvalRow('綜合', evaluation['overall']),
                  const Divider(height: 24),
                ],
                const Text('📊 每 100g 營養素含量：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ...nutrients.entries.where((e) => e.value != null && e.value.toString().toLowerCase() != 'null').map((e) {
                  num val = safeParseNum(e.value);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0), 
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(nutrientDisplayNames[e.key] ?? e.key), Text('$val', style: const TextStyle(fontWeight: FontWeight.bold))])
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
              Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已儲存！')));
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
          Expanded(child: Container(width: double.infinity, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)), child: _imageBytes == null ? const Center(child: Text('請點選下方按鈕拍照', style: TextStyle(color: Colors.grey))) : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, fit: BoxFit.cover)))),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('拍照'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)), ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('相簿'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))]),
          const SizedBox(height: 12),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: '文字備註 (例如：無糖、半份、去皮)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.edit_note))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: _isLoading ? null : _analyzeFood, child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('送出 AI 分析', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }
}

// ==========================================
// 2. 紀錄頁面
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
    final jsonStr = jsonEncode(_records);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('備份匯出 (純文字)'),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(jsonStr, style: const TextStyle(fontSize: 10, color: Colors.grey)))),
        actions: [
          TextButton(
            onPressed: () { Clipboard.setData(ClipboardData(text: jsonStr)); Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已複製全部紀錄到剪貼簿！'))); },
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
        content: TextField(controller: inputCtrl, maxLines: 8, decoration: const InputDecoration(hintText: '請貼上您之前複製的整段 JSON 資料...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              try {
                final List parsed = jsonDecode(inputCtrl.text.trim());
                setState(() { _records = parsed.map((e) => Map<String, dynamic>.from(e)).toList(); });
                await _saveRecords();
                if (!mounted) return;
                Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('資料匯入成功！')));
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
    final editCtrl = TextEditingController(text: item['food_name']?.toString() ?? '');
    final dynamic breakdownData = item['breakdown'];
    final dynamic evaluation = item['evaluation'];
    final String? base64Img = item['image_base64'];
    
    num tWeight = safeParseNum(item['total_weight_g']);
    num cPer100 = safeParseNum(nutrients['calories_kcal']);
    num totalCalories = item['calculated_total_calories'] ?? ((cPer100 / 100) * tWeight);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(item['food_name']?.toString() ?? '詳細數據')),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () {
                showDialog(context: context, builder: (editCtx) => AlertDialog(title: const Text('修改名稱'), content: TextField(controller: editCtrl), actions: [TextButton(onPressed: () => Navigator.pop(editCtx), child: const Text('取消')), ElevatedButton(onPressed: () { setState(() { item['food_name'] = editCtrl.text.trim(); }); _saveRecords(); Navigator.pop(editCtx); Navigator.pop(ctx); }, child: const Text('保存'))]));
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
                  Padding(padding: const EdgeInsets.only(bottom: 12.0), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(base64Img), height: 180, width: double.infinity, fit: BoxFit.cover))),
                Text('紀錄時間: ${item['record_date'] ?? '無'}'),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Text('總重: ${tWeight}g', style: const TextStyle(fontWeight: FontWeight.bold)), Text('總熱量: ${totalCalories.toStringAsFixed(1)} kcal', style: const TextStyle(fontWeight: FontWeight.bold))])),
                const Divider(height: 20),
                if (breakdownData is List && breakdownData.isNotEmpty) ...[
                  const Text('🍔 拆解：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ...breakdownData.whereType<Map>().map((b) {
                     num bWeight = safeParseNum(b['weight_g']);
                     num bKcal = safeParseNum(b['calories_kcal']);
                     return Text('• ${b['name']} (${bWeight}g, ${bKcal}大卡)');
                  }),
                  const Divider(height: 20),
                ],
                if (evaluation is Map) ...[
                  const Text('🤖 評價：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  _buildEvalRow('健身', evaluation['fitness']), _buildEvalRow('瘦身', evaluation['weight_loss']),
                  _buildEvalRow('多樣性', evaluation['diversity']), _buildEvalRow('綜合', evaluation['overall']),
                  const Divider(height: 20),
                ],
                const Text('📊 每 100g 數值：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ...nutrients.entries.where((e) => e.value != null && e.value.toString().toLowerCase() != 'null').map((e) {
                  num val = safeParseNum(e.value);
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 2.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(nutrientDisplayNames[e.key] ?? e.key), Text('$val', style: const TextStyle(fontWeight: FontWeight.bold))]));
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
              OutlinedButton.icon(onPressed: _exportJsonFile, icon: const Icon(Icons.copy), label: const Text('匯出資料')),
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
                    num totalCalories = item['calculated_total_calories'] ?? ((cPer100 / 100) * tWeight);
                    
                    return ListTile(
                      leading: base64Img != null && base64Img.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(base64Img), width: 50, height: 50, fit: BoxFit.cover)) : const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.restaurant, color: Colors.white)),
                      title: Text(item['food_name']?.toString() ?? '未命名食物', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item['record_date'] ?? ''}\n${tWeight}g · ${totalCalories.toStringAsFixed(0)} kcal'),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: (){ setState(() { _records.removeAt(i); }); _saveRecords(); }),
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
// 3. 熱量計算頁面
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

  @override
  Widget build(BuildContext context) {
    double totalKcal = 0, totalProtein = 0, totalFat = 0, totalCarbs = 0;

    for (var item in _selectedItems) {
      final record = item['record'];
      final double multiplier = item['multiplier'];
      final double weight = safeParseNum(record['total_weight_g']).toDouble();
      final nutrients = record['nutrients_per_100g'] is Map ? record['nutrients_per_100g'] : {};
      
      totalKcal += (safeParseNum(nutrients['calories_kcal']) / 100) * weight * multiplier;
      totalProtein += (safeParseNum(nutrients['protein_g']) / 100) * weight * multiplier;
      totalFat += (safeParseNum(nutrients['fat_g']) / 100) * weight * multiplier;
      totalCarbs += (safeParseNum(nutrients['carbs_g']) / 100) * weight * multiplier;
    }

    double remainingKcal = _targetCalories - totalKcal;

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
                      final record = _records[i];
                      final String? base64Img = record['image_base64'];
                      return InkWell(
                        onTap: () => _addToCalculator(record),
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Column(
                              children: [
                                if (base64Img != null && base64Img.isNotEmpty)
                                  ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(base64Img), height: 40, width: double.infinity, fit: BoxFit.cover))
                                else
                                  const Icon(Icons.restaurant, color: Colors.green),
                                const SizedBox(height: 4),
                                Text(record['food_name']?.toString() ?? '未命名', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
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
                          final item = _selectedItems[i];
                          final record = item['record'];
                          final double multiplier = item['multiplier'];
                          final double weight = safeParseNum(record['total_weight_g']).toDouble();
                          final nutrients = record['nutrients_per_100g'] is Map ? record['nutrients_per_100g'] : {};
                          
                          final kcal = (safeParseNum(nutrients['calories_kcal']) / 100) * weight * multiplier;
                          final protein = (safeParseNum(nutrients['protein_g']) / 100) * weight * multiplier;
                          final fat = (safeParseNum(nutrients['fat_g']) / 100) * weight * multiplier;
                          final carbs = (safeParseNum(nutrients['carbs_g']) / 100) * weight * multiplier;
                          final String? base64Img = record['image_base64'];

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  if (base64Img != null && base64Img.isNotEmpty)
                                    ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(base64Img), height: 50, width: 50, fit: BoxFit.cover))
                                  else
                                    Container(width: 50, height: 50, color: Colors.green, child: const Icon(Icons.restaurant, color: Colors.white)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(record['food_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text('${(weight * multiplier).toStringAsFixed(0)}g | ${kcal.toStringAsFixed(0)} kcal', style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                                        Text('碳水:${carbs.toStringAsFixed(1)} 蛋白:${protein.toStringAsFixed(1)} 脂肪:${fat.toStringAsFixed(1)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _updateMultiplier(i, 0.5)),
                                      Text('${multiplier} 份', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      IconButton(icon: const Icon(Icons.do_not_disturb_on, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _updateMultiplier(i, -0.5)),
                                    ],
                                  )
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
          padding: const EdgeInsets.all(16.0),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))]),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('加總熱量: ${totalKcal.toStringAsFixed(0)} kcal', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('目標: $_targetCalories | 剩餘: ${remainingKcal.toStringAsFixed(0)}', style: TextStyle(color: remainingKcal < 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => setState(() => _selectedItems.clear()),
                    icon: const Icon(Icons.delete_sweep, color: Colors.white),
                    label: const Text('清空', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('碳水: ${totalCarbs.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.orange)),
                  Text('蛋白質: ${totalProtein.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.blue)),
                  Text('脂肪: ${totalFat.toStringAsFixed(1)}g', style: const TextStyle(color: Colors.redAccent)),
                ],
              )
            ],
          ),
        )
      ],
    );
  }
}

// ==========================================
// 4. 教學與設定頁面
// ==========================================
class ApiKeyHelpPage extends StatelessWidget {
  const ApiKeyHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('如何獲取免費 API Key'), backgroundColor: Colors.blue),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          ListTile(leading: CircleAvatar(child: Text('1')), title: Text('前往 Google AI Studio 網站'), subtitle: Text('[https://aistudio.google.com/](https://aistudio.google.com/)')),
          ListTile(leading: CircleAvatar(child: Text('2')), title: Text('點擊左側 Get API key')),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      _targetCaloriesController.text = (prefs.getInt('target_calories') ?? 2000).toString(); 
      _selectedModel = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每日目標熱量 (kcal)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _targetCaloriesController,
            keyboardType: TextInputType.number,
            onChanged: (val) => _autoSaveSettings(),
            decoration: const InputDecoration(hintText: '預設 2000', border: OutlineInputBorder(), prefixIcon: Icon(Icons.local_fire_department, color: Colors.orange)), 
          ),
          const SizedBox(height: 16),
          
          const Text('Gemini API 金鑰', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            onChanged: (val) => _autoSaveSettings(), 
            decoration: const InputDecoration(hintText: '請輸入你的 API Key', border: OutlineInputBorder(), prefixIcon: Icon(Icons.vpn_key)), 
            obscureText: true
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiKeyHelpPage()));
            }, child: const Text('如何免費申請 API Key？', style: TextStyle(decoration: TextDecoration.underline, fontSize: 13, color: Colors.blue))),
          ),
          const SizedBox(height: 12),
          
          const Text('選擇 AI 分析模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
            child: Text(_modelDescriptions[_selectedModel] ?? '', style: const TextStyle(color: Colors.black87, height: 1.4)),
          ),
          const SizedBox(height: 24),

          const Text('進階設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: SwitchListTile(
              title: const Text('上傳原圖給 AI 分析', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('【開啟】AI 辨識更精準，但消耗網路流量。\n【關閉】上傳前自動壓縮圖片，省流量速度快。', style: TextStyle(fontSize: 12, height: 1.3)),
              value: _uploadOriginal,
              activeColor: Colors.green,
              onChanged: (val) { setState(() => _uploadOriginal = val); _autoSaveSettings(); },
            ),
          ),
        ],
      ),
    );
  }
}
