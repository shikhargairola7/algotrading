//+------------------------------------------------------------------+
//|        Zone Breakout Retest EA (UTC Based)                    |
//|        Version 2.1.2 - Final Compatibility Fixes               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025,Shikhar Shivam "
#property link      "@artificialintelligencefacts"
#property version   "2.1.2" // Updated version
#property strict

#include <Trade/Trade.mqh>
CTrade obj_Trade;

// ### Define Character Codes for Visuals ###
#define SYMBOL_CODE_ARROW_UP        233
#define SYMBOL_CODE_ARROW_DOWN      234
#define SYMBOL_CODE_TRIANGLE        113 // Used for retest touch
#define SYMBOL_CODE_THUMBS_UP       67
#define SYMBOL_CODE_DOT             159

// ### EA Magic Number ###
const int EA_MAGIC_NUMBER = 12345;

// ### Input Parameters ###
input group "Zone Definition (UTC Times)"
input int ZoneStartHourUTC = 22;           // Start hour of zone in UTC
input int ZoneStartMinuteUTC = 5;          // Start minute of zone in UTC
input int ZoneEndHourUTC = 0;              // End hour of zone in UTC
input int ZoneEndMinuteUTC = 0;            // End minute of zone in UTC
input ENUM_TIMEFRAMES ZoneTimeframe = PERIOD_M15; // Timeframe for zone definition

input group "Breakout & Entry Parameters"
input ENUM_TIMEFRAMES BreakoutDetectionTimeframe = PERIOD_M1; // Timeframe for breakout detection (1st Trade)
input ENUM_TIMEFRAMES EntryTimeframe = PERIOD_M1;              // Timeframe for retest and entry (1st Trade)
input double LotSize = 0.01;              // Fixed lot size for trading
input int InpSlippage = 3;                // Max deviation in points for order execution

input group "StopLoss & TakeProfit (Pip Based)"
input double PipSize = 0.1;            // Pip size in price units, e.g., 0.0001 for EURUSD, 0.01 for USDJPY, 0.1 for XAUUSD
input double MaxSL_Pips = 20.0;           // Max SL in pips. 0 to use only natural zone SL
input double TP_Pips = 100.0;              // TP in pips. 0 to use dynamic/zone based

input group "Liquidity Confirmation (FVG)"
input bool UseFVGConfirmation = true;         // Enable FVG confirmation for entry
input int  FVGMaxPatternsToCheck = 3;         // How many recent 3-bar patterns to check for an FVG on EntryTimeframe

input group "Cycle Management (UTC Times)"
input int CycleResetTriggerHourUTC = 21;  // Hour in UTC to reset daily cycle
input int MaxTradesPerCycle = 2;          // Maximum number of trades this EA can take in one cycle

input group "Conditional Trading (2nd Trade+)"
input bool UseConditionalTrading = true;        // Enable special logic for 2nd trade onwards
input int  CooldownMinutesAfterLoss = 60;      // Time to wait in minutes after a loss before re-entering
input ENUM_TIMEFRAMES BreakoutDetectionTimeframe_2nd = PERIOD_M5; // Breakout TF for 2nd+ trade
input ENUM_TIMEFRAMES EntryTimeframe_2nd = PERIOD_M5;             // Entry TF for 2nd+ trade

input group "Trade Management - Breakeven"
input double BreakEvenPips = 15.0;         // Pips in profit to trigger Breakeven. 0 to disable.
input double BreakEvenSecurePips = 2.0;    // Pips to secure above/below entry for BE.

input group "Trade Management - Secure Profit & ATR Trailing"
input double SecureProfitTargetPips = 150.0; // Pips in profit to trigger Secure Profit SL adjustment. 0 to disable.
input double SecureProfitLockPips = 100.0;   // Pips above/below entry to lock SL once Target is hit. 0 to disable this stage effectively
input bool   EnableATRTrailing = true;       // Enable ATR Trailing SL after Secure Profit/BE is locked.
input ENUM_TIMEFRAMES ATRTrailingTimeframe = PERIOD_CURRENT; // Timeframe for ATR calculation (PERIOD_CURRENT = chart TF)
input int    ATRTrailingPeriod = 14;         // Period for ATR
input double ATRTrailingMultiplier = 2.5;    // Multiplier for ATR

// ### Global Variables ###
// Zone State
double zone_high_price = -DBL_MAX;
double zone_low_price = DBL_MAX;
datetime zone_formation_start_time_utc;
datetime zone_formation_end_time_utc;
datetime trade_window_end_time_utc;

// Flags & Counters
bool isZoneDefined = false;
bool isH1ZoneBrokenOut = false;
int  h1_breakout_direction = 0;  // 1 for bullish, -1 for bearish
double h1_breakout_level = 0.0;
bool isRetestLevelTouched = false;
bool hasPriceReEnteredZoneAfterBreakout = false;
int tradesTakenThisCycleCount = 0;
bool isWindowExpiredMessageShown = false;

// Conditional trading variables
bool stop_cycle_on_profit_flag = false;
datetime cooldown_end_time_utc = 0;
ulong last_open_position_ticket = 0;

// Daily Cycle Management
static datetime current_cycle_day_start_utc = 0;
static bool initial_setup_done_for_cycle = false;

// Object Prefixes for Chart Objects
#define RECTANGLE_PREFIX "H1_ZONE_RECT_"
#define UPPER_LINE_PREFIX "ZONE_UPPER_LINE_"
#define LOWER_LINE_PREFIX "ZONE_LOWER_LINE_"
#define BREAKOUT_MARKER_PREFIX "ZONE_BREAKOUT_"
#define RETEST_MARKER_PREFIX "RETEST_POINT_"
#define FVG_RECT_PREFIX "FVG_RECT_"

// New Bar Detection (Server Time Based)
static datetime last_H1_bar_time_zone_calc;
static datetime last_BreakoutTF_bar_time_breakout_check;
static datetime last_EntryTF_bar_time_retest_check;

// ### Struct for FVG ###
struct PriceLevel {
    double high;
    double low;
    datetime time;
    bool   isValid;
};

// ### Function Definitions ###
void HandleTradeHistory();

long GetGMTOffsetSeconds()
{
   return (long)TimeTradeServer() - (long)TimeGMT();
}

bool HasOpenTradeByEA() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER) {
            return true;
        }
    }
    return false;
}

