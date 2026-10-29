"""VoiceLab: a small Mac app for making voice-over clips with the Kokoro voice model.

Runs a private web server on this computer (127.0.0.1 only) and shows it in a native window.
"""
import json, mimetypes, os, socket, subprocess, sys, threading, traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import engine  # noqa: E402

UI = os.path.join(HERE, 'ui')
studio = engine.Studio()
window = None


def state():
    return {
        'ready': studio.kokoro is not None, 'error': studio.error, 'voices': studio.voices,
        'settings': studio.settings, 'lexicon': studio.lexicon, 'takes': studio.takes,
        'out_dir': studio.out_dir, 'native': window is not None, 'home': os.path.expanduser('~'),
    }


def reveal(path):
    if sys.platform == 'darwin':
        subprocess.Popen(['open', '-R', path] if os.path.isfile(path) else ['open', path])
    elif sys.platform.startswith('win'):
        subprocess.Popen(['explorer', '/select,', path])
    else:
        subprocess.Popen(['xdg-open', os.path.dirname(path) if os.path.isfile(path) else path])


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype='application/json; charset=utf-8', extra=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def _file(self, path):
        if not os.path.isfile(path):
            return self._send(404, {'error': 'Not found'})
        size = os.path.getsize(path)
        ctype = mimetypes.guess_type(path)[0] or 'application/octet-stream'
        start, end = 0, size - 1
        rng = self.headers.get('Range')
        if rng and rng.startswith('bytes='):  # WebKit asks for audio in ranges
            a, _, b = rng[6:].partition('-')
            start = int(a) if a else max(0, size - int(b))
            end = int(b) if a and b else size - 1
            end = min(end, size - 1)
        with open(path, 'rb') as f:
            f.seek(start)
            data = f.read(end - start + 1)
        extra = {'Accept-Ranges': 'bytes'}
        if rng:
            extra['Content-Range'] = f'bytes {start}-{end}/{size}'
        self._send(206 if rng else 200, data, ctype, extra)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        p = unquote(urlparse(self.path).path)
        if p == '/api/state':
            return self._send(200, state())
        if p.startswith('/clips/'):
            return self._file(os.path.join(studio.out_dir, os.path.basename(p[7:])))
        if p.startswith('/samples/'):
            return self._file(os.path.join(engine.DATA_DIR, 'samples', os.path.basename(p[9:])))
        rel = 'index.html' if p in ('/', '') else p.lstrip('/')
        full = os.path.normpath(os.path.join(UI, rel))
        if not full.startswith(UI):
            return self._send(403, {'error': 'No'})
        self._file(full)

    def do_POST(self):
        p = urlparse(self.path).path
        try:
            n = int(self.headers.get('Content-Length') or 0)
            body = json.loads(self.rfile.read(n) or b'{}')
            if p == '/api/speak':
                s = studio.settings
                takes = studio.make_takes(body.get('text', ''), body.get('voice', s['voice']), float(body.get('speed', 1)),
                                          float(body.get('pause', .25)), body.get('mix_voice', ''), float(body.get('mix', 0)),
                                          bool(body.get('split')), int(body.get('at', 0)))
                return self._send(200, {'takes': takes})
            if p == '/api/sample':
                path = studio.sample(body['voice'], body.get('mix_voice', ''), float(body.get('mix', 0)))
                return self._send(200, {'url': '/samples/' + os.path.basename(path)})
            if p == '/api/test-word':
                path = studio.test_word(body['word'], body['say'], body.get('voice', studio.settings['voice']))
                return self._send(200, {'url': '/samples/' + os.path.basename(path) + f'?v={os.path.getmtime(path)}'})
            if p == '/api/rename':
                return self._send(200, {'take': studio.rename(body['id'], body['title'])})
            if p == '/api/delete':
                studio.delete(body['id'])
                return self._send(200, {'ok': True})
            if p == '/api/reveal':
                if body.get('id'):
                    reveal(os.path.join(studio.out_dir, studio.find(body['id'])['file']))
                else:
                    os.makedirs(studio.out_dir, exist_ok=True)
                    reveal(studio.out_dir)
                return self._send(200, {'ok': True})
            if p == '/api/settings':
                studio.update_settings(body)
                return self._send(200, state())
            if p == '/api/lexicon':
                studio.set_lexicon(body.get('entries', []))
                return self._send(200, {'ok': True})
            if p == '/api/pick-folder':
                return self._send(200, {'path': pick_folder()})
            return self._send(404, {'error': 'Unknown request'})
        except Exception as e:
            traceback.print_exc()
            return self._send(400, {'error': str(e)})


def pick_folder():
    if window is None:
        return None
    import webview
    kind = getattr(getattr(webview, 'FileDialog', None), 'FOLDER', None) or webview.FOLDER_DIALOG
    r = window.create_file_dialog(kind, directory=studio.out_dir)
    return r[0] if r else None


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


def mac_identity():
    """Show 'VoiceLab' and its icon in the Dock and menu bar, instead of Python's."""
    if sys.platform != 'darwin':
        return
    try:
        from AppKit import NSApplication, NSImage
        from Foundation import NSBundle
        info = NSBundle.mainBundle().localizedInfoDictionary() or NSBundle.mainBundle().infoDictionary()
        if info is not None:
            info['CFBundleName'] = engine.APP_NAME
        icon = os.environ.get('VOICELAB_ICON') or os.path.join(HERE, 'icon', 'AppIcon.icns')
        if os.path.exists(icon):
            NSApplication.sharedApplication().setApplicationIconImage_(NSImage.alloc().initWithContentsOfFile_(icon))
    except Exception:
        pass


def main():
    global window
    port = free_port()
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    url = f'http://127.0.0.1:{port}/'
    if '--browser' in sys.argv:
        print('VoiceLab is open at', url)
        import webbrowser
        webbrowser.open(url)
        server.serve_forever()
        return
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        import webview
    except ImportError:
        print('pywebview is not installed, so VoiceLab opens in your browser:', url)
        import webbrowser
        webbrowser.open(url)
        threading.Event().wait()
        return
    mac_identity()
    window = webview.create_window(engine.APP_NAME, url, width=1240, height=800, min_size=(960, 620),
                                   background_color='#FBF1F1', text_select=True)
    webview.start()
    server.shutdown()


if __name__ == '__main__':
    main()
