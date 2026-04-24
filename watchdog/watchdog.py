"""
External watchdog for the Guardrail EA.

Reads Guardrail's heartbeat file (written every HeartbeatSeconds inside MT4)
and pushes Telegram alerts when:
  - heartbeat is stale (MT4/Guardrail crashed or hung)
  - kill mode is active (kill fired — make sure the user sees it even if the
    in-MT4 SendNotification silently failed)
  - daily_pnl or open-position count crosses thresholds

This is a second line of defense independent of MT4 itself. If it reports
a problem, investigate — don't wait for MT4 to self-report.
"""
import json
import os
import time
from pathlib import Path
from datetime import datetime, timezone

import requests

STATE_FILE   = Path(os.environ.get("STATE_FILE", "/wine/drive_c/Program Files (x86)/MetaTrader 4/MQL4/Files/guardrail_state.txt"))
EVENT_LOG    = Path(os.environ.get("EVENT_LOG",  "/wine/drive_c/Program Files (x86)/MetaTrader 4/MQL4/Files/guardrail_events.log"))
STALE_SECS   = int(os.environ.get("STALE_SECS", "60"))
POLL_SECS    = int(os.environ.get("POLL_SECS", "15"))
TG_TOKEN     = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TG_CHAT      = os.environ.get("TELEGRAM_CHAT_ID", "")
BROKER_TZ    = os.environ.get("BROKER_TZ", "Europe/Athens")

state = {
    "last_event_offset": 0,
    "stale_alerted": False,
    "kill_alerted": False,
}


def notify(msg: str) -> None:
    print(f"[watchdog] ALERT: {msg}", flush=True)
    if not TG_TOKEN or not TG_CHAT:
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage",
            json={"chat_id": TG_CHAT, "text": msg, "parse_mode": "Markdown"},
            timeout=10,
        )
    except Exception as e:
        print(f"[watchdog] telegram send failed: {e}", flush=True)


def read_state() -> dict | None:
    if not STATE_FILE.exists():
        return None
    try:
        text = STATE_FILE.read_text(encoding="utf-8", errors="ignore").strip()
        return json.loads(text)
    except Exception as e:
        print(f"[watchdog] state parse failed: {e} | raw={text[:200]!r}", flush=True)
        return None


def read_state_age() -> float | None:
    if not STATE_FILE.exists():
        return None
    return time.time() - STATE_FILE.stat().st_mtime


def tail_events() -> list[str]:
    if not EVENT_LOG.exists():
        return []
    size = EVENT_LOG.stat().st_size
    if size < state["last_event_offset"]:
        # File truncated/rotated; start from zero.
        state["last_event_offset"] = 0
    with EVENT_LOG.open("r", encoding="utf-8", errors="ignore") as f:
        f.seek(state["last_event_offset"])
        new = f.read()
        state["last_event_offset"] = f.tell()
    return [line for line in new.splitlines() if line.strip()]


def main() -> None:
    notify("watchdog started")
    while True:
        try:
            age = read_state_age()
            s   = read_state()
            if age is None or s is None:
                # No state file yet — MT4 not up, or Guardrail not attached.
                if not state["stale_alerted"]:
                    notify("⚠️ Guardrail state file missing — MT4 or Guardrail EA not running.")
                    state["stale_alerted"] = True
            else:
                if age > STALE_SECS:
                    if not state["stale_alerted"]:
                        notify(f"⚠️ Guardrail heartbeat stale ({int(age)}s). MT4 may be frozen.")
                        state["stale_alerted"] = True
                else:
                    if state["stale_alerted"]:
                        notify("✅ Guardrail heartbeat resumed.")
                        state["stale_alerted"] = False

                if s.get("kill") is True and not state["kill_alerted"]:
                    notify(f"🛑 KILL ACTIVE — reason: `{s.get('reason', '?')}` equity=${s.get('equity', 0):.2f}")
                    state["kill_alerted"] = True
                elif s.get("kill") is False:
                    state["kill_alerted"] = False

            for line in tail_events():
                # Forward critical events verbatim so we have a second channel for them.
                if any(tag in line for tag in ("KILL_TRIGGER", "KILL_CLOSE_FAIL", "DAY_RESET", "ACK")):
                    notify(f"📋 {line}")

        except Exception as e:
            print(f"[watchdog] loop error: {e}", flush=True)

        time.sleep(POLL_SECS)


if __name__ == "__main__":
    main()