int OnInit()
{
   current_cycle_day_start_utc = 0;
   initial_setup_done_for_cycle = false;
   last_H1_bar_time_zone_calc = 0;
   last_BreakoutTF_bar_time_breakout_check = 0;
   last_EntryTF_bar_time_retest_check = 0;
   tradesTakenThisCycleCount = 0;
   isRetestLevelTouched = false;
   hasPriceReEnteredZoneAfterBreakout = false;

   obj_Trade.SetExpertMagicNumber(EA_MAGIC_NUMBER);
   obj_Trade.SetDeviationInPoints((uint)InpSlippage);
   obj_Trade.SetTypeFillingBySymbol(_Symbol);

   if(ZoneTimeframe != PERIOD_H1) Alert("Warning: ZoneTimeframe is not H1. Functionality might be affected.");
   if(BreakoutDetectionTimeframe >= ZoneTimeframe && PeriodSeconds(BreakoutDetectionTimeframe) > 0 && PeriodSeconds(ZoneTimeframe) > 0) Alert("Warning: BreakoutDetectionTimeframe should be smaller than ZoneTimeframe.");
   if(PipSize <= 0) { Alert("PipSize must be > 0."); return INIT_PARAMETERS_INCORRECT; }
   if(LotSize <= 0) { Alert("LotSize must be > 0."); return INIT_PARAMETERS_INCORRECT; }
   if(FVGMaxPatternsToCheck < 1) { Alert("FVGMaxPatternsToCheck must be >= 1."); return INIT_PARAMETERS_INCORRECT; }
   if(MaxTradesPerCycle < 1) { Alert(StringFormat("MaxTradesPerCycle (%d) invalid. Must be >= 1.", MaxTradesPerCycle)); return INIT_PARAMETERS_INCORRECT; }
   if(BreakEvenPips > 0 && BreakEvenSecurePips < 0) { Alert(StringFormat("BreakEvenSecurePips (%.2f) invalid with BreakEvenPips (%.2f).", BreakEvenSecurePips, BreakEvenPips)); return INIT_PARAMETERS_INCORRECT; }
   if(SecureProfitTargetPips < 0) { Alert("SecureProfitTargetPips cannot be negative. Set to 0 to disable."); return INIT_PARAMETERS_INCORRECT;}
   if(SecureProfitLockPips < 0) { Alert("SecureProfitLockPips cannot be negative."); return INIT_PARAMETERS_INCORRECT;}
   if(SecureProfitTargetPips > 0 && SecureProfitLockPips <=0 && SecureProfitTargetPips > 0) { Alert(StringFormat("SecureProfitLockPips (%.2f) must be > 0 if SecureProfitTargetPips (%.2f) is > 0.", SecureProfitLockPips, SecureProfitTargetPips)); return INIT_PARAMETERS_INCORRECT; }
   if(EnableATRTrailing && ATRTrailingPeriod < 1) { Alert("ATRTrailingPeriod must be >= 1."); return INIT_PARAMETERS_INCORRECT; }
   if(EnableATRTrailing && ATRTrailingMultiplier <= 0) { Alert("ATRTrailingMultiplier must be > 0."); return INIT_PARAMETERS_INCORRECT; }
   if(UseConditionalTrading && CooldownMinutesAfterLoss < 0) { Alert("CooldownMinutesAfterLoss cannot be negative."); return INIT_PARAMETERS_INCORRECT; }

   PrintFormat("EA Initialized. Name: %s, Magic: %d, LotSize: %.2f, PipSize: %.5f", MQLInfoString(MQL_PROGRAM_NAME), EA_MAGIC_NUMBER, LotSize, PipSize);
   PrintFormat("SL: %.2f pips, TP: %.2f pips, FVG Confirm: %s, FVG Check: %d patterns", MaxSL_Pips, TP_Pips, UseFVGConfirmation ? "Enabled" : "Disabled", FVGMaxPatternsToCheck);
   PrintFormat("Max Trades/Cycle: %d", MaxTradesPerCycle);
   if(UseConditionalTrading) {
      PrintFormat("Conditional Trading Enabled: Cooldown After Loss: %d mins. 2nd+ Trade TFs: %s (Breakout), %s (Entry)",
                  CooldownMinutesAfterLoss, EnumToString(BreakoutDetectionTimeframe_2nd), EnumToString(EntryTimeframe_2nd));
   }
   PrintFormat("BE: %.1fp (sec. %.1fp). SP: Targ. %.1fp, Lock %.1fp. ATR Trail: %s (TF: %s, Per: %d, Mult: %.1f)",
                BreakEvenPips, BreakEvenSecurePips,
                SecureProfitTargetPips, SecureProfitLockPips,
                EnableATRTrailing ? "On" : "Off",
                EnumToString(ATRTrailingTimeframe == PERIOD_CURRENT ? Period() : ATRTrailingTimeframe),
                ATRTrailingPeriod, ATRTrailingMultiplier);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   string day_str_part = TimeToString(current_cycle_day_start_utc, TIME_DATE);
   day_str_part = StringReplace(day_str_part, ".", "_");

   ObjectsDeleteAll(0, RECTANGLE_PREFIX + day_str_part);
   ObjectsDeleteAll(0, UPPER_LINE_PREFIX + day_str_part);
   ObjectsDeleteAll(0, LOWER_LINE_PREFIX + day_str_part);
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + day_str_part);
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + day_str_part + "_UP");
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + day_str_part + "_DOWN");
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + day_str_part + "_REV_UP");
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + day_str_part + "_REV_DOWN");
   ObjectsDeleteAll(0, RETEST_MARKER_PREFIX + day_str_part + "_BULLTOUCH_CONFIRM");
   ObjectsDeleteAll(0, RETEST_MARKER_PREFIX + day_str_part + "_BEARTOUCH_CONFIRM");
   ObjectsDeleteAll(0, RETEST_MARKER_PREFIX + day_str_part + "_BUYENTRY");
   ObjectsDeleteAll(0, RETEST_MARKER_PREFIX + day_str_part + "_SELLENTRY");
   ObjectsDeleteAll(0, FVG_RECT_PREFIX + day_str_part + "_BULL");
   ObjectsDeleteAll(0, FVG_RECT_PREFIX + day_str_part + "_BEAR");

   PrintFormat("EA Deinitialized. Objects for cycle starting %s cleared.", TimeToString(current_cycle_day_start_utc, TIME_DATE));
}

void OnTick()
{
   datetime current_utc_time = TimeGMT();
   ManageDailyCycle(current_utc_time);

   if(UseConditionalTrading) HandleTradeHistory();

   if (!initial_setup_done_for_cycle) {
      Comment(StringFormat("Waiting for cycle setup at/after %s:00 UTC for day: %s", IntegerToString(CycleResetTriggerHourUTC), TimeToString(current_cycle_day_start_utc, TIME_DATE)));
      return;
   }

   if(UseConditionalTrading) {
      if(stop_cycle_on_profit_flag) {
         Comment("Trading stopped for the cycle due to a profitable trade.");
         return;
      }
      if(current_utc_time < cooldown_end_time_utc) {
         Comment(StringFormat("Cooldown active after loss. Waiting until %s UTC.", TimeToString(cooldown_end_time_utc, TIME_DATE|TIME_MINUTES)));
         return;
      }
   }
   Comment("");

   if (!isZoneDefined && current_utc_time >= zone_formation_end_time_utc && initial_setup_done_for_cycle) DefineH1Zone();

   if (isZoneDefined && current_utc_time < trade_window_end_time_utc) CheckZoneBreakoutOnSelectedTF();
   
   bool can_look_for_trade = isH1ZoneBrokenOut &&
                             tradesTakenThisCycleCount < MaxTradesPerCycle &&
                             !HasOpenTradeByEA() &&
                             current_utc_time < trade_window_end_time_utc;

   if (UseConditionalTrading) {
       if (stop_cycle_on_profit_flag || current_utc_time < cooldown_end_time_utc) {
           can_look_for_trade = false;
       }
   }

   if (can_look_for_trade) {
       CheckRetestAndEntry(current_utc_time);
   }

   ManageOpenTrades();

   if (isZoneDefined && tradesTakenThisCycleCount == 0 && current_utc_time >= trade_window_end_time_utc) {
      if (!isWindowExpiredMessageShown) {
         PrintFormat("Trading window expired at %s UTC for cycle starting %s. No trade taken this cycle.", TimeToString(trade_window_end_time_utc, TIME_DATE|TIME_MINUTES), TimeToString(current_cycle_day_start_utc, TIME_DATE));
         Comment("Trading Window Expired. No trades this cycle.");
         isWindowExpiredMessageShown = true;
      }
   } else if (isZoneDefined && tradesTakenThisCycleCount >= MaxTradesPerCycle && current_utc_time >= trade_window_end_time_utc) {
        if (!isWindowExpiredMessageShown) {
            PrintFormat("Trading window expired at %s UTC for cycle starting %s. Max trades for cycle (%d) reached or trade open.", TimeToString(trade_window_end_time_utc, TIME_DATE|TIME_MINUTES), TimeToString(current_cycle_day_start_utc, TIME_DATE), MaxTradesPerCycle);
            Comment(StringFormat("Window Expired. Max trades (%d) reached or trade open.", MaxTradesPerCycle));
            isWindowExpiredMessageShown = true;
        }
    }
    ChartRedraw(0);
}

