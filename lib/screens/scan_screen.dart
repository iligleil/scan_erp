import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inventory_document.dart';
import '../models/scanned_item.dart';
import '../services/document_storage_service.dart';
import '../services/scanner_parser.dart';

class ScanScreen extends StatefulWidget {
  final InventoryDocument document;

  const ScanScreen({super.key, required this.document});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final List<ScannedItem> _scannedItems = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isBlockScanner = false;
  ScannedItem? _lastItem;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocument();
    _initFocus();
  }

  Future<void> _loadDocument() async {
    final items = await DocumentStorageService.loadDocumentItems(widget.document.path);
    if (!mounted) return;
    setState(() {
      _scannedItems
        ..clear()
        ..addAll(items);
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _initFocus() => Future.delayed(const Duration(milliseconds: 600), _requestFocus);

  void _requestFocus() {
    if (mounted) _focusNode.requestFocus();
  }

  void _processCode(String rawCode) {
    if (_isBlockScanner) return;

    final result = ScannerParser.parseRawCode(rawCode);

    setState(() {
      _isBlockScanner = true;

      final idx = _scannedItems.indexWhere((item) => item.displayTitle == result['title']);
      if (idx != -1) {
        _scannedItems[idx].quantity++;
        final item = _scannedItems.removeAt(idx);
        _scannedItems.insert(0, item);
        _lastItem = item;
      } else {
        final newItem = ScannedItem(
          fullContent: result['cleanJson'],
          displayTitle: result['title'],
          quantity: 1,
        );
        _scannedItems.insert(0, newItem);
        _lastItem = newItem;
      }

      _controller.value = TextEditingValue.empty;
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _controller.clear();
      setState(() => _isBlockScanner = false);
      _requestFocus();
    });
  }

  Future<void> _saveDocument() async {
    _focusNode.unfocus();
    await DocumentStorageService.saveDocumentItems(
      document: widget.document,
      items: _scannedItems,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Документ сохранён в папку приложения')),
    );
    _requestFocus();
  }

  void _showEditDialog(ScannedItem item) {
    final qtyController = TextEditingController(text: item.quantity.toString());
    final details = ScannerParser.getDetails(item.fullContent);

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
                const Text('Количество:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          final n = int.tryParse(val);
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
                const Text(
                  'Детали объекта:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                const SizedBox(height: 10),
                ...details.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ГОТОВО'),
            ),
          ],
        ),
      ),
    ).then((_) => _requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: Text(widget.document.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 28),
            onPressed: () {
              if (_scannedItems.isNotEmpty) _confirmClear();
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildScannerInput(),
                Expanded(child: _buildItemList()),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveDocument,
        backgroundColor: const Color(0xFF003387),
        child: const Icon(Icons.save, color: Colors.white),
      ),
    );
  }

  Widget _buildScannerInput() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        enableInteractiveSelection: false,
        showCursor: false,
        maxLines: 1,
        keyboardType: TextInputType.none,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) {
          final code = value.trim();
          if (code.isEmpty) return;
          _processCode(code);
        },
        decoration: InputDecoration(
          labelText: _isBlockScanner ? 'ПРИНЯТО' : 'СКАНЕР ГОТОВ',
          labelStyle: TextStyle(
            color: _isBlockScanner ? Colors.orange : const Color(0xFF43B02A),
            fontWeight: FontWeight.bold,
          ),
          helperText: 'ТСД отправляет данные как ввод с клавиатуры',
          filled: true,
          fillColor: _isBlockScanner ? Colors.orange.shade50 : const Color(0xFFF6FFF4),
          prefixIcon: Icon(
            Icons.qr_code_scanner,
            color: _isBlockScanner ? Colors.orange : const Color(0xFF43B02A),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF43B02A), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF43B02A), width: 2.5),
          ),
        ),
      ),
    );
  }

  Widget _buildItemList() {
    return ListView.builder(
      itemCount: _scannedItems.length,
      itemBuilder: (context, index) {
        final item = _scannedItems[index];
        final isLatest = item == _lastItem;

        return Dismissible(
          key: ObjectKey(item),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => setState(() => _scannedItems.removeAt(index)),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            elevation: isLatest ? 8 : 1,
            color: isLatest ? const Color(0xFFF0F9EE) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isLatest ? const Color(0xFF43B02A) : Colors.transparent,
                width: 2,
              ),
            ),
            child: ListTile(
              onTap: () => _showEditDialog(item),
              leading: isLatest
                  ? const Icon(Icons.stars, color: Color(0xFF43B02A), size: 30)
                  : Container(width: 4, height: 30, color: const Color(0xFF003387)),
              title: Text(
                item.displayTitle,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isLatest ? const Color(0xFF43B02A) : Colors.black87,
                ),
              ),
              subtitle: Text('Количество: ${item.quantity}'),
              trailing: isLatest
                  ? const Text(
                      'СВЕЖИЙ',
                      style: TextStyle(
                        color: Color(0xFF43B02A),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    )
                  : const Icon(Icons.edit_note),
            ),
          ),
        );
      },
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить всё?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ОТМЕНА'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _scannedItems.clear();
                _lastItem = null;
              });
              Navigator.pop(context);
              _requestFocus();
            },
            child: const Text('УДАЛИТЬ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
