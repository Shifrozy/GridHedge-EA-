//+------------------------------------------------------------------+
//|                                              GridHedge_EA.mq5    |
//|                         Advanced MT5 Grid Hedging EA             |
//|                         Dynamic Grid + Hedging + Progressive Lot |
//+------------------------------------------------------------------+
#property copyright "GridHedge EA"
#property link      ""
#property version   "1.00"
#property strict
#property description "Dynamic Grid + Hedging + Progressive Lot Scaling EA"
#property description "Supports Forex, Gold, Crypto, Indices & all MT5 symbols"

#include "CandlePatterns.mqh"
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_INIT_DIR { DIR_BUY=0, DIR_SELL=1, DIR_AUTO=2 };

//====================================================================
//  INPUT PARAMETERS
//====================================================================

//--- Core Trading Settings ---
input group "=== Core Trading Settings ==="
input double   InpStartLot        = 0.01;     // Starting Lot Size
input int      InpGridPips        = 100;       // Grid Offset (points)
input int      InpMaxGridTrades   = 5;         // Trades before cycle marked failed
input double   InpTakeProfit      = 10.0;      // Take Profit (account currency, 0=disabled)
input double   InpMaxLoss         = 50.0;      // Max Loss (account currency, 0=disabled)
input int      InpMagicNumber     = 777777;    // Magic Number
input ENUM_INIT_DIR InpInitDir    = DIR_AUTO;  // Initial Direction (Auto=candle/random)
input int      InpSlippage        = 10;        // Max Slippage (points)

//--- Progressive Lot Settings ---
input group "=== Progressive Lot Scaling ==="
input double   InpLotIncrement    = 0.01;      // Lot Increment After Failed Cycle
input double   InpMaxLotSize      = 0.0;       // Max Lot Size (0=no limit)

//--- Candlestick Filter ---
input group "=== Candlestick Filter ==="
input bool     InpUseCandleFilter = false;     // Enable Candlestick Pattern Filter
input ENUM_TIMEFRAMES InpCandleTF = PERIOD_CURRENT; // Candlestick Timeframe

//--- Time Filter ---
input group "=== Time Filter ==="
input bool     InpUseTimeFilter   = false;     // Enable Time Filter
input string   InpTimeStart       = "22:00";   // Stop New Trades Start Time
input string   InpTimeEnd         = "01:00";   // Stop New Trades End Time

//--- Spread Filter ---
input group "=== Spread Filter ==="
input double   InpMaxSpread       = 0.0;       // Max Spread (points, 0=disabled)

//--- Display ---
input group "=== Display Settings ==="
input bool     InpShowPanel       = true;      // Show Info Panel
input color    InpPanelColor      = clrMidnightBlue; // Panel Background Color
input color    InpTextColor       = clrWhite;  // Panel Text Color
input int      InpFontSize        = 9;         // Panel Font Size

//====================================================================
//  GLOBAL VARIABLES
//====================================================================
CTrade         trade;
string         g_symbol;
int            g_digits;
double         g_point;
double         g_tickSize;
double         g_lotStep;
double         g_lotMin;
double         g_lotMax;

// --- Cycle State ---
double         g_currentLot;          // Current lot size for this cycle
double         g_triggerPrice;         // Price where cycle started
int            g_buyCount;            // Buys opened at current lot level
int            g_sellCount;           // Sells opened at current lot level
double         g_lastBuyPrice;        // Last buy entry price
double         g_lastSellPrice;       // Last sell entry price
bool           g_cycleActive;         // Is a trading cycle active?
bool           g_cycleFailed;         // Has this cycle been marked as failed?
int            g_initialDirection;    // 1=BUY started, -1=SELL started
int            g_failedCycles;        // Count of consecutive failed cycles
bool           g_initialTradeOpened;  // First trade of cycle placed?
datetime       g_lastBarTime;         // For new bar detection
int            g_totalCyclesRun;      // Lifetime cycles

