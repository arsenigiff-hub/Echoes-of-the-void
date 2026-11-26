"""Tiny client for the blender-mcp addon socket (default 127.0.0.1:9876).
Usage: python tools/blender/bmcp.py script.py   -> runs the script inside the open Blender window."""
import json, socket, sys

def call(cmd_type, params=None, host="127.0.0.1", port=9876, timeout=300):
    with socket.create_connection((host, port), timeout=timeout) as s:
        s.sendall(json.dumps({"type": cmd_type, "params": params or {}}).encode("utf-8"))
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
            try:
                return json.loads(buf.decode("utf-8"))
            except json.JSONDecodeError:
                continue
    return json.loads(buf.decode("utf-8"))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(json.dumps(call("execute_code", {"code": open(sys.argv[1], encoding="utf-8").read()}), ensure_ascii=False)[:2000])
    else:
        print(json.dumps(call("get_scene_info"), ensure_ascii=False)[:1500])
