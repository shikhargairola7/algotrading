//+------------------------------------------------------------------+
//|                                                          BOS.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.00" // Final Version: Production Ready

#include <Trade/Trade.mqh>
CTrade obj_Trade;

//--- Expert Advisor Core Parameters
input group "Core Logic"
input int    length           = 2;      // Swing point strength (bars on each side)
input int    limit            = 2;      // Bar index to check for a swing point
input double LotSize          = 0.01;   // Trading lot size
input ulong  MagicNumber      = 13579;  // EA's magic number for order identification
input string TradeComment     = "BOS_V2"; // Comment for trades

//--- Master & Time Settings
input group "Trade Management"
input bool   EnableTrading    = true;   // Master switch to enable/disable all trading
input bool   Use_Time_Filter  = false;  // Enable the time filter
input int    StartHour        = 9;      // Trading start hour (server time)
input int    EndHour          = 17;     // Trading end hour (server time)

//--- Entry Filters
input group "Entry Signal Filters"
input bool   Use_ADX_Filter   = true;   // [Market Regime] Trade only in trending markets
input int    ADX_Period       = 14;     // ADX calculation period
input double ADX_Threshold    = 23.0;   // Minimum ADX value required to confirm a trend
input bool   Use_Momentum_Confirmation = true; // [Momentum] Require a strong breakout candle
input double Momentum_Body_To_Wick_Ratio = 1.2; // Min ratio of candle body to total wick size
input bool   Use_Volume_Filter   = true;   // [Volume] Require high volume on breakout
input int    Volume_Avg_Period   = 20;     // Period for calculating average volume
input double Volume_Multiplier   = 1.5;    // Multiplier for breakout volume vs. average
input bool   Use_MA_Filter    = false;  // [Trend] Price must be above/below this MA
input int    MA_Period        = 100;    // Moving Average period
input ENUM_MA_METHOD MA_Method= MODE_SMA; // Moving Average method
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE; // Price to apply MA on

//--- Stop Loss Settings
input group "Stop Loss Configuration"
input bool   Use_ATR_SL         = true;     // Use ATR for Stop Loss (recommended)
input int    ATR_Period         = 14;     // ATR period for SL calculation
input double ATR_SL_Multiplier  = 2.0;    // ATR multiplier for Stop Loss
input int    Fixed_StopLoss_Points = 3500;  // Fallback SL if ATR is disabled

//--- Exit & Profit Management
input group "Exit & Profit Management"
input bool   Use_Dynamic_TP       = true;     // Use a Risk/Reward based Take Profit
input double Reward_To_Risk_Ratio   = 1.5;    // TP will be this multiple of the SL distance
input int    Fixed_TakeProfit_Points = 5000;  // Fallback TP if Dynamic TP is disabled
input bool   Use_Auto_Breakeven   = true;     // Automatically move SL to breakeven
input int    BreakEven_Trigger_Points = 300;  // Points in profit to trigger Auto-Breakeven
input int    BreakEven_Lock_In_Points = 20;   // Points to lock in beyond entry price
input bool   Use_ATR_Trailing_SL    = true;   // Enable ATR Trailing SL after breakeven
input double Trail_Start_Points     = 500;    // Points in profit to activate trailing (should be > BE Trigger)
input int    Trail_ATR_Period       = 14;     // ATR Period for trailing
input double Trail_ATR_Multiplier   = 1.0;    // ATR Multiplier for trailing distance

//--- Global Indicator Handles
int ma_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;
int trail_atr_handle = INVALID_HANDLE;
int adx_handle = INVALID_HANDLE;

