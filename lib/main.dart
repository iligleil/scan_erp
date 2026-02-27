import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const MaterialApp(home: InventoryScreen(), debugShowCheckedModeBanner: false));

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final List<ScannedItem> _scannedItems = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isBlockScanner = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initFocus();
  }

  void _initFocus() {
    Future.delayed(const Duration(milliseconds: 600), () => _requestFocus());
  }

  void _requestFocus() {
    if (mounted) {
      _focusNode.requestFocus();
      // Скрываем системную клавиатуру, чтобы не мешала
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  void _processCode(String rawCode) {
    String input = rawCode.trim();
    
    // Ищем начало JSON объекта
    int start = input.indexOf('{');
    if (start == -1) return;

    // Если сканер продублировал код, берем только первый объект
    int nextStart = input.indexOf('{', start + 1);
    String workingPart = (nextStart != -1) ? input.substring(start, nextStart) : input.substring(start);
    workingPart = workingPart.trim();

    // Исправляем JSON, если потерялась закрывающая скобка
    if (!workingPart.endsWith('}')) {
      workingPart = '$workingPart}';
    }

    setState(() => _isBlockScanner = true);
    
    String displayTitle = "Объект";
    String cleanJsonForStorage = workingPart;

    try {
      // Очищаем JSON от лишних пробелов и переносов для хранения
      final Map<String, dynamic> data = jsonDecode(workingPart);
      cleanJsonForStorage = jsonEncode(data); 

      // Ищем NAME в любом регистре
      final String? foundKey = data.keys.firstWhere(
        (k) => k.toUpperCase() == 'NAME',
        orElse: () => '',
      );
      displayTitle = (foundKey != null && foundKey.isNotEmpty) 
          ? data[foundKey].toString() 
          : "Без названия";
    } catch (e) {
      // План Б: вытаскиваем имя через регулярное выражение, если JSON совсем плох
      RegExp nameRegex = RegExp(r'"NAME":\s*"([^"]+)"', caseSensitive: false);
      var match = nameRegex.firstMatch(workingPart);
      displayTitle = match?.group(1) ?? "Ошибка разбора";
      cleanJsonForStorage = workingPart.replaceAll(RegExp(r'\s+'), ' ');
    }

    setState(() {
      // Ищем, есть ли уже такой товар в списке
      int idx = _scannedItems.indexWhere((item) => item.displayTitle == displayTitle);
      if (idx != -1) {
        _scannedItems[idx].quantity++;
        final item = _scannedItems.removeAt(idx);
        _scannedItems.insert(0, item);
      } else {
        _scannedItems.insert(0, ScannedItem(
          fullContent: cleanJsonForStorage, 
          displayTitle: displayTitle, 
          quantity: 1
        ));
      }
      _controller.clear(); 
    });

    // Пауза 1 сек для предотвращения повторного считывания того же кода
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() => _isBlockScanner = false);
        _controller.clear();
        _requestFocus();
      }
    });
  }

  Future<void> _exportToJson() async {
    if (_scannedItems.isEmpty) return;

    // 1. Формируем данные
    List<Map<String, dynamic>> exportData = _scannedItems.map((item) {
      Map<String, dynamic> originalJson = jsonDecode(item.fullContent);
      return {
        "ORG": originalJson["ORG"] ?? "",
        "NAME": item.displayTitle,
        "GUID": originalJson["GUID"] ?? "",
        "COUNT": item.quantity,
      };
    }).toList();

    String jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

    // 2. Генерируем уникальное имя файла (чтобы не было скобок в конце)
    final now = DateTime.now();
    String timestamp = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_"
                      "${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}";
    String fileName = "inventory_$timestamp.json";

    // 3. Вызываем сохранение через диалог (самый надежный способ для Android 13)
    _saveWithBackupMethod(jsonString, fileName);
  }

  Future<void> _saveWithBackupMethod(String content, String name) async {
    try {
      Uint8List bytes = Uint8List.fromList(utf8.encode(content));
      
      // Вызываем системный диалог. 
      // Передавая 'bytes', мы просим СИСТЕМУ записать файл, у неё есть права.
      String? result = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить файл',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes, 
      );

      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Файл успешно сохранен!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка сохранения: $e")),
      );
    }
  }
    
  void _showEditDialog(ScannedItem item) {
    final TextEditingController qtyController = TextEditingController(text: item.quantity.toString());

    // Парсим детали один раз перед показом диалога
    Map<String, dynamic> details = {};
    try {
      details = jsonDecode(item.fullContent);
    } catch (e) {
      details = {"Ошибка": "Не удалось разобрать JSON"};
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item.displayTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Количество:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                // БЛОК КНОПОК И ВВОДА
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 30),
                      onPressed: () {
                        if (item.quantity > 1) {
                          setDialogState(() => item.quantity--);
                          qtyController.text = item.quantity.toString();
                          setState(() {}); // Обновляем основной список
                        }
                      },
                    ),
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: qtyController,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (val) {
                          int? n = int.tryParse(val);
                          if (n != null) {
                            item.quantity = n;
                            setState(() {});
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 30),
                      onPressed: () {
                        setDialogState(() => item.quantity++);
                        qtyController.text = item.quantity.toString();
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const Divider(height: 30),
                const Text("Детали объекта:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 10),
                // ВАША ЛОГИКА С RICHTEXT
                ...details.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black87, fontSize: 13),
                      children: [
                        TextSpan(text: "${e.key}: ", style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: "${e.value}"),
                      ],
                    ),
                  ),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("ГОТОВО")),
          ],
        ),
      ),
    ).then((_) => _requestFocus());
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Инвентаризация ERP'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          // КНОПКА ЭКСПОРТА
          IconButton(
            icon: const Icon(Icons.ios_share), // Иконка "поделиться/выгрузить"
            tooltip: 'Выгрузить в JSON',
            onPressed: _exportToJson,
          ),
          // КНОПКА ОЧИСТКИ ВСЕГО СПИСКА
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Очистить всё',
            onPressed: () {
              if (_scannedItems.isEmpty) return;
              
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Очистить список?'),
                  content: const Text('Все отсканированные позиции будут удалены безвозвратно.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context), 
                      child: const Text('ОТМЕНА')
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _scannedItems.clear());
                        Navigator.pop(context);
                        _requestFocus();
                      }, 
                      child: const Text('УДАЛИТЬ', style: TextStyle(color: Colors.red))
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Поле ввода: визуально ограничено, но принимает любой объем текста
          SizedBox(
            height: 80,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLines: null, // Важно для режима Wedge Multiply
                style: const TextStyle(fontSize: 10),
                decoration: InputDecoration(
                  labelText: _isBlockScanner ? 'ПРИНЯТО' : 'ГОТОВ К СКАНИРОВАНИЮ',
                  filled: true,
                  fillColor: _isBlockScanner ? Colors.orange.shade50 : Colors.green.shade50,
                  border: const OutlineInputBorder(),
                  prefixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.blueGrey),
                      onPressed: () {
                        _controller.clear();
                        _requestFocus();
                      },
                    ),
                    // Кнопка быстрой очистки поля справа (стандартный крестик)
                    suffixIcon: _controller.text.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _controller.clear()),
                        ) 
                      : null,
                ),
                onChanged: (value) {
                  setState(() {});
                  if (_isBlockScanner) return;
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  
                  // Ждем завершения "печати" сканером
                  _debounce = Timer(const Duration(milliseconds: 400), () {
                    if (_controller.text.isNotEmpty) _processCode(_controller.text);
                  });
                },
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _scannedItems.length,
              itemBuilder: (context, index) {
                final item = _scannedItems[index];

                // 1. Обернули в Dismissible для свайпа
                return Dismissible(
                  key: Key(item.displayTitle + item.fullContent + index.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red.shade400,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (direction) {
                    setState(() {
                      _scannedItems.removeAt(index);
                    });
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: ListTile(
                      // 2. Вызываем расширенный диалог
                      onTap: () => _showEditDialog(item), 
                      title: Text(
                        item.displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text("Количество: ${item.quantity}"),
                      // Меняем иконку на "редактирование", чтобы намекнуть на тап
                      trailing: const Icon(Icons.edit_note, color: Colors.blueGrey),
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

class ScannedItem {
  final String fullContent;
  final String displayTitle;
  int quantity;
  ScannedItem({required this.fullContent, required this.displayTitle, required this.quantity});
}