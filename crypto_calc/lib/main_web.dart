import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'calculator_service.dart';
import 'export_service.dart';
import 'localization.dart';
import 'market_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CryptoCalcWebApp());
}

class CryptoCalcWebApp extends StatelessWidget {
  const CryptoCalcWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crypto & Metals Multi-Asset DCA Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1216),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          surface: Color(0xFF1A1F26),
        ),
        useMaterial3: true,
      ),
      home: const WebHomeScreen(),
    );
  }
}

class WebHomeScreen extends StatefulWidget {
  const WebHomeScreen({super.key});

  @override
  State<WebHomeScreen> createState() => _WebHomeScreenState();
}

class AssetTabState {
  String assetName;
  final TextEditingController customAssetController;
  final TextEditingController feeController;
  final List<TextEditingController> priceControllers;
  final List<TextEditingController> amountControllers;
  final List<TextEditingController> totalSpendControllers;
  final List<TextEditingController> tpPriceControllers;
  final List<TextEditingController> tpPercentControllers;
  final TextEditingController revTargetPriceController;
  final TextEditingController revNewBuyPriceController;
  final TextEditingController stopLossPriceController;

  DcaResult? dcaResult;
  TakeProfitResult? tpResult;
  ReverseDcaResult? revResult;
  RiskManagementResult? riskResult;

  AssetTabState({
    required this.assetName,
    String? initialCustom,
  })  : customAssetController = TextEditingController(text: initialCustom ?? ''),
        feeController = TextEditingController(text: "0.1"),
        priceControllers = [TextEditingController()],
        amountControllers = [TextEditingController()],
        totalSpendControllers = [TextEditingController()],
        tpPriceControllers = [TextEditingController()],
        tpPercentControllers = [TextEditingController()],
        revTargetPriceController = TextEditingController(),
        revNewBuyPriceController = TextEditingController(),
        stopLossPriceController = TextEditingController();
}

class _WebHomeScreenState extends State<WebHomeScreen> with SingleTickerProviderStateMixin {
  String _currentLang = 'en';
  String _currentCurrency = 'USD';

  final Map<String, double> _ratesAgainstUsd = {
    'USD': 1.0,
    'TRY': 34.50,
    'EUR': 0.92,
    'GBP': 0.78,
  };

  final List<String> _presetAssets = [
    'Bitcoin (BTC)',
    'Ethereum (ETH)',
    'Solana (SOL)',
    'Binance Coin (BNB)',
    'Ripple (XRP)',
    'Gram Gold (USD)',
    'Gram Altın (TL)',
    'Ounce Gold (XAU)',
    'Silver (XAG)',
    'Platinum (XPT)',
    'Custom'
  ];

  late TabController _tabController;
  final List<AssetTabState> _tabs = [];

  List<MarketCoin> _coins = [];
  bool _isLoadingMarket = true;
  bool _isPulseActive = false;

  final ScrollController _tickerScrollController = ScrollController();
  Timer? _tickerTimer;
  Timer? _priceRefreshTimer;

  List<SavedPortfolioItem> _savedPortfolios = [];

  String t(String key) => AppStrings.tr(_currentLang, key);

  String get currencySymbol {
    switch (_currentCurrency) {
      case 'TRY': return '₺';
      case 'EUR': return '€';
      case 'GBP': return '£';
      default: return '\$';
    }
  }

  NumberFormat get _currencyFormat => NumberFormat.currency(symbol: currencySymbol);

  AssetTabState get currentTab => _tabs[_tabController.index];

  String getActiveTabName(AssetTabState tab) {
    if (tab.assetName == 'Custom') {
      return tab.customAssetController.text.trim().isEmpty ? 'Asset' : tab.customAssetController.text.trim();
    }
    return tab.assetName;
  }

  bool isAssetNameValid(AssetTabState tab) {
    if (tab.assetName == 'Custom') {
      return tab.customAssetController.text.trim().isNotEmpty;
    }
    return tab.assetName.trim().isNotEmpty;
  }

  final TextInputFormatter _decimalDotFormatter = TextInputFormatter.withFunction((oldVal, newVal) {
    String text = newVal.text.replaceAll(',', '.');
    if (RegExp(r'^\d*\.?\d*$').hasMatch(text)) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    return oldVal;
  });

