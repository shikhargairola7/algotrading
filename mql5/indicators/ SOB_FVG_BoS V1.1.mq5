//+------------------------------------------------------------------+
//|         SOB_FVG_BoS_Step4_Integrated_OB_Test.mq5                 |
//|  Test indicator: Draws OB rectangles that extend until mitigated  |
//|  only if the bar qualifies as a Bullish OB or Bearish OB.          |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

// Dummy plot properties (required for custom indicators)
#property indicator_label1  "Dummy"
#property indicator_type1   DRAW_NONE
#property indicator_color1  clrWhite

// Global buffer for dummy plot
double DummyBuffer[];

//--------------------------------------------------------------------------
// Step 1: Input Definitions
//--------------------------------------------------------------------------
input bool   InpPlotOB         = true;      // Enable OB drawing
input color  InpOB_BullColor   = clrGreen;  // Color for Bullish OB
input color  InpOB_BearColor   = clrRed;    // Color for Bearish OB
input ENUM_LINE_STYLE InpOB_BoxBorder = STYLE_SOLID; // Border style for OB boxes
input int    InpOB_MaxBoxCount = 100;       // Maximum number of OB boxes
input int    InpOB_LookbackBars = 500;      // Number of bars to look back for OBs

//--------------------------------------------------------------------------
// Step 2: Global variables for OB tracking
//--------------------------------------------------------------------------
#define MAX_OB_BOXES 200

// Structure to hold OB data
struct OrderBlock {
   bool     isValid;          // Whether this OB is valid/active
   bool     isBullish;        // Whether this is a bullish (true) or bearish (false) OB
   bool     isMitigated;      // Whether this OB has been mitigated
   datetime startTime;        // Start time of the OB (left edge)
   datetime mitigationTime;   // Time when the OB was mitigated (right edge for mitigated OBs)
   double   topPrice;         // Top price of the OB
   double   bottomPrice;      // Bottom price of the OB
   string   objectName;       // Name of the rectangle object
};

// Array to store OB data
OrderBlock g_OrderBlocks[MAX_OB_BOXES];
int g_OBCount = 0;

//--------------------------------------------------------------------------
// Step 3: Helper Functions for Market Condition Checks
//--------------------------------------------------------------------------

// Returns true if bar 'i' is bullish (close > open)
bool IsUp(const int i, const double &open[], const double &close[], const int rates_total)
{
   if(i < 0 || i >= rates_total) return false;
   return (close[i] > open[i]);
}

// Returns true if bar 'i' is bearish (close < open)
bool IsDown(const int i, const double &open[], const double &close[], const int rates_total)
{
   if(i < 0 || i >= rates_total) return false;
   return (close[i] < open[i]);
}

// Returns true if bar 'i' qualifies as a Bullish OB
bool IsObUp(const int i, const double &open[], const double &close[],
            const double &high[], const double &low[], const int rates_total)
{
   if(i < 0 || i+1 >= rates_total) return false;
   
   // First check basic conditions
   bool prevBarBearish = IsDown(i+1, open, close, rates_total);
   bool currBarBullish = IsUp(i, open, close, rates_total);
   
   // If basic conditions are met, check for breakout
   if(currBarBullish && prevBarBearish)
   {
      // Check if current bar's close breaks above previous bar's high
      return (close[i] > high[i+1]);
   }
   
   return false;
}

// Returns true if bar 'i' qualifies as a Bearish OB
bool IsObDown(const int i, const double &open[], const double &close[],
              const double &high[], const double &low[], const int rates_total)
{
   if(i < 0 || i+1 >= rates_total) return false;
   
   // First check basic conditions
   bool prevBarBullish = IsUp(i+1, open, close, rates_total);
   bool currBarBearish = IsDown(i, open, close, rates_total);
   
   // If basic conditions are met, check for breakout
   if(prevBarBullish && currBarBearish)
   {
      // Check if current bar's close breaks below previous bar's low
      return (close[i] < low[i+1]);
   }
   
   return false;
}

