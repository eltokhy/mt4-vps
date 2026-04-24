//+------------------------------------------------------------------+
//| Guardrail.mq4                                                    |
//| Independent safety layer for martingale/grid EAs.                |
//| Runs on its own chart. Monitors account equity, daily realized   |
//| P&L, and grid depth; closes matching trades and (optionally)     |
//| detaches the managed EA's chart when any kill rule trips.        |
//+------------------------------------------------------------------+
#property strict
#property description "Kill-switch for Deep+ Scalper and similar grid/martingale EAs."
#property version   "1.00"

input double  EquityFloorUSD       = 1700.0;    // Hard kill: equity <= this closes all
input double  WarningEquityUSD     = 1850.0;    // Push alert threshold (no action)
input double  DailyLossLimitUSD    = 200.0;     // Realized daily loss kill ($)
input int     MaxOpenPositions     = 8;         // Kill if matching open positions >= this
input int     MagicFilter          = 217;       // Only manage this magic (Deep+ Scalper default). 0 = any.
input string  SymbolFilter         = "XAUUSD";  // Only manage this symbol. "" = any.
input bool    EnablePushAlerts     = true;      // SendNotification to mobile MT4
input bool    KillManagedChart     = true;      // Detach the managed EA on kill by closing its chart
input string  ManagedChartSymbol   = "XAUUSD";  // Close charts with this symbol on kill (except self)
input int     HeartbeatSeconds     = 10;        // State-file write interval
input string  StateFileName        = "guardrail_state.txt";
input string  EventLogName         = "guardrail_events.log";
input bool    AcknowledgeKill      = false;     // Flip true + refresh inputs to clear kill mode

bool     kill_mode        = false;
string   kill_reason      = "";
datetime kill_time        = 0;
datetime last_heartbeat   = 0;
datetime last_warn_ts     = 0;
double   day_start_balance = 0;
int      day_start_day    = 0;
int      rogue_trade_closes = 0;

int OnInit() {
    if (GlobalVariableCheck("GUARD_KILL_ACTIVE") && GlobalVariableGet("GUARD_KILL_ACTIVE") > 0 && !AcknowledgeKill) {
        kill_mode = true;
        kill_reason = "resumed-from-globals";
    }
    if (AcknowledgeKill) {
        kill_mode = false;
        GlobalVariableSet("GUARD_KILL_ACTIVE", 0);
        LogEvent("ACK: kill mode cleared by operator");
    }
    day_start_balance = AccountBalance();
    day_start_day     = TimeDay(TimeCurrent());
    LogEvent(StringFormat(
        "INIT equity=%.2f balance=%.2f floor=%.2f warn=%.2f dailyCap=%.2f maxPos=%d magic=%d symbol=%s",
        AccountEquity(), AccountBalance(), EquityFloorUSD, WarningEquityUSD, DailyLossLimitUSD,
        MaxOpenPositions, MagicFilter, SymbolFilter));
    EventSetTimer(1);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    EventKillTimer();
    LogEvent(StringFormat("DEINIT reason=%d kill_mode=%s", reason, kill_mode ? "true" : "false"));
}

void OnTick()   { Evaluate(); }
void OnTimer()  { Evaluate(); }   // Runs even on symbols with no ticks over weekends

void Evaluate() {
    int today = TimeDay(TimeCurrent());
    if (today != day_start_day) {
        day_start_balance = AccountBalance();
        day_start_day = today;
        LogEvent(StringFormat("DAY_RESET baseline_balance=%.2f", day_start_balance));
    }

    double eq      = AccountEquity();
    double bal     = AccountBalance();
    double day_pnl = bal - day_start_balance;
    int    open_n  = CountMatchingPositions();

    if (!kill_mode) {
        string why = "";
        if      (eq <= EquityFloorUSD)           why = StringFormat("EQUITY_FLOOR eq=%.2f<=%.2f", eq, EquityFloorUSD);
        else if (day_pnl <= -DailyLossLimitUSD)  why = StringFormat("DAILY_LOSS pnl=%.2f<=-%.2f", day_pnl, DailyLossLimitUSD);
        else if (open_n >= MaxOpenPositions)     why = StringFormat("GRID_DEPTH open=%d>=%d", open_n, MaxOpenPositions);
        if (why != "") TripKill(why);
    }

    if (!kill_mode && eq <= WarningEquityUSD && TimeCurrent() - last_warn_ts > 600) {
        string m = StringFormat("GUARD WARN: equity %.2f < %.2f", eq, WarningEquityUSD);
        Alert(m);
        if (EnablePushAlerts) SendNotification(m);
        last_warn_ts = TimeCurrent();
    }

    if (kill_mode) CloseAllMatching();

    if (TimeCurrent() - last_heartbeat >= HeartbeatSeconds) {
        WriteStateFile(eq, bal, day_pnl, open_n);
        last_heartbeat = TimeCurrent();
    }
}

