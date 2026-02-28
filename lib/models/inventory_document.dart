class InventoryDocument {
  final String name;
  final String path;
  final DateTime updatedAt;
  final int itemCount;

  const InventoryDocument({
    required this.name,
    required this.path,
    required this.updatedAt,
    required this.itemCount,
  });
}