void ManageDailyCycle(datetime current_utc_time)
{
   MqlDateTime dt_current_utc; TimeToStruct(current_utc_time, dt_current_utc);
   MqlDateTime dt_today_00_struct;
   dt_today_00_struct.year = dt_current_utc.year; dt_today_00_struct.mon  = dt_current_utc.mon; dt_today_00_struct.day  = dt_current_utc.day;
   dt_today_00_struct.hour = 0; dt_today_00_struct.min  = 0; dt_today_00_struct.sec  = 0;
   datetime today_00_utc = StructToTime(dt_today_00_struct);
   bool needs_new_cycle_setup = false;
   if (current_cycle_day_start_utc == 0) { needs_new_cycle_setup = true; current_cycle_day_start_utc = today_00_utc; }
   else if (today_00_utc > current_cycle_day_start_utc) { if (dt_current_utc.hour >= CycleResetTriggerHourUTC) { needs_new_cycle_setup = true; current_cycle_day_start_utc = today_00_utc; } }
   else if (today_00_utc == current_cycle_day_start_utc && !initial_setup_done_for_cycle) { if (dt_current_utc.hour >= CycleResetTriggerHourUTC) { needs_new_cycle_setup = true; } }
   if (needs_new_cycle_setup) {
      PrintFormat("New cycle triggered at %s UTC for cycle starting %s UTC.", TimeToString(current_utc_time, TIME_DATE|TIME_SECONDS), TimeToString(current_cycle_day_start_utc, TIME_DATE));
      SetupNewCycle(current_cycle_day_start_utc);
      initial_setup_done_for_cycle = true;
      PrintFormat("Cycle setup complete for day starting %s UTC.", TimeToString(current_cycle_day_start_utc, TIME_DATE));
   }
}

void SetupNewCycle(datetime cycle_base_utc_date)
{
   string cycle_date_str_part = TimeToString(cycle_base_utc_date, TIME_DATE);
   cycle_date_str_part = StringReplace(cycle_date_str_part, ".", "_");
   ResetCycleVariables(cycle_date_str_part);
   CalculateCycleTimings(cycle_base_utc_date);
}

void ResetCycleVariables(string cycle_date_str_for_objects)
{
   PrintFormat("Resetting cycle variables for %s.", cycle_date_str_for_objects);
   isZoneDefined = false;
   isH1ZoneBrokenOut = false;
   h1_breakout_direction = 0;
   h1_breakout_level = 0.0;
   isRetestLevelTouched = false;
   hasPriceReEnteredZoneAfterBreakout = false;
   tradesTakenThisCycleCount = 0;
   isWindowExpiredMessageShown = false;
   zone_high_price = -DBL_MAX; zone_low_price = DBL_MAX;
   zone_formation_start_time_utc = 0; zone_formation_end_time_utc = 0; trade_window_end_time_utc = 0;
   last_H1_bar_time_zone_calc = 0; last_BreakoutTF_bar_time_breakout_check = 0; last_EntryTF_bar_time_retest_check = 0;
   
   stop_cycle_on_profit_flag = false;
   cooldown_end_time_utc = 0;
   last_open_position_ticket = 0;

   ObjectsDeleteAll(0, RECTANGLE_PREFIX + cycle_date_str_for_objects);
   ObjectsDeleteAll(0, UPPER_LINE_PREFIX + cycle_date_str_for_objects);
   ObjectsDeleteAll(0, LOWER_LINE_PREFIX + cycle_date_str_for_objects);
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + cycle_date_str_for_objects);
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + cycle_date_str_for_objects + "_UP");
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + cycle_date_str_for_objects + "_DOWN");
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + cycle_date_str_for_objects + "_REV_UP");
   ObjectsDeleteAll(0, BREAKOUT_MARKER_PREFIX + cycle_date_str_for_objects + "_REV_DOWN");
   ObjectsDeleteAll(0, RETEST_MARKER_PREFIX + cycle_date_str_for_objects + "_BULLTOUCH_CONFIRM");
   ObjectsDeleteAll(0, RETEST_MARKER_PREFIX + cycle_date_str_for_objects + "_BEARTOUCH_CONFIRM");
   ObjectsDeleteAll(0, RETEST_MARKER_PREFIX + cycle_date_str_for_objects + "_BUYENTRY");
   ObjectsDeleteAll(0, RETEST_MARKER_PREFIX + cycle_date_str_for_objects + "_SELLENTRY");
   ObjectsDeleteAll(0, FVG_RECT_PREFIX + cycle_date_str_for_objects + "_BULL");
   ObjectsDeleteAll(0, FVG_RECT_PREFIX + cycle_date_str_for_objects + "_BEAR");
}

void CalculateCycleTimings(datetime base_day_00_utc)
{
   MqlDateTime dt_calc_start, dt_calc_end; TimeToStruct(base_day_00_utc, dt_calc_start);
   dt_calc_start.hour = ZoneStartHourUTC; dt_calc_start.min = ZoneStartMinuteUTC; dt_calc_start.sec = 0;
   zone_formation_start_time_utc = StructToTime(dt_calc_start);
   TimeToStruct(base_day_00_utc, dt_calc_end);
   dt_calc_end.hour = ZoneEndHourUTC; dt_calc_end.min = ZoneEndMinuteUTC; dt_calc_end.sec = 0;
   datetime temp_zone_end_time_utc = StructToTime(dt_calc_end);
   if (temp_zone_end_time_utc <= zone_formation_start_time_utc && !(ZoneStartHourUTC == ZoneEndHourUTC && ZoneStartMinuteUTC == ZoneEndMinuteUTC)) {
      zone_formation_end_time_utc = temp_zone_end_time_utc + (24 * 3600);
   } else { zone_formation_end_time_utc = temp_zone_end_time_utc; }
   if (zone_formation_end_time_utc <= zone_formation_start_time_utc) {
      PrintFormat("Warning: Zone End Time (%s) <= Zone Start Time (%s). Adjusting end time +1 hour.", TimeToString(zone_formation_end_time_utc, TIME_DATE|TIME_MINUTES), TimeToString(zone_formation_start_time_utc, TIME_DATE|TIME_MINUTES));
      zone_formation_end_time_utc = zone_formation_start_time_utc + 3600;
   }
   trade_window_end_time_utc = zone_formation_end_time_utc + (long)(6 * 3600);
   PrintFormat("Cycle Timings for base day %s (UTC):", TimeToString(base_day_00_utc, TIME_DATE));
   PrintFormat("  Zone Start: %s", TimeToString(zone_formation_start_time_utc, TIME_DATE|TIME_MINUTES));
   PrintFormat("  Zone End:   %s", TimeToString(zone_formation_end_time_utc, TIME_DATE|TIME_MINUTES));
   PrintFormat("  Trade End:  %s", TimeToString(trade_window_end_time_utc, TIME_DATE|TIME_MINUTES));
}

