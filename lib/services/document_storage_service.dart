import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/inventory_document.dart';
import '../models/scanned_item.dart';

class DocumentStorageService {
  static const String _documentsFolderName = 'scan_erp_documents';

  static Future<Directory> _getDocumentsFolder() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final folder = Directory('${baseDir.path}${Platform.pathSeparator}$_documentsFolderName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  static Future<List<InventoryDocument>> listDocuments() async {
    final folder = await _getDocumentsFolder();
    final entities = await folder.list().where((e) => e.path.endsWith('.json')).toList();

    final docs = <InventoryDocument>[];
    for (final entity in entities.whereType<File>()) {
      try {
        final data = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final itemCount = (data['items'] as List<dynamic>? ?? const []).length;
        docs.add(
          InventoryDocument(
            name: (data['name'] as String?) ?? _fileNameToTitle(entity.path),
            path: entity.path,
            updatedAt: DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
                await entity.lastModified(),
            itemCount: itemCount,
          ),
        );
      } catch (_) {
        docs.add(
          InventoryDocument(
            name: _fileNameToTitle(entity.path),
            path: entity.path,
            updatedAt: await entity.lastModified(),
            itemCount: 0,
          ),
        );
      }
    }

    docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return docs;
  }

  static Future<InventoryDocument> createDocument() async {
    final folder = await _getDocumentsFolder();
    final now = DateTime.now();
    final id = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    final defaultName = 'Документ $id';
    final file = File('${folder.path}${Platform.pathSeparator}document_$id.json');

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'name': defaultName,
        'updatedAt': now.toIso8601String(),
        'items': <Map<String, dynamic>>[],
      }),
    );

    return InventoryDocument(name: defaultName, path: file.path, updatedAt: now, itemCount: 0);
  }

  static Future<List<ScannedItem>> loadDocumentItems(String path) async {
    final file = File(path);
    if (!await file.exists()) return [];

    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>? ?? const []);

      return items
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => ScannedItem(
              fullContent: item['fullContent']?.toString() ?? '',
              displayTitle: item['displayTitle']?.toString() ?? 'Без названия',
              quantity: (item['quantity'] as num?)?.toInt() ?? 1,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveDocumentItems({
    required InventoryDocument document,
    required List<ScannedItem> items,
  }) async {
    final file = File(document.path);
    final now = DateTime.now();

    final payload = {
      'name': document.name,
      'updatedAt': now.toIso8601String(),
      'items': items
          .map(
            (item) => {
              'fullContent': item.fullContent,
              'displayTitle': item.displayTitle,
              'quantity': item.quantity,
            },
          )
          .toList(),
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  static String _fileNameToTitle(String path) {
    final fullName = path.split(Platform.pathSeparator).last;
    final noExt = fullName.replaceAll(RegExp(r'\.json$'), '');
    return noExt.replaceAll('_', ' ');
  }
}