// Check if OB is mitigated by analyzing price history
bool IsObMitigated(int obIndex, const double &low[], const double &high[], const datetime &time[], const int rates_total)
{
   if(obIndex < 0 || obIndex >= g_OBCount) return false;
   if(!g_OrderBlocks[obIndex].isValid) return true;
   
   // Get OB creation time
   datetime obTime = g_OrderBlocks[obIndex].startTime;
   
   // For bullish OB: mitigated if price goes below the bottom of the OB
   // For bearish OB: mitigated if price goes above the top of the OB
   
   // Scan price action after OB formation
   for(int i = rates_total-1; i >= 0; i--)
   {
      // Only check bars after OB was formed
      if(time[i] <= obTime) continue;
      
      if(g_OrderBlocks[obIndex].isBullish)
      {
         // Bullish OB is mitigated when price drops below its bottom
         if(low[i] < g_OrderBlocks[obIndex].bottomPrice)
         {
            // Store the mitigation time for drawing the rectangle
            g_OrderBlocks[obIndex].mitigationTime = time[i];
            return true;
         }
      }
      else
      {
         // Bearish OB is mitigated when price rises above its top
         if(high[i] > g_OrderBlocks[obIndex].topPrice)
         {
            // Store the mitigation time for drawing the rectangle
            g_OrderBlocks[obIndex].mitigationTime = time[i];
            return true;
         }
      }
   }
   
   return false;
}

//--------------------------------------------------------------------------
// Step 4: Box Management & Drawing Functions
//--------------------------------------------------------------------------

// WriteLabelInsideBox: Creates a text object centered inside an existing rectangle
bool WriteLabelInsideBox(const string boxName, const string labelText, color textColor, int fontSize)
{
   // Retrieve rectangle coordinates
   datetime leftTime = (datetime)ObjectGetInteger(0, boxName, OBJPROP_TIME, 0);
   datetime rightTime = (datetime)ObjectGetInteger(0, boxName, OBJPROP_TIME, 1);
   double topPrice = ObjectGetDouble(0, boxName, OBJPROP_PRICE, 0);
   double bottomPrice = ObjectGetDouble(0, boxName, OBJPROP_PRICE, 1);
   
   if(leftTime == 0 || rightTime == 0)
   {
      Print("Invalid rectangle coordinates for ", boxName);
      return false;
   }
   
   // Calculate the center position
   datetime centerTime = (datetime)(leftTime + (rightTime - leftTime) / 2);
   double centerPrice = bottomPrice + (topPrice - bottomPrice) / 2;
   
   // Create a unique text object name
   string textObjName = boxName + "_label";
   if(ObjectFind(0, textObjName) != -1)
      ObjectDelete(0, textObjName);
   
   // Create the text object
   if(!ObjectCreate(0, textObjName, OBJ_TEXT, 0, centerTime, centerPrice))
   {
      Print("Failed to create text object ", textObjName, ", error: ", GetLastError());
      return false;
   }
   
   // Set text properties
   ObjectSetString(0, textObjName, OBJPROP_TEXT, labelText);
   ObjectSetInteger(0, textObjName, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, textObjName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, textObjName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, textObjName, OBJPROP_ANCHOR, ANCHOR_CENTER);
   
   return true;
}

// DrawOBRectangle: Creates or updates an OB rectangle
bool DrawOBRectangle(int obIndex)
{
   if(obIndex < 0 || obIndex >= g_OBCount) return false;
   if(!g_OrderBlocks[obIndex].isValid) return false;
   
   string name = g_OrderBlocks[obIndex].objectName;
   color c = g_OrderBlocks[obIndex].isBullish ? InpOB_BullColor : InpOB_BearColor;
   datetime leftTime = g_OrderBlocks[obIndex].startTime;
   double topPrice = g_OrderBlocks[obIndex].topPrice;
   double bottomPrice = g_OrderBlocks[obIndex].bottomPrice;
   
   // For mitigated OBs, use the mitigation time as right edge
   // For unmitigated OBs, use current time
   datetime rightTime = g_OrderBlocks[obIndex].isMitigated ? 
                       g_OrderBlocks[obIndex].mitigationTime : 
                       TimeCurrent();
   
   // If an object with the same name exists, delete it
   if(ObjectFind(0, name) != -1)
      ObjectDelete(0, name);
      
   // Create the rectangle
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, leftTime, topPrice, rightTime, bottomPrice))
   {
      Print("Failed to create rectangle: ", name, ", error: ", GetLastError());
      return false;
   }
   
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_STYLE, InpOB_BoxBorder);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);  // Draw behind the price
   
   // Add label
   string labelText = g_OrderBlocks[obIndex].isBullish ? "BULL OB+" : "Bear OB-";
   color textColor = g_OrderBlocks[obIndex].isBullish ? clrGreen : clrRed;
   WriteLabelInsideBox(name, labelText, textColor, 10);
   
   return true;
}

