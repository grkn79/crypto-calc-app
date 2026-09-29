import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'ad_iap_manager.dart';
import 'calculator_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final adIapManager = AdIapManager();
  await adIapManager.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: adIapManager,
      child: const CryptoCalcApp(),
    ),
  );
}

class CryptoCalcApp extends StatelessWidget {
  const CryptoCalcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crypto DCA & Profit Calc',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121418),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          surface: Color(0xFF1E222B),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<TextEditingController> _priceControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<TextEditingController> _amountControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  DcaResult? _result;
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');

  void _addNewRow() {
    setState(() {
      _priceControllers.add(TextEditingController());
      _amountControllers.add(TextEditingController());
    });
  }

  void _calculate() {
    List<DcaEntry> entries = [];
    for (int i = 0; i < _priceControllers.length; i++) {
      double price = double.tryParse(_priceControllers[i].text) ?? 0.0;
      double amount = double.tryParse(_amountControllers[i].text) ?? 0.0;
      if (price > 0 && amount > 0) {
        entries.add(DcaEntry(buyPrice: price, amount: amount));
      }
    }

    if (entries.isNotEmpty) {
      setState(() {
        _result = CalculatorService.calculateDca(entries);
      });
      Provider.of<AdIapManager>(context, listen: false).triggerInterstitialWithCounter();
    }
  }

  void _showProDialog(BuildContext context) {
    final adManager = Provider.of<AdIapManager>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E222B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium, color: Colors.amber, size: 54),
              const SizedBox(height: 12),
              const Text('PRO Sürüme Geçin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Tüm reklamları ömür boyu kaldırın ve kesintisiz hesaplama deneyimi yaşayın.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  adManager.buyRemoveAds();
                },
                child: const Text('Reklamları Kaldır (\$1.99)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  adManager.restorePurchases();
                },
                child: const Text('Satın Alımları Geri Yükle', style: TextStyle(color: Colors.white54)),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final adManager = Provider.of<AdIapManager>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('DCA Maliyet Hesaplayıcı'),
        backgroundColor: const Color(0xFF1E222B),
        actions: [
          if (!adManager.isProUser)
            IconButton(
              icon: const Icon(Icons.star, color: Colors.amber),
              tooltip: 'Reklamları Kaldır (PRO)',
              onPressed: () => _showProDialog(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_result != null) ...[
                    Card(
                      color: const Color(0xFF1E222B),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Color(0xFF00E676), width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text('Ortalama Birim Maliyetiniz', style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 6),
                            Text(
                              _currencyFormat.format(_result!.averagePrice),
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
                            ),
                            const Divider(height: 24, color: Colors.white24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Toplam: ${_currencyFormat.format(_result!.totalInvested)}'),
                                Text('Adet: ${_result!.totalUnits.toStringAsFixed(4)}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Alım Kademeleri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _priceControllers.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _priceControllers[index],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: '${index + 1}. Alış Fiyatı (\$)',
                                  filled: true,
                                  fillColor: const Color(0xFF1E222B),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _amountControllers[index],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Adet / Miktar',
                                  filled: true,
                                  fillColor: const Color(0xFF1E222B),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: _addNewRow,
                    icon: const Icon(Icons.add),
                    label: const Text('Yeni Kademe Ekle'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _calculate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Ortalama Maliyeti Hesapla', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          if (!adManager.isProUser && adManager.isBannerLoaded && adManager.bannerAd != null)
            SizedBox(
              height: adManager.bannerAd!.size.height.toDouble(),
              width: adManager.bannerAd!.size.width.toDouble(),
              child: AdWidget(ad: adManager.bannerAd!),
            ),
        ],
      ),
    );
  }
}