void DefineH1Zone()
{
   datetime current_zone_tf_bar_time_server = iTime(_Symbol, ZoneTimeframe, 0);
   if (current_zone_tf_bar_time_server == last_H1_bar_time_zone_calc && isZoneDefined) return;
   last_H1_bar_time_zone_calc = current_zone_tf_bar_time_server;
   PrintFormat("Defining %s zone boundaries...", EnumToString(ZoneTimeframe));
   double temp_high = -DBL_MAX; double temp_low = DBL_MAX; bool data_found_in_zone = false;
   long gmt_offset_seconds = GetGMTOffsetSeconds();
   datetime zone_start_server_time = zone_formation_start_time_utc - gmt_offset_seconds;
   datetime zone_end_server_time = zone_formation_end_time_utc - gmt_offset_seconds;
   int bars_to_scan = (int)((zone_end_server_time - zone_start_server_time) / PeriodSeconds(ZoneTimeframe)) + 48;
   if (bars_to_scan > iBars(_Symbol, ZoneTimeframe)) bars_to_scan = iBars(_Symbol, ZoneTimeframe);
   if (bars_to_scan > 500) bars_to_scan = 500; if (bars_to_scan < 5) bars_to_scan = 5;
   for (int i = 0; i <= bars_to_scan && i < Bars(_Symbol, ZoneTimeframe); i++) {
      datetime bar_open_time_server = iTime(_Symbol, ZoneTimeframe, i);
      if (bar_open_time_server < (zone_start_server_time - PeriodSeconds(ZoneTimeframe)) && data_found_in_zone && i > 0) break;
      if (!data_found_in_zone && bar_open_time_server < (zone_start_server_time - 2 * 24 * 3600) && i > (2 * 24 * PeriodSeconds(ZoneTimeframe)/3600) ) break;
      if (bar_open_time_server >= zone_start_server_time && bar_open_time_server < zone_end_server_time) {
         double bar_high = iHigh(_Symbol, ZoneTimeframe, i); double bar_low = iLow(_Symbol, ZoneTimeframe, i);
         if (bar_high > temp_high) temp_high = bar_high;
         if (bar_low < temp_low && bar_low > 0) temp_low = bar_low;
         data_found_in_zone = true;
      }
   }
   if (data_found_in_zone && temp_high > -DBL_MAX && temp_low < DBL_MAX && temp_high > temp_low) {
      zone_high_price = NormalizeDouble(temp_high, _Digits); zone_low_price = NormalizeDouble(temp_low, _Digits);
      isZoneDefined = true;
      PrintFormat("%s Zone Defined: High %.5f, Low %.5f (UTC %s to %s)", EnumToString(ZoneTimeframe), zone_high_price, zone_low_price, TimeToString(zone_formation_start_time_utc, TIME_DATE|TIME_MINUTES), TimeToString(zone_formation_end_time_utc, TIME_DATE|TIME_MINUTES));
      string cycle_date_str_part = TimeToString(current_cycle_day_start_utc, TIME_DATE); cycle_date_str_part = StringReplace(cycle_date_str_part, ".", "_");
      datetime rect_time_end_visual = zone_end_server_time; datetime line_time_end_visual = zone_end_server_time + (long)(7 * 24 * 3600);
      create_Rectangle(RECTANGLE_PREFIX + cycle_date_str_part, zone_start_server_time, zone_high_price, rect_time_end_visual, zone_low_price, clrAliceBlue);
      create_Line(UPPER_LINE_PREFIX + cycle_date_str_part, zone_start_server_time, zone_high_price, line_time_end_visual, zone_high_price, 2, clrDodgerBlue, "Zone H: " + DoubleToString(zone_high_price, _Digits));
      create_Line(LOWER_LINE_PREFIX + cycle_date_str_part, zone_start_server_time, zone_low_price, line_time_end_visual, zone_low_price, 2, clrDodgerBlue, "Zone L: " + DoubleToString(zone_low_price, _Digits));
   } else {
      PrintFormat("Failed to define %s zone. No data in UTC period or invalid prices. Start Server: %s, End Server: %s", EnumToString(ZoneTimeframe), TimeToString(zone_start_server_time, TIME_DATE|TIME_MINUTES), TimeToString(zone_end_server_time, TIME_DATE|TIME_MINUTES));
      isZoneDefined = false;
   }
}

void CheckZoneBreakoutOnSelectedTF()
{
   ENUM_TIMEFRAMES tf_to_use = BreakoutDetectionTimeframe;
   if (UseConditionalTrading && tradesTakenThisCycleCount > 0) {
       tf_to_use = BreakoutDetectionTimeframe_2nd;
   }

   datetime breakout_tf_prev_bar_server_time = iTime(_Symbol, tf_to_use, 1);
   if (breakout_tf_prev_bar_server_time == last_BreakoutTF_bar_time_breakout_check || breakout_tf_prev_bar_server_time == 0)
      return;
   last_BreakoutTF_bar_time_breakout_check = breakout_tf_prev_bar_server_time;

   double breakout_tf_close_prev = iClose(_Symbol, tf_to_use, 1);

   string cycle_date_str_part = TimeToString(current_cycle_day_start_utc, TIME_DATE);
   cycle_date_str_part = StringReplace(cycle_date_str_part, ".", "_");
   string time_str_suffix = TimeToString(breakout_tf_prev_bar_server_time, TIME_SECONDS);
   StringReplace(time_str_suffix, ":", "");
   string obj_name_suffix_base = BREAKOUT_MARKER_PREFIX + cycle_date_str_part + "_" + time_str_suffix + "_" + EnumToString(tf_to_use);

   if (isH1ZoneBrokenOut) {
      if (breakout_tf_close_prev < zone_high_price && breakout_tf_close_prev > zone_low_price && zone_high_price > 0 && zone_low_price < DBL_MAX) {
         if (!hasPriceReEnteredZoneAfterBreakout) {
             PrintFormat("Price re-entered zone after initial %s breakout. Close: %.5f. Zone: %.5f-%.5f. Waiting for potential reverse breakout.",
                         (h1_breakout_direction == 1 ? "bullish" : "bearish"),
                         breakout_tf_close_prev, zone_low_price, zone_high_price);
             hasPriceReEnteredZoneAfterBreakout = true;
             isRetestLevelTouched = false;
         }
         return;
      }

      if (hasPriceReEnteredZoneAfterBreakout) {
         if (h1_breakout_direction == 1 && breakout_tf_close_prev < zone_low_price && zone_low_price < DBL_MAX) {
            PrintFormat("REVERSE Bearish Breakout on %s after re-entry: Close %.5f < Zone Low %.5f",
                        EnumToString(tf_to_use), breakout_tf_close_prev, zone_low_price);
            h1_breakout_direction = -1;
            h1_breakout_level = zone_low_price;
            isRetestLevelTouched = false;
            hasPriceReEnteredZoneAfterBreakout = false;
            drawArrow(obj_name_suffix_base + "_REV_DOWN", breakout_tf_prev_bar_server_time, breakout_tf_close_prev, SYMBOL_CODE_ARROW_DOWN, clrDarkOrange, (int)ANCHOR_BOTTOM);
            return;
         } else if (h1_breakout_direction == -1 && breakout_tf_close_prev > zone_high_price && zone_high_price > 0) {
            PrintFormat("REVERSE Bullish Breakout on %s after re-entry: Close %.5f > Zone High %.5f",
                        EnumToString(tf_to_use), breakout_tf_close_prev, zone_high_price);
            h1_breakout_direction = 1;
            h1_breakout_level = zone_high_price;
            isRetestLevelTouched = false;
            hasPriceReEnteredZoneAfterBreakout = false;
            drawArrow(obj_name_suffix_base + "_REV_UP", breakout_tf_prev_bar_server_time, breakout_tf_close_prev, SYMBOL_CODE_ARROW_UP, clrPaleGreen, (int)ANCHOR_TOP);
            return;
         }
      }
   } else {
      if (breakout_tf_close_prev > zone_high_price && zone_high_price > 0) {
         isH1ZoneBrokenOut = true;
         h1_breakout_direction = 1;
         h1_breakout_level = zone_high_price;
         hasPriceReEnteredZoneAfterBreakout = false;
         PrintFormat("Initial Bullish Breakout on %s: Close %.5f > Zone High %.5f at %s (Server)",
                     EnumToString(tf_to_use), breakout_tf_close_prev, zone_high_price,
                     TimeToString(breakout_tf_prev_bar_server_time, TIME_DATE|TIME_MINUTES));
         drawArrow(obj_name_suffix_base + "_INIT_UP", breakout_tf_prev_bar_server_time, breakout_tf_close_prev, SYMBOL_CODE_ARROW_UP, clrLimeGreen, (int)ANCHOR_TOP);
      } else if (breakout_tf_close_prev < zone_low_price && zone_low_price < DBL_MAX) {
         isH1ZoneBrokenOut = true;
         h1_breakout_direction = -1;
         h1_breakout_level = zone_low_price;
         hasPriceReEnteredZoneAfterBreakout = false;
         PrintFormat("Initial Bearish Breakout on %s: Close %.5f < Zone Low %.5f at %s (Server)",
                     EnumToString(tf_to_use), breakout_tf_close_prev, zone_low_price,
                     TimeToString(breakout_tf_prev_bar_server_time, TIME_DATE|TIME_MINUTES));
         drawArrow(obj_name_suffix_base + "_INIT_DOWN", breakout_tf_prev_bar_server_time, breakout_tf_close_prev, SYMBOL_CODE_ARROW_DOWN, clrOrangeRed, (int)ANCHOR_BOTTOM);
      }
   }
}

