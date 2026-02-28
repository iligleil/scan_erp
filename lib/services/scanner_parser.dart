import 'dart:convert';
import 'package:flutter/foundation.dart';

class ScannerParser {
  static Map<String, dynamic> parseRawCode(String rawCode) {
    String input = rawCode.trim();
    
    // 1. Поиск начала объекта (как в старой версии)
    int start = input.indexOf('{');
    if (start == -1) return {'title': "Ошибка", 'cleanJson': input};

    // 2. Обрезка дублей (как в старой версии)
    int nextStart = input.indexOf('{', start + 1);
    String workingPart = (nextStart != -1) ? input.substring(start, nextStart) : input.substring(start);
    workingPart = workingPart.trim();

    // 3. Исправление скобки (как в старой версии)
    if (!workingPart.endsWith('}')) {
      workingPart = '$workingPart}';
    }

    String displayTitle = "Объект";
    String cleanJsonForStorage = workingPart;

    try {
      final Map<String, dynamic> data = jsonDecode(workingPart);
      cleanJsonForStorage = jsonEncode(data); // Сохраняем чистый JSON

      final String? foundKey = data.keys.firstWhere(
        (k) => k.toUpperCase() == 'NAME',
        orElse: () => '',
      );
      displayTitle = (foundKey != null && foundKey.isNotEmpty) 
          ? data[foundKey].toString() 
          : "Без названия";
    } catch (e) {
      // План Б: Регулярка (как в старой версии)
      RegExp nameRegex = RegExp(r'"NAME":\s*"([^"]+)"', caseSensitive: false);
      var match = nameRegex.firstMatch(workingPart);
      displayTitle = match?.group(1) ?? "Ошибка разбора";
      // Сохраняем строку целиком, чтобы GUID не пропал
      cleanJsonForStorage = workingPart.replaceAll(RegExp(r'\s+'), ' ');
    }

    return {
      'title': displayTitle,
      'cleanJson': cleanJsonForStorage,
    };
  }

  static Map<String, dynamic> getDetails(String content) {
    try {
      return jsonDecode(content);
    } catch (e) {
      return {"Сырые данные": content};
    }
  }
}