//====================================================================
//  INITIALIZATION
//====================================================================
int OnInit()
  {
   g_symbol   = _Symbol;
   g_digits   = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_point    = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_tickSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   g_lotStep  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   g_lotMin   = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   g_lotMax   = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);

   //--- Auto-detect filling mode (FOK may not work on all brokers)
   long fillType = SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
   if((fillType & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillType & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // Init cycle
   g_currentLot       = NormalizeLot(InpStartLot);
   g_triggerPrice      = 0;
   g_buyCount          = 0;
   g_sellCount         = 0;
   g_lastBuyPrice      = 0;
   g_lastSellPrice     = 0;
   g_cycleActive       = false;
   g_cycleFailed       = false;
   g_initialDirection  = 0;
   g_failedCycles      = 0;
   g_initialTradeOpened= false;
   g_lastBarTime       = 0;
   g_totalCyclesRun    = 0;

   // Recover state from existing positions
   RecoverState();

   PrintFormat("[GridHedge] Initialized on %s | Lot=%.2f | Grid=%d pts | MaxTrades=%d",
               g_symbol, g_currentLot, InpGridPips, InpMaxGridTrades);

   if(InpShowPanel) CreatePanel();

   return(INIT_SUCCEEDED);
  }

//====================================================================
//  DEINITIALIZATION
//====================================================================
void OnDeinit(const int reason)
  {
   if(InpShowPanel) DeletePanel();
   PrintFormat("[GridHedge] Deinitialized. Cycles run: %d | Failed: %d",
               g_totalCyclesRun, g_failedCycles);
  }

//====================================================================
//  MAIN TICK HANDLER
//====================================================================
void OnTick()
  {
   //--- Always check profit/loss targets (even during restricted hours)
   double totalProfit = CalcTotalProfit();

   if(InpTakeProfit > 0 && totalProfit >= InpTakeProfit)
     {
      PrintFormat("[GridHedge] TP reached! Profit=%.2f >= %.2f", totalProfit, InpTakeProfit);
      CloseAllPositions();
      ResetCycle(false); // successful cycle
      if(InpShowPanel) UpdatePanel();
      return;
     }

   if(InpMaxLoss > 0 && totalProfit <= -InpMaxLoss)
     {
      PrintFormat("[GridHedge] SL reached! Loss=%.2f >= %.2f", MathAbs(totalProfit), InpMaxLoss);
      CloseAllPositions();
      ResetCycle(true); // failed cycle
      if(InpShowPanel) UpdatePanel();
      return;
     }

   //--- Detect manual close: if cycle is active but no positions exist, reset
   if(g_cycleActive && TotalPositions() == 0)
     {
      PrintFormat("[GridHedge] All positions closed (manually or externally). Resetting cycle.");
      g_triggerPrice      = 0;
      g_buyCount          = 0;
      g_sellCount         = 0;
      g_lastBuyPrice      = 0;
      g_lastSellPrice     = 0;
      g_cycleActive       = false;
      g_cycleFailed       = false;
      g_initialDirection  = 0;
      g_initialTradeOpened= false;
      // Keep g_currentLot and g_failedCycles unchanged (don't penalize manual close)
      if(InpShowPanel) UpdatePanel();
      return;
     }

   //--- Check if failed cycle and price returned to trigger area
   if(g_cycleActive && g_cycleFailed && g_triggerPrice > 0)
     {
      double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      double gridDist = InpGridPips * g_point;
      double mid = (ask + bid) / 2.0;

      // Price returned within 1 grid distance of trigger
      if(MathAbs(mid - g_triggerPrice) <= gridDist)
        {
         // Increase lot size
         g_failedCycles++;
         g_currentLot = NormalizeLot(InpStartLot + g_failedCycles * InpLotIncrement);

         PrintFormat("[GridHedge] Price returned to trigger %.5f! Lot increased to %.2f (fail #%d)",
                     g_triggerPrice, g_currentLot, g_failedCycles);

         // Open new trade at trigger point in original direction
         bool opened = false;
         if(g_initialDirection == 1) // was BUY
           {
            opened = trade.Buy(g_currentLot, g_symbol, ask, 0, 0,
                               StringFormat("GridHedge Buy (new lot) %.2f", g_currentLot));
            if(opened)
              {
               // Reset ALL price references to new trigger point
               g_lastBuyPrice  = ask;
               g_lastSellPrice = 0;   // Clear old sell reference
               g_triggerPrice  = ask;
               PrintFormat("[GridHedge] New BUY @ %.5f | Lot=%.2f", ask, g_currentLot);
              }
           }
         else // was SELL
           {
            opened = trade.Sell(g_currentLot, g_symbol, bid, 0, 0,
                                StringFormat("GridHedge Sell (new lot) %.2f", g_currentLot));
            if(opened)
              {
               // Reset ALL price references to new trigger point
               g_lastSellPrice = bid;
               g_lastBuyPrice  = 0;   // Clear old buy reference
               g_triggerPrice  = bid;
               PrintFormat("[GridHedge] New SELL @ %.5f | Lot=%.2f", bid, g_currentLot);
              }
           }

         // Reset counters for new lot level
         g_buyCount  = (g_initialDirection == 1)  ? 1 : 0;
         g_sellCount = (g_initialDirection == -1) ? 1 : 0;
         g_cycleFailed = false;

         if(InpShowPanel) UpdatePanel();
         return;
        }
     }

   //--- Check spread filter
   if(!IsSpreadOK()) return;

   //--- If no cycle active, try to start one
   if(!g_cycleActive)
     {
      if(IsRestrictedTime()) return;
      TryStartCycle();
      if(InpShowPanel) UpdatePanel();
      return;
     }

   //--- Cycle is active: manage grid (unlimited trades)
   ManageGrid();

   //--- Update panel
   if(InpShowPanel) UpdatePanel();
  }

//====================================================================
//  CYCLE MANAGEMENT
//====================================================================
void TryStartCycle()
  {
   ENUM_CANDLE_SIGNAL signal = CANDLE_NONE;

   // Determine direction
   if(InpInitDir == DIR_BUY)
      signal = CANDLE_BUY;
   else if(InpInitDir == DIR_SELL)
      signal = CANDLE_SELL;
   else // AUTO
     {
      if(InpUseCandleFilter)
        {
         // Only on new bar
         datetime barTime = iTime(g_symbol, InpCandleTF, 0);
         if(barTime == g_lastBarTime) return;
         g_lastBarTime = barTime;

         signal = DetectCandleSignal(g_symbol, InpCandleTF);
         if(signal == CANDLE_NONE) return;
        }
      else
        {
         // Without candle filter: use simple momentum
         double close1 = iClose(g_symbol, PERIOD_CURRENT, 1);
         double close2 = iClose(g_symbol, PERIOD_CURRENT, 2);
         signal = (close1 > close2) ? CANDLE_BUY : CANDLE_SELL;
        }
     }

   if(signal == CANDLE_NONE) return;

   // Open initial trade
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   bool ok = false;

   if(signal == CANDLE_BUY)
     {
      ok = trade.Buy(g_currentLot, g_symbol, ask, 0, 0, "GridHedge Buy #1");
      if(ok)
        {
         g_lastBuyPrice = ask;
         g_buyCount = 1;
         g_triggerPrice = ask;
         g_initialDirection = 1;
         PrintFormat("[GridHedge] Cycle START BUY @ %.5f | Lot=%.2f", ask, g_currentLot);
        }
     }
   else
     {
      ok = trade.Sell(g_currentLot, g_symbol, bid, 0, 0, "GridHedge Sell #1");
      if(ok)
        {
         g_lastSellPrice = bid;
         g_sellCount = 1;
         g_triggerPrice = bid;
         g_initialDirection = -1;
         PrintFormat("[GridHedge] Cycle START SELL @ %.5f | Lot=%.2f", bid, g_currentLot);
        }
     }

   if(ok)
     {
      g_cycleActive = true;
      g_initialTradeOpened = true;
      g_totalCyclesRun++;
     }
   else
      PrintFormat("[GridHedge] Order failed: %d - %s", GetLastError(), trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Grid Management - add positions at grid intervals                |
//+------------------------------------------------------------------+
void ManageGrid()
  {
   if(IsRestrictedTime()) return;

   // STOP adding trades once cycle is marked failed
   // Wait for price to return to trigger area (handled in OnTick)
   if(g_cycleFailed) return;

   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double gridDist = InpGridPips * g_point;

   // --- Add BUY trades (capped at max grid trades per side)
   if(g_buyCount < InpMaxGridTrades)
     {
      double buyRef = (g_lastBuyPrice > 0) ? g_lastBuyPrice : g_triggerPrice;
      if(buyRef > 0 && ask >= buyRef + gridDist)
        {
         string label = (g_sellCount > 0 && g_buyCount == 0) ? "hedge" : "grid";
         if(trade.Buy(g_currentLot, g_symbol, ask, 0, 0,
                       StringFormat("GridHedge Buy (%s) #%d L=%.2f", label, g_buyCount+1, g_currentLot)))
           {
            g_lastBuyPrice = ask;
            g_buyCount++;
            PrintFormat("[GridHedge] BUY (%s) #%d @ %.5f | Lot=%.2f", label, g_buyCount, ask, g_currentLot);
           }
        }
     }

   // --- Add SELL trades (capped at max grid trades per side)
   if(g_sellCount < InpMaxGridTrades)
     {
      double sellRef = (g_lastSellPrice > 0) ? g_lastSellPrice : g_triggerPrice;
      if(sellRef > 0 && bid <= sellRef - gridDist)
        {
         string label = (g_buyCount > 0 && g_sellCount == 0) ? "hedge" : "grid";
         if(trade.Sell(g_currentLot, g_symbol, bid, 0, 0,
                        StringFormat("GridHedge Sell (%s) #%d L=%.2f", label, g_sellCount+1, g_currentLot)))
           {
            g_lastSellPrice = bid;
            g_sellCount++;
            PrintFormat("[GridHedge] SELL (%s) #%d @ %.5f | Lot=%.2f", label, g_sellCount, bid, g_currentLot);
           }
        }
     }

   // --- Mark cycle as failed when either side hits max grid trades
   if(!g_cycleFailed && (g_buyCount >= InpMaxGridTrades || g_sellCount >= InpMaxGridTrades))
     {
      g_cycleFailed = true;
      PrintFormat("[GridHedge] CYCLE FAILED! (Buys=%d, Sells=%d, Max=%d). No more trades until price returns to trigger %.5f",
                  g_buyCount, g_sellCount, InpMaxGridTrades, g_triggerPrice);
     }
  }

//+------------------------------------------------------------------+
//| Reset cycle after close-all                                      |
//+------------------------------------------------------------------+
void ResetCycle(bool failed)
  {
   if(failed)
     {
      g_failedCycles++;
      g_currentLot = NormalizeLot(InpStartLot + g_failedCycles * InpLotIncrement);
      PrintFormat("[GridHedge] FAILED cycle #%d. New lot=%.2f", g_failedCycles, g_currentLot);
     }
   else
     {
      g_failedCycles  = 0;
      g_currentLot    = NormalizeLot(InpStartLot);
      PrintFormat("[GridHedge] SUCCESS! Lot reset to %.2f", g_currentLot);
     }

   g_triggerPrice      = 0;
   g_buyCount          = 0;
   g_sellCount         = 0;
   g_lastBuyPrice      = 0;
   g_lastSellPrice     = 0;
   g_cycleActive       = false;
   g_cycleFailed       = false;
   g_initialDirection  = 0;
   g_initialTradeOpened= false;
  }

//====================================================================
//  TRADE HELPERS
//====================================================================

//+------------------------------------------------------------------+
//| Close all positions for this EA                                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      if(!trade.PositionClose(ticket, InpSlippage))
         PrintFormat("[GridHedge] Failed close ticket %d: %s", ticket, trade.ResultRetcodeDescription());
      else
         PrintFormat("[GridHedge] Closed ticket %d", ticket);
     }
  }

//+------------------------------------------------------------------+
//| Calculate total floating profit for this EA                      |
//+------------------------------------------------------------------+
double CalcTotalProfit()
  {
   double total = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return total;
  }

//+------------------------------------------------------------------+
//| Count positions by type                                          |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
  {
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Total open positions count                                       |
//+------------------------------------------------------------------+
int TotalPositions()
  {
   return CountPositions(POSITION_TYPE_BUY) + CountPositions(POSITION_TYPE_SELL);
  }

//+------------------------------------------------------------------+
//| Normalize lot to broker specs                                    |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   lot = MathMax(lot, g_lotMin);
   if(InpMaxLotSize > 0) lot = MathMin(lot, InpMaxLotSize);
   lot = MathMin(lot, g_lotMax);
   lot = MathRound(lot / g_lotStep) * g_lotStep;
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
//| Recover state from existing positions on restart                 |
//+------------------------------------------------------------------+
void RecoverState()
  {
   int buys = CountPositions(POSITION_TYPE_BUY);
   int sells = CountPositions(POSITION_TYPE_SELL);

   if(buys == 0 && sells == 0) return;

   g_cycleActive = true;
   g_initialTradeOpened = true;
   g_buyCount = buys;
   g_sellCount = sells;

   // Find last buy/sell prices
   double highBuy = 0, lowSell = DBL_MAX;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY && price > highBuy)
        { highBuy = price; g_lastBuyPrice = price; }
      if(type == POSITION_TYPE_SELL && price < lowSell)
        { lowSell = price; g_lastSellPrice = price; }
      if(g_triggerPrice == 0) g_triggerPrice = price;
     }

   PrintFormat("[GridHedge] Recovered: %d buys, %d sells. LastBuy=%.5f LastSell=%.5f",
               buys, sells, g_lastBuyPrice, g_lastSellPrice);
  }

