#!/usr/bin/env python3
"""
Kai Dashboard Server
Serves dashboard.html on port 8420 from the Mac Mini.
Access from any device on the same network:
  http://Kai.local:8420
  http://<mini-ip>:8420

Auto-refreshes every 60 seconds so you always see latest data.
Runs as a background process via launchd.
"""

import os
import http.server
import socketserver

PORT = 8420
DASHBOARD_DIR = os.path.expanduser("~/Documents/Projects/Kai")


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DASHBOARD_DIR, **kwargs)

    def do_GET(self):
        # Serve dashboard.html as the root
        if self.path == "/" or self.path == "":
            self.path = "/dashboard.html"
        return super().do_GET()

    def end_headers(self):
        # Add auto-refresh header (60 seconds)
        if self.path.endswith(".html"):
            self.send_header("Refresh", "60")
        # Allow local network access
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def log_message(self, format, *args):
        # Suppress request logs to keep things quiet
        pass


if __name__ == "__main__":
    with socketserver.TCPServer(("0.0.0.0", PORT), DashboardHandler) as httpd:
        print(f"Kai Dashboard serving on port {PORT}")
        print(f"  Local:   http://localhost:{PORT}")
        print(f"  Network: http://Kai.local:{PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down.")
