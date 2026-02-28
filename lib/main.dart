import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/scanned_item.dart';
import 'services/export_service.dart';
import 'services/scanner_parser.dart';

void main() => runApp(MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Calibri', 
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003387), 
          primary: const Color(0xFF003387),
          secondary: const Color(0xFF43B02A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF003387),
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      home: const InventoryScreen(),
      debugShowCheckedModeBanner: false,
    ));

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final List<ScannedItem> _scannedItems = [];
  bool _isBlockScanner = false;
  Timer? _debounce;
  ScannedItem? _lastItem;

  @override
  void initState() {
    super.initState();
    _initFocus();
  }


  void _processCode(String rawCode) {
    if (_isBlockScanner) return;

    // Парсим через наш сервис (который мы уже починили для GUID)
    final result = ScannerParser.parseRawCode(rawCode);

    setState(() {
      _isBlockScanner = true;
      
      int idx = _scannedItems.indexWhere((item) => item.displayTitle == result['title']);
      if (idx != -1) {
        _scannedItems[idx].quantity++;
        final item = _scannedItems.removeAt(idx);
        _scannedItems.insert(0, item);
      } else {
        _scannedItems.insert(0, ScannedItem(
          fullContent: result['cleanJson'], 
          displayTitle: result['title'], 
          quantity: 1
        ));
      }
      
    });

    // Блокировка на 500мс (вместо 1000мс), так как в буфере нет «дребезга» клавиш
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _isBlockScanner = false);
      }
    });
  }

  void _showEditDialog(ScannedItem item) {
    final TextEditingController qtyController = TextEditingController(text: item.quantity.toString());
    Map<String, dynamic> details = ScannerParser.getDetails(item.fullContent);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item.displayTitle, style: const TextStyle(color: Color(0xFF003387))),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Количество:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 35),
                      onPressed: () {
                        if (item.quantity > 1) {
                          setDialogState(() => item.quantity--);
                          qtyController.text = item.quantity.toString();
                          setState(() {});
                        }
                      },
                    ),
                    SizedBox(
                      width: 60,
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
                      icon: const Icon(Icons.add_circle_outline, color: Color(0xFF43B02A), size: 35),
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
                ...details.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text("${e.key}: ${e.value}", style: const TextStyle(fontSize: 12)),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("ГОТОВО")),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text('Инвентаризация ERP'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 28),
            onPressed: () { if (_scannedItems.isNotEmpty) _confirmClear(); },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          _buildScannerInput(),
          Expanded(child: _buildItemList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await ExportService.exportToInventoryJson(_scannedItems);
        },
        backgroundColor: const Color(0xFF003387),
        child: const Icon(Icons.save, color: Colors.white),
      ),
    );
  }

  Widget _buildScannerInput() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: RawKeyboardListener(
      focusNode: FocusNode(), // Отдельный узел для прослушки клавиш
      onKey: (RawKeyEvent event) {
        // Если сканер прислал "Enter" (LF) в конце
        if (event is RawKeyDownEvent && 
            (event.logicalKey == LogicalKeyboardKey.enter || 
             event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          if (_controller.text.isNotEmpty) {
            _processCode(_controller.text);
          }
        }
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        // Оставляем TextInputType.text, но скрываем клавиатуру. 
        // Это важно, чтобы система не блокировала ввод из буфера.
        keyboardType: TextInputType.text,
        maxLines: 1,
        showCursor: true,
        decoration: InputDecoration(
          labelText: _isBlockScanner ? 'ПРИНЯТО' : 'СКАНЕР ГОТОВ (CLIPBOARD)',
          labelStyle: TextStyle(
            color: _isBlockScanner ? Colors.orange : const Color(0xFF43B02A),
            fontWeight: FontWeight.bold
          ),
          filled: true,
          fillColor: _isBlockScanner ? Colors.orange.shade50 : const Color(0xFFF6FFF4),
          prefixIcon: Icon(
            Icons.qr_code_scanner, 
            color: _isBlockScanner ? Colors.orange : const Color(0xFF43B02A)
          ),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFF43B02A), width: 2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFF43B02A), width: 2.5)),
        ),
        onChanged: (val) {
          if (_isBlockScanner || val.isEmpty) return;

          // Если в строке уже есть полный JSON (Clipboard вставил всё сразу)
          if (val.contains('{') && val.contains('}')) {
            _processCode(val); 
          }
        },
        // Дополнительная подстраховка для терминатора LF
        onSubmitted: (val) {
          if (val.isNotEmpty) _processCode(val);
        },
      ),
    ),
  );
}

  Widget _buildItemList() {
    return ListView.builder(
      itemCount: _scannedItems.length,
      itemBuilder: (context, index) {
        final item = _scannedItems[index];
        final bool isLatest = item == _lastItem;

        return Dismissible(
          key: ObjectKey(item),
          direction: DismissDirection.endToStart,
          background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
          onDismissed: (_) => setState(() => _scannedItems.removeAt(index)),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            elevation: isLatest ? 8 : 1,
            color: isLatest ? const Color(0xFFF0F9EE) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: isLatest ? const Color(0xFF43B02A) : Colors.transparent, width: 2),
            ),
            child: ListTile(
              onTap: () => _showEditDialog(item),
              leading: isLatest 
                ? const Icon(Icons.stars, color: Color(0xFF43B02A), size: 30)
                : Container(width: 4, height: 30, color: const Color(0xFF003387)),
              title: Text(
                item.displayTitle, 
                style: TextStyle(fontWeight: FontWeight.bold, color: isLatest ? const Color(0xFF43B02A) : Colors.black87),
              ),
              subtitle: Text("Количество: ${item.quantity}"),
              trailing: isLatest ? const Text("СВЕЖИЙ", style: TextStyle(color: Color(0xFF43B02A), fontWeight: FontWeight.bold, fontSize: 10)) : const Icon(Icons.edit_note),
            ),
          ),
        );
      },
    );
  }

  void _confirmClear() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Очистить всё?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ОТМЕНА')),
        TextButton(onPressed: () { setState(() { _scannedItems.clear(); _lastItem = null; }); Navigator.pop(context); }, child: const Text('УДАЛИТЬ', style: TextStyle(color: Colors.red))),
      ],
    ));
  }
}