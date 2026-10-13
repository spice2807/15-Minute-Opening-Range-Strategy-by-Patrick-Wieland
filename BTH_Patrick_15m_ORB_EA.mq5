//+------------------------------------------------------------------+
//|                                       BTH_Patrick_15m_ORB_EA.mq5 |
//|                                              Backtest the Hype   |
//|                                                                  |
//|  Patrick Wieland - "Simple Day Trading Strategy for Market Open! |
//|  15 MINUTE RANGE!" - coded by Backtest the Hype.                 |
//|  Same rules as the TradingView visualizer v2.2                   |
//|  (BTH_Patrick_15m_ORB.pine). This EA gives the final numbers.    |
//|                                                                  |
//|  Attach to NAS100 or US500. All logic runs on M1 data            |
//|  internally. Strategy Tester: M1, "Every tick based on real      |
//|  ticks".                                                         |
//|                                                                  |
//|  HIS RULES                                                       |
//|   1. Opening range = first 15-minute candle, 9:30-9:45 New York. |
//|   2. Nothing to do inside the range.                             |
//|   3. Break above -> longs only. Break below -> shorts only.      |
//|   4. Enter in the break direction on the lower timeframe.        |
//|   5. Stop = the extreme of the candle you enter on.              |
//|   6. No fixed target: trail the stop to each new higher low      |
//|      (longs) / lower high (shorts).                              |
//|   7. If numbers come out at 9:45 / 10:00, wait for them.         |
//|                                                                  |
//|  OUR DEFINITIONS (identical to the Pine header, all inputs)      |
//|   - Break = a candle CLOSES beyond the range (1m default).       |
//|   - Entry = a FRESH break: previous candle closed inside, this   |
//|     one closes outside. Market order on the next tick (= the     |
//|     next candle's open) at the real bid/ask.                     |
//|   - Stop = breakout candle's opposite extreme (no buffer).       |
//|   - Trail = confirmed swing, 2 bars each side, strictly lower /  |
//|     higher than all of them (ties don't count). A swing is known |
//|     when its last bar closes, so the stop moves from the next    |
//|     candle. The stop only moves in the trade's favour.           |
//|   - Direction locked by the first break after the range closes.  |
//|   - Entries 9:45-12:00 NY. Everything closed by 15:55 NY.        |
//|   - One trade at a time, max trades per day = input (1).         |
//|     Re-entry needs a close back inside the range first.          |
//|   - News: the MT5 calendar does not work in the Strategy Tester, |
//|     so "wait for 10:00 numbers" = set Earliest entry to 1000.    |
//|   - Costs: real spread + your broker's commission + swap.        |
//|   - 1R = the money lost if the first stop is hit (from the real  |
//|     fill and the real lot size). |R| < 0.01 = break-even.        |
//+------------------------------------------------------------------+
#property copyright "Backtest the Hype"
#property version   "1.00"
#property description "Patrick Wieland 15-minute opening range breakout: first-break direction, breakout-candle stop, swing trailing stop. Coded by Backtest the Hype."

#include <Trade/Trade.mqh>

//--- enums (the comment after each value is what the inputs window shows)
enum ENUM_CONFIRM
  {
   CONF_1  = 1,  // 1-minute candle close
   CONF_5  = 5,  // 5-minute candle close
   CONF_15 = 15  // 15-minute candle close
  };
enum ENUM_DIRMODE
  {
   DIR_LOCKED = 0, // Locked by the first break
   DIR_EITHER = 1  // Either side (each break)
  };
enum ENUM_DIRFROM
  {
   FROM_RANGE = 0, // First break after the range
   FROM_ENTRY = 1  // First break after earliest entry
  };
enum ENUM_FRESH
  {
   FRESH_ONLY = 0, // Fresh break only
   FRESH_ANY  = 1  // Any close beyond the range
  };
enum ENUM_STOPMODE
  {
   STOP_CANDLE = 0, // Breakout candle extreme (his)
   STOP_RANGE  = 1, // Other side of the range
   STOP_MID    = 2  // Range midpoint
  };
enum ENUM_EXITMODE
  {
   EXIT_TRAIL    = 0, // Trail swings (his)
   EXIT_RR       = 1, // Fixed R:R
   EXIT_TRAILCAP = 2  // Trail + R:R cap
  };

enum ENUM_VARIANT
  {
   VAR_INPUTS = 0, // Use the settings below
   VAR_1      = 1, // V1 His rules (trail, candle stop, 1m, 9:45)
   VAR_2      = 2, // V2 Fixed 2R
   VAR_3      = 3, // V3 Fixed 3R
   VAR_4      = 4, // V4 Trail + 2R cap
   VAR_5      = 5, // V5 Classic ORB stop (other side of range)
   VAR_6      = 6, // V6 5-minute confirmation
   VAR_7      = 7  // V7 Wait for 10:00 news
  };

