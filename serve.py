#!/usr/bin/env python3
"""Simple HTTP server with no caching for local development."""

from http.server import HTTPServer, SimpleHTTPRequestHandler

class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8000), NoCacheHandler)
    print('Serving at http://localhost:8000 (no-cache)')
    server.serve_forever()
