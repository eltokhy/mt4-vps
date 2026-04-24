# MT4 on VPS — Dokploy deployment

Three-container stack:

| Service | Role |
|---|---|
| `mt4` | MetaTrader 4 in Wine, accessible via noVNC on `mt4.enginecy.cloud` |
| `news-fetcher` | Hourly cron: pulls ForexFactory high-impact USD/XAU calendar, writes broker-time windows the Guardrail EA reads |
| `watchdog` | Tails Guardrail heartbeat file, pushes Telegram alerts on stale / kill / failure |

## Required environment variables (set in Dokploy)

| Var | Required | Purpose |
|---|---|---|
| `VNC_PASSWORD` | yes | noVNC password for initial MT4 setup |
| `TELEGRAM_BOT_TOKEN` | yes | From @BotFather |
| `TELEGRAM_CHAT_ID` | yes | Your chat with the bot |
| `MT4_INSTALLER_URL` | no | IC Markets MT4 installer (defaults to the broker's public URL) |

## First-run setup

1. Deploy via Dokploy — it clones this repo and builds all three images on the VPS.
2. Navigate to `https://mt4.enginecy.cloud` → noVNC opens in browser.
3. Enter `VNC_PASSWORD`.
4. Inside MT4:
   - Login to your IC Markets demo account.
   - Open Tools → Options → Notifications → paste MetaQuotes ID, enable Push.
   - Tools → Options → Expert Advisors → tick "Allow automated trading" and "Allow DLL imports".
   - Drag `Deep+ Scalper EA V5 Master` onto an XAUUSD **M1** chart → load preset `Deep+ Scalper XAUUSD 2k-demo.set`.
   - Drag `Guardrail` onto a EURUSD chart → confirm inputs (`EquityFloorUSD=1700`, etc.).
5. Confirm Telegram gets `watchdog started` message.

## Updating the Guardrail EA

Edit `mt4/payload/MQL4/Experts/Guardrail.mq4`, commit, push. Dokploy rebuilds. Container restart stages the new `.mq4` into the prefix. Open MetaEditor inside noVNC and press F7 to compile.
