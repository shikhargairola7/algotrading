//+------------------------------------------------------------------+
//|                                                       XAUUSD.mq5 |
//|                                    Copyright 2025, Shivam Shikhar |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Shivam Shikhar"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

// Declare trade object
CTrade trade;

// Indicator handles for M15 timeframe (for exit/SL calculations)
int ema9_handle;   // M15 EMA9 handle
int vwap_handle;   // M15 VWAP handle (custom indicator)

// Global variables
datetime last_bar_time = 0;    // Last processed M15 bar time
datetime last_m5_time = 0;     // Last processed M5 bar time (for entry)
const double FIXED_LOT_SIZE = 0.20;
const string SYMBOL = "ETHUSDm";
const ENUM_TIMEFRAMES TIMEFRAME = PERIOD_M15; // M15 timeframe for exit conditions and SL

//+------------------------------------------------------------------+
//| Initialization Function                                          |
//+------------------------------------------------------------------+
void OnInit()
{
   // Create EMA9 indicator handle for M15
   ema9_handle = iMA(SYMBOL, TIMEFRAME, 9, 0, MODE_EMA, PRICE_CLOSE);
   if(ema9_handle == INVALID_HANDLE)
   {
      Print("Failed to create M15 EMA9 handle. EA will terminate.");
      ExpertRemove();
      return;
   }
   
   // Create handle for custom VWAP indicator for M15
   vwap_handle = iCustom(SYMBOL, TIMEFRAME, "VWAP_UTC_Final");
   if(vwap_handle == INVALID_HANDLE)
   {
      Print("Failed to create M15 VWAP handle. EA will terminate.");
      ExpertRemove();
      return;
   }
   
   trade.SetDeviationInPoints(10); // Allow slippage
   Print("EA initialized successfully on ", SYMBOL, " (M15 for exit/SL, M5 for entry)");
}

//+------------------------------------------------------------------+
//| Main Tick Function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //------ Process M15 Bar for Exit Conditions & Trade Management ------
   datetime current_bar_time = iTime(SYMBOL, TIMEFRAME, 0);
   if(current_bar_time > last_bar_time)
   {
      last_bar_time = current_bar_time;
      
      double ema9_M15[];
      ArraySetAsSeries(ema9_M15, true);
      if(CopyBuffer(ema9_handle, 0, 0, 3, ema9_M15) < 3)
      {
         Print("Failed to copy M15 EMA9 data");
      }
      
      double vwap_M15[];
      ArraySetAsSeries(vwap_M15, true);
      if(CopyBuffer(vwap_handle, 0, 0, 3, vwap_M15) < 3)
      {
         Print("Failed to copy M15 VWAP data");
      }
      
      // Get previous M15 candle's close for exit conditions
      double close1 = iClose(SYMBOL, TIMEFRAME, 1);
      
      if(PositionSelect(SYMBOL))
      {
         CheckExitCondition(close1, ema9_M15[1]);
         CheckBetterOpportunity(ema9_M15, vwap_M15);
      }
   }
   
   //------ Process M5 Bar for Entry Conditions ---------------------------
   datetime current_m5_time = iTime(SYMBOL, PERIOD_M5, 0);
   if(current_m5_time > last_m5_time)
   {
      last_m5_time = current_m5_time;
      
      if(!PositionSelect(SYMBOL))
      {
         CheckEntryConditions();
      }
   }
}