//====================================================================
//  FILTERS
//====================================================================

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                    |
//+------------------------------------------------------------------+
bool IsSpreadOK()
  {
   if(InpMaxSpread <= 0) return true;
   long spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   return spread <= InpMaxSpread;
  }

//+------------------------------------------------------------------+
//| Check if current time is in restricted window                    |
//+------------------------------------------------------------------+
bool IsRestrictedTime()
  {
   if(!InpUseTimeFilter) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;

   int startH=0, startM=0, endH=0, endM=0;
   if(!ParseTime(InpTimeStart, startH, startM)) return false;
   if(!ParseTime(InpTimeEnd, endH, endM))       return false;

   int startMin = startH * 60 + startM;
   int endMin   = endH * 60 + endM;

   if(startMin <= endMin)
      return (nowMin >= startMin && nowMin < endMin);
   else // crosses midnight
      return (nowMin >= startMin || nowMin < endMin);
  }

//+------------------------------------------------------------------+
//| Parse "HH:MM" string                                             |
//+------------------------------------------------------------------+
bool ParseTime(string timeStr, int &hours, int &minutes)
  {
   int pos = StringFind(timeStr, ":");
   if(pos < 0) return false;
   hours   = (int)StringToInteger(StringSubstr(timeStr, 0, pos));
   minutes = (int)StringToInteger(StringSubstr(timeStr, pos+1));
   return true;
  }