int CountMatchingPositions() {
    int n = 0;
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
        if (MagicFilter  != 0  && OrderMagicNumber() != MagicFilter) continue;
        if (SymbolFilter != "" && OrderSymbol() != SymbolFilter) continue;
        int t = OrderType();
        if (t == OP_BUY || t == OP_SELL) n++;
    }
    return n;
}

void CloseAllMatching() {
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
        if (MagicFilter  != 0  && OrderMagicNumber() != MagicFilter) continue;
        if (SymbolFilter != "" && OrderSymbol() != SymbolFilter) continue;

        int type = OrderType();
        int ticket = OrderTicket();
        string sym = OrderSymbol();

        if (type == OP_BUY || type == OP_SELL) {
            double price = (type == OP_BUY) ? MarketInfo(sym, MODE_BID) : MarketInfo(sym, MODE_ASK);
            if (OrderClose(ticket, OrderLots(), price, 20, clrRed)) {
                rogue_trade_closes++;
                LogEvent(StringFormat("KILL_CLOSE ticket=%d sym=%s type=%d lots=%.2f",
                                      ticket, sym, type, OrderLots()));
            } else {
                LogEvent(StringFormat("KILL_CLOSE_FAIL ticket=%d err=%d", ticket, GetLastError()));
            }
        } else {
            if (OrderDelete(ticket)) LogEvent(StringFormat("KILL_DELETE ticket=%d sym=%s", ticket, sym));
        }
    }
}

void TripKill(string reason) {
    kill_mode   = true;
    kill_reason = reason;
    kill_time   = TimeCurrent();
    GlobalVariableSet("GUARD_KILL_ACTIVE", 1);
    GlobalVariableSet("GUARD_KILL_TIME",   (double)kill_time);

    string m = "GUARD KILL: " + reason;
    LogEvent("KILL_TRIGGER " + reason);
    Alert(m);
    if (EnablePushAlerts) SendNotification(m);

    CloseAllMatching();

    if (KillManagedChart) {
        long cid = ChartFirst();
        while (cid >= 0) {
            long next = ChartNext(cid);
            if (cid != ChartID() && ChartSymbol(cid) == ManagedChartSymbol) {
                LogEvent(StringFormat("KILL_CHART_CLOSE chart_id=%d symbol=%s", cid, ChartSymbol(cid)));
                ChartClose(cid);
            }
            cid = next;
        }
    }
}

void WriteStateFile(double eq, double bal, double day_pnl, int open_n) {
    int h = FileOpen(StateFileName, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if (h == INVALID_HANDLE) return;
    FileWriteString(h, StringFormat(
        "{\"ts\":\"%s\",\"equity\":%.2f,\"balance\":%.2f,\"day_pnl\":%.2f,\"open\":%d,\"kill\":%s,\"reason\":\"%s\",\"rogue_closes\":%d,\"floor\":%.2f,\"daily_cap\":%.2f,\"max_pos\":%d}\n",
        TimeToStr(TimeCurrent(), TIME_DATE | TIME_SECONDS),
        eq, bal, day_pnl, open_n,
        kill_mode ? "true" : "false", kill_reason, rogue_trade_closes,
        EquityFloorUSD, DailyLossLimitUSD, MaxOpenPositions));
    FileClose(h);
}

void LogEvent(string msg) {
    int h = FileOpen(EventLogName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
    if (h == INVALID_HANDLE) return;
    FileSeek(h, 0, SEEK_END);
    FileWriteString(h, TimeToStr(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " | " + msg + "\n");
    FileClose(h);
    Print("GUARD: ", msg);
}
