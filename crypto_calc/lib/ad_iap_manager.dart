import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class AdIapManager extends ChangeNotifier {
  // Google Play Console'da tanimlanacak urun ID'si
  static const String removeAdsProductId = 'remove_ads_lifetime';

  // Google Test Reklam Birim ID'leri
  static const String testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';

  bool _isProUser = false;
  bool get isProUser => _isProUser;

  BannerAd? _bannerAd;
  BannerAd? get bannerAd => _bannerAd;
  bool _isBannerLoaded = false;
  bool get isBannerLoaded => _isBannerLoaded;

  InterstitialAd? _interstitialAd;
  int _actionCounter = 0;

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _initIap();
    if (!_isProUser) {
      loadBanner();
      _loadInterstitial();
    }
  }

  void _initIap() {
    final purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseList) {
      _listenToPurchaseUpdated(purchaseList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      debugPrint('IAP Hatasi: $error');
    });
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        if (purchaseDetails.productID == removeAdsProductId) {
          _isProUser = true;
          _bannerAd?.dispose();
          _bannerAd = null;
          _isBannerLoaded = false;
          notifyListeners();
        }
      }
      if (purchaseDetails.pendingCompletePurchase) {
        _iap.completePurchase(purchaseDetails);
      }
    }
  }

  // Banner Yukle
  void loadBanner() {
    if (_isProUser) return;
    _bannerAd = BannerAd(
      adUnitId: testBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _isBannerLoaded = true;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _isBannerLoaded = false;
          debugPrint('Banner yuklenemedi: $error');
        },
      ),
    )..load();
  }

  // Gecis Reklami (Her 3 hesaplamada bir tetiklenir)
  void _loadInterstitial() {
    if (_isProUser) return;
    InterstitialAd.load(
      adUnitId: testInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
        },
      ),
    );
  }

  void triggerInterstitialWithCounter() {
    if (_isProUser) return;
    _actionCounter++;
    if (_actionCounter >= 3) {
      if (_interstitialAd != null) {
        _interstitialAd!.show();
        _interstitialAd = null;
        _loadInterstitial();
      }
      _actionCounter = 0;
    }
  }

  // Satin Alma Surecini Baslat
  Future<void> buyRemoveAds() async {
    final bool available = await _iap.isAvailable();
    if (!available) return;

    final Set<String> kIds = <String>{removeAdsProductId};
    final ProductDetailsResponse response = await _iap.queryProductDetails(kIds);

    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
      // Magaza henuz onaylanmamissa test uyarisi
      debugPrint('Urun Google Play Store üzerinde bulunamadi.');
      return;
    }

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: response.productDetails.first);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  // Satin Alimlari Geri Yukle (Google zorunlu kilar)
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _subscription.cancel();
    super.dispose();
  }
}
