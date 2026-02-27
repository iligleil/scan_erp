import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Инвентаризация ERP'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
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
                ),
                onChanged: (value) {
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
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: ListTile(
                    onTap: () {
                      // Красивое окно с данными списком
                      Map<String, dynamic> details = {};
                      try {
                        details = jsonDecode(item.fullContent);
                      } catch (e) {
                        details = {"Сырые данные": item.fullContent};
                      }

                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(item.displayTitle),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Детали объекта:", 
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                const Divider(),
                                ...details.entries.map((e) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(color: Colors.black87, fontSize: 14),
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
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text("ОК")),
                          ],
                        ),
                      ).then((_) => _requestFocus());
                    },
                    title: Text(item.displayTitle, 
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis, // Защита от длинных имен
                    ),
                    subtitle: Text("Количество: ${item.quantity}"),
                    trailing: const Icon(Icons.chevron_right),
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