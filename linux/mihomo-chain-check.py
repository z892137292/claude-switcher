#!/usr/bin/env python3
"""查询 mihomo /connections: claude/anthropic 域名的连接若走 DIRECT 即判定绕过代理。
退出码: 0=正常 1=发现直连 2=API 不可用。
配置: ~/.claude-switcher/mihomo-api (一行,默认 http://127.0.0.1:9090)
密钥: ~/.claude-switcher/mihomo-secret (仅文件读取,不进命令行/日志)"""
import json, os, sys, urllib.request

BASE = os.path.expanduser("~/.claude-switcher")
KEYS = ("claude", "anthropic")


def read(name, default=""):
    try:
        with open(os.path.join(BASE, name), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return default


def main():
    url = read("mihomo-api", "http://127.0.0.1:9090").rstrip("/")
    secret = read("mihomo-secret")
    req = urllib.request.Request(url + "/connections")
    if secret:
        req.add_header("Authorization", "Bearer " + secret)
    try:
        with urllib.request.urlopen(req, timeout=3) as r:
            data = json.load(r)
    except Exception:
        return 2
    for c in data.get("connections") or []:
        host = (c.get("metadata") or {}).get("host", "").lower()
        if any(k in host for k in KEYS) and "DIRECT" in (c.get("chains") or []):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
