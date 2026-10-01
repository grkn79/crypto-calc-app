class DcaEntry {
  final double buyPrice;
  final double amount;

  DcaEntry({required this.buyPrice, required this.amount});

  double get totalSpent => buyPrice * amount;

  Map<String, dynamic> toJson() => {'buyPrice': buyPrice, 'amount': amount};
  factory DcaEntry.fromJson(Map<String, dynamic> json) => DcaEntry(
    buyPrice: (json['buyPrice'] as num).toDouble(),
    amount: (json['amount'] as num).toDouble(),
  );
}

class DcaResult {
  final double totalInvested;
  final double totalUnits;
  final double averagePrice;
  final double totalFeePaid;
  final double breakEvenPrice;

  DcaResult({
    required this.totalInvested,
    required this.totalUnits,
    required this.averagePrice,
    required this.totalFeePaid,
    required this.breakEvenPrice,
  });
}

class TakeProfitStep {
  final double sellPrice;
  final double percentage;

  TakeProfitStep({required this.sellPrice, required this.percentage});

  Map<String, dynamic> toJson() => {'sellPrice': sellPrice, 'percentage': percentage};
  factory TakeProfitStep.fromJson(Map<String, dynamic> json) => TakeProfitStep(
    sellPrice: (json['sellPrice'] as num).toDouble(),
    percentage: (json['percentage'] as num).toDouble(),
  );
}

class TakeProfitResult {
  final double totalRealizedCash;
  final double totalUnitsSold;
  final double weightedAverageSellPrice;
  final double netProfit;
  final double profitPercentage;
  final double remainingUnits;
  final double remainingPercentage;

  TakeProfitResult({
    required this.totalRealizedCash,
    required this.totalUnitsSold,
    required this.weightedAverageSellPrice,
    required this.netProfit,
    required this.profitPercentage,
    required this.remainingUnits,
    required this.remainingPercentage,
  });
}

class ReverseDcaResult {
  final double requiredUnits;
  final double requiredCash;
  final bool isAchievable;
  final String message;

  ReverseDcaResult({
    required this.requiredUnits,
    required this.requiredCash,
    required this.isAchievable,
    required this.message,
  });
}

class RiskManagementResult {
  final double stopLossPrice;
  final double potentialLossCash;
  final double potentialLossPercent;

  RiskManagementResult({
    required this.stopLossPrice,
    required this.potentialLossCash,
    required this.potentialLossPercent,
  });
}

class SavedPortfolioItem {
  final String id;
  final String title;
  final String assetName;
  final DateTime date;
  final List<DcaEntry> entries;
  final List<TakeProfitStep> tpSteps;

