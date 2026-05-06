//+------------------------------------------------------------------+
//|                                              CandlePatterns.mqh  |
//|                         Advanced MT5 Grid Hedging EA             |
//|                         Candlestick Pattern Detection Module     |
//+------------------------------------------------------------------+
#ifndef CANDLE_PATTERNS_MQH
#define CANDLE_PATTERNS_MQH

enum ENUM_CANDLE_SIGNAL { CANDLE_NONE=0, CANDLE_BUY=1, CANDLE_SELL=-1 };

//+------------------------------------------------------------------+
//| Helper: candle metrics                                           |
//+------------------------------------------------------------------+
double CandleBody(int idx, string sym, ENUM_TIMEFRAMES tf)
  {
   return MathAbs(iClose(sym,tf,idx) - iOpen(sym,tf,idx));
  }
double CandleRange(int idx, string sym, ENUM_TIMEFRAMES tf)
  {
   return iHigh(sym,tf,idx) - iLow(sym,tf,idx);
  }
double UpperWick(int idx, string sym, ENUM_TIMEFRAMES tf)
  {
   return iHigh(sym,tf,idx) - MathMax(iOpen(sym,tf,idx), iClose(sym,tf,idx));
  }
double LowerWick(int idx, string sym, ENUM_TIMEFRAMES tf)
  {
   return MathMin(iOpen(sym,tf,idx), iClose(sym,tf,idx)) - iLow(sym,tf,idx);
  }
bool IsBullish(int idx, string sym, ENUM_TIMEFRAMES tf)
  {
   return iClose(sym,tf,idx) > iOpen(sym,tf,idx);
  }
bool IsBearish(int idx, string sym, ENUM_TIMEFRAMES tf)
  {
   return iClose(sym,tf,idx) < iOpen(sym,tf,idx);
  }
double AvgBody(string sym, ENUM_TIMEFRAMES tf, int count=10, int start=1)
  {
   double sum=0;
   for(int i=start; i<start+count; i++) sum += CandleBody(i,sym,tf);
   return sum/count;
  }

//+------------------------------------------------------------------+
//| Bullish Engulfing                                                |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(string sym, ENUM_TIMEFRAMES tf)
  {
   if(!IsBearish(2,sym,tf) || !IsBullish(1,sym,tf)) return false;
   return iOpen(sym,tf,1) <= iClose(sym,tf,2) &&
          iClose(sym,tf,1) >= iOpen(sym,tf,2) &&
          CandleBody(1,sym,tf) > CandleBody(2,sym,tf);
  }

//+------------------------------------------------------------------+
//| Bearish Engulfing                                                |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(string sym, ENUM_TIMEFRAMES tf)
  {
   if(!IsBullish(2,sym,tf) || !IsBearish(1,sym,tf)) return false;
   return iOpen(sym,tf,1) >= iClose(sym,tf,2) &&
          iClose(sym,tf,1) <= iOpen(sym,tf,2) &&
          CandleBody(1,sym,tf) > CandleBody(2,sym,tf);
  }

//+------------------------------------------------------------------+
//| Doji                                                             |
//+------------------------------------------------------------------+
bool IsDoji(string sym, ENUM_TIMEFRAMES tf)
  {
   double range = CandleRange(1,sym,tf);
   if(range == 0) return false;
   return CandleBody(1,sym,tf) / range < 0.1;
  }

//+------------------------------------------------------------------+
//| Hammer (bullish reversal)                                        |
//+------------------------------------------------------------------+
bool IsHammer(string sym, ENUM_TIMEFRAMES tf)
  {
   double body  = CandleBody(1,sym,tf);
   double lower = LowerWick(1,sym,tf);
   double upper = UpperWick(1,sym,tf);
   double range = CandleRange(1,sym,tf);
   if(range == 0 || body == 0) return false;
   return lower >= body*2 && upper <= body*0.5 && body/range > 0.15;
  }