//+------------------------------------------------------------------+
//| Check Entry Conditions (using M5 crossover)                      |
//| - Entry signal is based on M5 EMA9 and VWAP crossover              |
//| - Order is executed at the M5 open price                         |
//| - Stop loss is calculated using the M15 VWAP                      |
//+------------------------------------------------------------------+
void CheckEntryConditions()
{
   //--- Calculate EMA9 on M5 timeframe ---
   double ema9_5min[];
   ArraySetAsSeries(ema9_5min, true);
   int handleEMA5 = iMA(SYMBOL, PERIOD_M5, 9, 0, MODE_EMA, PRICE_CLOSE);
   if(handleEMA5 == INVALID_HANDLE)
   {
      Print("Failed to create M5 EMA handle");
      return;
   }
   if(CopyBuffer(handleEMA5, 0, 0, 3, ema9_5min) < 3)
   {
      Print("Failed to copy M5 EMA9 data");
      IndicatorRelease(handleEMA5);
      return;
   }
   IndicatorRelease(handleEMA5);
   
   //--- Calculate VWAP on M5 timeframe (custom indicator) ---
   double vwap_5min[];
   ArraySetAsSeries(vwap_5min, true);
   int handleVWAP5 = iCustom(SYMBOL, PERIOD_M5, "VWAP_UTC_Final");
   if(handleVWAP5 == INVALID_HANDLE)
   {
      Print("Failed to create M5 VWAP handle");
      return;
   }
   if(CopyBuffer(handleVWAP5, 0, 0, 3, vwap_5min) < 3)
   {
      Print("Failed to copy M5 VWAP data");
      IndicatorRelease(handleVWAP5);
      return;
   }
   IndicatorRelease(handleVWAP5);
   
   //--- Retrieve current 5-min candle open price ---
   double open5 = iOpen(SYMBOL, PERIOD_M5, 0);
   
   //--- Get M15 VWAP for Stop Loss Calculation ---
   double vwap_M15[];
   ArraySetAsSeries(vwap_M15, true);
   if(CopyBuffer(vwap_handle, 0, 0, 3, vwap_M15) < 3)
   {
      Print("Failed to copy M15 VWAP data for SL calculation");
      return;
   }
   
   int digits = (int)SymbolInfoInteger(SYMBOL, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(SYMBOL, SYMBOL_POINT);
   
   //--- Entry Conditions based on M5 indicators ---
   // Buy: EMA9 crosses above VWAP on M5 and current open is above the M5 VWAP
   if(ema9_5min[2] < vwap_5min[2] && ema9_5min[1] > vwap_5min[1] && open5 > vwap_5min[1])
   {
      // Stop Loss using previous M15 VWAP value
      double sl = NormalizeDouble(vwap_M15[1] - 3 * point, digits);
      if(trade.Buy(FIXED_LOT_SIZE, SYMBOL, open5, sl, 0.0))
      {
         Print("Buy trade opened at M5 open (", open5, ") with SL based on M15 VWAP: ", sl);
      }
   }
   // Sell: EMA9 crosses below VWAP on M5 and current open is below the M5 VWAP
   else if(ema9_5min[2] > vwap_5min[2] && ema9_5min[1] < vwap_5min[1] && open5 < vwap_5min[1])
   {
      double sl = NormalizeDouble(vwap_M15[1] + 3 * point, digits);
      if(trade.Sell(FIXED_LOT_SIZE, SYMBOL, open5, sl, 0.0))
      {
         Print("Sell trade opened at M5 open (", open5, ") with SL based on M15 VWAP: ", sl);
      }
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
         Print("Buy position closed - previous M15 candle closed below EMA9");
      }
   }
   else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      if(close1 > ema9_prev)
      {
         trade.PositionClose(SYMBOL);
         Print("Sell position closed - previous M15 candle closed above EMA9");
      }
   }
}

//+------------------------------------------------------------------+
//| Check for Better Opportunity                                     |
//+------------------------------------------------------------------+
void CheckBetterOpportunity(double &ema9[], double &vwap[])
{
   int digits = (int)SymbolInfoInteger(SYMBOL, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(SYMBOL, SYMBOL_POINT);
   
   if(PositionSelect(SYMBOL))
   {
      long pos_type = PositionGetInteger(POSITION_TYPE);
      // Switch from Sell to Buy
      if(pos_type == POSITION_TYPE_SELL && ema9[2] < vwap[2] && ema9[1] > vwap[1])
      {
         trade.PositionClose(SYMBOL);
         double sl = NormalizeDouble(vwap[1] - 3 * point, digits);
         trade.Buy(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0);
         Print("Switched from Sell to Buy trade");
      }
      // Switch from Buy to Sell
      else if(pos_type == POSITION_TYPE_BUY && ema9[2] > vwap[2] && ema9[1] < vwap[1])
      {
         trade.PositionClose(SYMBOL);
         double sl = NormalizeDouble(vwap[1] + 3 * point, digits);
         trade.Sell(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0);
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
   Print("EA deinitialized. Reason: ", reason);
}
