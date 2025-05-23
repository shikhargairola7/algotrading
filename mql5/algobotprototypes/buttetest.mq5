//+------------------------------------------------------------------+
//|                      Gold Butterfly Pattern EA                   |
//|                       Copyright 2025, MetaTrader                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaTrader"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade Trade;

// Input Parameters
input group "Pattern Detection Settings"
input int     SwingStrength = 4;         // Swing point strength (bars on each side)
input int     MaxPatternBars = 60;       // Maximum bars for pattern formation
input int     MinPatternBars = 10;       // Minimum bars for pattern formation
input double  FibTolerance = 0.35;       // Fibonacci ratio tolerance (35%)

input group "Trading Settings"
input bool    EnableTrading = true;      // Enable automatic trading
input double  LotSize = 0.01;            // Trading lot size
input double  RiskPercent = 0;           // Risk percent per trade (0 = fixed lot)
input int     StopLossPips = 200;        // Stop loss in pips (0 = auto based on pattern)
input int     TakeProfitPips = 0;        // Take profit in pips (0 = auto based on pattern)
input double  TPRatio = 0.618;           // Take profit at this ratio of pattern size
input bool    UseBreakeven = true;       // Enable breakeven at 1:1 risk/reward
input bool    UseTrailingStop = true;    // Enable trailing stop
input int     TrailingStopPips = 50;     // Trailing stop in pips
input bool    HidePatterns = false;      // Hide pattern visualization

input group "Filter Settings"
input bool    FilterByStrength = true;   // Filter by pattern quality/strength
input double  MinQualityScore = 75;      // Minimum pattern quality score (0-100)
input bool    FilterByDirection = false; // Filter by market direction
input int     DirectionMA = 50;          // MA period for direction filter
input bool    FilterByVolatility = true; // Filter by volatility
input double  MaxVolatility = 3.0;       // Maximum volatility (ATR multiple)

input group "Expert Settings"
input int     MagicNumber = 9547721;     // EA magic number
input string  TradeComment = "Butterfly";// Trade comment
input bool    DisplayInfo = true;        // Display information on chart
input bool    EnableAlerts = true;       // Enable alerts
input bool    EnableEmail = false;       // Enable email notifications
input bool    EnablePush = false;        // Enable push notifications

// Pattern structure
struct PatternPoint {
    datetime time;
    double price;
    int bar;
    bool isHigh;
};

struct ButterflyPattern {
    PatternPoint X;
    PatternPoint A;
    PatternPoint B;
    PatternPoint C;
    PatternPoint D;
    string type;
    double quality;
    datetime detectionTime;
};

// Global variables
ButterflyPattern activePattern;
bool patternDetected = false;
bool orderPlaced = false;
int lastAnalyzedBar = -1;
double pointValue;
string symbolSuffix;