//====================================================================
//  ON-CHART INFO PANEL
//====================================================================
#define PANEL_X   10
#define PANEL_Y   30
#define LINE_H    18
#define PANEL_W   260

void CreatePanel()
  {
   string prefix = "GH_";
   int y = PANEL_Y;

   CreateLabel(prefix+"title", PANEL_X, y, "⬡ GridHedge EA v1.0", InpTextColor, InpFontSize+2, true);
   y += LINE_H + 4;
   CreateLabel(prefix+"sep1",  PANEL_X, y, "─────────────────────────", clrDarkGray, InpFontSize-1, false);
   y += LINE_H;
   CreateLabel(prefix+"sym",   PANEL_X, y, "Symbol: "+g_symbol, InpTextColor, InpFontSize, false);
   y += LINE_H;
   CreateLabel(prefix+"lot",   PANEL_X, y, "Lot: ", InpTextColor, InpFontSize, false);
   y += LINE_H;
   CreateLabel(prefix+"cycle", PANEL_X, y, "Cycle: ", InpTextColor, InpFontSize, false);
   y += LINE_H;
   CreateLabel(prefix+"buys",  PANEL_X, y, "Buys: ", InpTextColor, InpFontSize, false);
   y += LINE_H;
   CreateLabel(prefix+"sells", PANEL_X, y, "Sells: ", InpTextColor, InpFontSize, false);
   y += LINE_H;
   CreateLabel(prefix+"pnl",   PANEL_X, y, "P/L: ", InpTextColor, InpFontSize, false);
   y += LINE_H;
   CreateLabel(prefix+"fail",  PANEL_X, y, "Failed: ", InpTextColor, InpFontSize, false);
   y += LINE_H;
   CreateLabel(prefix+"sprd",  PANEL_X, y, "Spread: ", InpTextColor, InpFontSize, false);
   y += LINE_H;
   CreateLabel(prefix+"time",  PANEL_X, y, "Time OK: ", InpTextColor, InpFontSize, false);

   ChartRedraw();
  }

