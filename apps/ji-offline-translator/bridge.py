# -*- coding: utf-8 -*-
"""
离线翻译助手 · 极语言前端的桥接服务（bridge）
=================================================

背景
----
原 aardio 工程的前端用 `web.rest.jsonClient` 直接消费 `engine/service.py` 的
JSON HTTP 接口。极语言（SEC）没有 JSON 库；而本版编译器在「手写 JSON 解析过程」
和「GUI 程序里发送格式化构造的 HTTP 头缓冲」这两处都不可靠（实测：前者产出无法
加载的 PE，后者 send() 返回 -1）。

因此加一层*极薄*的桥：它 **import 原 service.py 的 handle() / 各业务函数**，
业务逻辑（CTranslate2 翻译 / PaddleOCR / Qwen 推理 / SQLite 历史）一行未改。

传输协议（裸 TCP，一次发送、一次接收）
--------------------------------------
请求：客户端连接后先发 8 字节 ASCII 十进制长度，再发该长度的 UTF-8 JSON 字节
响应：服务端回 8 字节 ASCII 十进制长度 + 该长度的 UTF-8 纯文本，然后关闭连接

纯文本载荷约定
--------------
    ping            -> pong
    translate       -> 译文
    ai              -> AI 回答
    ocr             -> 识别出的多行文本（\\n 连接）
    ocr_translate   -> <原文>\\n\\x1e\\n<译文>      （\\x1e 为分隔符）
    history_add     -> 记录 id
    history_list    -> 每行一条：id\\tdir\\tsource\\ttarget
    history_delete  -> 1
    history_clear   -> 1
    ai_tasks        -> 每行 `key\\t显示名`

启动后把实际监听端口写入 <本文件所在目录>\\bridge_port.txt
（极语言端轮询该文件即可，与原工程的 httpport.txt 机制一致）。
"""

import json
import os
import socket
import socketserver
import sys
import threading

BASE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.join(BASE, 'engine')
if not os.path.isdir(ENGINE):
    ENGINE = BASE
sys.path.insert(0, ENGINE)

import service  # noqa: E402  （原引擎，未做任何修改）

AI_TASK_MAP = [
    ('翻译润色', 'translate'),
    ('语法分析', 'syntax'),
    ('俚语解释', 'slang'),
    ('固定搭配', 'colloc'),
    ('词句讲解', 'explain'),
    ('用词造句', 'sentence'),
    ('微故事', 'story'),
]

SEP = '\x1e'
LOG = os.path.join(BASE, 'bridge_req.log')


def log(msg):
    try:
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(msg + '\n')
    except Exception:
        pass


def history_rows(limit):
    rows = service.history_list(limit)
    out = []
    for r in rows:
        src = str(r.get('source', '')).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')
        tgt = str(r.get('target', '')).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')
        out.append('%s\t%s\t%s\t%s' % (r.get('id', ''), r.get('dir', ''), src, tgt))
    return '\n'.join(out)


def dispatch(req):
    """把 service.handle() 的 JSON 结果改写成纯文本载荷。"""
    cmd = req.get('cmd', '')

    if cmd == 'ai_tasks':
        return '\n'.join('%s\t%s' % (k, label) for label, k in AI_TASK_MAP)

    data = service.handle(req)
    if isinstance(data, dict) and data.get('error'):
        raise RuntimeError(data['error'])

    if cmd == 'ping':
        return 'pong'
    if cmd == 'translate':
        text = req.get('text', '')
        d = req.get('dir', 'en_zh')
        if req.get('auto_dir'):
            d = 'en_zh' if service.detect_lang(text) == 'en' else 'zh_en'
        return service.translate(text, d)
    if cmd == 'ai':
        return service.ai_ask(req.get('task', 'explain'), req.get('prompt', ''))
    if cmd == 'ocr':
        path = req.get('img') or req.get('path', '')
        return '\n'.join(service.ocr_text(path))
    if cmd == 'ocr_translate':
        path = req.get('img') or req.get('path', '')
        d = req.get('dir', 'auto')
        lines = service.ocr_text(path)
        src = '\n'.join(lines)
        if d == 'auto':
            d = 'en_zh' if service.detect_lang(src) == 'en' else 'zh_en'
        tgt = service.translate(src, d)
        return src + '\n' + SEP + '\n' + tgt
    if cmd == 'history_add':
        rid = service.history_add(req.get('source', ''), req.get('target', ''),
                                  req.get('dir', req.get('direction', '')))
        return str(rid)
    if cmd == 'history_list':
        return history_rows(req.get('limit', 200))
    if cmd == 'history_delete':
        return '1' if service.history_delete(req.get('ids')) else '0'
    if cmd == 'history_clear':
        return '1' if service.history_clear() else '0'
    if cmd == 'detect_lang':
        return service.detect_lang(req.get('text', ''))
    return data


class RawHandler(socketserver.BaseRequestHandler):
    def recv_exact(self, n):
        buf = b''
        while len(buf) < n:
            chunk = self.request.recv(n - len(buf))
            if not chunk:
                break
            buf += chunk
        return buf

    def handle(self):
        try:
            hdr = self.recv_exact(8)
            log('HDR raw=%r' % (hdr,))
            if len(hdr) < 8:
                return
            try:
                n = int(hdr.decode('ascii', 'replace').strip() or '0')
            except Exception:
                return
            body = self.recv_exact(n)
            log('REQ len=%d body=%s' % (n, body.decode('utf-8', 'replace')))
            try:
                req = json.loads(body.decode('utf-8'))
                payload = dispatch(req)
                text = 'OK\r\n' + ('' if payload is None else str(payload))
            except Exception as ex:
                text = 'ERR\r\n%s: %s' % (type(ex).__name__, ex)
            data = text.encode('utf-8', 'replace')
            self.request.sendall(('%08d' % len(data)).encode('ascii') + data)
        except Exception as ex:
            log('EXC %r' % (ex,))
        finally:
            try:
                self.request.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def find_free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


if __name__ == '__main__':
    port = find_free_port()
    with open(os.path.join(BASE, 'bridge_port.txt'), 'w') as f:
        f.write(str(port))

    def warmup():
        try:
            service.get_translators()
        except Exception as ex:
            print('WARMUP_TRANSLATE_FAIL', ex, flush=True)

    threading.Thread(target=warmup, daemon=True).start()
    Server(('127.0.0.1', port), RawHandler).serve_forever()