// Buffers for ZigZag points
double highPivots[];
double lowPivots[];
datetime highPivotTime[];
datetime lowPivotTime[];
int highPivotIndex[];
int lowPivotIndex[];
int barCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Basic initialization
    Trade.SetExpertMagicNumber(MagicNumber);
    pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    symbolSuffix = _Symbol;
    
    // Configure arrays
    ArraySetAsSeries(highPivots, true);
    ArraySetAsSeries(lowPivots, true);
    ArraySetAsSeries(highPivotTime, true);
    ArraySetAsSeries(lowPivotTime, true);
    ArraySetAsSeries(highPivotIndex, true);
    ArraySetAsSeries(lowPivotIndex, true);
    
    // Initial messages
    Print("Gold Butterfly Pattern EA initialized");
    Print("Symbol: ", _Symbol, ", Point value: ", pointValue);
    
    // Create info label on chart
    if(DisplayInfo) {
        CreateLabel("LblInfo", "Gold Butterfly EA Running", 20, 20, clrWhite, CORNER_LEFT_UPPER);
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clean up any objects
    ObjectsDeleteAll(0, "BF_");
    if(DisplayInfo) {
        ObjectDelete(0, "LblInfo");
    }
    Print("Gold Butterfly Pattern EA removed");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Only process on new bars
    if(IsNewBar()) {
        AnalyzeMarket();
        ManageOpenTrades();
    }
}

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                    |
//+------------------------------------------------------------------+
bool IsNewBar() {
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    if(lastBar != currentBar) {
        lastBar = currentBar;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Analyze the market for butterfly patterns                        |
//+------------------------------------------------------------------+
void AnalyzeMarket() {
    // Get bar count
    barCount = Bars(_Symbol, PERIOD_CURRENT);
    
    // Skip if we've already analyzed this bar
    if(lastAnalyzedBar == barCount) return;
    lastAnalyzedBar = barCount;
    
    // Find swing points
    FindSwingPoints();
    
    // Search for patterns
    patternDetected = FindButterflyPattern();
    
    // Place orders if pattern is detected
    if(patternDetected && EnableTrading && !orderPlaced) {
        ExecuteTradeSignal();
    }
}

//+------------------------------------------------------------------+
//| Find swing high and low points                                   |
//+------------------------------------------------------------------+
void FindSwingPoints() {
    // Reset arrays
    ArrayFree(highPivots);
    ArrayFree(lowPivots);
    ArrayFree(highPivotTime);
    ArrayFree(lowPivotTime);
    ArrayFree(highPivotIndex);
    ArrayFree(lowPivotIndex);
    
    // Configure sizes
    int maxBars = MathMin(barCount, 500); // Limit to 500 bars for performance
    ArrayResize(highPivots, maxBars);
    ArrayResize(lowPivots, maxBars);
    ArrayResize(highPivotTime, maxBars);
    ArrayResize(lowPivotTime, maxBars);
    ArrayResize(highPivotIndex, maxBars);
    ArrayResize(lowPivotIndex, maxBars);
    
    // Initialize arrays
    for(int i = 0; i < maxBars; i++) {
        highPivots[i] = 0;
        lowPivots[i] = 0;
    }
    
    // Find high and low pivot points
    int highCount = 0;
    int lowCount = 0;
    
    for(int i = SwingStrength; i < maxBars - SwingStrength; i++) {
        bool isHigh = true;
        bool isLow = true;
        double currentHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
        double currentLow = iLow(_Symbol, PERIOD_CURRENT, i);
        
        // Check surrounding bars
        for(int j = i - SwingStrength; j <= i + SwingStrength; j++) {
            if(j == i) continue;
            
            if(iHigh(_Symbol, PERIOD_CURRENT, j) >= currentHigh) isHigh = false;
            if(iLow(_Symbol, PERIOD_CURRENT, j) <= currentLow) isLow = false;
            
            if(!isHigh && !isLow) break;
        }
        
        // Record pivot points
        if(isHigh) {
            highPivots[highCount] = currentHigh;
            highPivotTime[highCount] = iTime(_Symbol, PERIOD_CURRENT, i);
            highPivotIndex[highCount] = i;
            highCount++;
        }
        
        if(isLow) {
            lowPivots[lowCount] = currentLow;
            lowPivotTime[lowCount] = iTime(_Symbol, PERIOD_CURRENT, i);
            lowPivotIndex[lowCount] = i;
            lowCount++;
        }
    }
    
    // Resize arrays to actual count
    ArrayResize(highPivots, highCount);
    ArrayResize(lowPivots, lowCount);
    ArrayResize(highPivotTime, highCount);
    ArrayResize(lowPivotTime, lowCount);
    ArrayResize(highPivotIndex, highCount);
    ArrayResize(lowPivotIndex, lowCount);
    
    // Debug info
    Print("Found ", highCount, " swing highs and ", lowCount, " swing lows");
}

//+------------------------------------------------------------------+
//| Find butterfly pattern among swing points                        |
//+------------------------------------------------------------------+
bool FindButterflyPattern() {
    // Reset active pattern
    activePattern.quality = 0;
    
    // Need at least 3 swing highs and 2 swing lows or vice versa
    if(ArraySize(highPivots) < 2 || ArraySize(lowPivots) < 2) return false;
    
    // Search for bullish butterfly (X=low, A=high, B=low, C=high, D=low)
    SearchBullishButterfly();
    
    // Search for bearish butterfly (X=high, A=low, B=high, C=low, D=high)
    SearchBearishButterfly();
    
    // Display the pattern if found and scored well
    if(activePattern.quality > MinQualityScore) {
        if(!HidePatterns) {
            DisplayPattern();
        }
        
        // Alert if needed
        if(EnableAlerts && !orderPlaced) {
            string message = activePattern.type + " Butterfly pattern detected! Quality: " + 
                             DoubleToString(activePattern.quality, 1) + "%";
            Alert(message);
            
            if(EnableEmail) SendMail("Butterfly Pattern Alert", message);
            if(EnablePush) SendNotification(message);
        }
        
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Search for bullish butterfly pattern                             |
//+------------------------------------------------------------------+
void SearchBullishButterfly() {
    int lowCount = ArraySize(lowPivots);
    int highCount = ArraySize(highPivots);
    
    // Need at least 3 lows (X, B, D) and 2 highs (A, C)
    if(lowCount < 3 || highCount < 2) return;
    
    // Create temporary structure for pattern candidates
    ButterflyPattern candidatePattern;
    candidatePattern.type = "Bullish";
    
    // Loop through potential X points (starting from older swing lows)
    for(int xi = lowCount - 1; xi >= 2; xi--) {
        candidatePattern.X.price = lowPivots[xi];
        candidatePattern.X.time = lowPivotTime[xi];
        candidatePattern.X.bar = lowPivotIndex[xi];
        candidatePattern.X.isHigh = false;
        
        // Find A point (must be a high after X)
        for(int ai = highCount - 1; ai >= 1; ai--) {
            if(highPivotTime[ai] <= lowPivotTime[xi]) continue; // A must be after X
            
            candidatePattern.A.price = highPivots[ai];
            candidatePattern.A.time = highPivotTime[ai];
            candidatePattern.A.bar = highPivotIndex[ai];
            candidatePattern.A.isHigh = true;
            
            // Calculate XA leg
            double XA = candidatePattern.A.price - candidatePattern.X.price;
            if(XA <= 0) continue; // XA must be positive (upward)
            
            // Find B point (must be a low after A)
            for(int bi = lowCount - 1; bi >= 1; bi--) {
                if(lowPivotTime[bi] <= highPivotTime[ai]) continue; // B must be after A
                
                candidatePattern.B.price = lowPivots[bi];
                candidatePattern.B.time = lowPivotTime[bi];
                candidatePattern.B.bar = lowPivotIndex[bi];
                candidatePattern.B.isHigh = false;
                
                // Calculate AB leg and validate B position (B should be a 0.786 retracement of XA)
                double AB = candidatePattern.A.price - candidatePattern.B.price;
                double idealB = candidatePattern.A.price - 0.786 * XA;
                double bDeviation = MathAbs(candidatePattern.B.price - idealB) / XA;
                
                if(bDeviation > FibTolerance) continue; // B is too far from ideal position
                
                // Find C point (must be a high after B)
                for(int ci = highCount - 1; ci >= 0; ci--) {
                    if(highPivotTime[ci] <= lowPivotTime[bi]) continue; // C must be after B
                    
                    candidatePattern.C.price = highPivots[ci];
                    candidatePattern.C.time = highPivotTime[ci];
                    candidatePattern.C.bar = highPivotIndex[ci];
                    candidatePattern.C.isHigh = true;
                    
                    // Calculate BC leg (BC should be between 0.382 and 0.886 of XA)
                    double BC = candidatePattern.C.price - candidatePattern.B.price;
                    double bcRatio = BC / XA;
                    
                    if(bcRatio < 0.382 - FibTolerance || bcRatio > 0.886 + FibTolerance) continue;
                    
                    // Find D point (must be a low after C)
                    for(int di = lowCount - 1; di >= 0; di--) {
                        if(lowPivotTime[di] <= highPivotTime[ci]) continue; // D must be after C
                        
                        candidatePattern.D.price = lowPivots[di];
                        candidatePattern.D.time = lowPivotTime[di];
                        candidatePattern.D.bar = lowPivotIndex[di];
                        candidatePattern.D.isHigh = false;
                        
                        // Calculate CD leg (CD should be between 1.27 and 1.618 of XA)
                        double CD = candidatePattern.C.price - candidatePattern.D.price;
                        double cdRatio = CD / XA;
                        
                        if(cdRatio < 1.27 - FibTolerance || cdRatio > 1.618 + FibTolerance) continue;
                        
                        // Check if D is below X (not strict requirement but preferred)
                        bool dBelowX = candidatePattern.D.price < candidatePattern.X.price;
                        
                        // Calculate pattern quality score (0-100)
                        double qualityScore = CalculatePatternQuality(
                            bDeviation, bcRatio, cdRatio, dBelowX, true);
                        
                        // Update the active pattern if this one scores better
                        if(qualityScore > activePattern.quality) {
                            activePattern = candidatePattern;
                            activePattern.quality = qualityScore;
                            activePattern.detectionTime = iTime(_Symbol, PERIOD_CURRENT, 0);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Search for bearish butterfly pattern                             |
//+------------------------------------------------------------------+
void SearchBearishButterfly() {
    int highCount = ArraySize(highPivots);
    int lowCount = ArraySize(lowPivots);
    
    // Need at least 3 highs (X, B, D) and 2 lows (A, C)
    if(highCount < 3 || lowCount < 2) return;
    
    // Create temporary structure for pattern candidates
    ButterflyPattern candidatePattern;
    candidatePattern.type = "Bearish";
    
    // Loop through potential X points (starting from older swing highs)
    for(int xi = highCount - 1; xi >= 2; xi--) {
        candidatePattern.X.price = highPivots[xi];
        candidatePattern.X.time = highPivotTime[xi];
        candidatePattern.X.bar = highPivotIndex[xi];
        candidatePattern.X.isHigh = true;
        
        // Find A point (must be a low after X)
        for(int ai = lowCount - 1; ai >= 1; ai--) {
            if(lowPivotTime[ai] <= highPivotTime[xi]) continue; // A must be after X
            
            candidatePattern.A.price = lowPivots[ai];
            candidatePattern.A.time = lowPivotTime[ai];
            candidatePattern.A.bar = lowPivotIndex[ai];
            candidatePattern.A.isHigh = false;
            
            // Calculate XA leg
            double XA = candidatePattern.X.price - candidatePattern.A.price;
            if(XA <= 0) continue; // XA must be positive (downward)
            
            // Find B point (must be a high after A)
            for(int bi = highCount - 1; bi >= 1; bi--) {
                if(highPivotTime[bi] <= lowPivotTime[ai]) continue; // B must be after A
                
                candidatePattern.B.price = highPivots[bi];
                candidatePattern.B.time = highPivotTime[bi];
                candidatePattern.B.bar = highPivotIndex[bi];
                candidatePattern.B.isHigh = true;
                
                // Calculate AB leg and validate B position (B should be a 0.786 retracement of XA)
                double AB = candidatePattern.B.price - candidatePattern.A.price;
                double idealB = candidatePattern.A.price + 0.786 * XA;
                double bDeviation = MathAbs(candidatePattern.B.price - idealB) / XA;
                
                if(bDeviation > FibTolerance) continue; // B is too far from ideal position
                
                // Find C point (must be a low after B)
                for(int ci = lowCount - 1; ci >= 0; ci--) {
                    if(lowPivotTime[ci] <= highPivotTime[bi]) continue; // C must be after B
                    
                    candidatePattern.C.price = lowPivots[ci];
                    candidatePattern.C.time = lowPivotTime[ci];
                    candidatePattern.C.bar = lowPivotIndex[ci];
                    candidatePattern.C.isHigh = false;
                    
                    // Calculate BC leg (BC should be between 0.382 and 0.886 of XA)
                    double BC = candidatePattern.B.price - candidatePattern.C.price;
                    double bcRatio = BC / XA;
                    
                    if(bcRatio < 0.382 - FibTolerance || bcRatio > 0.886 + FibTolerance) continue;
                    
                    // Find D point (must be a high after C)
                    for(int di = highCount - 1; di >= 0; di--) {
                        if(highPivotTime[di] <= lowPivotTime[ci]) continue; // D must be after C
                        
                        candidatePattern.D.price = highPivots[di];
                        candidatePattern.D.time = highPivotTime[di];
                        candidatePattern.D.bar = highPivotIndex[di];
                        candidatePattern.D.isHigh = true;
                        
                        // Calculate CD leg (CD should be between 1.27 and 1.618 of XA)
                        double CD = candidatePattern.D.price - candidatePattern.C.price;
                        double cdRatio = CD / XA;
                        
                        if(cdRatio < 1.27 - FibTolerance || cdRatio > 1.618 + FibTolerance) continue;
                        
                        // Check if D is above X (not strict requirement but preferred)
                        bool dAboveX = candidatePattern.D.price > candidatePattern.X.price;
                        
                        // Calculate pattern quality score (0-100)
                        double qualityScore = CalculatePatternQuality(
                            bDeviation, bcRatio, cdRatio, dAboveX, false);
                        
                        // Update the active pattern if this one scores better
                        if(qualityScore > activePattern.quality) {
                            activePattern = candidatePattern;
                            activePattern.quality = qualityScore;
                            activePattern.detectionTime = iTime(_Symbol, PERIOD_CURRENT, 0);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate the quality score for a pattern (0-100)                |
//+------------------------------------------------------------------+
double CalculatePatternQuality(double bDeviation, double bcRatio, double cdRatio, 
                              bool dPositionGood, bool isBullish) {
    double score = 100.0;
    
    // Penalize for B deviation from ideal
    double bPenalty = (bDeviation / FibTolerance) * 30.0;
    score -= bPenalty;
    
    // Penalize for BC ratio deviation from ideal (0.618)
    double bcPenalty = MathAbs(bcRatio - 0.618) / 0.5 * 20.0;
    score -= bcPenalty;
    
    // Penalize for CD ratio deviation from ideal (1.414)
    double cdPenalty = MathAbs(cdRatio - 1.414) / 0.344 * 20.0;
    score -= cdPenalty;
    
    // Penalize if D is not positioned well relative to X
    if(!dPositionGood) score -= 10.0;
    
    // Apply directional filter if needed
    if(FilterByDirection) {
        double maValue = iMA(_Symbol, PERIOD_CURRENT, DirectionMA, 0, MODE_SMA, PRICE_CLOSE);
        double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
        bool isUptrend = currentPrice > maValue;
        
        // Penalize counter-trend patterns
        if((isBullish && !isUptrend) || (!isBullish && isUptrend)) {
            score -= 15.0;
        }
    }
    
    // Apply volatility filter if needed
    if(FilterByVolatility) {
        double atr = iATR(_Symbol, PERIOD_CURRENT, 14);
        double normalizedATR = atr / iClose(_Symbol, PERIOD_CURRENT, 0) * 100.0; // ATR as percentage of price
        
        if(normalizedATR > MaxVolatility) {
            score -= (normalizedATR - MaxVolatility) * 10.0;
        }
    }
    
    // Ensure score stays within 0-100 range
    score = MathMax(0, MathMin(100, score));
    
    return score;
}

//+------------------------------------------------------------------+
//| Display the detected pattern on the chart                        |
//+------------------------------------------------------------------+
void DisplayPattern() {
    // Clear previous pattern objects
    ObjectsDeleteAll(0, "BF_");
    
    // Create a unique name for this pattern
    string patternName = "BF_" + TimeToString(activePattern.detectionTime);
    
    // Set colors based on pattern type
    color patternColor = (activePattern.type == "Bullish") ? clrGreen : clrRed;
    
    // Draw lines connecting pattern points
    DrawLine(patternName + "_XA", activePattern.X.time, activePattern.X.price, 
             activePattern.A.time, activePattern.A.price, patternColor);
    
    DrawLine(patternName + "_AB", activePattern.A.time, activePattern.A.price, 
             activePattern.B.time, activePattern.B.price, patternColor);
    
    DrawLine(patternName + "_BC", activePattern.B.time, activePattern.B.price, 
             activePattern.C.time, activePattern.C.price, patternColor);
    
    DrawLine(patternName + "_CD", activePattern.C.time, activePattern.C.price, 
             activePattern.D.time, activePattern.D.price, patternColor);
    
    // Draw points with labels
    DrawPoint(patternName + "_X", activePattern.X.time, activePattern.X.price, "X", patternColor);
    DrawPoint(patternName + "_A", activePattern.A.time, activePattern.A.price, "A", patternColor);
    DrawPoint(patternName + "_B", activePattern.B.time, activePattern.B.price, "B", patternColor);
    DrawPoint(patternName + "_C", activePattern.C.time, activePattern.C.price, "C", patternColor);
    DrawPoint(patternName + "_D", activePattern.D.time, activePattern.D.price, "D", patternColor);
    
    // Draw pattern name
    string nameText = activePattern.type + " Butterfly (" + 
                      DoubleToString(activePattern.quality, 1) + "%)";
    
    // Calculate position for the label (between X and D)
    datetime labelTime = (activePattern.X.time + activePattern.D.time) / 2;
    double labelPrice;
    
    if(activePattern.type == "Bullish") {
        labelPrice = activePattern.D.price - (activePattern.X.price - activePattern.D.price) * 0.15;
    } else {
        labelPrice = activePattern.D.price + (activePattern.D.price - activePattern.X.price) * 0.15;
    }
    
    CreateText(patternName + "_Label", nameText, labelTime, labelPrice, patternColor, 9);
    
    // Draw potential entry, stop loss, and take profit levels
    if(EnableTrading) {
        DrawEntryLevels(patternName);
    }
}

//+------------------------------------------------------------------+
//| Draw potential entry, SL, and TP levels                          |
//+------------------------------------------------------------------+
void DrawEntryLevels(string baseName) {
    double entryPrice, stopLoss, takeProfit;
    color levelColor = (activePattern.type == "Bullish") ? clrGreen : clrRed;
    
    // Calculate entry, SL, and TP levels
    CalculateTradeLevels(entryPrice, stopLoss, takeProfit);
    
    // Draw entry level
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    datetime futureTime = currentTime + PeriodSeconds(PERIOD_CURRENT) * 10;
    
    DrawHorizontalLine(baseName + "_Entry", entryPrice, currentTime, futureTime, clrMagenta, STYLE_DASH);
    CreateText(baseName + "_EntryLabel", "Entry: " + DoubleToString(entryPrice, _Digits), 
               futureTime, entryPrice, clrMagenta, 8);
    
    // Draw stop loss level
    DrawHorizontalLine(baseName + "_SL", stopLoss, currentTime, futureTime, clrRed, STYLE_DASH);
    CreateText(baseName + "_SLLabel", "SL: " + DoubleToString(stopLoss, _Digits), 
               futureTime, stopLoss, clrRed, 8);
    
    // Draw take profit level
    DrawHorizontalLine(baseName + "_TP", takeProfit, currentTime, futureTime, clrGreen, STYLE_DASH);
    CreateText(baseName + "_TPLabel", "TP: " + DoubleToString(takeProfit, _Digits), 
               futureTime, takeProfit, clrGreen, 8);
}

//+------------------------------------------------------------------+
//| Calculate entry, stop loss, and take profit levels               |
//+------------------------------------------------------------------+
void CalculateTradeLevels(double &entry, double &sl, double &tp) {
    if(activePattern.type == "Bullish") {
        // For bullish pattern - BUY
        entry = activePattern.D.price;
        
        // Calculate stop loss
        if(StopLossPips > 0) {
            sl = entry - StopLossPips * 0.1; // For Gold, 1 pip = 0.1
        } else {
            // Auto stop loss based on pattern (below D)
            double xdDistance = MathAbs(activePattern.X.price - activePattern.D.price);
            sl = entry - xdDistance * 0.5;
        }
        
        // Calculate take profit
        if(TakeProfitPips > 0) {
            tp = entry + TakeProfitPips * 0.1; // For Gold, 1 pip = 0.1
        } else {
            // Auto take profit based on pattern (target C or ratio of risk)
            double risk = MathAbs(entry - sl);
            tp = entry + risk * TPRatio;
            
            // Alternative: Use C level as target
            if(TPRatio == 0) tp = activePattern.C.price;
        }
    } else {
        // For bearish pattern - SELL
        entry = activePattern.D.price;
        
        // Calculate stop loss
        if(StopLossPips > 0) {
            sl = entry + StopLossPips * 0.1; // For Gold, 1 pip = 0.1
        } else {
            // Auto stop loss based on pattern (above D)
            double xdDistance = MathAbs(activePattern.X.price - activePattern.D.price);
            sl = entry + xdDistance * 0.5;
        }
        
        // Calculate take profit
        if(TakeProfitPips > 0) {
            tp = entry - TakeProfitPips * 0.1; // For Gold, 1 pip = 0.1
        } else {
            // Auto take profit based on pattern (target C or ratio of risk)
            double risk = MathAbs(sl - entry);
            tp = entry - risk * TPRatio;
            
            // Alternative: Use C level as target
            if(TPRatio == 0) tp = activePattern.C.price;
        }
    }
}

//+------------------------------------------------------------------+
//| Execute trade based on the detected pattern                      |
//+------------------------------------------------------------------+
void ExecuteTradeSignal() {
    double entryPrice, stopLoss, takeProfit;
    double tradeLots = LotSize;
    
    // Calculate entry, SL, and TP levels
    CalculateTradeLevels(entryPrice, stopLoss, takeProfit);
    
    // Calculate lot size based on risk if RiskPercent is set
    if(RiskPercent > 0) {
        double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        double riskAmount = accountEquity * (RiskPercent / 100.0);
        double priceDiff = MathAbs(entryPrice - stopLoss);
        double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * 10; // For gold
        
        if(priceDiff > 0 && pipValue > 0) {
            tradeLots = NormalizeDouble(riskAmount / (priceDiff * pipValue / 0.1), 2);
            tradeLots = MathMax(0.01, MathMin(tradeLots, 10.0)); // Limit lot size between 0.01 and 10
        }
    }
    
    // Place trade based on pattern type
    if(activePattern.type == "Bullish") {
        // BUY trade
        Trade.Buy(tradeLots, _Symbol, 0, stopLoss, takeProfit, TradeComment);
        Print("Bullish Butterfly: BUY order placed at market. Lot size: ", tradeLots,
              ", SL: ", stopLoss, ", TP: ", takeProfit);
    } else {
        // SELL trade
        Trade.Sell(tradeLots, _Symbol, 0, stopLoss, takeProfit, TradeComment);
        Print("Bearish Butterfly: SELL order placed at market. Lot size: ", tradeLots,
              ", SL: ", stopLoss, ", TP: ", takeProfit);
    }
    
    orderPlaced = true;
}

//+------------------------------------------------------------------+
//| Manage open trades (breakeven, trailing stop)                    |
//+------------------------------------------------------------------+
void ManageOpenTrades() {
    // Check if we have an open position for this symbol
    if(!PositionSelect(_Symbol)) return;
    
    // Get position details
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    // Calculate profit in pips
    double profitPips = (posType == POSITION_TYPE_BUY) ? 
                        (currentPrice - openPrice) / 0.1 : 
                        (openPrice - currentPrice) / 0.1;
    
    // Move to breakeven if enabled and reached 1:1 risk/reward
    if(UseBreakeven && currentSL != openPrice) {
        double riskPips = (posType == POSITION_TYPE_BUY) ? 
                          (openPrice - currentSL) / 0.1 : 
                          (currentSL - openPrice) / 0.1;
        
        if(profitPips >= riskPips) {
            Trade.PositionModify(_Symbol, openPrice, currentTP);
            Print("Moving stop loss to breakeven: ", openPrice);
        }
    }
    
    // Apply trailing stop if enabled
    if(UseTrailingStop && TrailingStopPips > 0) {
        double trailDistance = TrailingStopPips * 0.1; // Convert to price
        
        if(posType == POSITION_TYPE_BUY) {
            double newSL = currentPrice - trailDistance;
            if(newSL > currentSL) {
                Trade.PositionModify(_Symbol, newSL, currentTP);
                Print("Trailing stop updated for BUY: ", newSL);
            }
        } else {
            double newSL = currentPrice + trailDistance;
            if(newSL < currentSL || currentSL == 0) {
                Trade.PositionModify(_Symbol, newSL, currentTP);
                Print("Trailing stop updated for SELL: ", newSL);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Draw a line on the chart                                         |
//+------------------------------------------------------------------+
void DrawLine(string name, datetime time1, double price1, datetime time2, double price2, color clr) {
    ObjectDelete(0, name);
    
    if(ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    }
}

//+------------------------------------------------------------------+
//| Draw a horizontal line on the chart                              |
//+------------------------------------------------------------------+
void DrawHorizontalLine(string name, double price, datetime time1, datetime time2, color clr, int style) {
    ObjectDelete(0, name);
    
    if(ObjectCreate(0, name, OBJ_TREND, 0, time1, price, time2, price)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    }
}

//+------------------------------------------------------------------+
//| Draw a point with label on the chart                             |
//+------------------------------------------------------------------+
void DrawPoint(string name, datetime time, double price, string label, color clr) {
    ObjectDelete(0, name);
    
    if(ObjectCreate(0, name, OBJ_TEXT, 0, time, price)) {
        ObjectSetString(0, name, OBJPROP_TEXT, label);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
    }
}

//+------------------------------------------------------------------+
//| Create a text label on the chart                                 |
//+------------------------------------------------------------------+
void CreateText(string name, string text, datetime time, double price, color clr, int size) {
    ObjectDelete(0, name);
    
    if(ObjectCreate(0, name, OBJ_TEXT, 0, time, price)) {
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
    }
}

//+------------------------------------------------------------------+
//| Create a label in the corner of the chart                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int corner) {
    ObjectDelete(0, name);
    
    if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
    }
}