import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CartService {
  static final CartService instance = CartService._internal();
  CartService._internal();

  static const String _key = 'market_cart';

  Future<List<Map<String, dynamic>>> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> getCount() async {
    final items = await getItems();
    int c = 0;
    for (var it in items) {
      c += (it['quantity'] as int? ?? 1);
    }
    return c;
  }

  Future<void> addItem(Map<String, dynamic> product, {int quantity = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getItems();
    final idx = items.indexWhere((e) => e['id'] == product['id'] && e['name'] == product['name']);
    if (idx >= 0) {
      items[idx]['quantity'] = (items[idx]['quantity'] as int? ?? 1) + quantity;
    } else {
      final entry = Map<String, dynamic>.from(product);
      entry['quantity'] = quantity;
      items.add(entry);
    }
    await prefs.setString(_key, jsonEncode(items));
  }

  Future<void> changeItemQuantity(String id, int delta) async {
    final items = await getItems();
    for (var it in items) {
      if (it['id'] == id) {
        it['quantity'] = (it['quantity'] ?? 1) + delta;
        if (it['quantity'] <= 0) it['quantity'] = 1;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }

  Future<void> removeItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getItems();
    items.removeWhere((e) => e['id'] == id);
    await prefs.setString(_key, jsonEncode(items));
  }

  Future<void> updateQuantity(String id, int quantity) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getItems();
    final idx = items.indexWhere((e) => e['id'] == id);
    if (idx >= 0) {
      if (quantity <= 0) {
        items.removeAt(idx);
      } else {
        items[idx]['quantity'] = quantity;
      }
      await prefs.setString(_key, jsonEncode(items));
    }
  }

  Future<void> changeQuantity(String id, int delta) async {
    final items = await getItems();
    final idx = items.indexWhere((e) => e['id'] == id);
    if (idx >= 0) {
      final current = (items[idx]['quantity'] as int?) ?? 1;
      final next = current + delta;
      await updateQuantity(id, next);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