//+------------------------------------------------------------------+
//| Shooting Star (bearish reversal)                                 |
//+------------------------------------------------------------------+
bool IsShootingStar(string sym, ENUM_TIMEFRAMES tf)
  {
   double body  = CandleBody(1,sym,tf);
   double lower = LowerWick(1,sym,tf);
   double upper = UpperWick(1,sym,tf);
   double range = CandleRange(1,sym,tf);
   if(range == 0 || body == 0) return false;
   return upper >= body*2 && lower <= body*0.5 && body/range > 0.15;
  }

//+------------------------------------------------------------------+
//| Morning Star (bullish reversal - 3 candle)                       |
//+------------------------------------------------------------------+
bool IsMorningStar(string sym, ENUM_TIMEFRAMES tf)
  {
   double avgB = AvgBody(sym,tf);
   if(!IsBearish(3,sym,tf)) return false;
   if(CandleBody(3,sym,tf) < avgB) return false;
   if(CandleBody(2,sym,tf) > avgB*0.5) return false;
   if(!IsBullish(1,sym,tf)) return false;
   if(CandleBody(1,sym,tf) < avgB) return false;
   return iClose(sym,tf,1) > (iOpen(sym,tf,3)+iClose(sym,tf,3))/2.0;
  }

//+------------------------------------------------------------------+
//| Evening Star (bearish reversal - 3 candle)                       |
//+------------------------------------------------------------------+
bool IsEveningStar(string sym, ENUM_TIMEFRAMES tf)
  {
   double avgB = AvgBody(sym,tf);
   if(!IsBullish(3,sym,tf)) return false;
   if(CandleBody(3,sym,tf) < avgB) return false;
   if(CandleBody(2,sym,tf) > avgB*0.5) return false;
   if(!IsBearish(1,sym,tf)) return false;
   if(CandleBody(1,sym,tf) < avgB) return false;
   return iClose(sym,tf,1) < (iOpen(sym,tf,3)+iClose(sym,tf,3))/2.0;
  }

//+------------------------------------------------------------------+
//| Bullish Harami                                                   |
//+------------------------------------------------------------------+
bool IsBullishHarami(string sym, ENUM_TIMEFRAMES tf)
  {
   if(!IsBearish(2,sym,tf) || !IsBullish(1,sym,tf)) return false;
   return iOpen(sym,tf,1) > iClose(sym,tf,2) &&
          iClose(sym,tf,1) < iOpen(sym,tf,2) &&
          CandleBody(1,sym,tf) < CandleBody(2,sym,tf)*0.6;
  }

//+------------------------------------------------------------------+
//| Bearish Harami                                                   |
//+------------------------------------------------------------------+
bool IsBearishHarami(string sym, ENUM_TIMEFRAMES tf)
  {
   if(!IsBullish(2,sym,tf) || !IsBearish(1,sym,tf)) return false;
   return iOpen(sym,tf,1) < iClose(sym,tf,2) &&
          iClose(sym,tf,1) > iOpen(sym,tf,2) &&
          CandleBody(1,sym,tf) < CandleBody(2,sym,tf)*0.6;
  }

//+------------------------------------------------------------------+
//| Piercing Pattern (bullish)                                       |
//+------------------------------------------------------------------+
bool IsPiercingPattern(string sym, ENUM_TIMEFRAMES tf)
  {
   if(!IsBearish(2,sym,tf) || !IsBullish(1,sym,tf)) return false;
   double mid2 = (iOpen(sym,tf,2)+iClose(sym,tf,2))/2.0;
   return iOpen(sym,tf,1) < iClose(sym,tf,2) &&
          iClose(sym,tf,1) > mid2 &&
          iClose(sym,tf,1) < iOpen(sym,tf,2);
  }

//+------------------------------------------------------------------+
//| Dark Cloud Cover (bearish)                                       |
//+------------------------------------------------------------------+
bool IsDarkCloudCover(string sym, ENUM_TIMEFRAMES tf)
  {
   if(!IsBullish(2,sym,tf) || !IsBearish(1,sym,tf)) return false;
   double mid2 = (iOpen(sym,tf,2)+iClose(sym,tf,2))/2.0;
   return iOpen(sym,tf,1) > iClose(sym,tf,2) &&
          iClose(sym,tf,1) < mid2 &&
          iClose(sym,tf,1) > iOpen(sym,tf,2);
  }