void CheckRetestAndEntry(datetime current_utc_time)
{
   ENUM_TIMEFRAMES tf_to_use = EntryTimeframe;
   if (UseConditionalTrading && tradesTakenThisCycleCount > 0) {
       tf_to_use = EntryTimeframe_2nd;
   }

   datetime entry_tf_prev_bar_server_time = iTime(_Symbol, tf_to_use, 1);
   if (entry_tf_prev_bar_server_time == last_EntryTF_bar_time_retest_check || entry_tf_prev_bar_server_time == 0)
      return;
   last_EntryTF_bar_time_retest_check = entry_tf_prev_bar_server_time;

   double entry_tf_low_prev = iLow(_Symbol, tf_to_use, 1);
   double entry_tf_high_prev = iHigh(_Symbol, tf_to_use, 1);
   double entry_tf_close_prev = iClose(_Symbol, tf_to_use, 1);

   string cycle_date_str_part = TimeToString(current_cycle_day_start_utc, TIME_DATE);
   cycle_date_str_part = StringReplace(cycle_date_str_part, ".", "_");
   string time_str_suffix = TimeToString(entry_tf_prev_bar_server_time, TIME_SECONDS);
   StringReplace(time_str_suffix, ":", "");
   string retest_obj_suffix = cycle_date_str_part + "_" + time_str_suffix;
   string fvg_obj_name_base = FVG_RECT_PREFIX + cycle_date_str_part;

   if (!isRetestLevelTouched && isH1ZoneBrokenOut)
   {
      if (h1_breakout_direction == 1 && entry_tf_low_prev <= h1_breakout_level && h1_breakout_level > 0)
      {
         isRetestLevelTouched = true;
         PrintFormat("Retest Touch Confirmed (Bullish Level %.5f): Low %.5f at %s (Server, %s)",
                     h1_breakout_level, entry_tf_low_prev,
                     TimeToString(entry_tf_prev_bar_server_time, TIME_DATE|TIME_MINUTES), EnumToString(tf_to_use));
         drawArrow(RETEST_MARKER_PREFIX + retest_obj_suffix + "_BULLTOUCH_CONFIRM",
                   entry_tf_prev_bar_server_time, entry_tf_low_prev,
                   SYMBOL_CODE_TRIANGLE, clrGold, (int)ANCHOR_TOP);
         return;
      }
      else if (h1_breakout_direction == -1 && entry_tf_high_prev >= h1_breakout_level && h1_breakout_level > 0)
      {
         isRetestLevelTouched = true;
         PrintFormat("Retest Touch Confirmed (Bearish Level %.5f): High %.5f at %s (Server, %s)",
                     h1_breakout_level, entry_tf_high_prev,
                     TimeToString(entry_tf_prev_bar_server_time, TIME_DATE|TIME_MINUTES), EnumToString(tf_to_use));
         drawArrow(RETEST_MARKER_PREFIX + retest_obj_suffix + "_BEARTOUCH_CONFIRM",
                   entry_tf_prev_bar_server_time, entry_tf_high_prev,
                   SYMBOL_CODE_TRIANGLE, clrGold, (int)ANCHOR_BOTTOM);
         return;
      }
   }

   if (isRetestLevelTouched)
   {
      bool fvg_condition_met = !UseFVGConfirmation;
      PriceLevel fvg;

      if (UseFVGConfirmation) {
          if (h1_breakout_direction == 1 && entry_tf_close_prev > h1_breakout_level) {
              fvg = FindRecentFVG_Standard(tf_to_use, 1, 1, FVGMaxPatternsToCheck);
              if (fvg.isValid) {
                  drawFVG(fvg_obj_name_base + "_BULL_" + time_str_suffix, fvg.time, fvg.low, fvg.high, clrLightSkyBlue, tf_to_use);
                  if (entry_tf_low_prev <= fvg.high && entry_tf_close_prev > fvg.low ) {
                       PrintFormat("BUY FVG Confirmed: Low %.5f interacted with Bullish FVG [%.5f - %.5f]. Entry bar close %.5f", entry_tf_low_prev, fvg.low, fvg.high, entry_tf_close_prev);
                       fvg_condition_met = true;
                  } else { PrintFormat("BUY FVG Not Interacted: Low %.5f (close %.5f) vs FVG [%.5f - %.5f]", entry_tf_low_prev, entry_tf_close_prev, fvg.low, fvg.high); }
              } else { Print("No Bullish FVG for BUY confirmation."); }
          } else if (h1_breakout_direction == -1 && entry_tf_close_prev < h1_breakout_level) {
              fvg = FindRecentFVG_Standard(tf_to_use, 1, -1, FVGMaxPatternsToCheck);
              if (fvg.isValid) {
                  drawFVG(fvg_obj_name_base + "_BEAR_" + time_str_suffix, fvg.time, fvg.low, fvg.high, clrMistyRose, tf_to_use);
                  if (entry_tf_high_prev >= fvg.low && entry_tf_close_prev < fvg.high) {
                      PrintFormat("SELL FVG Confirmed: High %.5f interacted with Bearish FVG [%.5f - %.5f]. Entry bar close %.5f", entry_tf_high_prev, fvg.low, fvg.high, entry_tf_close_prev);
                      fvg_condition_met = true;
                  } else { PrintFormat("SELL FVG Not Interacted: High %.5f (close %.5f) vs FVG [%.5f - %.5f]", entry_tf_high_prev, entry_tf_close_prev, fvg.low, fvg.high); }
              } else { Print("No Bearish FVG for SELL confirmation."); }
          }
      }

      double final_sl = 0.0;
      double final_tp = 0.0;
      double entry_price = 0.0;

      if (h1_breakout_direction == 1 && entry_tf_close_prev > h1_breakout_level)
      {
         if (UseFVGConfirmation && !fvg_condition_met) { Print("Skipping BUY: FVG confirmation failed."); return; }
         entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(entry_price == 0) { Print("Invalid Ask for BUY."); return; }
         final_sl = zone_low_price; if (MaxSL_Pips > 0) { double max_sl_val = entry_price - MaxSL_Pips * PipSize; if (final_sl < max_sl_val || final_sl == 0.0 || final_sl >= entry_price) final_sl = max_sl_val; }
         final_sl = NormalizeDouble(final_sl, _Digits);
         if (TP_Pips > 0) final_tp = entry_price + TP_Pips * PipSize;
         else { double tp_dist = MathAbs(zone_high_price - zone_low_price); if (tp_dist < PipSize*10) tp_dist = PipSize*10; final_tp = h1_breakout_level + tp_dist; }
         final_tp = NormalizeDouble(final_tp, _Digits);

         if (final_sl >= entry_price - SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)*_Point) { PrintFormat("BUY SL Error: SL %.5f >= Ask %.5f (StopsLevel %d pts). SL not set or too close.", final_sl, entry_price, SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)); return; }
         if (TP_Pips > 0 && final_tp <= entry_price + SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)*_Point) { PrintFormat("BUY TP Error: TP %.5f <= Ask %.5f (StopsLevel %d pts). TP not set or too close.", final_tp, entry_price, SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)); return; }

         string trade_comment = "H1ZBR Buy" + (UseFVGConfirmation && fvg_condition_met ? " FVG" : "");
         PrintFormat("BUY Signal%s: Ask %.5f, SL %.5f (%.2fp), TP %.5f (%.2fp)", (UseFVGConfirmation && fvg_condition_met ? " (FVG)" : ""), entry_price, final_sl, (entry_price-final_sl)/PipSize, final_tp, (final_tp-entry_price)/PipSize);
         if (obj_Trade.Buy(LotSize, _Symbol, entry_price, final_sl, final_tp, trade_comment)) {
            tradesTakenThisCycleCount++; isRetestLevelTouched = false;
            PrintFormat("BUY Order placed. Result Order: %s. Trades/Cycle: %d", (string)obj_Trade.ResultOrder(), tradesTakenThisCycleCount);
            // *** FIXED *** Using the compatible method to get the position ticket
            if(UseConditionalTrading)
            {
               ulong deal_ticket = obj_Trade.ResultDeal();
               if(HistoryDealSelect(deal_ticket))
               {
                  last_open_position_ticket = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
                  PrintFormat("Now tracking position ticket #%d from deal #%d", last_open_position_ticket, deal_ticket);
               }
               else
               {
                  last_open_position_ticket = 0; // Failsafe
                  Print("Could not select deal to find position ticket.");
               }
            }
            drawArrow(RETEST_MARKER_PREFIX+retest_obj_suffix+"_BUYENTRY", entry_tf_prev_bar_server_time, entry_price, SYMBOL_CODE_THUMBS_UP, clrLime, (int)ANCHOR_LEFT_LOWER);
         } else PrintFormat("BUY Order failed: %d - %s", obj_Trade.ResultRetcode(), obj_Trade.ResultComment());
      }
      else if (h1_breakout_direction == -1 && entry_tf_close_prev < h1_breakout_level)
      {
         if (UseFVGConfirmation && !fvg_condition_met) { Print("Skipping SELL: FVG confirmation failed."); return; }
         entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(entry_price == 0) { Print("Invalid Bid for SELL."); return; }
         final_sl = zone_high_price; if (MaxSL_Pips > 0) { double max_sl_val = entry_price + MaxSL_Pips * PipSize; if (final_sl > max_sl_val || final_sl == 0.0 || final_sl <= entry_price) final_sl = max_sl_val; }
         final_sl = NormalizeDouble(final_sl, _Digits);
         if (TP_Pips > 0) final_tp = entry_price - TP_Pips * PipSize;
         else { double tp_dist = MathAbs(zone_high_price - zone_low_price); if (tp_dist < PipSize*10) tp_dist = PipSize*10; final_tp = h1_breakout_level - tp_dist; }
         final_tp = NormalizeDouble(final_tp, _Digits);

         if (final_sl <= entry_price + SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)*_Point) { PrintFormat("SELL SL Error: SL %.5f <= Bid %.5f (StopsLevel %d pts). SL not set or too close.", final_sl, entry_price, SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)); return; }
         if (TP_Pips > 0 && final_tp >= entry_price - SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)*_Point) { PrintFormat("SELL TP Error: TP %.5f >= Bid %.5f (StopsLevel %d pts). TP not set or too close.", final_tp, entry_price, SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)); return; }

         string trade_comment = "H1ZBR Sell" + (UseFVGConfirmation && fvg_condition_met ? " FVG" : "");
         PrintFormat("SELL Signal%s: Bid %.5f, SL %.5f (%.2fp), TP %.5f (%.2fp)",(UseFVGConfirmation && fvg_condition_met ? " (FVG)" : ""), entry_price, final_sl, (final_sl-entry_price)/PipSize, final_tp, (entry_price-final_tp)/PipSize);
         if (obj_Trade.Sell(LotSize, _Symbol, entry_price, final_sl, final_tp, trade_comment)) {
            tradesTakenThisCycleCount++; isRetestLevelTouched = false;
            PrintFormat("SELL Order placed. Result Order: %s. Trades/Cycle: %d", (string)obj_Trade.ResultOrder(), tradesTakenThisCycleCount);
            // *** FIXED *** Using the compatible method to get the position ticket
            if(UseConditionalTrading)
            {
               ulong deal_ticket = obj_Trade.ResultDeal();
               if(HistoryDealSelect(deal_ticket))
               {
                  last_open_position_ticket = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
                  PrintFormat("Now tracking position ticket #%d from deal #%d", last_open_position_ticket, deal_ticket);
               }
               else
               {
                  last_open_position_ticket = 0; // Failsafe
                  Print("Could not select deal to find position ticket.");
               }
            }
            drawArrow(RETEST_MARKER_PREFIX+retest_obj_suffix+"_SELLENTRY", entry_tf_prev_bar_server_time, entry_price, SYMBOL_CODE_THUMBS_UP, clrTomato, (int)ANCHOR_LEFT_UPPER);
         } else PrintFormat("SELL Order failed: %d - %s", obj_Trade.ResultRetcode(), obj_Trade.ResultComment());
      }
   }
}