//--------------------------------------------------------------------------
// OnInit: Initialization function
//--------------------------------------------------------------------------
int OnInit()
{
   // Initialize OB array
   for(int i = 0; i < MAX_OB_BOXES; i++)
   {
      g_OrderBlocks[i].isValid = false;
      g_OrderBlocks[i].isMitigated = false;
      g_OrderBlocks[i].objectName = "OB_" + IntegerToString(i);
   }
   
   SetIndexBuffer(0, DummyBuffer, INDICATOR_DATA);
   ArraySetAsSeries(DummyBuffer, true);
   
   // Force full recalculation
   ChartRedraw();
   
   return(INIT_SUCCEEDED);
}

//--------------------------------------------------------------------------
// OnDeinit: Clean up objects when indicator is removed
//--------------------------------------------------------------------------
void OnDeinit(const int reason)
{
   // Delete all OB objects
   for(int i = 0; i < MAX_OB_BOXES; i++)
   {
      string name = "OB_" + IntegerToString(i);
      if(ObjectFind(0, name) != -1)
         ObjectDelete(0, name);
         
      string labelName = name + "_label";
      if(ObjectFind(0, labelName) != -1)
         ObjectDelete(0, labelName);
   }
}

//--------------------------------------------------------------------------
// OnCalculate: Main function where OB rectangles and labels are drawn.
//--------------------------------------------------------------------------
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // Ensure arrays are treated as series (index 0 is the most recent bar)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(rates_total > 0)
      DummyBuffer[0] = 0.0;
   
   // Complete recalculation on first call
   if(prev_calculated == 0)
   {
      Print("Performing full OB scan...");
      // Reset OB counter and clear objects
      g_OBCount = 0;
      
      for(int i = 0; i < MAX_OB_BOXES; i++)
      {
         g_OrderBlocks[i].isValid = false;
         g_OrderBlocks[i].isMitigated = false;
         
         string name = "OB_" + IntegerToString(i);
         if(ObjectFind(0, name) != -1)
            ObjectDelete(0, name);
            
         string labelName = name + "_label";
         if(ObjectFind(0, labelName) != -1)
            ObjectDelete(0, labelName);
      }
      
      // Process historical data to find OBs - scan from oldest to newest
      int numBars = MathMin(InpOB_LookbackBars, rates_total - 2);
      
      for(int i = numBars; i > 0; i--)
      {
         if(!InpPlotOB || g_OBCount >= InpOB_MaxBoxCount) break;
         
         // Check for Bullish OB
         if(IsObUp(i, open, close, high, low, rates_total))
         {
            // Previous bar becomes the OB
            int prevBar = i+1;
            
            // Store OB data
            g_OrderBlocks[g_OBCount].isValid = true;
            g_OrderBlocks[g_OBCount].isBullish = true;
            g_OrderBlocks[g_OBCount].isMitigated = false;
            g_OrderBlocks[g_OBCount].startTime = time[prevBar];
            g_OrderBlocks[g_OBCount].topPrice = high[prevBar];
            g_OrderBlocks[g_OBCount].bottomPrice = low[prevBar];
            g_OrderBlocks[g_OBCount].objectName = "OB_" + IntegerToString(g_OBCount);
            
            // Check if this OB is already mitigated
            g_OrderBlocks[g_OBCount].isMitigated = IsObMitigated(g_OBCount, low, high, time, rates_total);
            
            // Draw the OB
            DrawOBRectangle(g_OBCount);
            
            g_OBCount++;
         }
         // Check for Bearish OB
         else if(IsObDown(i, open, close, high, low, rates_total))
         {
            // Previous bar becomes the OB
            int prevBar = i+1;
            
            // Store OB data
            g_OrderBlocks[g_OBCount].isValid = true;
            g_OrderBlocks[g_OBCount].isBullish = false;
            g_OrderBlocks[g_OBCount].isMitigated = false;
            g_OrderBlocks[g_OBCount].startTime = time[prevBar];
            g_OrderBlocks[g_OBCount].topPrice = high[prevBar];
            g_OrderBlocks[g_OBCount].bottomPrice = low[prevBar];
            g_OrderBlocks[g_OBCount].objectName = "OB_" + IntegerToString(g_OBCount);
            
            // Check if this OB is already mitigated
            g_OrderBlocks[g_OBCount].isMitigated = IsObMitigated(g_OBCount, low, high, time, rates_total);
            
            // Draw the OB
            DrawOBRectangle(g_OBCount);
            
            g_OBCount++;
         }
      }
      
      Print("Found ", g_OBCount, " order blocks");
   }
   else
   {
      // Check for new OB on the most recent completed bar (index 1)
      if(InpPlotOB && g_OBCount < InpOB_MaxBoxCount)
      {
         // Check for Bullish OB
         if(IsObUp(1, open, close, high, low, rates_total))
         {
            // Previous bar becomes the OB
            int prevBar = 2;
            
            // Store OB data
            g_OrderBlocks[g_OBCount].isValid = true;
            g_OrderBlocks[g_OBCount].isBullish = true;
            g_OrderBlocks[g_OBCount].isMitigated = false;
            g_OrderBlocks[g_OBCount].startTime = time[prevBar];
            g_OrderBlocks[g_OBCount].topPrice = high[prevBar];
            g_OrderBlocks[g_OBCount].bottomPrice = low[prevBar];
            g_OrderBlocks[g_OBCount].objectName = "OB_" + IntegerToString(g_OBCount);
            
            // New OB won't be mitigated yet, so draw it
            DrawOBRectangle(g_OBCount);
            
            g_OBCount++;
         }
         // Check for Bearish OB
         else if(IsObDown(1, open, close, high, low, rates_total))
         {
            // Previous bar becomes the OB
            int prevBar = 2;
            
            // Store OB data
            g_OrderBlocks[g_OBCount].isValid = true;
            g_OrderBlocks[g_OBCount].isBullish = false;
            g_OrderBlocks[g_OBCount].isMitigated = false;
            g_OrderBlocks[g_OBCount].startTime = time[prevBar];
            g_OrderBlocks[g_OBCount].topPrice = high[prevBar];
            g_OrderBlocks[g_OBCount].bottomPrice = low[prevBar];
            g_OrderBlocks[g_OBCount].objectName = "OB_" + IntegerToString(g_OBCount);
            
            // New OB won't be mitigated yet, so draw it
            DrawOBRectangle(g_OBCount);
            
            g_OBCount++;
         }
      }
      
      // Update all existing OBs - check for mitigation and redraw active ones
      for(int i = 0; i < g_OBCount; i++)
      {
         if(g_OrderBlocks[i].isValid && !g_OrderBlocks[i].isMitigated)
         {
            // Check if mitigated by current price
            bool wasMitigated = false;
            
            if(g_OrderBlocks[i].isBullish)
            {
               // Bullish OB is mitigated if price goes below bottom
               if(low[0] < g_OrderBlocks[i].bottomPrice)
               {
                  wasMitigated = true;
                  g_OrderBlocks[i].mitigationTime = time[0];
               }
            }
            else
            {
               // Bearish OB is mitigated if price goes above top
               if(high[0] > g_OrderBlocks[i].topPrice)
               {
                  wasMitigated = true;
                  g_OrderBlocks[i].mitigationTime = time[0];
               }
            }
            
            if(wasMitigated)
            {
               g_OrderBlocks[i].isMitigated = true;
            }
            
            // Always redraw the OB - mitigated ones with fixed width, 
            // unmitigated ones extended to current time
            DrawOBRectangle(i);
         }
      }
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+