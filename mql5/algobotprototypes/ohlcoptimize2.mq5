//+------------------------------------------------------------------+
//|                                                utbotea1_hlc.mq5 |
//|                                                   shikhar shivam |
//|                                     @artificialintelligencefacts |
//+------------------------------------------------------------------+
#property copyright "shikhar shivam"
#property link      "@artificialintelligencefacts"
#property version   "1.00"

// Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Input parameters - Trading parameters
input double   LotSize = 0.2;         // Lot Size
input bool     EnableBuy = true;       // Enable Buy Signals
input bool     EnableSell = true;      // Enable Sell Signals
input int      MaxPositions = 1;       // Maximum Open Positions
input double   StopLossPercent = 1.0;  // Stop Loss (% of ATR)
input double   TakeProfitPercent = 2.0; // Take Profit (% of ATR)
input bool     UseTrailingStop = true; // Use Trailing Stop
input int      MagicNumber = 123456;   // Magic Number
input bool     CloseOnOppositeSignal = true; // Close on Opposite Signal
input int      CheckEveryXTicks = 10;   // Check signals every X ticks

// Signal detection parameters
input double   SignalThreshold = 0.15;  // Minimum threshold to consider a valid signal (0.05-0.5)
input bool     UseStrictSignalValidation = true; // Use extra strict signal validation
input int      SignalConfirmationTicks = 2; // Wait this many ticks to confirm signal stability
input bool     EnableDebugMode = true;      // Print detailed signal debug information

// Partial Booking parameters
input bool     UsePartialBooking = true;   // Use Partial Booking instead of TP
input int      PartialLevels = 3;          // Number of partial booking levels (1-5)
input double   Level1Percent = 40;         // % of position to close at level 1
input double   Level2Percent = 30;         // % of position to close at level 2
input double   Level3Percent = 20;         // % of position to close at level 3
input double   Level4Percent = 10;         // % of position to close at level 4
input double   Level5Percent = 0;          // % of position to close at level 5
input double   Target1Multiple = 1.0;      // Target 1 (multiple of ATR)
input double   Target2Multiple = 1.5;      // Target 2 (multiple of ATR)
input double   Target3Multiple = 2.0;      // Target 3 (multiple of ATR)
input double   Target4Multiple = 2.5;      // Target 4 (multiple of ATR)
input double   Target5Multiple = 3.0;      // Target 5 (multiple of ATR)

// Trend Filter parameters
input bool     UseTrendFilter = true;      // Use trend filter for signal confirmation
input int      TrendEMA1Period = 50;       // Trend EMA1 Period
input int      TrendEMA2Period = 200;      // Trend EMA2 Period
input bool     OnlyTradeWithTrend = false; // Only trade in direction of the trend

// Input parameters - UT Bot Indicator parameters
input double   UTBot_KeyValue = 3.0;   // UT Bot: Key Value (Sensitivity)
input int      UTBot_ATRPeriod = 14;   // UT Bot: ATR Period
input bool     UTBot_UseHeikinAshi = false; // UT Bot: Use Heikin Ashi Candles

// Global variables
CTrade         trade;                   // Trading object
CPositionInfo  positionInfo;            // Position information object
int            utbotHandle;             // Handle for the UT Bot indicator
double         buyBuffer[];             // Buffer for buy signals
double         sellBuffer[];            // Buffer for sell signals
double         atrTrailingStopBuffer[]; // Buffer for ATR Trailing Stop
double         currentATR;              // Current ATR value
int            atrHandle;               // Handle for the ATR indicator
datetime       lastBarTime;             // Last processed bar time
int            ema1Handle;              // Handle for the EMA1 indicator
int            ema2Handle;              // Handle for the EMA2 indicator
double         ema1Buffer[];            // Buffer for EMA1 values
double         ema2Buffer[];            // Buffer for EMA2 values
int            tickCounter = 0;         // Counter for ticks
bool           signalConfirmed = false; // Flag to indicate signal confirmation
int            signalConfirmationCounter = 0; // Counter for signal confirmation