//--- Forward declarations
bool HasOpenTrade();
void ManageTradeExits();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   obj_Trade.SetExpertMagicNumber(MagicNumber);
   
   if(Use_MA_Filter)
      ma_handle = iMA(_Symbol, _Period, MA_Period, 0, MA_Method, MA_Price);
   if(Use_ATR_SL)
      atr_handle = iATR(_Symbol, _Period, ATR_Period);
   if(Use_ATR_Trailing_SL)
      trail_atr_handle = iATR(_Symbol, _Period, Trail_ATR_Period);
   if(Use_ADX_Filter)
      adx_handle = iADX(_Symbol, _Period, ADX_Period);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ma_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(trail_atr_handle);
   IndicatorRelease(adx_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!EnableTrading) return;
   
   // Manage exits for any open positions first
   ManageTradeExits();

   // Do not look for new trades if one is already open
   if(HasOpenTrade()) return;

   // Check if trading is allowed at the current time
   if(Use_Time_Filter)
     {
      MqlDateTime dt; TimeCurrent(dt); int currentHour = dt.hour;
      if(StartHour < EndHour) { if(currentHour < StartHour || currentHour >= EndHour) return; }
      else { if(currentHour < StartHour && currentHour >= EndHour) return; }
     }

   // --- New Bar Detection ---
   static bool isNewBar = false;
   int currBars = iBars(_Symbol, _Period);
   static int prevBars = currBars;
   if(prevBars == currBars) isNewBar = false;
   else { isNewBar = true; prevBars = currBars; }

   // Static variables to hold the latest swing point data
   static double swing_H = -1.0, swing_L = -1.0;
   static datetime swing_H_time = 0, swing_L_time = 0;
   
   if(isNewBar)
     {
      // --- Swing Point Identification ---
      int right_index, left_index;
      bool isSwingHigh=true, isSwingLow=true;
      int curr_bar = limit;

      for(int j=1; j<=length; j++)
        {
         right_index = curr_bar - j; left_index = curr_bar + j;
         if((high(curr_bar) <= high(right_index)) || (high(curr_bar) < high(left_index))) isSwingHigh = false;
         if((low(curr_bar) >= low(right_index)) || (low(curr_bar) > low(left_index))) isSwingLow = false;
        }
      if(isSwingHigh)
        {
         swing_H = high(curr_bar);
         swing_H_time = time(curr_bar);
         drawSwingPoint(TimeToString(time(curr_bar)), time(curr_bar), high(curr_bar), 77, clrBlue, -1);
        }
      if(isSwingLow)
        {
         swing_L = low(curr_bar);
         swing_L_time = time(curr_bar);
         drawSwingPoint(TimeToString(time(curr_bar)), time(curr_bar), low(curr_bar), 77, clrRed, 1);
        }

      // --- SIGNAL CHECKING & FILTERING ---
      bool isBuySignal = (swing_H > 0 && high(1) > swing_H && close(1) > swing_H);
      bool isSellSignal = (swing_L > 0 && low(1) < swing_L && close(1) < swing_L);

      if(isBuySignal || isSellSignal)
        {
         bool signal_valid = true;
         
         // --- Filter Cascade ---
         if(Use_ADX_Filter) {
            double adx_buffer[1];
            if(CopyBuffer(adx_handle, 0, 1, 1, adx_buffer) > 0 && adx_buffer[0] < ADX_Threshold) signal_valid = false;
         }
         if(signal_valid && Use_Momentum_Confirmation) {
            double c_open=open(1), c_close=close(1), c_high=high(1), c_low=low(1);
            if(isBuySignal && c_close <= c_open) signal_valid = false;
            if(isSellSignal && c_close >= c_open) signal_valid = false;
            if(signal_valid) {
               double body = MathAbs(c_close - c_open);
               double wicks = (c_high - MathMax(c_open, c_close)) + (MathMin(c_open, c_close) - c_low);
               if(wicks > 0 && (body / wicks) < Momentum_Body_To_Wick_Ratio) signal_valid = false;
            }
         }
         if(signal_valid && Use_Volume_Filter) {
            long vol_buf[]; ArraySetAsSeries(vol_buf, true);
            if(CopyTickVolume(_Symbol, _Period, 1, Volume_Avg_Period, vol_buf) > 0) {
               long avg_vol = 0;
               for(int k=1; k < Volume_Avg_Period; k++) avg_vol += vol_buf[k];
               avg_vol /= (Volume_Avg_Period - 1);
               if(vol_buf[0] < avg_vol * Volume_Multiplier) signal_valid = false;
            }
         }
         if(signal_valid && Use_MA_Filter) {
            double ma_buf[1];
            if(CopyBuffer(ma_handle, 0, 1, 1, ma_buf) > 0) {
               if(isBuySignal && close(1) < ma_buf[0]) signal_valid = false;
               if(isSellSignal && close(1) > ma_buf[0]) signal_valid = false;
            }
         }

         // --- TRADE EXECUTION ---
         if(signal_valid) {
            if(isBuySignal) {
               Print("VALID BUY SIGNAL. Executing trade.");
               drawBreakLevel(TimeToString(time(1)), swing_H_time, swing_H, time(1), swing_H, clrBlue, -1);
               double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double sl, tp;
               if(Use_ATR_SL) {
                  double atr_val[1];
                  sl = (CopyBuffer(atr_handle, 0, 1, 1, atr_val) > 0) ? Ask - (atr_val[0] * ATR_SL_Multiplier) : Ask - Fixed_StopLoss_Points * _Point;
               } else { sl = Ask - Fixed_StopLoss_Points * _Point; }
               tp = Use_Dynamic_TP ? Ask + ((Ask - sl) * Reward_To_Risk_Ratio) : Ask + Fixed_TakeProfit_Points * _Point;
               obj_Trade.Buy(LotSize, _Symbol, Ask, sl, tp, TradeComment + " BUY");
               swing_H = -1.0; swing_H_time = 0;
            }
            if(isSellSignal) {
               Print("VALID SELL SIGNAL. Executing trade.");
               drawBreakLevel(TimeToString(time(1)), swing_L_time, swing_L, time(1), swing_L, clrRed, 1);
               double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double sl, tp;
               if(Use_ATR_SL) {
                  double atr_val[1];
                  sl = (CopyBuffer(atr_handle, 0, 1, 1, atr_val) > 0) ? Bid + (atr_val[0] * ATR_SL_Multiplier) : Bid + Fixed_StopLoss_Points * _Point;
               } else { sl = Bid + Fixed_StopLoss_Points * _Point; }
               tp = Use_Dynamic_TP ? Bid - ((sl - Bid) * Reward_To_Risk_Ratio) : Bid - Fixed_TakeProfit_Points * _Point;
               obj_Trade.Sell(LotSize, _Symbol, Bid, sl, tp, TradeComment + " SELL");
               swing_L = -1.0; swing_L_time = 0;
            }
         }
        }
     }
  }
