#!/usr/bin/env python3
"""Генерация моделей через Tripo3D API (text-to-model) для проекта ECHOES OF THE VOID.

Ключ API читается из переменной окружения TRIPO_API_KEY или из файла .env в корне проекта
(строка TRIPO_API_KEY=tsk_...). Файл .env в git не попадает. Ключ нигде не печатается.

Примеры:
  python tools/tripo_generate.py --balance
  python tools/tripo_generate.py --name pilot_seat --prompt "worn pilot seat ..." --out assetss/tripo_incoming
  python tools/tripo_generate.py --batch tools/tripo_trial.json --out assetss/tripo_incoming --max-tasks 4

Формат batch-файла: [{"name": "pilot_seat", "prompt": "...", "face_limit": 3000}, ...]

База API и поля ответа могут отличаться между версиями Tripo; при ошибке скрипт печатает ответ
сервера (без ключа). Базу можно переопределить: TRIPO_API_BASE=https://api.tripo3d.ai/v2/openapi
Скачиваются только GLB и превью-картинка в указанную папку; ничего не исполняется.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

DEFAULT_BASE = "https://api.tripo3d.ai/v2/openapi"
STYLE = (
    "low-poly retro-industrial prop, 1990s space shuttle, worn matte paint, scuffed metal, "
    "dull desaturated colors, PS1-era game asset, chunky simple shapes, no neon, no glowing blue, "
    "no holograms, single object, centered, neutral background"
)


def load_key():
    key = os.environ.get("TRIPO_API_KEY", "").strip()
    if not key:
        env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")
        if os.path.exists(env_path):
            for line in open(env_path, encoding="utf-8"):
                line = line.strip()
                if line.startswith("TRIPO_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit("Нет ключа: задайте TRIPO_API_KEY (переменная окружения или .env в корне проекта).")
    return key


def call(base, key, method, path, payload=None):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(
        base + path, data=data, method=method,
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json",
                 "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) echoes-tripo-client/1.0",
                 "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        sys.exit("HTTP %s от Tripo: %s" % (error.code, body[:600]))


def balance(base, key):
    reply = call(base, key, "GET", "/user/balance")
    return reply.get("data", reply)


def find_url(output, suffixes):
    """Ищет в output первый URL с нужным расширением (формат полей зависит от версии API)."""
    if isinstance(output, dict):
        for value in output.values():
            found = find_url(value, suffixes)
            if found:
                return found
    elif isinstance(output, str) and output.startswith("http"):
        if any(output.split("?")[0].lower().endswith(s) for s in suffixes):
            return output
    return None


def download(url, path):
    with urllib.request.urlopen(url, timeout=120) as response, open(path, "wb") as out:
        out.write(response.read())
    return os.path.getsize(path)


def generate(base, key, item, out_dir, poll_seconds=6, timeout_seconds=600):
    name = item["name"]
    payload = {
        "type": "text_to_model",
        "prompt": item["prompt"].rstrip(".") + ". " + STYLE,
        "texture": True,
    }
    if "face_limit" in item:
        payload["face_limit"] = item["face_limit"]
    if "model_version" in item:
        payload["model_version"] = item["model_version"]
    reply = call(base, key, "POST", "/task", payload)
    task_id = reply.get("data", {}).get("task_id")
    if not task_id:
        sys.exit("Нет task_id в ответе: %s" % json.dumps(reply)[:400])
    print("[%s] задача %s создана" % (name, task_id))
    started = time.time()
    while time.time() - started < timeout_seconds:
        time.sleep(poll_seconds)
        data = call(base, key, "GET", "/task/" + task_id).get("data", {})
        status = data.get("status")
        print("[%s] %s %s%%" % (name, status, data.get("progress", "?")))
        if status == "success":
            os.makedirs(out_dir, exist_ok=True)
            output = data.get("output", {})
            glb = find_url(output, (".glb",))
            preview = find_url(output, (".webp", ".png", ".jpg", ".jpeg"))
            result = {"name": name, "task_id": task_id}
            if glb:
                result["glb"] = download(glb, os.path.join(out_dir, name + ".glb"))
            if preview:
                ext = os.path.splitext(preview.split("?")[0])[1] or ".png"
                result["preview"] = download(preview, os.path.join(out_dir, name + "_preview" + ext))
            return result
        if status in ("failed", "cancelled", "unknown", "banned", "expired"):
            sys.exit("[%s] задача завершилась статусом %s" % (name, status))
    sys.exit("[%s] таймаут ожидания" % name)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--balance", action="store_true", help="показать баланс кредитов и выйти")
    parser.add_argument("--name")
    parser.add_argument("--prompt")
    parser.add_argument("--face-limit", type=int)
    parser.add_argument("--batch", help="JSON со списком предметов")
    parser.add_argument("--out", default="assetss/tripo_incoming")
    parser.add_argument("--max-tasks", type=int, default=4, help="предохранитель по расходу кредитов")
    args = parser.parse_args()

    base = os.environ.get("TRIPO_API_BASE", DEFAULT_BASE).rstrip("/")
    key = load_key()
    if args.balance:
        print(json.dumps(balance(base, key), ensure_ascii=False))
        return
    items = []
    if args.batch:
        items = json.load(open(args.batch, encoding="utf-8"))
    elif args.name and args.prompt:
        item = {"name": args.name, "prompt": args.prompt}
        if args.face_limit:
            item["face_limit"] = args.face_limit
        items = [item]
    else:
        parser.error("нужен --balance, --batch или --name с --prompt")
    if len(items) > args.max_tasks:
        sys.exit("В списке %d предметов, лимит --max-tasks %d. Поднимите лимит осознанно." % (len(items), args.max_tasks))
    print("Баланс до:", json.dumps(balance(base, key), ensure_ascii=False))
    for item in items:
        print(json.dumps(generate(base, key, item, args.out), ensure_ascii=False))
    print("Баланс после:", json.dumps(balance(base, key), ensure_ascii=False))


if __name__ == "__main__":
    main()