// Structure to manage partial bookings
struct PartialTarget {
   double price;           // Target price level
   double percentToClose;  // Percentage of position to close at this level
   bool reached;           // Whether this target has been reached
};

PartialTarget targets[5]; // Array to hold the 5 possible target levels

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Clear debug log
   if(EnableDebugMode)
   {
      Print("========== UT BOT EA INITIALIZATION ==========");
      Print("Symbol: ", _Symbol, ", Period: ", EnumToString(Period()));
      Print("Current ATR Period: ", UTBot_ATRPeriod);
   }
   
   // Get UT Bot indicator handle with custom parameters
   utbotHandle = iCustom(_Symbol, PERIOD_CURRENT, "utbot", 
                        UTBot_KeyValue,      // Key Value (Sensitivity)
                        UTBot_ATRPeriod,     // ATR Period
                        UTBot_UseHeikinAshi  // Use Heikin Ashi Candles
                      );
                      
   if(utbotHandle == INVALID_HANDLE)
   {
      Print("CRITICAL ERROR: Failed to create handle for the UT Bot indicator");
      Print("Please verify the indicator 'utbot' is installed in your terminal");
      Print("KeyValue=", UTBot_KeyValue, 
            ", ATRPeriod=", UTBot_ATRPeriod, 
            ", UseHeikinAshi=", UTBot_UseHeikinAshi);
      return(INIT_FAILED);
   }
   
   // Verify UT Bot indicator data
   double testBuffer[];
   ArraySetAsSeries(testBuffer, true);
   if(CopyBuffer(utbotHandle, 0, 0, 1, testBuffer) <= 0)
   {
      Print("WARNING: UT Bot indicator returns no data. Indicator may not be calculating correctly.");
      Print("Will continue initialization but EA may not function until data is available.");
   }
   else if(EnableDebugMode)
   {
      Print("UT Bot indicator data verified successfully");
   }
   
   // Get ATR indicator handle for stop loss and take profit calculations
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, UTBot_ATRPeriod);  // Use same ATR period as UTBot
   if(atrHandle == INVALID_HANDLE)
   {
      Print("CRITICAL ERROR: Failed to create ATR indicator handle");
      return(INIT_FAILED);
   }
   
   // Initialize EMA handles for trend filter
   if(UseTrendFilter)
   {
      ema1Handle = iMA(_Symbol, PERIOD_CURRENT, TrendEMA1Period, 0, MODE_EMA, PRICE_CLOSE);
      ema2Handle = iMA(_Symbol, PERIOD_CURRENT, TrendEMA2Period, 0, MODE_EMA, PRICE_CLOSE);
      
      if(ema1Handle == INVALID_HANDLE || ema2Handle == INVALID_HANDLE)
      {
         Print("CRITICAL ERROR: Failed to create EMA indicator handles");
         return(INIT_FAILED);
      }
      
      // Allocate EMA buffers
      ArraySetAsSeries(ema1Buffer, true);
      ArraySetAsSeries(ema2Buffer, true);
      
      // Verify EMA data
      if(CopyBuffer(ema1Handle, 0, 0, 1, ema1Buffer) <= 0 || 
         CopyBuffer(ema2Handle, 0, 0, 1, ema2Buffer) <= 0)
      {
         Print("WARNING: EMA indicators return no data. Trend filter may not work initially.");
      }
      else if(EnableDebugMode)
      {
         Print("EMA indicator data verified successfully");
      }
   }
   
   // Allocate buffers
   ArraySetAsSeries(buyBuffer, true);
   ArraySetAsSeries(sellBuffer, true);
   ArraySetAsSeries(atrTrailingStopBuffer, true);
   
   // Initialize last bar time
   lastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Initialize partial targets array
   for(int i=0; i<ArraySize(targets); i++)
   {
      targets[i].reached = false;
      targets[i].price = 0;
      targets[i].percentToClose = 0;
   }
   
   // Print parameter verification
   if(EnableDebugMode)
   {
      Print("Lot Size: ", LotSize);
      Print("MaxPositions: ", MaxPositions);
      Print("StopLossPercent: ", StopLossPercent);
      Print("TakeProfitPercent: ", TakeProfitPercent);
      Print("UseTrailingStop: ", UseTrailingStop ? "Yes" : "No");
      Print("UsePartialBooking: ", UsePartialBooking ? "Yes" : "No");
      Print("PartialLevels: ", PartialLevels);
      Print("UseTrendFilter: ", UseTrendFilter ? "Yes" : "No");
   }
   
   Print("UT Bot EA initialized successfully with KeyValue=", UTBot_KeyValue, 
         ", ATRPeriod=", UTBot_ATRPeriod, 
         ", UseHeikinAshi=", UTBot_UseHeikinAshi,
         ", Partial Booking=", UsePartialBooking ? "Enabled" : "Disabled",
         ", Trend Filter=", UseTrendFilter ? "Enabled" : "Disabled");
         
   // Force immediate signal check
   tickCounter = CheckEveryXTicks;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(utbotHandle != INVALID_HANDLE)
      IndicatorRelease(utbotHandle);
      
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
      
   if(UseTrendFilter)
   {
      if(ema1Handle != INVALID_HANDLE)
         IndicatorRelease(ema1Handle);
         
      if(ema2Handle != INVALID_HANDLE)
         IndicatorRelease(ema2Handle);
   }
      
   Print("UT Bot EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if market is closed
   if(!IsMarketOpen())
   {
      if(EnableDebugMode && tickCounter >= CheckEveryXTicks)
         Print("Market is closed. Skipping tick processing.");
      return;
   }
   
   // Increment tick counter
   tickCounter++;
   
   // Only check signals every X ticks (to reduce CPU usage)
   if(tickCounter < CheckEveryXTicks && tickCounter > 0)
   {
      // Still check partial targets and trailing stops on every tick
      if(UsePartialBooking)
         CheckPartialTargets();
         
      if(UseTrailingStop)
         ManageTrailingStop();
         
      return;
   }
   
   // Reset tick counter
   tickCounter = 0;
   
   // Get current bar time
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == 0)
   {
      Print("ERROR: Could not get current bar time. Skipping signal check.");
      return;
   }
   
   // Debug current price and time
   if(EnableDebugMode)
   {
      string timeStr = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      Print("Checking signals at ", timeStr, " - Bid: ", bid, ", Ask: ", ask);
   }
   
   // Check for new bar - this is the key change to HLC basis
   // Only process when a new bar/candle has formed
   bool isNewBar = (currentBarTime != lastBarTime);
   
   // If no new bar has formed, only check trailing stops if needed
   if(!isNewBar)
   {
      if(EnableDebugMode)
         Print("No new bar formed yet. Checking partial targets and trailing stops only.");
         
      // For HLC basis, we still want to manage trailing stops on ticks
      // to capture price movements within the current bar
      if(UseTrailingStop)
      {
         if(CopyBuffer(utbotHandle, 0, 0, 1, atrTrailingStopBuffer) > 0)
         {
            ManageTrailingStop();
         }
         else if(EnableDebugMode)
         {
            Print("WARNING: Failed to copy ATR trailing stop buffer");
         }
      }
      
      // Check partial targets on every tick
      if(UsePartialBooking)
      {
         CheckPartialTargets();
      }
      
      return;  // Exit if no new bar
   }
   
   // Update last bar time since we have a new bar
   lastBarTime = currentBarTime;
   
   if(EnableDebugMode)
      Print("New bar detected at ", TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES), ". Processing signals...");
   
   // Copy indicator buffers using HLC data - with more robust error handling
   int copyBuy = CopyBuffer(utbotHandle, 1, 0, 3, buyBuffer);
   int copySell = CopyBuffer(utbotHandle, 2, 0, 3, sellBuffer);
   int copyAtr = CopyBuffer(utbotHandle, 0, 0, 3, atrTrailingStopBuffer);
   
   if(copyBuy <= 0 || copySell <= 0 || copyAtr <= 0)
   {
      Print("Error copying indicator buffers: Buy=", copyBuy, ", Sell=", copySell, ", ATR=", copyAtr);
      return;
   }
   
   // Verify buffer sizes
   if(ArraySize(buyBuffer) < 3 || ArraySize(sellBuffer) < 3 || ArraySize(atrTrailingStopBuffer) < 3)
   {
      Print("Error: Indicator buffers have insufficient size");
      return;
   }
   
   // Copy ATR values for stop loss and take profit
   double atrValues[];
   ArraySetAsSeries(atrValues, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) <= 0)
   {
      Print("Error copying ATR buffer");
      return;
   }
   currentATR = atrValues[0];
   
   if(EnableDebugMode)
   {
      Print("Current ATR: ", currentATR);
      Print("Buy Signal[1]: ", buyBuffer[1], ", Sell Signal[1]: ", sellBuffer[1]);
   }
   
   // Copy trend EMA values if trend filter is enabled
   bool uptrend = true; // Default to uptrend if trend filter is disabled
   if(UseTrendFilter)
   {
      if(CopyBuffer(ema1Handle, 0, 0, 1, ema1Buffer) <= 0 ||
         CopyBuffer(ema2Handle, 0, 0, 1, ema2Buffer) <= 0)
      {
         Print("Error copying EMA buffers");
         return;
      }
      
      // Determine trend direction
      uptrend = (ema1Buffer[0] > ema2Buffer[0]);
      
      if(EnableDebugMode)
      {
         Print("Trend status: ", uptrend ? "UPTREND" : "DOWNTREND", 
               ", EMA1(", TrendEMA1Period, "): ", ema1Buffer[0], 
               ", EMA2(", TrendEMA2Period, "): ", ema2Buffer[0]);
      }
   }
   
   // Process trade signals based on completed bar data
   bool hasBuySignal = (buyBuffer[1] > 0) && (!UseTrendFilter || !OnlyTradeWithTrend || uptrend);
   bool hasSellSignal = (sellBuffer[1] > 0) && (!UseTrendFilter || !OnlyTradeWithTrend || !uptrend);
   
   // Debug show signal strength
   if(EnableDebugMode)
   {
      if(buyBuffer[1] > 0 || sellBuffer[1] > 0)
      {
         Print("RAW SIGNALS - Buy: ", buyBuffer[1], ", Sell: ", sellBuffer[1]);
      }
   }
   
   // Apply signal threshold filter if enabled
   if(UseStrictSignalValidation)
   {
      bool buyBeforeFilter = hasBuySignal;
      bool sellBeforeFilter = hasSellSignal;
      
      hasBuySignal = hasBuySignal && (buyBuffer[1] >= SignalThreshold);
      hasSellSignal = hasSellSignal && (sellBuffer[1] >= SignalThreshold);
      
      if(EnableDebugMode && (buyBeforeFilter || sellBeforeFilter))
      {
         Print("Signal threshold filter: ", SignalThreshold);
         Print("Buy signal: ", buyBeforeFilter ? "YES→" : "NO→", hasBuySignal ? "PASSED" : "FILTERED");
         Print("Sell signal: ", sellBeforeFilter ? "YES→" : "NO→", hasSellSignal ? "PASSED" : "FILTERED");
      }
   }
   
   // Signal confirmation logic
   if(hasBuySignal || hasSellSignal)
   {
      if(signalConfirmationCounter < SignalConfirmationTicks)
      {
         signalConfirmationCounter++;
         if(EnableDebugMode)
            Print("Signal confirmation: ", signalConfirmationCounter, "/", SignalConfirmationTicks);
         
         if(signalConfirmationCounter >= SignalConfirmationTicks)
         {
            signalConfirmed = true;
            if(EnableDebugMode)
               Print("SIGNAL CONFIRMED: ", hasBuySignal ? "BUY" : "SELL");
         }
      }
   }
   else
   {
      // Reset if no signal
      if(signalConfirmationCounter > 0 && EnableDebugMode)
         Print("Signal lost. Resetting confirmation counter.");
         
      signalConfirmationCounter = 0;
      signalConfirmed = false;
   }
   
   // Count current positions
   int totalPositions = CountPositions();
   
   if(EnableDebugMode)
      Print("Current positions: ", totalPositions, "/", MaxPositions);
      
   // Check for opposite signals to close positions
   if(CloseOnOppositeSignal && signalConfirmed)
   {
      if(hasBuySignal && IsPositionOpen(POSITION_TYPE_SELL))
      {
         if(EnableDebugMode)
            Print("Closing SELL positions due to opposite BUY signal");
         CloseAllPositions(POSITION_TYPE_SELL);
      }
         
      if(hasSellSignal && IsPositionOpen(POSITION_TYPE_BUY))
      {
         if(EnableDebugMode)
            Print("Closing BUY positions due to opposite SELL signal");
         CloseAllPositions(POSITION_TYPE_BUY);
      }
   }
   
   // Check for trailing stops on existing positions
   if(UseTrailingStop)
      ManageTrailingStop();
   
   // Check if we can open new positions
   if(totalPositions < MaxPositions && signalConfirmed)
   {
      // Check for buy signal
      if(EnableBuy && hasBuySignal && !IsPositionOpen(POSITION_TYPE_BUY))
      {
         if(EnableDebugMode)
            Print("Opening BUY position based on confirmed signal");
         OpenBuyPosition();
      }
      
      // Check for sell signal
      if(EnableSell && hasSellSignal && !IsPositionOpen(POSITION_TYPE_SELL))
      {
         if(EnableDebugMode)
            Print("Opening SELL position based on confirmed signal");
         OpenSellPosition();
      }
   }
   else if(signalConfirmed && totalPositions >= MaxPositions)
   {
      if(EnableDebugMode)
         Print("Signal confirmed but maximum positions (", MaxPositions, ") already open");
   }
   
   // Check partial targets
   if(UsePartialBooking)
   {
      CheckPartialTargets();
   }
}