//--- inputs
input group "Test version (optimise this 1-7 to run every version in one go)"
input ENUM_VARIANT   InpVariant       = VAR_INPUTS;   // Test version
input group "Session - New York time (HHMM)"
input int            InpServerMinusNY = 7;            // Server time minus New York time (hours). Most brokers = 7
input int            InpOpen          = 930;          // Session open
input int            InpORMinutes     = 15;           // Opening range length (minutes)
input int            InpStart         = 945;          // Earliest entry (1000 = wait for 10:00 news)
input int            InpLast          = 1200;         // Last entry
input int            InpFlat          = 1555;         // Close every trade by
input group "Entry"
input ENUM_CONFIRM   InpConfirm       = CONF_1;       // Break confirmed by
input ENUM_DIRMODE   InpDirMode       = DIR_LOCKED;   // Direction for the day
input ENUM_DIRFROM   InpDirFrom       = FROM_RANGE;   // First break counted from
input ENUM_FRESH     InpFresh         = FRESH_ONLY;   // Entry candle
input int            InpMaxTrades     = 1;            // Max trades per day
input group "Stop & exit"
input ENUM_STOPMODE  InpStop          = STOP_CANDLE;  // Stop
input ENUM_EXITMODE  InpExit          = EXIT_TRAIL;   // Exit style
input double         InpRR            = 2.0;          // R:R target (Fixed / cap)
input int            InpPivLen        = 2;            // Swing size for trailing (bars each side)
input group "Risk"
input double         InpRiskUSD       = 1000.0;       // Risk per trade (account currency) = 1R
input group "Visuals & log"
input bool           InpDraw          = true;         // Draw range, trades and results panel
input bool           InpLogCSV        = true;         // Write every trade to a CSV (Common\Files)
input group "Misc"
input ulong          InpMagic         = 26101101;     // Magic number
input int            InpWarmupDays    = 3;            // Warm-up history (days)

//+------------------------------------------------------------------+
//| Data                                                             |
//+------------------------------------------------------------------+
struct SBar
  {
   datetime          t;
   double            o, h, l, c;
  };

CTrade   g_trade;
//--- effective settings (inputs, or the chosen test version)
ENUM_EXITMODE g_exit;
ENUM_STOPMODE g_stop;
ENUM_CONFIRM  g_conf;
int           g_start;
double        g_rr;
bool     g_draw = false;
datetime g_lastProc = 0;
bool     g_warm = false;
int      g_openM, g_orEndM, g_startM, g_lastM, g_flatM, g_detM;
string   g_csv = "";

//--- day state
int      g_dayKey = -1;
double   g_orH = 0, g_orL = 0;
bool     g_orDone = false;
datetime g_orT0 = 0;
int      g_dayDir = 0;          // 0 none, 1 longs only, -1 shorts only
int      g_tradesToday = 0;
bool     g_needReset = false;
double   g_bH = 0, g_bL = 0;    // running high/low of the confirmation candle
bool     g_bInit = false;
double   g_prevBC = 0;          // close of the previous confirmation candle
bool     g_hasPrevBC = false;
SBar     g_win[];               // last 2*pivLen+1 M1 bars (swings)

//--- open trade
ulong    g_ticket = 0;
int      g_dir = 0;
double   g_ent = 0, g_stp = 0, g_stop0 = 0, g_tgt = 0, g_riskPts = 0, g_riskMoney = 0, g_lots = 0, g_best = 0;
datetime g_sigT = 0, g_entT = 0, g_segT = 0;
int      g_entDay = 0, g_trailMoves = 0, g_tradeId = 0;

//--- results
int      s_days = 0, s_breakDays = 0, s_T = 0, s_W = 0, s_BE = 0, s_consec = 0, s_maxConsec = 0, s_skipped = 0;
double   s_sumR = 0, s_gW = 0, s_gL = 0, s_pts = 0, s_eq = 0, s_peak = 0, s_dd = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int HHMM(const int v) { return (v / 100) * 60 + v % 100; }

datetime ToNY(const datetime serverT) { return serverT - (datetime)(InpServerMinusNY * 3600); }

int NYMin(const datetime serverT)
  {
   MqlDateTime d;
   TimeToStruct(ToNY(serverT), d);
   return d.hour * 60 + d.min;
  }

