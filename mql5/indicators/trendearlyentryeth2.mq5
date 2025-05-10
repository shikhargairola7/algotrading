//+------------------------------------------------------------------+
//|                                                       XAUUSD.mq5 |
//|                                    Copyright 2025, Shivam Shikhar |
//|                                                                  |
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

// Indicator handles
int ema9_handle;
int ema50_handle; // Handle for EMA50 (trend filter) on H1
int vwap_handle;  // Handle for custom VWAP indicator

// Global variables
datetime last_bar_time = 0;
const double FIXED_LOT_SIZE = 0.20;
const string SYMBOL = "ETHUSDm";
const ENUM_TIMEFRAMES TIMEFRAME = PERIOD_M15;     // Trading timeframe
const ENUM_TIMEFRAMES TREND_TIMEFRAME = PERIOD_H1; // Trend timeframe

//+------------------------------------------------------------------+
//| Initialization Function                                          |
//+------------------------------------------------------------------+
void OnInit()
{
    // Create EMA9 indicator handle (on M15)
    ema9_handle = iMA(SYMBOL, TIMEFRAME, 9, 0, MODE_EMA, PRICE_CLOSE);
    if(ema9_handle == INVALID_HANDLE)
    {
        Print("Failed to create EMA9 handle. EA will terminate.");
        ExpertRemove();
        return;
    }

    // Create EMA50 indicator handle (on H1)
    ema50_handle = iMA(SYMBOL, TREND_TIMEFRAME, 50, 0, MODE_EMA, PRICE_CLOSE);
    if(ema50_handle == INVALID_HANDLE)
    {
        Print("Failed to create EMA50 handle. EA will terminate.");
        ExpertRemove();
        return;
    }

    // Create handle for custom VWAP indicator (on M15)
    vwap_handle = iCustom(SYMBOL, TIMEFRAME, "VWAP_UTC_Final");
    if(vwap_handle == INVALID_HANDLE)
    {
        Print("Failed to create VWAP handle. EA will terminate.");
        ExpertRemove();
        return;
    }

    trade.SetDeviationInPoints(10); // Allow 1 pip slippage
    Print("EA initialized successfully on ", SYMBOL, " (M15), Trend analysis on H1");
}

//+------------------------------------------------------------------+
//| Main Tick Function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    // // Check for new bar (on M15) - Commenting out to process every tick
    // datetime current_bar_time = iTime(SYMBOL, TIMEFRAME, 0);
    // if(current_bar_time <= last_bar_time)
    //     return;
    // last_bar_time = current_bar_time;

    // Get indicator values
    double ema9[];
    ArraySetAsSeries(ema9, true);
    if(CopyBuffer(ema9_handle, 0, 0, 3, ema9) < 3)
    {
        Print("Failed to copy EMA9 data");
        return;
    }

    // Get EMA50 values from H1 timeframe
    double ema50[];
    ArraySetAsSeries(ema50, true);
    if(CopyBuffer(ema50_handle, 0, 0, 2, ema50) < 2)  // Only need 2 values for trend
    {
        Print("Failed to copy EMA50 data");
        return;
    }

    double vwap[];
    ArraySetAsSeries(vwap, true);
    if(CopyBuffer(vwap_handle, 0, 0, 3, vwap) < 3)
    {
        Print("Failed to copy VWAP data");
        return;
    }

    // Get previous candle's close (on M15)
    double close1 = iClose(SYMBOL, TIMEFRAME, 1);

    // Check and manage existing position (on M15)
    if(PositionSelect(SYMBOL))
    {
        CheckExitCondition(close1, ema9[1]);
        CheckBetterOpportunity(ema9, vwap); // Still on M15
    }
    else
    {
        CheckEntryConditions(ema9, vwap, ema50); // Pass H1 EMA50
    }
}

//+------------------------------------------------------------------+
//| Check Entry Conditions (Trend Filtered on H1)                    |
//+------------------------------------------------------------------+
void CheckEntryConditions(double &ema9[], double &vwap[], double &ema50[])
{
    int digits = (int)SymbolInfoInteger(SYMBOL, SYMBOL_DIGITS);
    double point = SymbolInfoDouble(SYMBOL, SYMBOL_POINT);

    // Determine the trend based on EMA50 on H1
    bool isUptrend  = (ema50[0] > ema50[1]);
    bool isDowntrend = (ema50[0] < ema50[1]);

    // Buy condition: EMA9 crosses above VWAP AND uptrend (on H1)
    if(isUptrend && ema9[1] < vwap[1] && ema9[0] > vwap[0]) // Changed to current and previous values for faster entry
    {
        double sl = NormalizeDouble(vwap[1] - 3 * point, digits);
        if(trade.Buy(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0))
        {
            Print("Buy trade opened IMMEDIATELY with SL: ", sl, " (H1 Uptrend)"); // Modified print for clarity
        }
    }
    // Sell condition: EMA9 crosses below VWAP AND downtrend (on H1)
    else if(isDowntrend && ema9[1] > vwap[1] && ema9[0] < vwap[0]) // Changed to current and previous values for faster entry
    {
        double sl = NormalizeDouble(vwap[1] + 3 * point, digits);
        if(trade.Sell(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0))
        {
            Print("Sell trade opened with SL: ", sl, " (H1 Downtrend)");
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
            Print("Buy position closed - previous candle closed below EMA9");
        }
    }
    else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
    {
        if(close1 > ema9_prev)
        {
            trade.PositionClose(SYMBOL);
            Print("Sell position closed - previous candle closed above EMA9");
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
        // Switch from sell to buy
        if(pos_type == POSITION_TYPE_SELL && ema9[1] < vwap[1] && ema9[0] > vwap[0]) // Changed to current and previous values for faster switching
        {
            trade.PositionClose(SYMBOL);
            double sl = NormalizeDouble(vwap[1] - 3 * point, digits);
            trade.Buy(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0);
            Print("Switched from Sell to Buy trade IMMEDIATELY"); // Modified print for clarity
        }
        // Switch from buy to sell
        else if(pos_type == POSITION_TYPE_BUY && ema9[1] > vwap[1] && ema9[0] < vwap[0]) // Changed to current and previous values for faster switching
        {
            trade.PositionClose(SYMBOL);
            double sl = NormalizeDouble(vwap[1] + 3 * point, digits);
            trade.Sell(FIXED_LOT_SIZE, SYMBOL, 0.0, sl, 0.0);
            Print("Switched from Buy to Sell trade IMMEDIATELY"); // Modified print for clarity
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
    if(ema50_handle != INVALID_HANDLE)  // Release EMA50 handle
        IndicatorRelease(ema50_handle);
    if(vwap_handle != INVALID_HANDLE)
        IndicatorRelease(vwap_handle);
    Print("EA deinitialized. Reason: ", reason);
}
