"""Local-only WebDAV fixture. Uses synthetic data in memory and logs no headers/body.
Run with python3 tools/serve-webdav-fixture.py; stop after WebDavHttp tests.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

FILES = {}
DIRECTORIES = {'/dav/'}
AUTH = 'Basic Zml4dHVyZTpmaXh0dXJl'  # Synthetic fixture:fixture only.

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        pass

    def reply(self, status, body=b'', **headers):
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def authenticated(self):
        if self.headers.get('Authorization') != AUTH:
            self.reply(401)
            return False
        return True

    def do_PROPFIND(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if not self.authenticated():
            return
        if self.headers.get('Depth') != '1':
            return self.reply(400)
        if self.path not in DIRECTORIES:
            return self.reply(404)
        items = (f'<d:response><d:href>{escape(self.path)}</d:href><d:propstat><d:prop>'
                 '<d:resourcetype><d:collection/></d:resourcetype></d:prop>'
                 '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>')
        items += ''.join(f'<d:response><d:href>{escape(path)}</d:href><d:propstat><d:prop>'
                        f'<d:getcontentlength>{len(body)}</d:getcontentlength><d:resourcetype/>'
                        '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>'
                        for path, body in FILES.items() if path.rsplit('/', 1)[0] + '/' == self.path)
        self.reply(207, ('<d:multistatus xmlns:d="DAV:">' + items + '</d:multistatus>').encode())

    def do_MKCOL(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if not self.authenticated():
            return
        if self.path in DIRECTORIES or self.path in FILES:
            return self.reply(405)
        if self.path.rstrip('/').rsplit('/', 1)[0] + '/' not in DIRECTORIES:
            return self.reply(409)
        DIRECTORIES.add(self.path)
        self.reply(201)

    def do_PUT(self):
        size = int(self.headers.get('Content-Length', '0'))
        if size > 1024 * 1024:
            self.close_connection = True
            return self.reply(413)
        body = self.rfile.read(size)
        if not self.authenticated():
            return
        if self.headers.get('If-None-Match') != '*':
            return self.reply(400)
        if self.path in FILES:
            return self.reply(412)
        FILES[self.path] = body
        self.reply(201)

    def do_GET(self):
        if not self.authenticated():
            return
        if self.path == '/redirect':
            return self.reply(302, Location='/must-not-follow')
        if self.path == '/must-not-follow':
            return self.reply(500, b'REDIRECT_FOLLOWED')
        if self.path in FILES:
            return self.reply(200, FILES[self.path])
        self.reply(404)

if __name__ == '__main__':
    print('WebDAV fixture listening on 127.0.0.1:18765', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 18765), Handler).serve_forever()