void HandleTradeHistory()
{
    if (last_open_position_ticket == 0) return;

    if (PositionSelectByTicket(last_open_position_ticket)) return;

    if (HistorySelectByPosition(last_open_position_ticket))
    {
        double total_profit = 0;
        for (int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong deal_ticket = HistoryDealGetTicket(i);
            if (HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID) == last_open_position_ticket)
            {
                total_profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                total_profit += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
                total_profit += HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
            }
        }

        if (total_profit >= 0)
        {
            stop_cycle_on_profit_flag = true;
            PrintFormat("Trade #%d (Position: %d) closed with PROFIT (%.2f). No more trades will be taken this cycle.",
                        tradesTakenThisCycleCount, last_open_position_ticket, total_profit);
        }
        else
        {
            cooldown_end_time_utc = TimeGMT() + (ulong)CooldownMinutesAfterLoss * 60;
            PrintFormat("Trade #%d (Position: %d) closed with LOSS (%.2f). Cooldown period initiated until %s UTC.",
                        tradesTakenThisCycleCount, last_open_position_ticket, total_profit, TimeToString(cooldown_end_time_utc, TIME_DATE|TIME_MINUTES));
        }

        last_open_position_ticket = 0;
    }
    else
    {
        PrintFormat("Could not find closed position #%d in history yet. Will check again.", last_open_position_ticket);
    }
}


