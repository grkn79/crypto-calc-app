import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'calculator_service.dart';

// Evrensel web indirme tetikleyicisi (Yalnızca kIsWeb iken çalışır)
import 'export_web_stub.dart'
    if (dart.library.html) 'export_web_real.dart' as platform_export;

class ExportService {
  static void exportToCsv({
    required String assetName,
    required DcaResult dcaResult,
    required List<DcaEntry> entries,
    TakeProfitResult? tpResult,
    List<TakeProfitStep>? tpSteps,
  }) {
    final buffer = StringBuffer();
    buffer.writeln("sep=,");
    buffer.writeln("Portfolio Report - $assetName");
    buffer.writeln("Date,${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}");
    buffer.writeln("");

    buffer.writeln("DCA SUMMARY");
    buffer.writeln("Metric,Value");
    buffer.writeln("Average Cost per Unit,${dcaResult.averagePrice.toStringAsFixed(2)}");
    buffer.writeln("Total Invested,${dcaResult.totalInvested.toStringAsFixed(2)}");
    buffer.writeln("Total Units,${dcaResult.totalUnits.toStringAsFixed(4)}");
    buffer.writeln("Break-Even Price,${dcaResult.breakEvenPrice.toStringAsFixed(2)}");
    buffer.writeln("");

    buffer.writeln("PURCHASE TIERS");
    buffer.writeln("Tier,Price,Units,Total");
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      buffer.writeln("${i + 1},${e.buyPrice.toStringAsFixed(2)},${e.amount.toStringAsFixed(4)},${(e.buyPrice * e.amount).toStringAsFixed(2)}");
    }

    if (tpResult != null && tpSteps != null && tpSteps.isNotEmpty) {
      buffer.writeln("");
      buffer.writeln("TAKE-PROFIT TIERS");
      buffer.writeln("Tier,Sell Price,Sell %,Realized Cash");
      for (int i = 0; i < tpSteps.length; i++) {
        final s = tpSteps[i];
        final stepCash = (dcaResult.totalUnits * (s.percentage / 100)) * s.sellPrice;
        buffer.writeln("${i + 1},${s.sellPrice.toStringAsFixed(2)},${s.percentage}%,${stepCash.toStringAsFixed(2)}");
      }
      buffer.writeln("Net Realized Cash,${tpResult.totalRealizedCash.toStringAsFixed(2)}");
      buffer.writeln("Net Profit,${tpResult.netProfit.toStringAsFixed(2)}");
    }

    final bytes = utf8.encode(buffer.toString());
    final filename = "${assetName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_dca_report.csv";
    
    if (kIsWeb) {
      platform_export.downloadFileWeb(bytes, filename, 'text/csv');
    }
  }

  static void printPdfReport({
    required String assetName,
    required DcaResult dcaResult,
    required List<DcaEntry> entries,
    TakeProfitResult? tpResult,
    List<TakeProfitStep>? tpSteps,
  }) {
    final buffer = StringBuffer();
    buffer.writeln("=== DCA SUMMARY REPORT: $assetName ===");
    buffer.writeln("Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}");
    buffer.writeln("---------------------------------------");
    buffer.writeln("Average Cost: \$${dcaResult.averagePrice.toStringAsFixed(2)}");
    buffer.writeln("Total Invested: \$${dcaResult.totalInvested.toStringAsFixed(2)}");
    buffer.writeln("Total Units: ${dcaResult.totalUnits.toStringAsFixed(4)}");
    buffer.writeln("Break-Even: \$${dcaResult.breakEvenPrice.toStringAsFixed(2)}");
    buffer.writeln("---------------------------------------");
    buffer.writeln("BUY TIERS:");
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      buffer.writeln(" ${i + 1}. Price: \$${e.buyPrice.toStringAsFixed(2)} | Amount: ${e.amount.toStringAsFixed(4)} | Total: \$${(e.buyPrice * e.amount).toStringAsFixed(2)}");
    }

    final bytes = utf8.encode(buffer.toString());
    final filename = "${assetName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_dca_summary.txt";

    if (kIsWeb) {
      platform_export.downloadFileWeb(bytes, filename, 'text/plain');
    }
  }
}