int NYDay(const datetime serverT)
  {
   MqlDateTime d;
   TimeToStruct(ToNY(serverT), d);
   return d.year * 10000 + d.mon * 100 + d.day;
  }

string NYStr(const datetime serverT) { return TimeToString(ToNY(serverT), TIME_DATE | TIME_MINUTES); }

double NormLots(double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < mn) return 0;
   if(lots > mx) lots = mx;
   return NormalizeDouble(lots, 8);
  }

double MoneyPerLot(const double dist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0) return 0;
   return dist / ts * tv;
  }

bool FindOurPosition(ulong &ticket)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
        { ticket = tk; return true; }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Drawing (same look as the TradingView version)                   |
//+------------------------------------------------------------------+
#define PFX "BTH_ORB_"
color C_GREEN  = C'0,229,97';
color C_RED    = C'255,77,94';
color C_GREY   = C'126,145,138';
color C_WHITE  = C'238,244,240';
color C_AMBER  = C'245,185,66';
color C_PANEL  = C'11,20,16';
color C_RISK   = C'92,36,44';
color C_REWARD = C'20,84,48';
color C_RANGE  = C'44,52,50';

void DrawLine(const string name, datetime t1, double p1, datetime t2, double p2, color c, int width, ENUM_LINE_STYLE st)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

void DrawBox(const string name, datetime t1, double p1, datetime t2, double p2, color c)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void DrawText(const string name, datetime t, double p, const string txt, color c, ENUM_ANCHOR_POINT anchor, int size = 8)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void PanelLabel(const string name, int x, int y, const string txt, color c, ENUM_ANCHOR_POINT anchor, int size)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

string ConfirmTxt() { return g_conf == CONF_1 ? "1m close" : g_conf == CONF_5 ? "5m close" : "15m close"; }