PriceLevel FindRecentFVG_Standard(ENUM_TIMEFRAMES timeframe, int bar_idx_candle_k, int direction, int max_patterns_to_check)
{
    PriceLevel fvg; fvg.isValid = false;
    for (int k_offset = 0; k_offset < max_patterns_to_check; k_offset++) {
        int idx_k = bar_idx_candle_k + k_offset; int idx_k_minus_1 = idx_k + 1; int idx_k_minus_2 = idx_k + 2;
        if (idx_k_minus_2 >= Bars(_Symbol, timeframe) -1 || idx_k < 0) continue;
        datetime time_k_minus_1 = iTime(_Symbol, timeframe, idx_k_minus_1);
        if(iTime(_Symbol, timeframe, idx_k) == 0 || time_k_minus_1 == 0 || iTime(_Symbol, timeframe, idx_k_minus_2) == 0) continue;

        if (direction == 1) {
            double high_k_minus_2 = iHigh(_Symbol, timeframe, idx_k_minus_2);
            double low_k = iLow(_Symbol, timeframe, idx_k);
            if (high_k_minus_2 <= 0 || low_k <= 0) continue;
            if (low_k > high_k_minus_2) {
                fvg.low = high_k_minus_2;
                fvg.high = low_k;
                fvg.time = time_k_minus_1;
                fvg.isValid = true;
                PrintFormat("Bullish FVG on %s at %s: L %.5f, H %.5f. (Bars: k-2 High:%.5f, k-1:%s, k Low:%.5f)", EnumToString(timeframe), TimeToString(fvg.time, TIME_DATE|TIME_MINUTES), fvg.low, fvg.high, high_k_minus_2, TimeToString(time_k_minus_1,TIME_DATE|TIME_MINUTES),low_k);
                return fvg;
            }
        } else if (direction == -1) {
            double low_k_minus_2 = iLow(_Symbol, timeframe, idx_k_minus_2);
            double high_k = iHigh(_Symbol, timeframe, idx_k);
            if (low_k_minus_2 <= 0 || high_k <= 0) continue;
            if (high_k < low_k_minus_2) {
                fvg.low = high_k;
                fvg.high = low_k_minus_2;
                fvg.time = time_k_minus_1;
                fvg.isValid = true;
                 PrintFormat("Bearish FVG on %s at %s: L %.5f, H %.5f. (Bars: k-2 Low:%.5f, k-1:%s, k High:%.5f)", EnumToString(timeframe), TimeToString(fvg.time, TIME_DATE|TIME_MINUTES), fvg.low, fvg.high, low_k_minus_2, TimeToString(time_k_minus_1,TIME_DATE|TIME_MINUTES), high_k);
                return fvg;
            }
        }
    } return fvg;
}

void drawFVG(string objName, datetime fvgTime, double fvgPriceLow, double fvgPriceHigh, color clr, ENUM_TIMEFRAMES timeframe)
{
    if (ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);
    datetime time1 = fvgTime; datetime time2 = fvgTime + (long)PeriodSeconds(timeframe);
    if(!ObjectCreate(0, objName, OBJ_RECTANGLE, 0, time1, fvgPriceHigh, time2, fvgPriceLow)) { PrintFormat("Error FVG rect %s: %d", objName, GetLastError()); return; }
    ObjectSetInteger(0, objName, OBJPROP_COLOR, clr); ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, objName, OBJPROP_BACK, true); ObjectSetInteger(0, objName, OBJPROP_FILL, true);
    ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
}

void create_Rectangle(string objName, datetime time1, double price1, datetime time2, double price2, color clr)
{
   if (ObjectFind(0, objName) >= 0) {
        ObjectSetInteger(0, objName, OBJPROP_TIME, 0, time1); ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, price1);
        ObjectSetInteger(0, objName, OBJPROP_TIME, 1, time2); ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, price2);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   } else { if(!ObjectCreate(0, objName, OBJ_RECTANGLE, 0, time1, price1, time2, price2)) { PrintFormat("Error rect %s: %d", objName, GetLastError()); return; } }
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1); ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_FILL, true); ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
}

void create_Line(string objName, datetime time1, double price1, datetime time2, double price2, int width, color clr, string text = "")
{
   datetime T2 = (time1 < time2 ? time2 : (time1 + (long)3600 * 24));
   if (ObjectFind(0, objName) >= 0) {
        ObjectSetInteger(0, objName, OBJPROP_TIME, 0, time1); ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, price1);
        ObjectSetInteger(0, objName, OBJPROP_TIME, 1, T2); ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, price2);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr); ObjectSetString(0, objName, OBJPROP_TEXT, text);
   } else { if(!ObjectCreate(0, objName, OBJ_TREND, 0, time1, price1, T2, price2)) { PrintFormat("Error line %s: %d", objName, GetLastError()); return; } }
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID); ObjectSetInteger(0, objName, OBJPROP_WIDTH, width); ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); ObjectSetString(0, objName, OBJPROP_TEXT, text); ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
}

void drawArrow(string objName, datetime time_val, double price_val, int arrowCode, color clr, int anchor_as_int = ANCHOR_CENTER, int size = 1)
{
   if (ObjectFind(0, objName) < 0) { if(!ObjectCreate(0, objName, OBJ_ARROW, 0, time_val, price_val)) { PrintFormat("Error arrow %s: %d", objName, GetLastError()); return; }
   } else { ObjectMove(0, objName, 0, time_val, price_val); }
   ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, arrowCode); ObjectSetInteger(0, objName, OBJPROP_COLOR, clr); ObjectSetInteger(0, objName, OBJPROP_WIDTH, size);
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, anchor_as_int); ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
}

