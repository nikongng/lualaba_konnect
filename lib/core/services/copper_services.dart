// TODO Implement this library.import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CopperServices {
  final String apiKey = "T227DYXQS9F943K3";

  Future<Map<String, dynamic>> getCopperPrice() async {
    // API pour le Cuivre (Global Price of Copper)
    final url = 'https://www.alphavantage.co/query?function=COPPER&interval=monthly&apikey=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Alpha Vantage renvoie une liste de prix. On prend le plus récent.
        final latestData = data['data'][0];
        
        return {
          "price": double.parse(latestData['value']).toStringAsFixed(2),
          "date": latestData['date'],
          "success": true
        };
      }
    } catch (e) {
      print("Erreur API Marché: $e");
    }
    return {"success": false};
  }
}