void ShowPanel()
  {
   if(!g_draw) return;
   const int W = 380, rowH = 18, rows = 15;
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int x0 = MathMax(10, chartW - W - 70);
   int y0 = 24;
   string bg = PFX + "pnl_bg";
   if(ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x0);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y0);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, rows * rowH + 12);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C_PANEL);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'52,66,60');
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);

   double wr = s_T > 0 ? 100.0 * s_W / s_T : 0.0;
   string pf = s_gL > 0 ? DoubleToString(s_gW / s_gL, 2) : "-";
   string dirTxt = InpDirMode == DIR_LOCKED ? (InpDirFrom == FROM_RANGE ? "locked at range" : "locked at entry time") : "either";
   string stopTxt = g_stop == STOP_CANDLE ? "candle" : g_stop == STOP_RANGE ? "range side" : "midpoint";
   string exitTxt = g_exit == EXIT_TRAIL ? "trail" : g_exit == EXIT_RR ? DoubleToString(g_rr, 2) + "R" : "trail+" + DoubleToString(g_rr, 2) + "R";

   string L[15], V[15];
   color  LC[15], VC[15];
   L[0]  = "BTH | Patrick 15m ORB | EA" + (InpVariant == VAR_INPUTS ? "" : " | V" + IntegerToString((int)InpVariant));  V[0]  = _Symbol + " | M1 data";                                              LC[0] = C_GREEN; VC[0] = C_GREEN;
   L[1]  = "Break by | direction";       V[1]  = ConfirmTxt() + (InpFresh == FRESH_ONLY ? " | fresh | " : " | any | ") + dirTxt; LC[1] = C_WHITE; VC[1] = C_AMBER;
   L[2]  = "Stop | exit";                V[2]  = stopTxt + " | " + exitTxt;                                            LC[2] = C_WHITE; VC[2] = C_AMBER;
   L[3]  = "TESTED HISTORY";             V[3]  = IntegerToString(s_days) + " days";                                    LC[3] = C_GREEN; VC[3] = C_WHITE;
   L[4]  = "Days the range broke";       V[4]  = IntegerToString(s_breakDays);                                         LC[4] = C_WHITE; VC[4] = C_WHITE;
   L[5]  = "Trades";                     V[5]  = IntegerToString(s_T) + (s_BE > 0 ? "  (" + IntegerToString(s_BE) + " break-even)" : ""); LC[5] = C_WHITE; VC[5] = C_WHITE;
   L[6]  = "Win rate";                   V[6]  = DoubleToString(wr, 1) + "%";                                          LC[6] = C_WHITE; VC[6] = C_WHITE;
   L[7]  = "Total (R)";                  V[7]  = DoubleToString(s_sumR, 2) + "R";                                      LC[7] = C_WHITE; VC[7] = s_sumR >= 0 ? C_GREEN : C_RED;
   L[8]  = "Average per trade";          V[8]  = s_T > 0 ? DoubleToString(s_sumR / s_T, 3) + "R" : "-";                LC[8] = C_WHITE; VC[8] = C_WHITE;
   L[9]  = "Profit factor";              V[9]  = pf;                                                                   LC[9] = C_WHITE; VC[9] = C_WHITE;
   L[10] = "Total points";               V[10] = DoubleToString(s_pts, 1);                                             LC[10] = C_WHITE; VC[10] = s_pts >= 0 ? C_GREEN : C_RED;
   L[11] = "Max drawdown (R)";           V[11] = DoubleToString(s_dd, 2) + "R";                                        LC[11] = C_WHITE; VC[11] = C_WHITE;
   L[12] = "Worst losing streak";        V[12] = IntegerToString(s_maxConsec);                                         LC[12] = C_WHITE; VC[12] = C_WHITE;
   L[13] = "Fills | costs";              V[13] = "real bid/ask | spread + commission";                                 LC[13] = C_GREY;  VC[13] = C_GREY;
   L[14] = "Risk per trade (1R)";        V[14] = DoubleToString(InpRiskUSD, 0) + " " + AccountInfoString(ACCOUNT_CURRENCY) + (s_skipped > 0 ? " | skipped " + IntegerToString(s_skipped) : ""); LC[14] = C_GREY; VC[14] = C_GREY;

   for(int i = 0; i < rows; i++)
     {
      int y = y0 + 7 + i * rowH;
      int sz = i >= 13 ? 8 : 9;
      PanelLabel(PFX + "pnl_l" + IntegerToString(i), x0 + 10, y, L[i], LC[i], ANCHOR_LEFT_UPPER, sz);
      PanelLabel(PFX + "pnl_v" + IntegerToString(i), x0 + W - 10, y, V[i], VC[i], ANCHOR_RIGHT_UPPER, sz);
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| CSV log                                                          |
//+------------------------------------------------------------------+
void CsvInit()
  {
   if(!InpLogCSV) return;
   // one file per variant, e.g. BTH_ORB_NAS100_trail_candle_1m_0945.csv
   string ex = g_exit == EXIT_TRAIL ? "trail" : g_exit == EXIT_RR ? "rr" + DoubleToString(g_rr, 1) : "trailcap" + DoubleToString(g_rr, 1);
   string st = g_stop == STOP_CANDLE ? "candle" : g_stop == STOP_RANGE ? "range" : "mid";
   string cf = IntegerToString((int)g_conf) + "m";
   string tm = StringFormat("%04d", g_start);
   string vn = InpVariant == VAR_INPUTS ? "" : "V" + IntegerToString((int)InpVariant) + "_";
   g_csv = "BTH_ORB_" + vn + _Symbol + "_" + ex + "_" + st + "_" + cf + "_" + tm + ".csv";
   int h = FileOpen(g_csv, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(h == INVALID_HANDLE) { Print("ORB: could not create ", g_csv); g_csv = ""; return; }
   FileWrite(h, "trade", "date_ny", "side", "signal_ny", "entry_ny", "entry", "first_stop", "risk_pts", "lots", "exit_ny", "exit", "reason", "trail_moves", "points", "profit", "R", "best_R");
   FileClose(h);
  }

void CsvRow(const datetime exitT, const double exitPx, const string why, const double pts, const double profit, const double r, const double bestR)
  {
   if(g_csv == "") return;
   int h = FileOpen(g_csv, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, g_tradeId, IntegerToString(g_entDay), g_dir == 1 ? "LONG" : "SHORT", NYStr(g_sigT + 60), NYStr(g_entT),
             DoubleToString(g_ent, _Digits), DoubleToString(g_stop0, _Digits), DoubleToString(g_riskPts, _Digits),
             DoubleToString(g_lots, 2), NYStr(exitT), DoubleToString(exitPx, _Digits), why, g_trailMoves,
             DoubleToString(pts, _Digits), DoubleToString(profit, 2), DoubleToString(r, 3), DoubleToString(bestR, 2));
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Orders                                                           |
//+------------------------------------------------------------------+
void OpenTrade(const int dir, const double stop, const datetime sigT)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) { s_skipped++; return; }
   double entry = dir == 1 ? tick.ask : tick.bid;
   // the next price is already through the stop -> no trade (same as the Pine version)
   if((dir == 1 && stop >= entry) || (dir == -1 && stop <= entry)) { s_skipped++; return; }
   double risk = MathAbs(entry - stop);
   double mpl = MoneyPerLot(risk);
   if(mpl <= 0) { s_skipped++; return; }
   double lots = NormLots(InpRiskUSD / mpl);
   if(lots <= 0)
     {
      PrintFormat("ORB: skipped - lot size below the broker minimum (risk %.2f points)", risk);
      s_skipped++;
      return;
     }
   double tp = g_exit == EXIT_TRAIL ? 0 : NormalizeDouble(dir == 1 ? entry + g_rr * risk : entry - g_rr * risk, _Digits);
   double sl = NormalizeDouble(stop, _Digits);
   string cmt = (dir == 1 ? "BTH ORB L" : "BTH ORB S");
   bool ok = dir == 1 ? g_trade.Buy(lots, _Symbol, 0, sl, tp, cmt) : g_trade.Sell(lots, _Symbol, 0, sl, tp, cmt);
   if(!ok || (g_trade.ResultRetcode() != TRADE_RETCODE_DONE && g_trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     {
      PrintFormat("ORB: order failed, retcode %u", g_trade.ResultRetcode());
      s_skipped++;
      return;
     }
   ulong tk = 0;
   if(!FindOurPosition(tk)) { s_skipped++; return; }
   PositionSelectByTicket(tk);

   g_ticket    = tk;
   g_dir       = dir;
   g_ent       = PositionGetDouble(POSITION_PRICE_OPEN);
   g_lots      = PositionGetDouble(POSITION_VOLUME);
   g_stp       = stop;
   g_stop0     = stop;
   g_riskPts   = MathAbs(g_ent - stop);
   g_riskMoney = g_lots * MoneyPerLot(g_riskPts);
   g_best      = g_ent;
   g_sigT      = sigT;
   g_entT      = TimeCurrent();
   g_segT      = g_entT;
   g_entDay    = NYDay(g_entT);
   g_trailMoves = 0;
   g_tradeId++;
   g_tgt = 0;
   if(g_exit != EXIT_TRAIL)
     {
      // target from the REAL fill, so the R:R is exact
      g_tgt = NormalizeDouble(dir == 1 ? g_ent + g_rr * g_riskPts : g_ent - g_rr * g_riskPts, _Digits);
      g_trade.PositionModify(g_ticket, sl, g_tgt);
     }

   if(g_draw)
     {
      string id = IntegerToString(g_tradeId);
      datetime tR = g_entT + 60;
      DrawBox(PFX + "risk_" + id, g_entT, g_ent, tR, stop, C_RISK);
      DrawBox(PFX + "rew_" + id, g_entT, g_ent, tR, g_tgt > 0 ? g_tgt : g_ent, C_REWARD);
      DrawText(PFX + "stopT_" + id, g_entT, stop, "Stop " + DoubleToString(stop, _Digits), C_RED, dir == 1 ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER, 7);
      if(g_tgt > 0)
         DrawText(PFX + "tgtT_" + id, g_entT, g_tgt, "Target " + DoubleToString(g_tgt, _Digits) + "  1:" + DoubleToString(g_rr, 2), C_GREEN, dir == 1 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER, 7);
      DrawText(PFX + "lab_" + id, g_entT, g_ent, dir == 1 ? "LONG" : "SHORT", dir == 1 ? C_GREEN : C_RED, dir == 1 ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER, 9);
      DrawLine(PFX + "stp_" + id + "_0", g_entT, stop, tR, stop, C_RED, 2, STYLE_SOLID);
     }
  }

// stretch the drawing of the open trade to time t
void DrawOpenTrade(const datetime t)
  {
   if(!g_draw || g_ticket == 0) return;
   string id = IntegerToString(g_tradeId);
   datetime tR = (t > g_entT + 60) ? t : g_entT + 60;
   ObjectSetInteger(0, PFX + "risk_" + id, OBJPROP_TIME, 1, tR);
   ObjectSetInteger(0, PFX + "rew_" + id, OBJPROP_TIME, 1, tR);
   if(g_exit == EXIT_TRAIL)
     {
      ObjectSetDouble(0, PFX + "rew_" + id, OBJPROP_PRICE, 1, g_best);
      double ran = g_riskPts > 0 ? MathAbs(g_best - g_ent) / g_riskPts : 0;
      DrawText(PFX + "tgtT_" + id, g_entT, g_best, "Ran +" + DoubleToString(ran, 1) + "R", C_GREEN, g_dir == 1 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER, 7);
     }
   string seg = PFX + "stp_" + id + "_" + IntegerToString(g_trailMoves);
   ObjectSetInteger(0, seg, OBJPROP_TIME, 1, tR);
  }

// every tick: flat time, and detect a closed trade
void ManageTrade()
  {
   if(g_ticket == 0) return;
   if(PositionSelectByTicket(g_ticket))
     {
      datetime now = TimeCurrent();
      if(NYMin(now) >= g_flatM || NYDay(now) != g_entDay)
         g_trade.PositionClose(g_ticket);
      return;
     }

   //--- the trade is closed: read the deals
   double profit = 0, exitPx = 0;
   datetime exitT = TimeCurrent();
   long reason = -1;
   if(HistorySelectByPosition(g_ticket))
     {
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         profit += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP);
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT || HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT_BY)
           {
            exitPx = HistoryDealGetDouble(d, DEAL_PRICE);
            exitT  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            reason = HistoryDealGetInteger(d, DEAL_REASON);
           }
        }
     }
   if(exitPx <= 0) exitPx = g_dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   string why = reason == DEAL_REASON_SL ? (g_trailMoves > 0 ? "trail stop" : "stop") : reason == DEAL_REASON_TP ? "target" : "close 15:55";
   double pts = g_dir == 1 ? exitPx - g_ent : g_ent - exitPx;
   double r = g_riskMoney > 0 ? profit / g_riskMoney : 0;
   if(g_dir == 1) g_best = MathMax(g_best, MathMax(exitPx, g_ent));
   else           g_best = MathMin(g_best, MathMin(exitPx, g_ent));
   double bestR = g_riskPts > 0 ? MathAbs(g_best - g_ent) / g_riskPts : 0;

   //--- results (same counting as the Pine panel)
   s_T++;
   s_sumR += r;
   s_pts  += pts;
   s_eq   += r;
   s_peak  = MathMax(s_peak, s_eq);
   s_dd    = MathMax(s_dd, s_peak - s_eq);
   bool isBE = MathAbs(r) < 0.01;
   if(isBE) s_BE++;
   else
      if(r > 0) { s_W++; s_gW += r; s_consec = 0; }
      else      { s_gL += -r; s_consec++; s_maxConsec = MathMax(s_maxConsec, s_consec); }

   CsvRow(exitT, exitPx, why, pts, profit, r, bestR);

   if(g_draw)
     {
      DrawOpenTrade(exitT);
      string id = IntegerToString(g_tradeId);
      color c = isBE ? C_GREY : r > 0 ? C_GREEN : C_RED;
      DrawLine(PFX + "path_" + id, g_entT, g_ent, exitT, exitPx, c, 1, STYLE_DOT);
      DrawText(PFX + "res_" + id, exitT, exitPx, (r >= 0 ? "+" : "") + DoubleToString(r, 2) + "R", c, ANCHOR_LEFT, 9);
     }
   g_ticket = 0;
   g_dir = 0;
   g_needReset = true;   // a re-entry needs a close back inside the range
   ShowPanel();
  }

