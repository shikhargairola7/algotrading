//+------------------------------------------------------------------+ 
//|                                                     XAUUSD.mq5   |
//|                                    Copyright 2025, Shivam Shikhar|
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Shivam Shikhar"
#property link      ""
#property version   "1.00"

//+------------------------------------------------------------------+
//| Includes and Declarations                                        |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

// Declare trade object
CTrade trade;

// Indicator handles (for the main chart timeframe)
int ema9_handle;
int vwap_handle;

// Trend filter indicator handles (higher timeframe)
int maFast_handle;
int maSlow_handle;

// Global variables
const double         FIXED_LOT_SIZE    = 0.20;
const string         SYMBOL            = "ETHUSDm";
const ENUM_TIMEFRAMES TIMEFRAME        = PERIOD_M15;

//--- For the Trend Filter (higher timeframe) ---
const ENUM_TIMEFRAMES TREND_TIMEFRAME  = PERIOD_H1;
const int           FAST_MA_PERIOD     = 50;
const int           SLOW_MA_PERIOD     = 200;

//--- Time Filter Settings (server time) ---
const bool          USE_TIME_FILTER    = true;
const int           START_HOUR         = 6;   // trade start hour
const int           END_HOUR           = 18;  // trade end hour

//--- Intrabar noise filtering (confirmation) ---
int                 buyTickCount       = 0;
int                 sellTickCount      = 0;
const int           CONFIRMATION_TICKS = 5;   // number of consecutive ticks required

//--- Prevent duplicate entries ---
int                 lastSignal         = 0;   // 1 = last was Buy, -1 = last was Sell, 0 = none

//+------------------------------------------------------------------+
//| Initialization Function                                          |
//+------------------------------------------------------------------+
void OnInit()
{
   // Create EMA9 indicator handle
   ema9_handle = iMA(SYMBOL, TIMEFRAME, 9, 0, MODE_EMA, PRICE_CLOSE);
   if(ema9_handle == INVALID_HANDLE)
   {
      Print("Failed to create EMA9 handle. EA will terminate.");
      ExpertRemove();
      return;
   }
   
   // Create handle for custom VWAP indicator
   vwap_handle = iCustom(SYMBOL, TIMEFRAME, "VWAP_UTC_Final");
   if(vwap_handle == INVALID_HANDLE)
   {
      Print("Failed to create VWAP handle. EA will terminate.");
      ExpertRemove();
      return;
   }

   // Create higher timeframe MAs for trend filter
   maFast_handle = iMA(SYMBOL, TREND_TIMEFRAME, FAST_MA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   if(maFast_handle == INVALID_HANDLE)
   {
      Print("Failed to create Fast MA handle for trend filter. EA will terminate.");
      ExpertRemove();
      return;
   }

   maSlow_handle = iMA(SYMBOL, TREND_TIMEFRAME, SLOW_MA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   if(maSlow_handle == INVALID_HANDLE)
   {
      Print("Failed to create Slow MA handle for trend filter. EA will terminate.");
      ExpertRemove();
      return;
   }
   
   trade.SetDeviationInPoints(10); // Allow some slippage
   Print("EA initialized successfully on ", SYMBOL, " (M15)");
}

//+------------------------------------------------------------------+
//| Main Tick Function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // OPTIONAL: Evaluate only on a new M15 bar by uncommenting the code below.
   /*
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(SYMBOL, TIMEFRAME, 0);
   if(current_bar_time <= last_bar_time)
      return;
   last_bar_time = current_bar_time;
   */
   
   // 1) Time Filter Check
   if(USE_TIME_FILTER && !AllowedTime())
   {
      // If not in allowed trading hours, reset counters and do nothing
      buyTickCount = 0;
      sellTickCount = 0;
      lastSignal    = 0;
      return;
   }
   
   // 2) Retrieve the latest two data points for EMA9
   double ema9[];
   ArraySetAsSeries(ema9, true);
   if(CopyBuffer(ema9_handle, 0, 0, 2, ema9) < 2)
   {
      Print("Failed to copy EMA9 data");
      return;
   }
   
   // 3) Retrieve the latest two data points for VWAP
   double vwap[];
   ArraySetAsSeries(vwap, true);
   if(CopyBuffer(vwap_handle, 0, 0, 2, vwap) < 2)
   {
      Print("Failed to copy VWAP data");
      return;
   }
   
   // 4) Check and manage existing position
   if(PositionSelect(SYMBOL))
   {
      // For exit, we use the previous completed candle data
      CheckExitCondition(iClose(SYMBOL, TIMEFRAME, 1), ema9[1]);
      CheckBetterOpportunity(ema9, vwap);
   }
   else
   {
      CheckEntryConditions(ema9, vwap);
   }
}

//+------------------------------------------------------------------+
//| Check Entry Conditions                                           |
//+------------------------------------------------------------------+
void CheckEntryConditions(double &ema9[], double &vwap[])
{
   int    digits = (int)SymbolInfoInteger(SYMBOL, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(SYMBOL, SYMBOL_POINT);
   
   // Intrabar Crossover conditions
   bool buyCondition  = (ema9[1] < vwap[1] && ema9[0] > vwap[0]);
   bool sellCondition = (ema9[1] > vwap[1] && ema9[0] < vwap[0]);

   // Trend Filter
   bool upTrend   = IsUpTrend();
   bool downTrend = IsDownTrend();

   // If buy condition is true AND we have an uptrend
   if(buyCondition && upTrend)
   {
      buyTickCount++;
      sellTickCount = 0; // Reset sell counter
      if(buyTickCount >= CONFIRMATION_TICKS && lastSignal != 1)
      {
         double sl = NormalizeDouble(vwap[0] - 3 * point, digits);
         if(trade.Buy(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0))
         {
            lastSignal   = 1;   // Mark that a Buy was executed
            buyTickCount = 0;   // Reset the counter
            Print("Buy trade opened at market price with SL: ", sl);
         }
      }
   }
   // If sell condition is true AND we have a downtrend
   else if(sellCondition && downTrend)
   {
      sellTickCount++;
      buyTickCount = 0; // Reset buy counter
      if(sellTickCount >= CONFIRMATION_TICKS && lastSignal != -1)
      {
         double sl = NormalizeDouble(vwap[0] + 3 * point, digits);
         if(trade.Sell(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0))
         {
            lastSignal    = -1; // Mark that a Sell was executed
            sellTickCount = 0;  // Reset the counter
            Print("Sell trade opened at market price with SL: ", sl);
         }
      }
   }
   else
   {
      // If neither condition is met, reset counters and signal
      buyTickCount  = 0;
      sellTickCount = 0;
      lastSignal    = 0;
   }
}

//+------------------------------------------------------------------+
//| Check Exit Condition                                             |
//+------------------------------------------------------------------+
void CheckExitCondition(double close1, double ema9_prev)
{
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      if(close1 < ema9_prev)
      {
         trade.PositionClose(SYMBOL);
         lastSignal = 0; // Reset signal flag after exit
         Print("Buy position closed - previous candle closed below EMA9");
      }
   }
   else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      if(close1 > ema9_prev)
      {
         trade.PositionClose(SYMBOL);
         lastSignal = 0; // Reset signal flag after exit
         Print("Sell position closed - previous candle closed above EMA9");
      }
   }
}