  @override
  void initState() {
    super.initState();
    _tabs.add(AssetTabState(assetName: 'Bitcoin (BTC)'));
    _tabs.add(AssetTabState(assetName: 'Ethereum (ETH)'));
    _tabs.add(AssetTabState(assetName: 'Gram Altın (TL)'));

    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) setState(() {});
    });

    _fetchMarket(initial: true);
    _loadSavedPortfoliosFromStorage();

    _priceRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchMarket(initial: false);
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _priceRefreshTimer?.cancel();
    _tickerScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _addNewAssetTab([String asset = 'Bitcoin (BTC)']) {
    setState(() {
      _tabs.add(AssetTabState(assetName: asset));
      int newIndex = _tabs.length - 1;
      _tabController.dispose();
      _tabController = TabController(length: _tabs.length, vsync: this, initialIndex: newIndex);
      _tabController.addListener(() {
        if (_tabController.indexIsChanging) setState(() {});
      });
    });
  }

  void _removeCurrentTab() {
    if (_tabs.length <= 1) return;
    int currentIndex = _tabController.index;
    setState(() {
      _tabs.removeAt(currentIndex);
      int newIndex = currentIndex >= _tabs.length ? _tabs.length - 1 : currentIndex;
      _tabController.dispose();
      _tabController = TabController(length: _tabs.length, vsync: this, initialIndex: newIndex);
      _tabController.addListener(() {
        if (_tabController.indexIsChanging) setState(() {});
      });
    });
  }

  double get totalPortfolioCapitalInvested {
    double total = 0.0;
    for (var tab in _tabs) {
      if (tab.dcaResult != null) {
        total += tab.dcaResult!.totalInvested;
      }
    }
    return total;
  }

  double get totalPortfolioRealizedCash {
    double total = 0.0;
    for (var tab in _tabs) {
      if (tab.tpResult != null) {
        total += tab.tpResult!.totalRealizedCash;
      }
    }
    return total;
  }

  void _onCurrencyChanged(String newCur) {
    if (newCur == _currentCurrency) return;

    double fromRate = _ratesAgainstUsd[_currentCurrency] ?? 1.0;
    double toRate = _ratesAgainstUsd[newCur] ?? 1.0;
    double factor = toRate / fromRate;

    setState(() {
      _currentCurrency = newCur;

      for (var tab in _tabs) {
        for (int i = 0; i < tab.priceControllers.length; i++) {
          double p = double.tryParse(tab.priceControllers[i].text.replaceAll(',', '.')) ?? 0.0;
          double a = double.tryParse(tab.amountControllers[i].text.replaceAll(',', '.')) ?? 0.0;

          if (p > 0) {
            double convertedPrice = p * factor;
            tab.priceControllers[i].text = convertedPrice >= 1
                ? convertedPrice.toStringAsFixed(2)
                : convertedPrice.toStringAsFixed(4);

            if (a > 0) {
              tab.totalSpendControllers[i].text = (convertedPrice * a).toStringAsFixed(2);
            }
          }
        }

        for (int i = 0; i < tab.tpPriceControllers.length; i++) {
          double tpPrice = double.tryParse(tab.tpPriceControllers[i].text.replaceAll(',', '.')) ?? 0.0;
          if (tpPrice > 0) {
            double convertedTp = tpPrice * factor;
            tab.tpPriceControllers[i].text = convertedTp >= 1
                ? convertedTp.toStringAsFixed(2)
                : convertedTp.toStringAsFixed(4);
          }
        }

        double sl = double.tryParse(tab.stopLossPriceController.text.replaceAll(',', '.')) ?? 0.0;
        if (sl > 0) {
          double convertedSl = sl * factor;
          tab.stopLossPriceController.text = convertedSl >= 1
              ? convertedSl.toStringAsFixed(2)
              : convertedSl.toStringAsFixed(4);
        }

        double revTarget = double.tryParse(tab.revTargetPriceController.text.replaceAll(',', '.')) ?? 0.0;
        if (revTarget > 0) {
          double cTarget = revTarget * factor;
          tab.revTargetPriceController.text = cTarget >= 1 ? cTarget.toStringAsFixed(2) : cTarget.toStringAsFixed(4);
        }

        double revNew = double.tryParse(tab.revNewBuyPriceController.text.replaceAll(',', '.')) ?? 0.0;
        if (revNew > 0) {
          double cNew = revNew * factor;
          tab.revNewBuyPriceController.text = cNew >= 1 ? cNew.toStringAsFixed(2) : cNew.toStringAsFixed(4);
        }

        _calculateTab(tab);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('All tabs converted to $currencySymbol $newCur'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  void _onAmountChanged(AssetTabState tab, int index, String val) {
    double p = double.tryParse(tab.priceControllers[index].text.replaceAll(',', '.')) ?? 0.0;
    double a = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;

    if (p > 0 && a > 0) {
      String calculated = (p * a).toStringAsFixed(2);
      if (tab.totalSpendControllers[index].text != calculated) {
        tab.totalSpendControllers[index].text = calculated;
      }
    } else if (val.isEmpty) {
      tab.totalSpendControllers[index].clear();
    }
    setState(() => _calculateTab(tab));
  }

  void _onTotalSpendChanged(AssetTabState tab, int index, String val) {
    double p = double.tryParse(tab.priceControllers[index].text.replaceAll(',', '.')) ?? 0.0;
    double tVal = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;

    if (p > 0 && tVal > 0) {
      String calculated = (tVal / p).toStringAsFixed(6);
      if (tab.amountControllers[index].text != calculated) {
        tab.amountControllers[index].text = calculated;
      }
    } else if (val.isEmpty) {
      tab.amountControllers[index].clear();
    }
    setState(() => _calculateTab(tab));
  }

  void _onPriceChanged(AssetTabState tab, int index, String val) {
    double p = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    double a = double.tryParse(tab.amountControllers[index].text.replaceAll(',', '.')) ?? 0.0;
    double tVal = double.tryParse(tab.totalSpendControllers[index].text.replaceAll(',', '.')) ?? 0.0;

    if (p > 0) {
      if (a > 0) {
        tab.totalSpendControllers[index].text = (p * a).toStringAsFixed(2);
      } else if (tVal > 0) {
        tab.amountControllers[index].text = (tVal / p).toStringAsFixed(6);
      }
    }
    setState(() => _calculateTab(tab));
  }

  List<DcaEntry> _getActiveEntries(AssetTabState tab) {
    List<DcaEntry> entries = [];
    for (int i = 0; i < tab.priceControllers.length; i++) {
      double p = double.tryParse(tab.priceControllers[i].text.replaceAll(',', '.')) ?? 0.0;
      double a = double.tryParse(tab.amountControllers[i].text.replaceAll(',', '.')) ?? 0.0;
      double tVal = double.tryParse(tab.totalSpendControllers[i].text.replaceAll(',', '.')) ?? 0.0;

      // Eğer tutar ve fiyat varsa ama adet henüz hesaplanmadıysa otomatik tamamla
      if (p > 0 && a <= 0 && tVal > 0) {
        a = tVal / p;
      }

      if (p > 0 && a > 0) {
        entries.add(DcaEntry(buyPrice: p, amount: a));
      }
    }
    return entries;
  }

  List<TakeProfitStep> _getActiveTpSteps(AssetTabState tab) {
    List<TakeProfitStep> steps = [];
    for (int i = 0; i < tab.tpPriceControllers.length; i++) {
      double p = double.tryParse(tab.tpPriceControllers[i].text.replaceAll(',', '.')) ?? 0.0;
      double pct = double.tryParse(tab.tpPercentControllers[i].text.replaceAll(',', '.')) ?? 0.0;
      if (p > 0 && pct > 0) {
        steps.add(TakeProfitStep(sellPrice: p, percentage: pct));
      }
    }
    return steps;
  }

  void _calculateTab(AssetTabState tab) {
    final entries = _getActiveEntries(tab);
    double fee = double.tryParse(tab.feeController.text.replaceAll(',', '.')) ?? 0.0;
    final tpSteps = _getActiveTpSteps(tab);

    if (isAssetNameValid(tab) && entries.isNotEmpty) {
      final dca = CalculatorService.calculateDca(entries, feePercent: fee);

      TakeProfitResult? tp;
      if (tpSteps.isNotEmpty && dca.totalUnits > 0) {
        tp = CalculatorService.calculateTakeProfit(
          totalUnits: dca.totalUnits,
          averageBuyPrice: dca.averagePrice,
          steps: tpSteps,
          feePercent: fee,
        );
      }

      double targetAvg = double.tryParse(tab.revTargetPriceController.text.replaceAll(',', '.')) ?? 0.0;
      double newPrice = double.tryParse(tab.revNewBuyPriceController.text.replaceAll(',', '.')) ?? 0.0;
      ReverseDcaResult? rev;
      if (dca.totalUnits > 0 && targetAvg > 0 && newPrice > 0) {
        rev = CalculatorService.calculateReverseDca(
          currentUnits: dca.totalUnits,
          currentAvgPrice: dca.averagePrice,
          targetAvgPrice: targetAvg,
          newBuyPrice: newPrice,
        );
      }

      double stopPrice = double.tryParse(tab.stopLossPriceController.text.replaceAll(',', '.')) ?? 0.0;
      RiskManagementResult? risk;
      if (dca.totalUnits > 0 && stopPrice > 0) {
        risk = CalculatorService.calculateStopLoss(
          totalUnits: dca.totalUnits,
          averageBuyPrice: dca.averagePrice,
          stopLossPrice: stopPrice,
        );
      }

      tab.dcaResult = dca;
      tab.tpResult = tp;
      tab.revResult = rev;
      tab.riskResult = risk;
    } else {
      tab.dcaResult = null;
      tab.tpResult = null;
      tab.revResult = null;
      tab.riskResult = null;
    }
  }

  void _exportCsv() {
    final tab = currentTab;
    if (tab.dcaResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('buySteps'))));
      return;
    }
    ExportService.exportToCsv(
      assetName: getActiveTabName(tab),
      dcaResult: tab.dcaResult!,
      entries: _getActiveEntries(tab),
      tpResult: tab.tpResult,
      tpSteps: _getActiveTpSteps(tab),
    );
  }

  void _exportPdf() {
    final tab = currentTab;
    if (tab.dcaResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('buySteps'))));
      return;
    }
    ExportService.printPdfReport(
      assetName: getActiveTabName(tab),
      dcaResult: tab.dcaResult!,
      entries: _getActiveEntries(tab),
      tpResult: tab.tpResult,
      tpSteps: _getActiveTpSteps(tab),
    );
  }

  Future<void> _loadSavedPortfoliosFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('saved_portfolios');
    if (raw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        setState(() {
          _savedPortfolios = decoded.map((e) => SavedPortfolioItem.fromJson(e)).toList();
        });
      } catch (_) {}
    }
  }

  Future<void> _savePortfoliosToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_savedPortfolios.map((e) => e.toJson()).toList());
    await prefs.setString('saved_portfolios', encoded);
  }

  void _showSavePortfolioDialog() {
    final tab = currentTab;
    final nameCtrl = TextEditingController(text: '${getActiveTabName(tab)} Plan');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F26),
        title: Text(t('savePortfolio')),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            hintText: t('portfolioNameHint'),
            filled: true,
            fillColor: const Color(0xFF151922),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
            onPressed: () {
              final title = nameCtrl.text.trim().isEmpty ? 'Portfolio' : nameCtrl.text.trim();
              final item = SavedPortfolioItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: title,
                assetName: getActiveTabName(tab),
                date: DateTime.now(),
                entries: _getActiveEntries(tab),
                tpSteps: _getActiveTpSteps(tab),
              );

              setState(() {
                _savedPortfolios.insert(0, item);
              });
              _savePortfoliosToStorage();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('saveSuccess'))));
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  void _showSavedPortfoliosDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t('savedPortfolios'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  if (_savedPortfolios.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('No saved portfolios found.', style: TextStyle(color: Colors.white54))),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _savedPortfolios.length,
                        itemBuilder: (context, index) {
                          final item = _savedPortfolios[index];
                          return Card(
                            color: const Color(0xFF151922),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${item.assetName} • ${item.entries.length} Tiers', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.upload_file, color: Color(0xFF00E676)),
                                    onPressed: () {
                                      _loadPortfolioAsNewTab(item);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () {
                                      setState(() => _savedPortfolios.removeAt(index));
                                      setModalState(() {});
                                      _savePortfoliosToStorage();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _loadPortfolioAsNewTab(SavedPortfolioItem item) {
    final tab = AssetTabState(assetName: 'Custom', initialCustom: item.assetName);
    tab.priceControllers.clear();
    tab.amountControllers.clear();
    tab.totalSpendControllers.clear();

    for (var entry in item.entries) {
      tab.priceControllers.add(TextEditingController(text: entry.buyPrice.toString()));
      tab.amountControllers.add(TextEditingController(text: entry.amount.toString()));
      tab.totalSpendControllers.add(TextEditingController(text: (entry.buyPrice * entry.amount).toStringAsFixed(2)));
    }

    tab.tpPriceControllers.clear();
    tab.tpPercentControllers.clear();
    if (item.tpSteps.isNotEmpty) {
      for (var step in item.tpSteps) {
        tab.tpPriceControllers.add(TextEditingController(text: step.sellPrice.toString()));
        tab.tpPercentControllers.add(TextEditingController(text: step.percentage.toString()));
      }
    } else {
      tab.tpPriceControllers.add(TextEditingController());
      tab.tpPercentControllers.add(TextEditingController());
    }

    _calculateTab(tab);

    setState(() {
      _tabs.add(tab);
      _tabController.dispose();
      _tabController = TabController(length: _tabs.length, vsync: this, initialIndex: _tabs.length - 1);
      _tabController.addListener(() {
        if (_tabController.indexIsChanging) setState(() {});
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.title} opened as tab!')));
  }

  Future<void> _fetchMarket({bool initial = false}) async {
    if (initial) setState(() => _isLoadingMarket = true);
    final list = await MarketService.fetchTopCoins();
    if (mounted && list.isNotEmpty) {
      setState(() {
        _coins = list;
        _isLoadingMarket = false;
        _isPulseActive = true;
      });

      if (initial) _startAutoScroll();

      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _isPulseActive = false);
      });
    }
  }

  void _startAutoScroll() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!_tickerScrollController.hasClients) return;
      double maxScroll = _tickerScrollController.position.maxScrollExtent;
      double current = _tickerScrollController.offset;
      if (current >= maxScroll) {
        _tickerScrollController.jumpTo(0);
      } else {
        _tickerScrollController.jumpTo(current + 1.2);
      }
    });
  }

  void _onCoinTap(MarketCoin coin) {
    final tab = currentTab;
    setState(() {
      String matched = _presetAssets.firstWhere(
        (a) => a.toUpperCase().contains(coin.symbol.toUpperCase()),
        orElse: () => 'Custom',
      );
      tab.assetName = matched;
      if (matched == 'Custom') {
        tab.customAssetController.text = '${coin.name} (${coin.symbol})';
      }

      double toRate = _ratesAgainstUsd[_currentCurrency] ?? 1.0;
      double convertedCoinPrice = coin.currentPrice * toRate;

      String pStr = convertedCoinPrice >= 1
          ? convertedCoinPrice.toStringAsFixed(2)
          : convertedCoinPrice.toStringAsFixed(4);

      if (tab.priceControllers.isNotEmpty && tab.priceControllers.last.text.isEmpty) {
        tab.priceControllers.last.text = pStr;
        _onPriceChanged(tab, tab.priceControllers.length - 1, pStr);
      } else {
        tab.priceControllers.add(TextEditingController(text: pStr));
        tab.amountControllers.add(TextEditingController());
        tab.totalSpendControllers.add(TextEditingController());
      }

      tab.revNewBuyPriceController.text = pStr;
      _calculateTab(tab);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${coin.name} ($currencySymbol${coin.currentPrice.toStringAsFixed(2)}) added to current tab!'), duration: const Duration(seconds: 1)),
    );
  }

  void _addNewRow(AssetTabState tab) {
    setState(() {
      tab.priceControllers.add(TextEditingController());
      tab.amountControllers.add(TextEditingController());
      tab.totalSpendControllers.add(TextEditingController());
    });
  }

  void _removeRow(AssetTabState tab, int index) {
    if (tab.priceControllers.length <= 1) return;
    setState(() {
      tab.priceControllers.removeAt(index);
      tab.amountControllers.removeAt(index);
      tab.totalSpendControllers.removeAt(index);
      _calculateTab(tab);
    });
  }

  void _addTpRow(AssetTabState tab) {
    setState(() {
      tab.tpPriceControllers.add(TextEditingController());
      tab.tpPercentControllers.add(TextEditingController());
    });
  }

  void _removeTpRow(AssetTabState tab, int index) {
    if (tab.tpPriceControllers.length <= 1) return;
    setState(() {
      tab.tpPriceControllers.removeAt(index);
      tab.tpPercentControllers.removeAt(index);
      _calculateTab(tab);
    });
  }

  void _resetCurrentTab() {
    final tab = currentTab;
    setState(() {
      tab.priceControllers.clear();
      tab.amountControllers.clear();
      tab.totalSpendControllers.clear();
      tab.priceControllers.add(TextEditingController());
      tab.amountControllers.add(TextEditingController());
      tab.totalSpendControllers.add(TextEditingController());

      tab.tpPriceControllers.clear();
      tab.tpPercentControllers.clear();
      tab.tpPriceControllers.add(TextEditingController());
      tab.tpPercentControllers.add(TextEditingController());

      tab.revTargetPriceController.clear();
      tab.revNewBuyPriceController.clear();
      tab.stopLossPriceController.clear();

      tab.customAssetController.clear();
      tab.dcaResult = null;
      tab.tpResult = null;
      tab.revResult = null;
      tab.riskResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('appTitle'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        backgroundColor: const Color(0xFF1A1F26),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF242A35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF00E676)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _currentCurrency,
                dropdownColor: const Color(0xFF1A1F26),
                style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                onChanged: (val) {
                  if (val != null) _onCurrencyChanged(val);
                },
                items: const [
                  DropdownMenuItem(value: 'USD', child: Text('\$ USD')),
                  DropdownMenuItem(value: 'TRY', child: Text('₺ TRY')),
                  DropdownMenuItem(value: 'EUR', child: Text('€ EUR')),
                  DropdownMenuItem(value: 'GBP', child: Text('£ GBP')),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF242A35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _currentLang,
                dropdownColor: const Color(0xFF1A1F26),
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                onChanged: (val) {
                  if (val != null) setState(() => _currentLang = val);
                },
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('EN')),
                  DropdownMenuItem(value: 'tr', child: Text('TR')),
                  DropdownMenuItem(value: 'es', child: Text('ES')),
                  DropdownMenuItem(value: 'de', child: Text('DE')),
                  DropdownMenuItem(value: 'fr', child: Text('FR')),
                  DropdownMenuItem(value: 'it', child: Text('IT')),
                  DropdownMenuItem(value: 'ru', child: Text('RU')),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_special, color: Color(0xFF00E676), size: 20),
            tooltip: t('savedPortfolios'),
            onPressed: _showSavedPortfoliosDrawer,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Reset Tab',
            onPressed: _resetCurrentTab,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              // Canlı Ticker Şeridi
              Container(
                color: const Color(0xFF14181F),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: _isPulseActive ? 10 : 8,
                                height: _isPulseActive ? 10 : 8,
                                decoration: BoxDecoration(
                                  color: _isPulseActive ? const Color(0xFF69F0AE) : const Color(0xFF00E676),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${t('liveMarketTitle')} • 3s',
                                style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => _fetchMarket(initial: false),
                            child: const Icon(Icons.refresh, size: 15, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 50,
                      child: _isLoadingMarket
                          ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                          : ListView.builder(
                              controller: _tickerScrollController,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _coins.length * 3,
                              itemBuilder: (context, idx) {
                                final coin = _coins[idx % _coins.length];
                                final isUp = coin.change24h >= 0;
                                final rate = _ratesAgainstUsd[_currentCurrency] ?? 1.0;
                                final price = coin.currentPrice * rate;
                                return GestureDetector(
                                  onTap: () => _onCoinTap(coin),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E242E),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: coin.isMetal ? const Color(0x80FFD54F) : Colors.white10,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              coin.symbol,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: coin.isMetal ? Colors.amberAccent : Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${isUp ? "+" : ""}${coin.change24h.toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isUp ? const Color(0xFF00E676) : Colors.redAccent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '$currencySymbol${price >= 1 ? price.toStringAsFixed(2) : price.toStringAsFixed(4)}',
                                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // Konsolide Portföy Toplam Kartı
              Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF172822), Color(0xFF1A1F26)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Color(0xFF00E676)),
                            const SizedBox(width: 6),
                            Text(t('portfolioOverview'), style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currencyFormat.format(totalPortfolioCapitalInvested),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${t('activeTabsCount')}: ${_tabs.length}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        if (totalPortfolioRealizedCash > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Realized: ${_currencyFormat.format(totalPortfolioRealizedCash)}',
                            style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Çoklu Sekme Başlıkları
              Container(
                color: const Color(0xFF12161D),
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorColor: const Color(0xFF00E676),
                        indicatorWeight: 3,
                        labelColor: const Color(0xFF00E676),
                        unselectedLabelColor: Colors.white54,
                        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        tabs: _tabs.map((tab) {
                          String title = getActiveTabName(tab);
                          if (title.contains('(')) {
                            title = title.split('(').last.replaceAll(')', '');
                          }
                          return Tab(text: title);
                        }).toList(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00E676), size: 20),
                      tooltip: t('addAssetTab'),
                      onPressed: () => _addNewAssetTab('Bitcoin (BTC)'),
                    ),
                    if (_tabs.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                        tooltip: t('deleteAssetTab'),
                        onPressed: _removeCurrentTab,
                      ),
                  ],
                ),
              ),

              // Sekme İçerikleri
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _tabs.map((tab) => _buildTabContent(tab)).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(AssetTabState tab) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  initialValue: tab.assetName,
                  decoration: InputDecoration(
                    labelText: t('assetDropdownLabel'),
                    prefixIcon: const Icon(Icons.pie_chart_outline, color: Color(0xFF00E676)),
                    filled: true,
                    fillColor: const Color(0xFF1A1F26),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  dropdownColor: const Color(0xFF1A1F26),
                  items: _presetAssets.map((asset) {
                    return DropdownMenuItem(
                      value: asset,
                      child: Text(asset == 'Custom' ? t('customOption') : asset),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        tab.assetName = val;
                        _calculateTab(tab);
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: tab.feeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_decimalDotFormatter],
                  decoration: InputDecoration(
                    labelText: t('feeLabel'),
                    suffixText: '%',
                    filled: true,
                    fillColor: const Color(0xFF1A1F26),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => setState(() => _calculateTab(tab)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.bookmark_add_outlined, color: Color(0xFF00E676)),
                tooltip: t('savePortfolio'),
                onPressed: _showSavePortfolioDialog,
              ),
            ],
          ),
          if (tab.assetName == 'Custom') ...[
            const SizedBox(height: 10),
            TextField(
              controller: tab.customAssetController,
              decoration: InputDecoration(
                labelText: t('customAssetLabel'),
                prefixIcon: const Icon(Icons.edit, color: Color(0xFF00E676)),
                filled: true,
                fillColor: const Color(0xFF1A1F26),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() => _calculateTab(tab)),
            ),
          ],
          const SizedBox(height: 14),

          // ORTALAMA BİRİM FİYAT ÖZET KARTI
          // Varlık geçerli ve kademe hesaplanmışsa tam kart gösterilir; değilse kullanıcıya bilgilendirici rehber kutusu görünür
          if (tab.dcaResult != null) ...[
            Card(
              color: const Color(0xFF1A1F26),
              elevation: 2,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFF00E676), width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x2600E676),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        getActiveTabName(tab),
                        style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(t('avgCostLabel'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      _currencyFormat.format(tab.dcaResult!.averagePrice),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
                    ),
                    const Divider(height: 20, color: Colors.white12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('totalInvested'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(_currencyFormat.format(tab.dcaResult!.totalInvested), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(t('totalUnits'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(tab.dcaResult!.totalUnits.toStringAsFixed(4), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142426),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(t('breakEvenLabel'), style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                          Text(
                            _currencyFormat.format(tab.dcaResult!.breakEvenPrice),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD32F2F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: Text(t('exportPdf'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _exportPdf,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.table_chart, size: 18),
                    label: Text(t('exportCsv'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _exportCsv,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Alış Kademeleri
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t('buySteps'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              TextButton.icon(
                onPressed: () => _addNewRow(tab),
                icon: const Icon(Icons.add, size: 18),
                label: Text(t('addStep')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tab.priceControllers.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: tab.priceControllers[index],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_decimalDotFormatter],
                        decoration: InputDecoration(
                          labelText: '${index + 1}. ${t('priceLabel')} ($currencySymbol)',
                          filled: true,
                          fillColor: const Color(0xFF1A1F26),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) => _onPriceChanged(tab, index, val),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: tab.amountControllers[index],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_decimalDotFormatter],
                        decoration: InputDecoration(
                          labelText: t('amountLabel'),
                          filled: true,
                          fillColor: const Color(0xFF1A1F26),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) => _onAmountChanged(tab, index, val),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: tab.totalSpendControllers[index],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_decimalDotFormatter],
                        decoration: InputDecoration(
                          labelText: '${t('totalLabel')} ($currencySymbol)',
                          filled: true,
                          fillColor: const Color(0xFF1A1F26),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) => _onTotalSpendChanged(tab, index, val),
                      ),
                    ),
                    if (tab.priceControllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                        onPressed: () => _removeRow(tab, index),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 18),

          // Take-Profit Simulator
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF151922),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x55FFA000)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Text(t('tpTitle'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber)),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () => _addTpRow(tab),
                      icon: const Icon(Icons.add, size: 16, color: Colors.amber),
                      label: Text(t('tpAddStep'), style: const TextStyle(color: Colors.amber, fontSize: 12)),
                    ),
                  ],
                ),
                Text(t('tpSub'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tab.tpPriceControllers.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: tab.tpPriceControllers[index],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [_decimalDotFormatter],
                              decoration: InputDecoration(
                                labelText: '${index + 1}. ${t('tpStepPrice')} ($currencySymbol)',
                                filled: true,
                                fillColor: const Color(0xFF1E242E),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setState(() => _calculateTab(tab)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: tab.tpPercentControllers[index],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [_decimalDotFormatter],
                              decoration: InputDecoration(
                                labelText: t('tpStepPercent'),
                                suffixText: '%',
                                filled: true,
                                fillColor: const Color(0xFF1E242E),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setState(() => _calculateTab(tab)),
                            ),
                          ),
                          if (tab.tpPriceControllers.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                              onPressed: () => _removeTpRow(tab, index),
                            ),
                        ],
                      ),
                    );
                  },
                ),

                if (tab.tpResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF102117),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x6600E676)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(t('tpAvgSellPrice'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text(_currencyFormat.format(tab.tpResult!.weightedAverageSellPrice), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(t('tpRealizedCash'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text(_currencyFormat.format(tab.tpResult!.totalRealizedCash), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Divider(height: 14, color: Colors.white12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Net Profit (After Fee)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Text(
                              '+${_currencyFormat.format(tab.tpResult!.netProfit)} (+${tab.tpResult!.profitPercentage.toStringAsFixed(1)}%)',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676), fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(t('tpRemaining'), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            Text(
                              '${tab.tpResult!.remainingUnits.toStringAsFixed(4)} units (${tab.tpResult!.remainingPercentage.toStringAsFixed(0)}%)',
                              style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Stop-Loss
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF221518),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66EF5350)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(t('stopLossTitle'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.redAccent)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(t('stopLossSub'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                TextField(
                  controller: tab.stopLossPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_decimalDotFormatter],
                  decoration: InputDecoration(
                    labelText: '${t('stopPriceLabel')} ($currencySymbol)',
                    filled: true,
                    fillColor: const Color(0xFF2B161B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() => _calculateTab(tab)),
                ),
                if (tab.riskResult != null && tab.riskResult!.potentialLossCash > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t('potentialLoss'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(
                        '-${_currencyFormat.format(tab.riskResult!.potentialLossCash)} (-${tab.riskResult!.potentialLossPercent.toStringAsFixed(1)}%)',
                        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Reverse DCA
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF171B26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x5500E5FF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calculate_outlined, color: Colors.cyanAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t('reverseDcaTitle'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.cyanAccent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(t('reverseDcaSub'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tab.revTargetPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_decimalDotFormatter],
                        decoration: InputDecoration(
                          labelText: '${t('targetAvgPrice')} ($currencySymbol)',
                          filled: true,
                          fillColor: const Color(0xFF1E242E),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (_) => setState(() => _calculateTab(tab)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: tab.revNewBuyPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_decimalDotFormatter],
                        decoration: InputDecoration(
                          labelText: '${t('newBuyPrice')} ($currencySymbol)',
                          filled: true,
                          fillColor: const Color(0xFF1E242E),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (_) => setState(() => _calculateTab(tab)),
                      ),
                    ),
                  ],
                ),
                if (tab.revResult != null) ...[
                  const SizedBox(height: 12),
                  if (tab.revResult!.isAchievable)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2625),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x6600E5FF)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(t('reqUnits'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(
                                '${tab.revResult!.requiredUnits.toStringAsFixed(4)} units',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(t('reqCash'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(
                                _currencyFormat.format(tab.revResult!.requiredCash),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      tab.revResult!.message,
                      style: const TextStyle(color: Colors.amber, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: () => setState(() => _calculateTab(tab)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(t('calculate'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