//+------------------------------------------------------------------+
//| Inside Bar                                                       |
//+------------------------------------------------------------------+
bool IsInsideBar(string sym, ENUM_TIMEFRAMES tf)
  {
   return iHigh(sym,tf,1) < iHigh(sym,tf,2) &&
          iLow(sym,tf,1) > iLow(sym,tf,2);
  }

//+------------------------------------------------------------------+
//| Pin Bar (bullish or bearish)                                     |
//+------------------------------------------------------------------+
ENUM_CANDLE_SIGNAL PinBarSignal(string sym, ENUM_TIMEFRAMES tf)
  {
   double body  = CandleBody(1,sym,tf);
   double range = CandleRange(1,sym,tf);
   double upper = UpperWick(1,sym,tf);
   double lower = LowerWick(1,sym,tf);
   if(range == 0) return CANDLE_NONE;
   if(body/range > 0.35) return CANDLE_NONE;
   // Bullish pin bar: long lower wick
   if(lower > range*0.6 && upper < range*0.2) return CANDLE_BUY;
   // Bearish pin bar: long upper wick
   if(upper > range*0.6 && lower < range*0.2) return CANDLE_SELL;
   return CANDLE_NONE;
  }

//+------------------------------------------------------------------+
//| Master detection: scan all patterns, return signal               |
//+------------------------------------------------------------------+
ENUM_CANDLE_SIGNAL DetectCandleSignal(string sym, ENUM_TIMEFRAMES tf)
  {
   // --- Bullish patterns ---
   if(IsBullishEngulfing(sym,tf))  { Print("[Candle] Bullish Engulfing");  return CANDLE_BUY;  }
   if(IsHammer(sym,tf))           { Print("[Candle] Hammer");             return CANDLE_BUY;  }
   if(IsMorningStar(sym,tf))      { Print("[Candle] Morning Star");       return CANDLE_BUY;  }
   if(IsBullishHarami(sym,tf))    { Print("[Candle] Bullish Harami");     return CANDLE_BUY;  }
   if(IsPiercingPattern(sym,tf))  { Print("[Candle] Piercing Pattern");   return CANDLE_BUY;  }

   // --- Bearish patterns ---
   if(IsBearishEngulfing(sym,tf)) { Print("[Candle] Bearish Engulfing");  return CANDLE_SELL; }
   if(IsShootingStar(sym,tf))     { Print("[Candle] Shooting Star");      return CANDLE_SELL; }
   if(IsEveningStar(sym,tf))      { Print("[Candle] Evening Star");       return CANDLE_SELL; }
   if(IsBearishHarami(sym,tf))    { Print("[Candle] Bearish Harami");     return CANDLE_SELL; }
   if(IsDarkCloudCover(sym,tf))   { Print("[Candle] Dark Cloud Cover");   return CANDLE_SELL; }

   // --- Neutral / contextual ---
   if(IsDoji(sym,tf))
     {
      // Doji after bullish move = potential sell, after bearish = potential buy
      if(IsBullish(2,sym,tf)) { Print("[Candle] Doji (after bull)"); return CANDLE_SELL; }
      if(IsBearish(2,sym,tf)) { Print("[Candle] Doji (after bear)"); return CANDLE_BUY;  }
     }

   ENUM_CANDLE_SIGNAL pin = PinBarSignal(sym,tf);
   if(pin != CANDLE_NONE) { Print("[Candle] Pin Bar"); return pin; }

   if(IsInsideBar(sym,tf))
     {
      if(IsBullish(1,sym,tf)) { Print("[Candle] Inside Bar (bull)"); return CANDLE_BUY;  }
      if(IsBearish(1,sym,tf)) { Print("[Candle] Inside Bar (bear)"); return CANDLE_SELL; }
     }

   return CANDLE_NONE;
  }

#endif // CANDLE_PATTERNS_MQH