//+------------------------------------------------------------------+
//| Check for Better Opportunity                                     |
//+------------------------------------------------------------------+
void CheckBetterOpportunity(double &ema9[], double &vwap[])
{
   int    digits = (int)SymbolInfoInteger(SYMBOL, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(SYMBOL, SYMBOL_POINT);
   
   if(PositionSelect(SYMBOL))
   {
      long pos_type = PositionGetInteger(POSITION_TYPE);
      // Switch from sell to buy
      if(pos_type == POSITION_TYPE_SELL && (ema9[1] < vwap[1] && ema9[0] > vwap[0]) && IsUpTrend())
      {
         trade.PositionClose(SYMBOL);
         double sl = NormalizeDouble(vwap[0] - 3 * point, digits);
         trade.Buy(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0);
         lastSignal = 1;
         Print("Switched from Sell to Buy trade");
      }
      // Switch from buy to sell
      else if(pos_type == POSITION_TYPE_BUY && (ema9[1] > vwap[1] && ema9[0] < vwap[0]) && IsDownTrend())
      {
         trade.PositionClose(SYMBOL);
         double sl = NormalizeDouble(vwap[0] + 3 * point, digits);
         trade.Sell(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0);
         lastSignal = -1;
         Print("Switched from Buy to Sell trade");
      }
   }
}

//+------------------------------------------------------------------+
//| Deinitialization Function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ema9_handle != INVALID_HANDLE)
      IndicatorRelease(ema9_handle);
   if(vwap_handle != INVALID_HANDLE)
      IndicatorRelease(vwap_handle);

   // Release trend filter MAs
   if(maFast_handle != INVALID_HANDLE)
      IndicatorRelease(maFast_handle);
   if(maSlow_handle != INVALID_HANDLE)
      IndicatorRelease(maSlow_handle);

   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Time Filter Function                                             |
//+------------------------------------------------------------------+
bool AllowedTime()
{
   // Get current server time and extract the hour.
   int hour = TimeHour(TimeCurrent());
   // Allow trades between START_HOUR (inclusive) and END_HOUR (exclusive)
   if(hour >= START_HOUR && hour < END_HOUR)
      return true;
   return false;
}

//+------------------------------------------------------------------+
//| Trend Filter Functions                                           |
//+------------------------------------------------------------------+
bool IsUpTrend()
{
   double fastMaArr[1];
   double slowMaArr[1];
   
   if(CopyBuffer(maFast_handle, 0, 0, 1, fastMaArr) < 1)
      return false;
   if(CopyBuffer(maSlow_handle, 0, 0, 1, slowMaArr) < 1)
      return false;
   
   return (fastMaArr[0] > slowMaArr[0]);
}

bool IsDownTrend()
{
   double fastMaArr[1];
   double slowMaArr[1];
   
   if(CopyBuffer(maFast_handle, 0, 0, 1, fastMaArr) < 1)
      return false;
   if(CopyBuffer(maSlow_handle, 0, 0, 1, slowMaArr) < 1)
      return false;
   
   return (fastMaArr[0] < slowMaArr[0]);
}
