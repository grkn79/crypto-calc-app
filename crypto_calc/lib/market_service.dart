import 'dart:convert';
import 'package:http/http.dart' as http;

class MarketCoin {
  final String symbol;
  final String name;
  final double currentPrice;
  final double change24h;
  final bool isMetal;

  MarketCoin({
    required this.symbol,
    required this.name,
    required this.currentPrice,
    required this.change24h,
    this.isMetal = false,
  });

  factory MarketCoin.fromJson(Map<String, dynamic> json) {
    String sym = (json['symbol'] ?? '').toString().replaceAll('USDT', '');
    bool metal = sym.contains('XAU') || sym.contains('GA_') || sym.contains('XAG') || sym.contains('XPT');
    return MarketCoin(
      symbol: sym,
      name: json['name'] ?? sym,
      currentPrice: double.tryParse(json['lastPrice']?.toString() ?? '0') ?? 0.0,
      change24h: double.tryParse(json['priceChangePercent']?.toString() ?? '0') ?? 0.0,
      isMetal: metal,
    );
  }
}

class MarketService {
  static Future<List<MarketCoin>> fetchTopCoins() async {
    try {
      final response = await http.get(Uri.parse('/api/prices')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        if (list.isNotEmpty) {
          return list.map((item) => MarketCoin.fromJson(item)).toList();
        }
      }
    } catch (_) {}

    return [
      MarketCoin(symbol: 'BTC', name: 'Bitcoin', currentPrice: 65400.0, change24h: 1.8),
      MarketCoin(symbol: 'ETH', name: 'Ethereum', currentPrice: 3450.0, change24h: -0.9),
      MarketCoin(symbol: 'SOL', name: 'Solana', currentPrice: 154.0, change24h: 4.2),
      MarketCoin(symbol: 'XAU_OZ', name: 'Ons Altin (USD)', currentPrice: 2655.0, change24h: 0.4, isMetal: true),
      MarketCoin(symbol: 'GA_TRY', name: 'Gram Altin (TL)', currentPrice: 2920.0, change24h: 0.6, isMetal: true),
      MarketCoin(symbol: 'XAG_OZ', name: 'Gumus Ons (USD)', currentPrice: 31.80, change24h: -0.2, isMetal: true),
    ];
  }
}
