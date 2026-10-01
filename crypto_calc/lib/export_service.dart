import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:intl/intl.dart';
import 'calculator_service.dart';

class ExportService {
  /// CSV Formatında Dışa Aktarma ve İndirme
  static void exportToCsv({
    required String assetName,
    required DcaResult dcaResult,
    required List<DcaEntry> entries,
    TakeProfitResult? tpResult,
    List<TakeProfitStep>? tpSteps,
  }) {
    final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final StringBuffer buffer = StringBuffer();

    buffer.writeln("DCA & Portfolio Report - $assetName");
    buffer.writeln("Date,${DateTime.now().toIso8601String()}");
    buffer.writeln("");
    buffer.writeln("SUMMARY");
    buffer.writeln("Asset,$assetName");
    buffer.writeln("Average Cost,${dcaResult.averagePrice.toStringAsFixed(4)}");
    buffer.writeln("Total Invested,${dcaResult.totalInvested.toStringAsFixed(2)}");
    buffer.writeln("Total Units,${dcaResult.totalUnits.toStringAsFixed(6)}");
    buffer.writeln("");

    buffer.writeln("PURCHASE TIERS (DCA)");
    buffer.writeln("Tier,Buy Price (USD),Amount,Total Spent (USD)");
    for (int i = 0; i < entries.length; i++) {
      buffer.writeln("${i + 1},${entries[i].buyPrice},${entries[i].amount},${entries[i].totalSpent.toStringAsFixed(2)}");
    }
    buffer.writeln("");

    if (tpResult != null && tpSteps != null && tpSteps.isNotEmpty) {
      buffer.writeln("TAKE PROFIT (PARTIAL SALES)");
      buffer.writeln("Tier,Sell Price (USD),Percentage (%),Sold Units,Cash (USD)");
      for (int i = 0; i < tpSteps.length; i++) {
        double units = dcaResult.totalUnits * (tpSteps[i].percentage / 100.0);
        double cash = units * tpSteps[i].sellPrice;
        buffer.writeln("${i + 1},${tpSteps[i].sellPrice},${tpSteps[i].percentage}%,${units.toStringAsFixed(6)},${cash.toStringAsFixed(2)}");
      }
      buffer.writeln("");
      buffer.writeln("TP Realized Cash,${tpResult.totalRealizedCash.toStringAsFixed(2)}");
      buffer.writeln("TP Net Profit,${tpResult.netProfit.toStringAsFixed(2)}");
      buffer.writeln("TP Profit %,${tpResult.profitPercentage.toStringAsFixed(2)}%");
      buffer.writeln("Remaining Units,${tpResult.remainingUnits.toStringAsFixed(6)}");
    }

    final bytes = utf8.encode(buffer.toString());
    final base64Content = base64Encode(bytes);
    final fileName = "${assetName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_DCA_$dateStr.csv";

    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = 'data:text/csv;charset=utf-8;base64,$base64Content';
    anchor.download = fileName;
    web.document.body?.appendChild(anchor);
    anchor.click();
    web.document.body?.removeChild(anchor);
  }