//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

//--- Checks if a trade is already open by this EA
bool HasOpenTrade()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return(true);
   }
   return(false);
  }
  
//--- Manages all exit logic for open positions
void ManageTradeExits()
  {
   bool isTrailingActive = Use_ATR_Trailing_SL;
   bool isBreakevenActive = Use_Auto_Breakeven;
   if(!isTrailingActive && !isBreakevenActive) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_sl = PositionGetDouble(POSITION_SL);
         double current_tp = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         // --- Auto-Breakeven Logic ---
         if(isBreakevenActive) {
            if(type == POSITION_TYPE_BUY && current_sl < open_price) {
               if(SymbolInfoDouble(_Symbol, SYMBOL_BID) > open_price + BreakEven_Trigger_Points * _Point) {
                  double new_sl = NormalizeDouble(open_price + BreakEven_Lock_In_Points * _Point, _Digits);
                  if(new_sl > current_sl) {
                     obj_Trade.PositionModify(ticket, new_sl, current_tp);
                     current_sl = new_sl; // Update current_sl for trailing stop logic below
                  }
               }
            }
            if(type == POSITION_TYPE_SELL && (current_sl > open_price || current_sl == 0)) {
               if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) < open_price - BreakEven_Trigger_Points * _Point) {
                  double new_sl = NormalizeDouble(open_price - BreakEven_Lock_In_Points * _Point, _Digits);
                  if(new_sl < current_sl || current_sl == 0) {
                     obj_Trade.PositionModify(ticket, new_sl, current_tp);
                     current_sl = new_sl;
                  }
               }
            }
         }
         
         // --- ATR Trailing Stop Logic ---
         if(isTrailingActive) {
            double atr_buffer[1];
            if(CopyBuffer(trail_atr_handle, 0, 0, 1, atr_buffer) > 0) {
               double atr_value = atr_buffer[0];
               if(type == POSITION_TYPE_BUY) {
                  if(SymbolInfoDouble(_Symbol, SYMBOL_BID) > open_price + Trail_Start_Points * _Point) {
                     double new_sl = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - (atr_value * Trail_ATR_Multiplier), _Digits);
                     if(new_sl > current_sl) {
                        obj_Trade.PositionModify(ticket, new_sl, current_tp);
                     }
                  }
               }
               if(type == POSITION_TYPE_SELL) {
                  if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) < open_price - Trail_Start_Points * _Point) {
                     double new_sl = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + (atr_value * Trail_ATR_Multiplier), _Digits);
                     if(new_sl < current_sl || current_sl == 0) {
                        obj_Trade.PositionModify(ticket, new_sl, current_tp);
                     }
                  }
               }
            }
         }
         break; // Found our trade, exit loop
        }
     }
  }

//--- Standard Drawing Functions
double high(int index) { return(iHigh(_Symbol,_Period,index)); }
double low(int index) { return(iLow(_Symbol,_Period,index)); }
double close(int index) { return(iClose(_Symbol,_Period,index)); }
double open(int index) { return(iOpen(_Symbol,_Period,index)); }
datetime time(int index) { return(iTime(_Symbol,_Period,index)); }
void drawSwingPoint(string objName,datetime time,double price,int arrCode, color clr,int direction) {
   if(ObjectFind(0,objName)<0) {
      ObjectCreate(0,objName,OBJ_ARROW,0,time,price);
      ObjectSetInteger(0,objName,OBJPROP_ARROWCODE,arrCode);
      ObjectSetInteger(0,objName,OBJPROP_COLOR,clr);
      if(direction > 0) ObjectSetInteger(0,objName,OBJPROP_ANCHOR,ANCHOR_TOP);
      if(direction < 0) ObjectSetInteger(0,objName,OBJPROP_ANCHOR,ANCHOR_BOTTOM);
   }
}
void drawBreakLevel(string objName,datetime time1,double price1, datetime time2,double price2,color clr,int direction) {
   if(ObjectFind(0,objName)<0) {
      ObjectCreate(0,objName,OBJ_ARROWED_LINE,0,time1,price1,time2,price2);
      ObjectSetInteger(0,objName,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,objName,OBJPROP_WIDTH,1);
   }
}