//+------------------------------------------------------------------+
//| Open a buy position                                             |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = 0;
   double takeProfit = 0;
   
   // Calculate stop loss
   if(StopLossPercent > 0)
      stopLoss = NormalizeDouble(ask - (currentATR * StopLossPercent), _Digits);
      
   // Calculate take profit if not using partial booking
   if(!UsePartialBooking && TakeProfitPercent > 0)
      takeProfit = NormalizeDouble(ask + (currentATR * TakeProfitPercent), _Digits);
      
   // Open buy position
   if(!trade.Buy(
      LotSize,
      _Symbol,
      ask,
      stopLoss,
      takeProfit,
      "UT Bot Buy Signal"
   ))
   {
      Print("Error opening buy position: ", GetLastError());
   }
   else
   {
      Print("Buy position opened at price ", ask, 
            ", SL: ", stopLoss, 
            ", TP: ", takeProfit);
            
      // Setup partial targets if enabled
      if(UsePartialBooking)
      {
         int maxLevels = MathMin(PartialLevels, 5);
         maxLevels = MathMin(maxLevels, ArraySize(targets));
         
         // Reset targets
         for(int i=0; i<ArraySize(targets); i++)
         {
            targets[i].reached = false;
            targets[i].price = 0;
            targets[i].percentToClose = 0;
         }
         
         // Set target levels based on ATR
         if(maxLevels >= 1)
         {
            targets[0].price = NormalizeDouble(ask + (currentATR * Target1Multiple), _Digits);
            targets[0].percentToClose = Level1Percent;
         }
         
         if(maxLevels >= 2)
         {
            targets[1].price = NormalizeDouble(ask + (currentATR * Target2Multiple), _Digits);
            targets[1].percentToClose = Level2Percent;
         }
         
         if(maxLevels >= 3)
         {
            targets[2].price = NormalizeDouble(ask + (currentATR * Target3Multiple), _Digits);
            targets[2].percentToClose = Level3Percent;
         }
         
         if(maxLevels >= 4)
         {
            targets[3].price = NormalizeDouble(ask + (currentATR * Target4Multiple), _Digits);
            targets[3].percentToClose = Level4Percent;
         }
         
         if(maxLevels >= 5)
         {
            targets[4].price = NormalizeDouble(ask + (currentATR * Target5Multiple), _Digits);
            targets[4].percentToClose = Level5Percent;
         }
         
         if(EnableDebugMode)
         {
            for(int i=0; i<PartialLevels; i++)
            {
               if(targets[i].percentToClose > 0)
               {
                  Print("Target ", i+1, " set at ", targets[i].price, 
                        " (", targets[i].percentToClose, "% of position)");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open a sell position                                            |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = 0;
   double takeProfit = 0;
   
   // Calculate stop loss
   if(StopLossPercent > 0)
      stopLoss = NormalizeDouble(bid + (currentATR * StopLossPercent), _Digits);
      
   // Calculate take profit if not using partial booking
   if(!UsePartialBooking && TakeProfitPercent > 0)
      takeProfit = NormalizeDouble(bid - (currentATR * TakeProfitPercent), _Digits);
      
   // Open sell position
   if(!trade.Sell(
      LotSize,
      _Symbol,
      bid,
      stopLoss,
      takeProfit,
      "UT Bot Sell Signal"
   ))
   {
      Print("Error opening sell position: ", GetLastError());
   }
   else
   {
      Print("Sell position opened at price ", bid, 
            ", SL: ", stopLoss, 
            ", TP: ", takeProfit);
            
      // Setup partial targets if enabled
      if(UsePartialBooking)
      {
         int maxLevels = MathMin(PartialLevels, 5);
         maxLevels = MathMin(maxLevels, ArraySize(targets));
         
         // Reset targets
         for(int i=0; i<ArraySize(targets); i++)
         {
            targets[i].reached = false;
            targets[i].price = 0;
            targets[i].percentToClose = 0;
         }
         
         // Set target levels based on ATR
         if(maxLevels >= 1)
         {
            targets[0].price = NormalizeDouble(bid - (currentATR * Target1Multiple), _Digits);
            targets[0].percentToClose = Level1Percent;
         }
         
         if(maxLevels >= 2)
         {
            targets[1].price = NormalizeDouble(bid - (currentATR * Target2Multiple), _Digits);
            targets[1].percentToClose = Level2Percent;
         }
         
         if(maxLevels >= 3)
         {
            targets[2].price = NormalizeDouble(bid - (currentATR * Target3Multiple), _Digits);
            targets[2].percentToClose = Level3Percent;
         }
         
         if(maxLevels >= 4)
         {
            targets[3].price = NormalizeDouble(bid - (currentATR * Target4Multiple), _Digits);
            targets[3].percentToClose = Level4Percent;
         }
         
         if(maxLevels >= 5)
         {
            targets[4].price = NormalizeDouble(bid - (currentATR * Target5Multiple), _Digits);
            targets[4].percentToClose = Level5Percent;
         }
         
         if(EnableDebugMode)
         {
            for(int i=0; i<PartialLevels; i++)
            {
               if(targets[i].percentToClose > 0)
               {
                  Print("Target ", i+1, " set at ", targets[i].price, 
                        " (", targets[i].percentToClose, "% of position)");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if partial targets have been hit                          |
//+------------------------------------------------------------------+
void CheckPartialTargets()
{
   if(!UsePartialBooking || PartialLevels <= 0)
      return;
   
   // Limit PartialLevels to maximum of 5 to prevent array out of bounds
   int validLevels = MathMin(PartialLevels, 5);
      
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double positionVolume = PositionGetDouble(POSITION_VOLUME);
         
         // Check each target level
         for(int j = 0; j < validLevels; j++)
         {
            // Skip if index out of bounds
            if(j >= ArraySize(targets))
               break;
               
            // Skip if target already reached or percentage is zero
            if(targets[j].reached || targets[j].percentToClose <= 0)
               continue;
               
            bool targetHit = false;
            
            // Check if price has reached the target
            if(posType == POSITION_TYPE_BUY)
            {
               targetHit = (bid >= targets[j].price);
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               targetHit = (ask <= targets[j].price);
            }
            
            // If target hit, partially close the position
            if(targetHit)
            {
               // Calculate volume to close
               double volumeToClose = NormalizeDouble(positionVolume * (targets[j].percentToClose / 100.0), 2);
               
               // Ensure minimum volume
               double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               if(volumeToClose < minVolume)
                  volumeToClose = minVolume;
                  
               // Ensure we don't close more than available
               if(volumeToClose > positionVolume)
                  volumeToClose = positionVolume;
                  
               // Close part of the position
               if(trade.PositionClosePartial(ticket, volumeToClose))
               {
                  targets[j].reached = true;
                  
                  if(EnableDebugMode)
                  {
                     Print("Target ", j+1, " reached at price ", targets[j].price, 
                           ". Closed ", volumeToClose, " lots (", targets[j].percentToClose, "%)");
                  }
               }
               else
               {
                  Print("Error closing partial position: ", GetLastError());
               }
               
               // Only process one target per cycle
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions                                            |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if a specific position type is open                        |
//+------------------------------------------------------------------+
bool IsPositionOpen(ENUM_POSITION_TYPE posType)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_TYPE) == posType)
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close all positions of a specific type                          |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_TYPE) == posType)
      {
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stops for open positions                        |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   // Check if buffer is valid and has data
   if(ArraySize(atrTrailingStopBuffer) == 0 || atrTrailingStopBuffer[0] == 0)
   {
      if(EnableDebugMode)
         Print("Warning: atrTrailingStopBuffer is empty or invalid");
      return;
   }
   
   // Cache the trailing stop value to avoid repetitive buffer access
   double currentTrailingStop = atrTrailingStopBuffer[0];
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double currentStopLoss = PositionGetDouble(POSITION_SL);
         double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         // For buy positions
         if(posType == POSITION_TYPE_BUY)
         {
            // Normalize the stop loss value with proper precision
            double newStopLoss = NormalizeDouble(currentTrailingStop, _Digits);
            
            // Only modify if there's a significant difference (to reduce unnecessary modifications)
            if(newStopLoss > currentStopLoss + 10*_Point && newStopLoss < SymbolInfoDouble(_Symbol, SYMBOL_BID))
            {
               trade.PositionModify(
                  ticket,
                  newStopLoss,
                  PositionGetDouble(POSITION_TP)
               );
               
               if(EnableDebugMode)
                  Print("Updated trailing stop for BUY position to ", newStopLoss);
            }
         }
         // For sell positions
         else if(posType == POSITION_TYPE_SELL)
         {
            // Normalize the stop loss value with proper precision
            double newStopLoss = NormalizeDouble(currentTrailingStop, _Digits);
            
            // Only modify if there's a significant difference and new SL is below current price
            if((currentStopLoss == 0 || newStopLoss < currentStopLoss - 10*_Point) && 
               newStopLoss > SymbolInfoDouble(_Symbol, SYMBOL_ASK))
            {
               trade.PositionModify(
                  ticket,
                  newStopLoss,
                  PositionGetDouble(POSITION_TP)
               );
               
               if(EnableDebugMode)
                  Print("Updated trailing stop for SELL position to ", newStopLoss);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if the market is open                                     |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   // Get current time
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   
   // Check if it's the weekend
   if(now.day_of_week == 0 || now.day_of_week == 6)
   {
      if(EnableDebugMode && tickCounter >= CheckEveryXTicks)
         Print("Market appears closed (weekend day)");
      return false;
   }
   
   // Additional check for market activity
   double tick_volume = iVolume(_Symbol, PERIOD_CURRENT, 0);
   if(tick_volume <= 0)
   {
      if(EnableDebugMode && tickCounter >= CheckEveryXTicks)
         Print("Warning: Current bar has no volume data. Market may be closed.");
   }
   
   // Check if data feed is active
   datetime last_server_time = 0;
   RefreshRates();  // Force update to current rates
   
   last_server_time = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
   
   // If data feed is stale for more than 1 hour, consider market closed
   if(TimeCurrent() - last_server_time > 3600)
   {
      if(EnableDebugMode && tickCounter >= CheckEveryXTicks)
         Print("Warning: Stale data feed (last update ", TimeToString(last_server_time), "). Market may be closed.");
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+