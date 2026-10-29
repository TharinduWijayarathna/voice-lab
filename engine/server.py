"""VoiceLab's engine server: runs the Kokoro voice model behind the Swift window.

It listens on this Mac only (127.0.0.1), on a free port, and prints `VOICELAB_PORT=<port>` once it is ready.
With --watch-stdin it quits as soon as the app that started it goes away (its stdin closes).
"""
import json, os, socket, sys, threading, traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import engine  # noqa: E402

studio = engine.Studio()


def state():
    return {
        'ready': studio.kokoro is not None, 'error': studio.error, 'voices': studio.voices,
        'settings': studio.settings, 'lexicon': studio.lexicon, 'takes': studio.takes,
        'out_dir': studio.out_dir, 'home': os.path.expanduser('~'),
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def _send(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if urlparse(self.path).path == '/api/state':
            return self._send(200, state())
        self._send(404, {'error': 'Unknown request'})

    def do_POST(self):
        p = urlparse(self.path).path
        try:
            n = int(self.headers.get('Content-Length') or 0)
            body = json.loads(self.rfile.read(n) or b'{}')
            s = studio.settings
            if p == '/api/speak':
                takes = studio.make_takes(body.get('text', ''), body.get('voice', s['voice']), float(body.get('speed', 1)),
                                          float(body.get('pause', .25)), body.get('mix_voice', ''), float(body.get('mix', 0)),
                                          bool(body.get('split')), int(body.get('at', 0)))
                return self._send(200, {'takes': takes})
            if p == '/api/sample':
                return self._send(200, {'path': studio.sample(body['voice'], body.get('mix_voice', ''), float(body.get('mix', 0)))})
            if p == '/api/test-word':
                return self._send(200, {'path': studio.test_word(body['word'], body['say'], body.get('voice', s['voice']))})
            if p == '/api/rename':
                return self._send(200, {'take': studio.rename(body['id'], body['title'])})
            if p == '/api/delete':
                studio.delete(body['id'])
                return self._send(200, {'ok': True})
            if p == '/api/settings':
                studio.update_settings(body)
                return self._send(200, state())
            if p == '/api/lexicon':
                studio.set_lexicon(body.get('entries', []))
                return self._send(200, {'ok': True})
            return self._send(404, {'error': 'Unknown request'})
        except Exception as e:
            traceback.print_exc()
            return self._send(400, {'error': str(e)})


def free_port(prefer=47823):
    for port in (prefer, 0):
        s = socket.socket()
        try:
            s.bind(('127.0.0.1', port))
            port = s.getsockname()[1]
            s.close()
            return port
        except OSError:
            s.close()
    return 0


def main():
    server = ThreadingHTTPServer(('127.0.0.1', free_port()), Handler)
    if '--watch-stdin' in sys.argv:
        def watch():
            try:
                while sys.stdin.buffer.read(1024):
                    pass
            finally:
                os._exit(0)
        threading.Thread(target=watch, daemon=True).start()
    print(f'VOICELAB_PORT={server.server_address[1]}', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
