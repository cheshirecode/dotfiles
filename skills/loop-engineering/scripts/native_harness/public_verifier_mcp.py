"""Minimal stdio MCP bridge to one controller-owned public verifier callback."""
import json
import hmac
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import secrets
import threading
import os
import sys
import urllib.request

TOOL={'name':'verify_work_order','description':'Run public behavior and source/Git integrity checks for the declared work order. This is not private final acceptance.',
      'inputSchema':{'type':'object','properties':{},'additionalProperties':False}}


class PublicVerifier:
    """Controller-owned loopback endpoint shared by native MCP adapters."""
    def __init__(self,public_verifier):
        token=secrets.token_urlsafe(32);lock=threading.Lock()
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_POST(self):
                if self.path!='/verify' or not hmac.compare_digest(self.headers.get('X-Factory-Token',''),token):
                    self.send_error(403);return
                if self.headers.get('Content-Length')!='2' or self.rfile.read(2)!=b'{}':
                    self.send_error(400);return
                try:
                    with lock:body=json.dumps(public_verifier()).encode()
                    self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
                except Exception:
                    self.send_error(500,'Public verifier failed; inspect controller evidence')
        self.http=ThreadingHTTPServer(('127.0.0.1',0),Handler);self.http.daemon_threads=True
        self.http_thread=threading.Thread(target=self.http.serve_forever,daemon=True);self.http_thread.start()
        self.environment={'FACTORY_PUBLIC_PORT':str(self.http.server_port),'FACTORY_PUBLIC_TOKEN':token}

    def close(self):
        self.http.shutdown();self.http.server_close();self.http_thread.join(timeout=2)


def dispatch(message,verify):
    if not isinstance(message,dict):raise ValueError('Request must be an object')
    method=message.get('method');params=message.get('params') or {}
    if not isinstance(params,dict):raise ValueError('Parameters must be an object')
    if method=='initialize':
        return {'protocolVersion':params.get('protocolVersion','2024-11-05'),
                'capabilities':{'tools':{}},'serverInfo':{'name':'factory-public-verifier','version':'1'}}
    if method=='ping':return {}
    if method=='tools/list':return {'tools':[TOOL]}
    if method=='tools/call':
        if params.get('name')!='verify_work_order' or params.get('arguments',{})!={}:
            raise ValueError('Only verify_work_order with empty arguments is available')
        return {'content':[{'type':'text','text':json.dumps(verify())}],'isError':False}
    raise ValueError('Unsupported method')


def main():
    url='http://127.0.0.1:'+os.environ['FACTORY_PUBLIC_PORT']+'/verify'
    def verify():
        request=urllib.request.Request(url,data=b'{}',headers={'X-Factory-Token':os.environ['FACTORY_PUBLIC_TOKEN']})
        with urllib.request.urlopen(request,timeout=100) as response:return json.load(response)
    for line in sys.stdin:
        try:
            message=json.loads(line)
            if not isinstance(message,dict):raise ValueError('Request must be an object')
            if 'id' not in message:continue
            try:reply={'jsonrpc':'2.0','id':message['id'],'result':dispatch(message,verify)}
            except Exception as error:reply={'jsonrpc':'2.0','id':message['id'],'error':{'code':-32602,'message':str(error)}}
            print(json.dumps(reply),flush=True)
        except (ValueError,TypeError):
            print(json.dumps({'jsonrpc':'2.0','id':None,'error':{'code':-32700,'message':'Invalid JSON request'}}),flush=True)


if __name__=='__main__':main()