  /// Yazdırmaya ve PDF Kaydetmeye Hazır Şık Rapor Penceresi
  static void printPdfReport({
    required String assetName,
    required DcaResult dcaResult,
    required List<DcaEntry> entries,
    TakeProfitResult? tpResult,
    List<TakeProfitStep>? tpSteps,
  }) {
    final dateFormatted = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    String rowsHtml = '';
    for (int i = 0; i < entries.length; i++) {
      rowsHtml += '''
        <tr>
          <td>#${i + 1}</td>
          <td>\$${entries[i].buyPrice.toStringAsFixed(2)}</td>
          <td>${entries[i].amount.toStringAsFixed(4)}</td>
          <td>\$${entries[i].totalSpent.toStringAsFixed(2)}</td>
        </tr>
      ''';
    }

    String tpHtml = '';
    if (tpResult != null && tpSteps != null && tpSteps.isNotEmpty) {
      String tpRows = '';
      for (int i = 0; i < tpSteps.length; i++) {
        double units = dcaResult.totalUnits * (tpSteps[i].percentage / 100.0);
        double cash = units * tpSteps[i].sellPrice;
        tpRows += '''
          <tr>
            <td>TP #${i + 1}</td>
            <td>\$${tpSteps[i].sellPrice.toStringAsFixed(2)}</td>
            <td>${tpSteps[i].percentage.toStringAsFixed(0)}%</td>
            <td>${units.toStringAsFixed(4)}</td>
            <td>\$${cash.toStringAsFixed(2)}</td>
          </tr>
        ''';
      }

      tpHtml = '''
        <h3 style="margin-top:24px; color:#d97706;">Take-Profit (Kademeli Satis) Stratejisi</h3>
        <table>
          <thead>
            <tr style="background:#d97706; color:#fff;">
              <th>Hedef</th>
              <th>Satis Fiyati</th>
              <th>Cikis %</th>
              <th>Satilan Adet</th>
              <th>Nakit Karsiligi</th>
            </tr>
          </thead>
          <tbody>$tpRows</tbody>
        </table>
        <div style="background:#fef3c7; border:1px solid #fde68a; padding:10px 14px; border-radius:6px; margin-top:8px; display:flex; justify-content:space-between; font-size:13px; font-weight:bold;">
          <span>Ortalama Satis: \$${tpResult.weightedAverageSellPrice.toStringAsFixed(2)}</span>
          <span style="color:#059669;">Realize Kar: +\$${tpResult.netProfit.toStringAsFixed(2)} (+${tpResult.profitPercentage.toStringAsFixed(1)}%)</span>
          <span>Kalan: ${tpResult.remainingUnits.toStringAsFixed(4)} (%${tpResult.remainingPercentage.toStringAsFixed(0)})</span>
        </div>
      ''';
    }

    final String htmlString = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>$assetName - Portfoy Raporu</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; color: #1f2937; padding: 32px; max-width: 800px; margin: 0 auto; }
          .header { display: flex; justify-content: space-between; border-bottom: 2px solid #00c853; padding-bottom: 12px; margin-bottom: 20px; }
          .kpi-container { display: flex; gap: 14px; margin-bottom: 24px; }
          .kpi { flex: 1; background: #f3f4f6; border-radius: 8px; padding: 12px 16px; border: 1px solid #e5e7eb; }
          .kpi-title { font-size: 11px; text-transform: uppercase; color: #6b7280; font-weight: 600; }
          .kpi-value { font-size: 20px; font-weight: bold; color: #111827; margin-top: 4px; }
          table { width: 100%; border-collapse: collapse; margin-top: 8px; font-size: 13px; }
          th, td { border: 1px solid #e5e7eb; padding: 8px 12px; text-align: left; }
          th { background: #00c853; color: white; font-weight: 600; }
          tr:nth-child(even) { background: #f9fafb; }
          @media print { body { padding: 0; } }
        </style>
      </head>
      <body>
        <div class="header">
          <div>
            <h2 style="margin:0; color:#059669;">DCA & Portfoy Raporu</h2>
            <p style="margin:4px 0 0; font-size:12px; color:#6b7280;">CryptoCalc Pro</p>
          </div>
          <div style="text-align:right;">
            <h3 style="margin:0;">$assetName</h3>
            <p style="margin:4px 0 0; font-size:12px; color:#6b7280;">$dateFormatted</p>
          </div>
        </div>

        <div class="kpi-container">
          <div class="kpi">
            <div class="kpi-title">Ortalama Maliyet</div>
            <div class="kpi-value" style="color:#059669;">\$${dcaResult.averagePrice.toStringAsFixed(2)}</div>
          </div>
          <div class="kpi">
            <div class="kpi-title">Toplam Yatirim</div>
            <div class="kpi-value">\$${dcaResult.totalInvested.toStringAsFixed(2)}</div>
          </div>
          <div class="kpi">
            <div class="kpi-title">Toplam Adet</div>
            <div class="kpi-value">${dcaResult.totalUnits.toStringAsFixed(4)}</div>
          </div>
        </div>

        <h3>Alis Kademeleri (DCA)</h3>
        <table>
          <thead>
            <tr>
              <th>Kademe</th>
              <th>Alis Fiyati</th>
              <th>Miktar / Adet</th>
              <th>Toplam Tutar</th>
            </tr>
          </thead>
          <tbody>$rowsHtml</tbody>
        </table>

        $tpHtml

        <script>
          window.onload = function() {
            setTimeout(function() { window.print(); }, 400);
          };
        </script>
      </body>
      </html>
    ''';

    final base64Html = base64Encode(utf8.encode(htmlString));
    web.window.open('data:text/html;charset=utf-8;base64,$base64Html', '_blank');
  }
}