//+------------------------------------------------------------------+
//| One closed M1 bar - same order of operations as the Pine script  |
//+------------------------------------------------------------------+
void ProcessBar(const SBar &b, const bool live)
  {
   int mOpen  = NYMin(b.t);
   int mClose = mOpen + 1;
   int key    = NYDay(b.t);

   //--- new day
   if(key != g_dayKey)
     {
      g_dayKey = key;
      g_orH = 0; g_orL = 0; g_orDone = false; g_orT0 = 0;
      g_dayDir = 0; g_tradesToday = 0; g_needReset = false;
      g_hasPrevBC = false;
      if(g_warm) s_days++;
     }

   //--- opening range
   bool inOR = mOpen >= g_openM && mOpen < g_orEndM;
   if(inOR)
     {
      g_orH = (g_orH == 0) ? b.h : MathMax(g_orH, b.h);
      g_orL = (g_orL == 0) ? b.l : MathMin(g_orL, b.l);
      if(g_orT0 == 0) g_orT0 = b.t;
     }
   if(!g_orDone && g_orH > 0 && mOpen >= g_orEndM) g_orDone = true;
   if(g_draw && g_orT0 > 0 && (inOR || (g_orDone && mOpen < g_flatM)))
     {
      string d = IntegerToString(key);
      DrawBox(PFX + "or_" + d, g_orT0, g_orH, b.t + 60, g_orL, C_RANGE);
      if(g_orDone)
        {
         DrawLine(PFX + "orH_" + d, g_orT0, g_orH, b.t + 60, g_orH, C'0,150,70', 1, STYLE_SOLID);
         DrawLine(PFX + "orL_" + d, g_orT0, g_orL, b.t + 60, g_orL, C'190,60,72', 1, STYLE_SOLID);
        }
     }

   //--- running high/low of the confirmation candle (1 / 5 / 15 minutes, New York clock)
   int N = (int)g_conf;
   bool blockStart = mOpen % N == 0;
   bool blockEnd   = mClose % N == 0;
   if(blockStart || !g_bInit) { g_bH = b.h; g_bL = b.l; g_bInit = true; }
   else { g_bH = MathMax(g_bH, b.h); g_bL = MathMin(g_bL, b.l); }

   //--- swing window
   int W = 2 * InpPivLen + 1;
   int n = ArraySize(g_win);
   if(n < W) { ArrayResize(g_win, n + 1); g_win[n] = b; }
   else { for(int i = 0; i < W - 1; i++) g_win[i] = g_win[i + 1]; g_win[W - 1] = b; }

   //--- manage the open trade: best price, then trail (the new stop is live from the next candle)
   if(g_ticket != 0 && PositionSelectByTicket(g_ticket))
     {
      if(b.t > g_sigT)
         g_best = g_dir == 1 ? MathMax(g_best, b.h) : MathMin(g_best, b.l);
      bool trail = g_exit != EXIT_RR;
      if(trail && ArraySize(g_win) == W)
        {
         SBar mid = g_win[InpPivLen];
         bool isLow = true, isHigh = true;
         for(int i = 0; i < W; i++)
           {
            if(i == InpPivLen) continue;
            if(g_win[i].l <= mid.l) isLow = false;
            if(g_win[i].h >= mid.h) isHigh = false;
           }
         double newStp = 0;
         // the swing must have formed after the breakout candle
         if(mid.t > g_sigT)
           {
            if(g_dir == 1 && isLow && mid.l > g_stp && mid.l < b.c) newStp = mid.l;
            if(g_dir == -1 && isHigh && mid.h < g_stp && mid.h > b.c) newStp = mid.h;
           }
         if(newStp > 0 && live)
           {
            double sl = NormalizeDouble(newStp, _Digits);
            if(g_trade.PositionModify(g_ticket, sl, PositionGetDouble(POSITION_TP)))
              {
               if(g_draw)
                 {
                  string id = IntegerToString(g_tradeId);
                  DrawOpenTrade(b.t + 60);
                  datetime tNow = b.t + 60;
                  DrawLine(PFX + "stpv_" + id + "_" + IntegerToString(g_trailMoves), tNow, g_stp, tNow, newStp, C'150,60,70', 1, STYLE_DOT);
                  DrawLine(PFX + "stp_" + id + "_" + IntegerToString(g_trailMoves + 1), tNow, newStp, tNow + 60, newStp, C_RED, 2, STYLE_SOLID);
                 }
               g_stp = newStp;
               g_trailMoves++;
              }
           }
        }
      DrawOpenTrade(b.t + 60);
     }

   //--- breaks & entries
   bool posOpen = g_ticket != 0;
   bool inside = g_orDone && b.c <= g_orH && b.c >= g_orL;
   if(g_needReset && inside) g_needReset = false;

   bool canEnter = g_orDone && !posOpen && blockEnd && mClose >= g_startM && mClose <= g_lastM && g_tradesToday < InpMaxTrades && !g_needReset;
   bool up = g_orDone && blockEnd && b.c > g_orH;
   bool dn = g_orDone && blockEnd && b.c < g_orL;
   bool firstBreak = g_dayDir == 0 && (up || dn) && mClose >= g_detM;
   if(firstBreak && g_warm) s_breakDays++;
   bool wasInside = g_hasPrevBC && g_prevBC <= g_orH && g_prevBC >= g_orL;
   bool freshOK = InpFresh == FRESH_ANY || wasInside;
   int sig = 0;
   if(canEnter && freshOK && up && (g_dayDir == 0 || g_dayDir == 1 || InpDirMode == DIR_EITHER)) sig = 1;
   if(canEnter && freshOK && dn && (g_dayDir == 0 || g_dayDir == -1 || InpDirMode == DIR_EITHER)) sig = -1;
   if(firstBreak) g_dayDir = up ? 1 : -1;
   if(blockEnd && (inOR || g_orDone)) { g_prevBC = b.c; g_hasPrevBC = true; }

   if(sig != 0)
     {
      double s = g_stop == STOP_RANGE ? (sig == 1 ? g_orL : g_orH) : g_stop == STOP_MID ? (g_orH + g_orL) / 2.0 : (sig == 1 ? g_bL : g_bH);
      g_tradesToday++;
      // signal on this candle's close -> market order now, on the next candle's first tick
      if(live) OpenTrade(sig, s, b.t);
     }
  }