void ManageOpenTrades()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)
        {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double initial_current_sl = PositionGetDouble(POSITION_SL);
            double current_tp = PositionGetDouble(POSITION_TP);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double point_value = _Point;
            double price_pip_size = PipSize;

            double sl_after_stage1_or_2 = initial_current_sl;
            bool sl_modified_this_tick = false;

            // --- Stage 1: Original Breakeven ---
            if (BreakEvenPips > 0 && BreakEvenSecurePips >= 0)
            {
                double be_trigger_profit_level;
                double be_sl_target_price;

                if (type == POSITION_TYPE_BUY)
                {
                    be_trigger_profit_level = NormalizeDouble(open_price + BreakEvenPips * price_pip_size, _Digits);
                    be_sl_target_price = NormalizeDouble(open_price + BreakEvenSecurePips * price_pip_size, _Digits);
                    double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

                    if (current_bid >= be_trigger_profit_level)
                    {
                        if (initial_current_sl < be_sl_target_price || initial_current_sl == 0.0)
                        {
                            if (be_sl_target_price < current_bid - SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value)
                            {
                                if (obj_Trade.PositionModify(ticket, be_sl_target_price, current_tp))
                                {
                                    PrintFormat("BE for Buy #%s. SL to %.5f (triggered at %.1f pips, secured %.1f pips)",
                                                (string)ticket, be_sl_target_price, BreakEvenPips, BreakEvenSecurePips);
                                    sl_after_stage1_or_2 = be_sl_target_price;
                                    sl_modified_this_tick = true;
                                }
                                else
                                    PrintFormat("Error BE Buy #%s (SL: %.5f): %d - %s", (string)ticket, be_sl_target_price, obj_Trade.ResultRetcode(), obj_Trade.ResultComment());
                            }
                        }
                    }
                }
                else if (type == POSITION_TYPE_SELL)
                {
                    be_trigger_profit_level = NormalizeDouble(open_price - BreakEvenPips * price_pip_size, _Digits);
                    be_sl_target_price = NormalizeDouble(open_price - BreakEvenSecurePips * price_pip_size, _Digits);
                    double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

                    if (current_ask <= be_trigger_profit_level)
                    {
                        if (initial_current_sl > be_sl_target_price || initial_current_sl == 0.0)
                        {
                            if (be_sl_target_price > current_ask + SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value)
                            {
                                if (obj_Trade.PositionModify(ticket, be_sl_target_price, current_tp))
                                {
                                    PrintFormat("BE for Sell #%s. SL to %.5f (triggered at %.1f pips, secured %.1f pips)",
                                                (string)ticket, be_sl_target_price, BreakEvenPips, BreakEvenSecurePips);
                                    sl_after_stage1_or_2 = be_sl_target_price;
                                    sl_modified_this_tick = true;
                                }
                                else
                                    PrintFormat("Error BE Sell #%s (SL: %.5f): %d - %s", (string)ticket, be_sl_target_price, obj_Trade.ResultRetcode(), obj_Trade.ResultComment());
                            }
                        }
                    }
                }
            }

            // --- Stage 2: Secure Significant Profit ---
            if (SecureProfitTargetPips > 0 && SecureProfitLockPips > 0)
            {
                double sp_trigger_profit_level;
                double sp_sl_target_price;

                if (type == POSITION_TYPE_BUY)
                {
                    sp_trigger_profit_level = NormalizeDouble(open_price + SecureProfitTargetPips * price_pip_size, _Digits);
                    sp_sl_target_price = NormalizeDouble(open_price + SecureProfitLockPips * price_pip_size, _Digits);
                    double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

                    if (current_bid >= sp_trigger_profit_level)
                    {
                        if (sp_sl_target_price > sl_after_stage1_or_2 || sl_after_stage1_or_2 == 0.0)
                        {
                            if (sp_sl_target_price < current_bid - SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value)
                            {
                                if (obj_Trade.PositionModify(ticket, sp_sl_target_price, current_tp))
                                {
                                    PrintFormat("SecureProfit for Buy #%s. SL to %.5f (triggered at %.1f pips, locked %.1f pips)",
                                                (string)ticket, sp_sl_target_price, SecureProfitTargetPips, SecureProfitLockPips);
                                    sl_after_stage1_or_2 = sp_sl_target_price;
                                    sl_modified_this_tick = true;
                                }
                                else
                                    PrintFormat("Error SecureProfit Buy #%s (SL: %.5f): %d - %s", (string)ticket, sp_sl_target_price, obj_Trade.ResultRetcode(), obj_Trade.ResultComment());
                            }
                        }
                    }
                }
                else if (type == POSITION_TYPE_SELL)
                {
                    sp_trigger_profit_level = NormalizeDouble(open_price - SecureProfitTargetPips * price_pip_size, _Digits);
                    sp_sl_target_price = NormalizeDouble(open_price - SecureProfitLockPips * price_pip_size, _Digits);
                    double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

                    if (current_ask <= sp_trigger_profit_level)
                    {
                        if (sp_sl_target_price < sl_after_stage1_or_2 || sl_after_stage1_or_2 == 0.0)
                        {
                             if (sp_sl_target_price > current_ask + SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value)
                            {
                                if (obj_Trade.PositionModify(ticket, sp_sl_target_price, current_tp))
                                {
                                    PrintFormat("SecureProfit for Sell #%s. SL to %.5f (triggered at %.1f pips, locked %.1f pips)",
                                                (string)ticket, sp_sl_target_price, SecureProfitTargetPips, SecureProfitLockPips);
                                    sl_after_stage1_or_2 = sp_sl_target_price;
                                    sl_modified_this_tick = true;
                                }
                                else
                                    PrintFormat("Error SecureProfit Sell #%s (SL: %.5f): %d - %s", (string)ticket, sp_sl_target_price, obj_Trade.ResultRetcode(), obj_Trade.ResultComment());
                            }
                        }
                    }
                }
            }

            // --- Stage 3: ATR Trailing Stop ---
            bool atr_conditions_met = false;
            double atr_floor_price = open_price;

            if (SecureProfitTargetPips > 0 && SecureProfitLockPips > 0) {
                double target_sp_lock_sl;
                if (type == POSITION_TYPE_BUY) target_sp_lock_sl = NormalizeDouble(open_price + SecureProfitLockPips * price_pip_size, _Digits);
                else target_sp_lock_sl = NormalizeDouble(open_price - SecureProfitLockPips * price_pip_size, _Digits);

                if ((type == POSITION_TYPE_BUY && sl_after_stage1_or_2 >= target_sp_lock_sl && target_sp_lock_sl > open_price) ||
                    (type == POSITION_TYPE_SELL && sl_after_stage1_or_2 <= target_sp_lock_sl && target_sp_lock_sl < open_price && sl_after_stage1_or_2 != 0.0)) {
                    atr_conditions_met = true;
                    atr_floor_price = target_sp_lock_sl;
                }
            }

            if (!atr_conditions_met && BreakEvenPips > 0 && BreakEvenSecurePips >= 0) {
                double target_be_lock_sl;
                if (type == POSITION_TYPE_BUY) target_be_lock_sl = NormalizeDouble(open_price + BreakEvenSecurePips * price_pip_size, _Digits);
                else target_be_lock_sl = NormalizeDouble(open_price - BreakEvenSecurePips * price_pip_size, _Digits);

                if ((type == POSITION_TYPE_BUY && sl_after_stage1_or_2 >= target_be_lock_sl) ||
                    (type == POSITION_TYPE_SELL && sl_after_stage1_or_2 <= target_be_lock_sl && sl_after_stage1_or_2 != 0.0)) {
                    atr_conditions_met = true;
                    atr_floor_price = target_be_lock_sl;
                }
            }
            
            if (!atr_conditions_met) {
                 if ((type == POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID) > open_price && sl_after_stage1_or_2 > open_price && sl_after_stage1_or_2 != 0.0) ||
                     (type == POSITION_TYPE_SELL && SymbolInfoDouble(_Symbol, SYMBOL_ASK) < open_price && sl_after_stage1_or_2 < open_price && sl_after_stage1_or_2 != 0.0)) {
                     atr_conditions_met = true;
                     atr_floor_price = sl_after_stage1_or_2;
                 } else if ((type == POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID) > open_price) ||
                            (type == POSITION_TYPE_SELL && SymbolInfoDouble(_Symbol, SYMBOL_ASK) < open_price)) {
                     atr_conditions_met = true;
                 }
            }

            if (EnableATRTrailing && atr_conditions_met)
            {
                ENUM_TIMEFRAMES atr_tf_to_use = (ATRTrailingTimeframe == PERIOD_CURRENT) ? Period() : ATRTrailingTimeframe;
                
                // Using the original 3-parameter iATR call for your environment
                double atr_value = iATR(_Symbol, atr_tf_to_use, ATRTrailingPeriod);

                if (atr_value > 0)
                {
                    double atr_sl_target_price;
                    if (type == POSITION_TYPE_BUY)
                    {
                        double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                        atr_sl_target_price = NormalizeDouble(current_bid - (atr_value * ATRTrailingMultiplier), _Digits);
                        if (atr_sl_target_price > sl_after_stage1_or_2 && atr_sl_target_price >= atr_floor_price)
                        {
                            if (atr_sl_target_price < current_bid - SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value)
                            {
                                if (obj_Trade.PositionModify(ticket, atr_sl_target_price, current_tp))
                                    PrintFormat("ATR Trail for Buy #%s. SL to %.5f (ATR:%.5f on %s, Mult:%.1f, Floor: %.5f, PrevSL: %.5f)",
                                        (string)ticket, atr_sl_target_price, atr_value, EnumToString(atr_tf_to_use), ATRTrailingMultiplier, atr_floor_price, sl_after_stage1_or_2);
                            }
                        }
                    }
                    else if (type == POSITION_TYPE_SELL)
                    {
                        double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                        atr_sl_target_price = NormalizeDouble(current_ask + (atr_value * ATRTrailingMultiplier), _Digits);
                        if ((atr_sl_target_price < sl_after_stage1_or_2 || sl_after_stage1_or_2 == 0.0) && atr_sl_target_price <= atr_floor_price)
                        {
                             if (atr_sl_target_price > current_ask + SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value)
                            {
                                if (obj_Trade.PositionModify(ticket, atr_sl_target_price, current_tp))
                                    PrintFormat("ATR Trail for Sell #%s. SL to %.5f (ATR:%.5f on %s, Mult:%.1f, Floor: %.5f, PrevSL: %.5f)",
                                        (string)ticket, atr_sl_target_price, atr_value, EnumToString(atr_tf_to_use), ATRTrailingMultiplier, atr_floor_price, sl_after_stage1_or_2);
                            }
                        }
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+