void UpdatePanel()
  {
   string prefix = "GH_";
   double profit = CalcTotalProfit();
   color  pColor = (profit >= 0) ? clrLime : clrOrangeRed;
   long   spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);

   SetLabelText(prefix+"lot",   StringFormat("Lot: %.2f (base: %.2f)", g_currentLot, InpStartLot));
   string cycleStr = "WAITING";
   if(g_cycleActive && g_cycleFailed) cycleStr = "FAILED ⚠";
   else if(g_cycleActive) cycleStr = "ACTIVE";
   SetLabelText(prefix+"cycle", StringFormat("Cycle: %s | Total: %d", cycleStr, g_totalCyclesRun));
   SetLabelText(prefix+"buys",  StringFormat("Buys: %d (fail@%d)", g_buyCount, InpMaxGridTrades));
   SetLabelText(prefix+"sells", StringFormat("Sells: %d (fail@%d)", g_sellCount, InpMaxGridTrades));
   SetLabelText(prefix+"pnl",   StringFormat("P/L: %.2f", profit));
   ObjectSetInteger(0, prefix+"pnl", OBJPROP_COLOR, pColor);
   SetLabelText(prefix+"fail",  StringFormat("Failed Cycles: %d | Next Lot: %.2f", g_failedCycles, NormalizeLot(InpStartLot + (g_failedCycles+1) * InpLotIncrement)));
   SetLabelText(prefix+"sprd",  StringFormat("Spread: %d pts", (int)spread));
   SetLabelText(prefix+"time",  StringFormat("Time OK: %s", IsRestrictedTime()?"NO ⛔":"YES ✅"));
  }

void DeletePanel()
  {
   string prefix = "GH_";
   string names[] = {"title","sep1","sym","lot","cycle","buys","sells","pnl","fail","sprd","time"};
   for(int i=0; i<ArraySize(names); i++)
      ObjectDelete(0, prefix+names[i]);
   ChartRedraw();
  }

void CreateLabel(string name, int x, int y, string text, color clr, int size, bool bold)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetString(0,  name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void SetLabelText(string name, string text)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
  }
//+------------------------------------------------------------------+
