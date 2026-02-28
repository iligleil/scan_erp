import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../models/scanned_item.dart';

class ExportService {
  static Future<void> exportToInventoryJson(List<ScannedItem> items) async {
    if (items.isEmpty) return;

    try {
      // 1. Формируем данные (в точности как в main_old.dart)
      List<Map<String, dynamic>> exportData = items.map((item) {
        Map<String, dynamic> details = {};
        try {
          details = jsonDecode(item.fullContent);
        } catch (e) {
          // Если JSON битый, пытаемся вытащить GUID регуляркой
          RegExp guidRegex = RegExp(r'"GUID":\s*"([^"]+)"', caseSensitive: false);
          RegExp orgRegex = RegExp(r'"ORG":\s*"([^"]+)"', caseSensitive: false);
          details = {
            "ORG": orgRegex.firstMatch(item.fullContent)?.group(1) ?? "",
            "GUID": guidRegex.firstMatch(item.fullContent)?.group(1) ?? "",
          };
        }

        return {
          "ORG": details["ORG"] ?? "",
          "NAME": item.displayTitle,
          "GUID": details["GUID"] ?? "",
          "COUNT": item.quantity,
        };
      }).toList();

      String jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      Uint8List bytes = Uint8List.fromList(utf8.encode(jsonString));

      // 2. Имя файла
      final now = DateTime.now();
      String timestamp = "${now.year}${now.month}${now.day}_${now.hour}${now.minute}";
      String fileName = "inventory_$timestamp.json";

      // 3. Сохранение через системный диалог (самый стабильный метод)
      await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить результат',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
    } catch (e) {
      print("Ошибка экспорта: $e");
    }
  }
}