  SavedPortfolioItem({
    required this.id,
    required this.title,
    required this.assetName,
    required this.date,
    required this.entries,
    required this.tpSteps,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'assetName': assetName,
    'date': date.toIso8601String(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'tpSteps': tpSteps.map((e) => e.toJson()).toList(),
  };

  factory SavedPortfolioItem.fromJson(Map<String, dynamic> json) => SavedPortfolioItem(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    assetName: json['assetName'] ?? '',
    date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
    entries: (json['entries'] as List<dynamic>? ?? [])
        .map((e) => DcaEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    tpSteps: (json['tpSteps'] as List<dynamic>? ?? [])
        .map((e) => TakeProfitStep.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class CalculatorService {
  static DcaResult calculateDca(List<DcaEntry> entries, {double feePercent = 0.0}) {
    double totalSpent = 0;
    double totalUnits = 0;

    for (var entry in entries) {
      totalSpent += entry.totalSpent;
      totalUnits += entry.amount;
    }

    double feePaid = totalSpent * (feePercent / 100.0);
    double grossAvgPrice = totalUnits > 0 ? totalSpent / totalUnits : 0.0;
    double breakEvenPrice = totalUnits > 0 ? (totalSpent + (2 * feePaid)) / totalUnits : 0.0;

    return DcaResult(
      totalInvested: totalSpent,
      totalUnits: totalUnits,
      averagePrice: grossAvgPrice,
      totalFeePaid: feePaid,
      breakEvenPrice: breakEvenPrice,
    );
  }

  static TakeProfitResult calculateTakeProfit({
    required double totalUnits,
    required double averageBuyPrice,
    required List<TakeProfitStep> steps,
    double feePercent = 0.0,
  }) {
    double totalCash = 0.0;
    double totalUnitsSold = 0.0;
    double totalPercentageUsed = 0.0;

    for (var step in steps) {
      if (step.sellPrice > 0 && step.percentage > 0) {
        double stepUnits = totalUnits * (step.percentage / 100.0);
        totalUnitsSold += stepUnits;
        totalCash += stepUnits * step.sellPrice;
        totalPercentageUsed += step.percentage;
      }
    }

    double exitFee = totalCash * (feePercent / 100.0);
    double costOfSoldUnits = totalUnitsSold * averageBuyPrice;
    double netProfit = (totalCash - exitFee) - costOfSoldUnits;
    double percentageGain = costOfSoldUnits > 0 ? (netProfit / costOfSoldUnits) * 100.0 : 0.0;
    double avgSellPrice = totalUnitsSold > 0 ? totalCash / totalUnitsSold : 0.0;
    double remainingUnits = totalUnits > totalUnitsSold ? totalUnits - totalUnitsSold : 0.0;
    double remainingPercentage = 100.0 - totalPercentageUsed;

    return TakeProfitResult(
      totalRealizedCash: totalCash - exitFee,
      totalUnitsSold: totalUnitsSold,
      weightedAverageSellPrice: avgSellPrice,
      netProfit: netProfit,
      profitPercentage: percentageGain,
      remainingUnits: remainingUnits < 0.000001 ? 0.0 : remainingUnits,
      remainingPercentage: remainingPercentage < 0 ? 0.0 : remainingPercentage,
    );
  }

  static ReverseDcaResult calculateReverseDca({
    required double currentUnits,
    required double currentAvgPrice,
    required double targetAvgPrice,
    required double newBuyPrice,
  }) {
    if (currentUnits <= 0 || currentAvgPrice <= 0 || targetAvgPrice <= 0 || newBuyPrice <= 0) {
      return ReverseDcaResult(requiredUnits: 0, requiredCash: 0, isAchievable: false, message: 'Geçersiz değerler');
    }

    if (newBuyPrice < currentAvgPrice) {
      if (targetAvgPrice <= newBuyPrice) {
        return ReverseDcaResult(
          requiredUnits: 0,
          requiredCash: 0,
          isAchievable: false,
          message: 'Hedef fiyat, yeni alış fiyatından büyük olmalıdır.',
        );
      }
      if (targetAvgPrice >= currentAvgPrice) {
        return ReverseDcaResult(
          requiredUnits: 0,
          requiredCash: 0,
          isAchievable: false,
          message: 'Hedef maliyet zaten mevcut maliyetinizden yüksek veya eşit.',
        );
      }
    } else if (newBuyPrice > currentAvgPrice) {
      if (targetAvgPrice >= newBuyPrice || targetAvgPrice <= currentAvgPrice) {
        return ReverseDcaResult(
          requiredUnits: 0,
          requiredCash: 0,
          isAchievable: false,
          message: 'Hedef fiyat mevcut ortalama ile yeni fiyat arasında olmalıdır.',
        );
      }
    } else {
      return ReverseDcaResult(
        requiredUnits: 0,
        requiredCash: 0,
        isAchievable: false,
        message: 'Yeni alış fiyatı mevcut ortalama ile aynı.',
      );
    }

    double totalInvested = currentUnits * currentAvgPrice;
    double numerator = totalInvested - (currentUnits * targetAvgPrice);
    double denominator = targetAvgPrice - newBuyPrice;
    double requiredUnits = numerator / denominator;
    double requiredCash = requiredUnits * newBuyPrice;

    return ReverseDcaResult(
      requiredUnits: requiredUnits > 0 ? requiredUnits : 0,
      requiredCash: requiredCash > 0 ? requiredCash : 0,
      isAchievable: true,
      message: 'Başarılı',
    );
  }

  static RiskManagementResult calculateStopLoss({
    required double totalUnits,
    required double averageBuyPrice,
    required double stopLossPrice,
  }) {
    if (totalUnits <= 0 || averageBuyPrice <= 0 || stopLossPrice <= 0) {
      return RiskManagementResult(stopLossPrice: 0, potentialLossCash: 0, potentialLossPercent: 0);
    }

    double totalInvested = totalUnits * averageBuyPrice;
    double exitCash = totalUnits * stopLossPrice;
    double lossCash = totalInvested - exitCash;
    double lossPercent = totalInvested > 0 ? (lossCash / totalInvested) * 100.0 : 0.0;

    return RiskManagementResult(
      stopLossPrice: stopLossPrice,
      potentialLossCash: lossCash,
      potentialLossPercent: lossPercent,
    );
  }
}
