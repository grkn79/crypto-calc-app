class DcaEntry {
  final double buyPrice;
  final double amount;

  DcaEntry({required this.buyPrice, required this.amount});
}

class DcaResult {
  final double totalInvested;
  final double totalUnits;
  final double averagePrice;

  DcaResult({
    required this.totalInvested,
    required this.totalUnits,
    required this.averagePrice,
  });
}

class CalculatorService {
  static DcaResult calculateDca(List<DcaEntry> entries) {
    double totalInvested = 0.0;
    double totalUnits = 0.0;

    for (var entry in entries) {
      if (entry.buyPrice > 0 && entry.amount > 0) {
        totalInvested += (entry.buyPrice * entry.amount);
        totalUnits += entry.amount;
      }
    }

    double avgPrice = totalUnits > 0 ? (totalInvested / totalUnits) : 0.0;

    return DcaResult(
      totalInvested: totalInvested,
      totalUnits: totalUnits,
      averagePrice: avgPrice,
    );
  }

  static Map<String, double> calculateProfitLoss({
    required double entryPrice,
    required double exitPrice,
    required double amount,
    double feePercent = 0.1,
  }) {
    double investment = entryPrice * amount;
    double grossExit = exitPrice * amount;

    double buyFee = investment * (feePercent / 100);
    double sellFee = grossExit * (feePercent / 100);
    double totalFees = buyFee + sellFee;

    double netProfit = (grossExit - investment) - totalFees;
    double percentage = investment > 0 ? (netProfit / investment) * 100 : 0.0;

    return {
      'investment': investment,
      'grossExit': grossExit,
      'netProfit': netProfit,
      'percentage': percentage,
      'totalFees': totalFees,
    };
  }
}