//+------------------------------------------------------------------+
//| Expert events                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_exit = InpExit; g_stop = InpStop; g_conf = InpConfirm; g_start = InpStart; g_rr = InpRR;
   if(InpVariant != VAR_INPUTS)
     {
      // every version starts from his rules and changes ONE thing
      g_exit = EXIT_TRAIL; g_stop = STOP_CANDLE; g_conf = CONF_1; g_start = 945; g_rr = 2.0;
      if(InpVariant == VAR_2) { g_exit = EXIT_RR; g_rr = 2.0; }
      if(InpVariant == VAR_3) { g_exit = EXIT_RR; g_rr = 3.0; }
      if(InpVariant == VAR_4) { g_exit = EXIT_TRAILCAP; g_rr = 2.0; }
      if(InpVariant == VAR_5) g_stop = STOP_RANGE;
      if(InpVariant == VAR_6) g_conf = CONF_5;
      if(InpVariant == VAR_7) g_start = 1000;
     }
   g_openM  = HHMM(InpOpen);
   g_orEndM = g_openM + InpORMinutes;
   g_startM = MathMax(HHMM(g_start), g_orEndM);
   g_lastM  = HHMM(InpLast);
   g_flatM  = HHMM(InpFlat);
   g_detM   = InpDirFrom == FROM_RANGE ? g_orEndM : g_startM;
   if(InpPivLen < 1 || InpORMinutes < 1 || InpMaxTrades < 1 || InpRiskUSD <= 0)
     { Print("ORB: check the inputs (swing size, range length, max trades, risk must be positive)"); return INIT_PARAMETERS_INCORRECT; }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(50);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   bool tester = (bool)MQLInfoInteger(MQL_TESTER);
   g_draw = InpDraw && (!tester || (bool)MQLInfoInteger(MQL_VISUAL_MODE));
   g_lastProc = 0;
   g_warm = false;
   ArrayResize(g_win, 0);
   CsvInit();

   // restarted with a trade already open: pick it up
   ulong tk = 0;
   if(FindOurPosition(tk) && PositionSelectByTicket(tk))
     {
      g_ticket = tk;
      g_dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      g_ent = PositionGetDouble(POSITION_PRICE_OPEN);
      g_stp = PositionGetDouble(POSITION_SL);
      g_stop0 = g_stp;
      g_lots = PositionGetDouble(POSITION_VOLUME);
      g_riskPts = MathAbs(g_ent - g_stp);
      g_riskMoney = g_lots * MoneyPerLot(g_riskPts);
      g_best = g_ent;
      g_entT = (datetime)PositionGetInteger(POSITION_TIME);
      g_sigT = g_entT - 60;
      g_entDay = NYDay(g_entT);
     }
   ShowPanel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   double wr = s_T > 0 ? 100.0 * s_W / s_T : 0.0;
   PrintFormat("BTH Patrick ORB | %d days | %d range-break days | %d trades (%d BE) | win %.1f%% | total %.2fR | avg %.3fR | PF %s | max DD %.2fR | worst streak %d | skipped %d",
               s_days, s_breakDays, s_T, s_BE, wr, s_sumR, s_T > 0 ? s_sumR / s_T : 0.0,
               s_gL > 0 ? DoubleToString(s_gW / s_gL, 2) : "-", s_dd, s_maxConsec, s_skipped);
   if(g_csv != "") PrintFormat("BTH Patrick ORB | trade log: %s (MetaTrader 5 Common\\Files folder)", g_csv);
  }

// custom optimisation criterion = total R
double OnTester() { return s_sumR; }

void OnTick()
  {
   ManageTrade();

   datetime cur = iTime(_Symbol, PERIOD_M1, 0);
   if(cur == 0) return;
   if(g_lastProc != 0 && cur - 60 <= g_lastProc) return;

   MqlRates r[];
   datetime from = (g_lastProc == 0) ? cur - (datetime)(InpWarmupDays * 86400) : g_lastProc + 1;
   int got = CopyRates(_Symbol, PERIOD_M1, from, cur - 60, r);
   if(got <= 0) return;

   for(int i = 0; i < got; i++)
     {
      if(r[i].time <= g_lastProc) continue;
      if(r[i].time >= cur) break;
      SBar b;
      b.t = r[i].time; b.o = r[i].open; b.h = r[i].high; b.l = r[i].low; b.c = r[i].close;
      bool live = g_warm && (i == got - 1);
      ProcessBar(b, live);
      g_lastProc = r[i].time;
     }
   g_warm = true;
   ShowPanel();
  }
//+------------------------------------------------------------------+
