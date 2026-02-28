import 'package:flutter/material.dart';

import '../models/inventory_document.dart';
import '../services/document_storage_service.dart';
import 'scan_screen.dart';

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  List<InventoryDocument> _documents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    final docs = await DocumentStorageService.listDocuments();
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _isLoading = false;
    });
  }

  Future<void> _openDocument(InventoryDocument document) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScanScreen(document: document)),
    );
    await _loadDocuments();
  }

  Future<void> _createAndOpenDocument() async {
    final document = await DocumentStorageService.createDocument();
    if (!mounted) return;
    await _openDocument(document);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(title: const Text('Документы инвентаризации')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _documents.isEmpty
              ? const Center(
                  child: Text(
                    'Нет документов.\nНажмите «+», чтобы создать новый.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                )
              : ListView.separated(
                  itemCount: _documents.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemBuilder: (context, index) {
                    final doc = _documents[index];
                    // Используем doc.name вместо doc.id, так как имя файла уникально
                    final String documentKey = doc.name; 

                    return Dismissible(
                      key: Key(documentKey), 
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20.0),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Удалить документ?'),
                            content: Text('Вы уверены, что хотите удалить "${doc.name}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('ОТМЕНА'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('УДАЛИТЬ', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (direction) async {
                        // Сохраняем имя для уведомления ДО удаления
                        final deletedName = doc.name;

                        // Удаляем через сервис (используем doc.name как идентификатор файла)
                        await DocumentStorageService.deleteDocument(doc.name);
                        
                        setState(() {
                          _documents.removeAt(index);
                        });

                        // Проверка mounted для исправления ошибки BuildContext
                        if (!mounted) return;
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Документ "$deletedName" удален')),
                        );
                      },
                      child: Card(
                        child: ListTile(
                          onTap: () => _openDocument(doc),
                          leading: const Icon(Icons.description_outlined, color: Color(0xFF003387)),
                          title: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'Позиций: ${doc.itemCount} · Обновлён: ${_formatDate(doc.updatedAt)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createAndOpenDocument,
        backgroundColor: const Color(0xFF003387),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final d = dateTime;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
