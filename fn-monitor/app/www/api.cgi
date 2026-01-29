#!/usr/bin/env python3
import os, sys, json, time, subprocess

LOGIND_PATH = "/etc/systemd/logind.conf"
BASE_DIR = os.path.dirname(__file__)
SCREEN_STATE_PATH = os.path.join(BASE_DIR, "screen_state.json")


def respond(obj, status=200):
    print("Content-Type: application/json")
    print()
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.exit(0)


def read_logind():
    try:
        with open(LOGIND_PATH, "r", encoding="utf-8") as f:
            txt = f.read()
    except Exception as e:
        respond({"ok": False, "error": "read failed: " + str(e)})
    # parse simple key=value pairs (no full ini parsing)
    parsed = {}
    section = None
    for raw in txt.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and "]" in line:
            section = line[1 : line.index("]")].strip()
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            parsed[k.strip()] = v.strip()
    respond({"ok": True, "content": txt, "parsed": parsed})


def write_logind(body):
    # body may contain 'content' (full file) or 'changes' dict
    content = body.get("content")
    if content is None:
        # apply changes to file textually
        try:
            with open(LOGIND_PATH, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception as e:
            respond({"ok": False, "error": "read before write failed: " + str(e)})
        changes = body.get("changes", {})
        out_lines = []
        section = None
        applied = set()
        login_out_index = None
        for ln in lines:
            s = ln.strip()
            if s.startswith("[") and "]" in s:
                section = s[1 : s.index("]")].strip()
                out_lines.append(ln)
                if section == "Login" and login_out_index is None:
                    # record insertion point (after the [Login] header)
                    login_out_index = len(out_lines)
                continue
            if "=" in ln and section == "Login":
                k = ln.split("=", 1)[0].strip()
                if k in changes:
                    # empty string or null means remove the key to restore system default
                    val = changes[k]
                    if val is None or (isinstance(val, str) and val == ""):
                        # skip this line (remove the setting)
                        applied.add(k)
                    else:
                        out_lines.append(f"{k}={changes[k]}\n")
                        applied.add(k)
                else:
                    out_lines.append(ln)
            else:
                out_lines.append(ln)
        # append missing keys under [Login]
        # Only add missing keys that have a non-empty value (empty means remove/default)
        missing = [
            k
            for k in changes.keys()
            if k not in applied
            and (
                changes[k] is not None
                and not (isinstance(changes[k], str) and changes[k] == "")
            )
        ]
        if missing:
            if login_out_index is not None:
                # insert missing keys right after the existing [Login] header
                insert_lines = [f"{k}={changes[k]}\n" for k in missing]
                out_lines[login_out_index:login_out_index] = insert_lines
            else:
                out_lines.append("\n[Login]\n")
                for k in missing:
                    out_lines.append(f"{k}={changes[k]}\n")
        content = "".join(out_lines)
    try:
        with open(LOGIND_PATH, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception as e:
        respond({"ok": False, "error": "write failed: " + str(e)})
    if body.get("apply"):
        try:
            p = subprocess.run(
                ["systemctl", "restart", "systemd-logind"],
                capture_output=True,
                text=True,
                timeout=20,
            )
            if p.returncode != 0:
                respond(
                    {
                        "ok": False,
                        "error": "restart failed",
                        "stdout": p.stdout,
                        "stderr": p.stderr,
                    }
                )
            else:
                respond(
                    {"ok": True, "message": "written and restarted", "stdout": p.stdout}
                )
        except Exception as e:
            respond({"ok": False, "error": "restart exception: " + str(e)})
    respond({"ok": True, "message": "written"})


def get_query_param(name):
    qs = os.environ.get("QUERY_STRING", "")
    for part in qs.split("&"):
        if "=" in part:
            k, v = part.split("=", 1)
            if k == name:
                return v
    return None


def read_post_json():
    try:
        if os.environ.get("REQUEST_METHOD", "").upper() != "POST":
            return {}
        cl = int(os.environ.get("CONTENT_LENGTH", "0") or 0)
        body = sys.stdin.read(cl) if cl else ""
        if not body:
            return {}
        return json.loads(body)
    except Exception:
        return {}


def main():
    action = get_query_param("action") or "read"
    if action == "read":
        return read_logind()
    if action == "write":
        body = read_post_json()
        return write_logind(body)
    if action == "screen":
        # handle screen blank/poke via setterm
        state = get_query_param("state") or ""
        state = state.lower()
        try:
            tty = "/dev/tty1"
            if state in ("off", "blank", "force"):
                # turn off / blank the console
                with open(tty, "rb") as fd:
                    p = subprocess.run(
                        ["setterm", "--blank", "force", "--term", "linux"],
                        stdin=fd,
                        capture_output=True,
                        text=True,
                        timeout=5,
                    )
            elif state in ("on", "poke"):
                with open(tty, "rb") as fd:
                    p = subprocess.run(
                        ["setterm", "--blank", "poke", "--term", "linux"],
                        stdin=fd,
                        capture_output=True,
                        text=True,
                        timeout=5,
                    )
            else:
                respond({"ok": False, "error": "missing or unknown state parameter"})
            if p.returncode != 0:
                respond(
                    {
                        "ok": False,
                        "error": "setterm failed",
                        "stdout": p.stdout,
                        "stderr": p.stderr,
                    }
                )
            # persist last known state
            try:
                with open(SCREEN_STATE_PATH, "w", encoding="utf-8") as sf:
                    json.dump({"state": state, "ts": int(time.time())}, sf)
            except Exception:
                pass
            respond(
                {
                    "ok": True,
                    "message": "screen " + state,
                    "stdout": p.stdout,
                    "stderr": p.stderr,
                }
            )
        except Exception as e:
            respond({"ok": False, "error": "exception: " + str(e)})

    if action == "screen_status":
        # return last persisted state if available
        try:
            if os.path.exists(SCREEN_STATE_PATH):
                with open(SCREEN_STATE_PATH, "r", encoding="utf-8") as sf:
                    j = json.load(sf)
                    respond({"ok": True, "state": j.get("state"), "ts": j.get("ts")})
            else:
                respond({"ok": True, "state": None, "ts": None})
        except Exception as e:
            respond({"ok": False, "error": "read status failed: " + str(e)})
    respond({"ok": False, "error": "unknown action"})


if __name__ == "__main__":
    main()
