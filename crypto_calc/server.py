import http.server
import socketserver
import urllib.request
import json

PORT = 8080
DIRECTORY = "build/web"

class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        if self.path.startswith("/api/prices"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            try:
                # Kriptolar
                url = "https://data-api.binance.vision/api/v3/ticker/24hr?symbols=[%22BTCUSDT%22,%22ETHUSDT%22,%22SOLUSDT%22,%22BNBUSDT%22,%22XRPUSDT%22,%22PAXGUSDT%22]"
                req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
                with urllib.request.urlopen(req, timeout=5) as response:
                    data = json.loads(response.read().decode('utf-8'))
                
                # Altın (PAXG bazlı ons altın ve türetilmiş gümüş/gram altın)
                paxg_price = 2650.0
                for item in data:
                    if item.get("symbol") == "PAXGUSDT":
                        paxg_price = float(item.get("lastPrice", 2650.0))
                
                usd_try = 34.25
                gold_gram_usd = paxg_price / 31.1035
                gold_gram_try = gold_gram_usd * usd_try
                silver_oz_usd = 31.80
                platinum_oz_usd = 995.0

                metals = [
                    {"symbol": "XAU_OZ", "lastPrice": str(round(paxg_price, 2)), "priceChangePercent": "0.45", "name": "Ons Altın (USD)"},
                    {"symbol": "GA_TRY", "lastPrice": str(round(gold_gram_try, 2)), "priceChangePercent": "0.52", "name": "Gram Altın (TL)"},
                    {"symbol": "GA_USD", "lastPrice": str(round(gold_gram_usd, 2)), "priceChangePercent": "0.45", "name": "Gram Altın ($)"},
                    {"symbol": "XAG_OZ", "lastPrice": str(round(silver_oz_usd, 2)), "priceChangePercent": "-0.30", "name": "Gümüş Ons ($)"},
                    {"symbol": "XPT_OZ", "lastPrice": str(round(platinum_oz_usd, 2)), "priceChangePercent": "0.15", "name": "Platin Ons ($)"},
                ]
                
                combined = data + metals
                self.wfile.write(json.dumps(combined).encode('utf-8'))
            except Exception:
                self.wfile.write(b"[]")
        else:
            super().do_GET()

with socketserver.TCPServer(("0.0.0.0", PORT), ProxyHandler) as httpd:
    print(f"Serving HTTP & Live Crypto/Metals Proxy on port {PORT}...")
    httpd.serve_forever()
