//+------------------------------------------------------------------+
//| DMHM.mq5                                                         |
//| Dynamic Multi-Horizon Momentum                                   |
//| Full MQL5 port of VIDYA Regime + SMC Confluence Strategy         |
//| Modules: VIDYA, Volume Profile, Order Block, FVG, Volume OB      |
//| Target: XAUUSD (any timeframe)                                   |
//| Version 3.1 - Fix volume shift=1, indicators shift=1             |
//+------------------------------------------------------------------+
#property copyright "DMHM"
#property version   "3.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

#define DMHM_MAGIC 20241028

CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

//==================================================================
// INPUT
//==================================================================
input group "=== Engine Selection ==="
input bool   InpUseVIDYA = true;
input bool   InpUseVP    = true;
input bool   InpUseOB    = true;
input bool   InpUseFVG   = true;
input bool   InpUseVOB   = true;
input bool   InpUseVPInScore = false;

input group "=== VIDYA ==="
input int    InpVidyaFastLen = 10;
input int    InpVidyaSlowLen = 30;
input int    InpVidyaMomLen  = 20;
input int    InpSlopeLen     = 5;
input ENUM_APPLIED_PRICE InpVidyaPrice = PRICE_CLOSE;

input group "=== Volume Profile ==="
input int    InpVPLen        = 300;
input int    InpVPBins       = 100;
input int    InpVPUpdateN    = 10;

input group "=== Order Block ==="
input int    InpOBBufLen     = 50;
input double InpOBMult       = 3.5;
input int    InpOBPivot      = 7;
input double InpOBMinPct     = 50.0;

input group "=== Fair Value Gap ==="
input int    InpFVGMaxCount  = 10;
input double InpFVGMinSize   = 10.0;

input group "=== Volume Order Blocks ==="
input int    InpVOBSens      = 5;

input group "=== Risk Management ==="
input double InpRiskPct      = 1.0;
input double InpAtrSLMult    = 2.0;
input double InpAtrTPMult    = 2.8;
input int    InpTimeStopBars = 40;
input int    InpMaxBars      = 60;
input double InpContractSize = 100.0;
input double InpMinLot       = 0.01;
input int    InpATRLen       = 14;

input group "=== Session & Filters ==="
input string InpSession      = "08:00-16:00";
input int    InpVolSMALen    = 20;
input int    InpATRPctLen    = 50;
input double InpATRPctMin    = 10.0;
input int    InpBrokerGMTOffset = 2;
input bool   InpIgnoreSession   = false;

input group "=== Confluence Score ==="
input int    InpMinScore     = 5;

input group "=== Debug ==="
input bool   InpDebugEnabled = true;
input bool   InpDebugTable   = true;
input bool   InpDebugLogs    = true;
input int    InpDebugEveryN  = 60;

//==================================================================
// HANDLES & BUFFERS
//==================================================================
int hVidyaFast = INVALID_HANDLE;
int hVidyaSlow = INVALID_HANDLE;
int hATR       = INVALID_HANDLE;
int hEMA1      = INVALID_HANDLE;
int hEMA2      = INVALID_HANDLE;

double g_vidyaFast[], g_vidyaSlow[], g_atr[];
double g_ema1[], g_ema2[];
double g_atrHist[];

//==================================================================
// STATE
//==================================================================
double g_poc = 0.0, g_vah = 0.0, g_val = 0.0;
datetime g_lastVPUpdate = 0;

double g_obTop = 0.0, g_obBot = 0.0;
int    g_obTrend = 0;
double g_obBuyRatio = 0.5;

struct FVGLevel { double top; double bot; bool isBull; datetime time; };
FVGLevel g_fvgs[];

struct VOBLevel { double upper; double lower; bool isBull; datetime time; };
VOBLevel g_vobBulls[], g_vobBears[];

int g_rejRegime = 0, g_rejStruct = 0, g_rejVP = 0;
int g_rejVolume = 0, g_rejATR = 0, g_rejSession = 0, g_rejDupe = 0;
int g_errNA = 0, g_errDiv = 0;
int g_sigCount = 0, g_tradeCount = 0;
datetime g_lastSignalTime = 0;
int g_barsProcessed = 0;
int g_lastDiagBar = 0;

//==================================================================
// INIT
//==================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(DMHM_MAGIC);
   trade.SetTypeFillingBySymbol(_Symbol);
   symInfo.Name(_Symbol);
   symInfo.Refresh();

   hVidyaFast = iVIDyA(_Symbol, PERIOD_CURRENT, InpVidyaMomLen, InpVidyaFastLen, 0, InpVidyaPrice);
   hVidyaSlow = iVIDyA(_Symbol, PERIOD_CURRENT, InpVidyaMomLen, InpVidyaSlowLen, 0, InpVidyaPrice);
   hATR       = iATR(_Symbol, PERIOD_CURRENT, InpATRLen);
   hEMA1      = iMA(_Symbol, PERIOD_CURRENT, InpVOBSens, 0, MODE_EMA, PRICE_CLOSE);
   hEMA2      = iMA(_Symbol, PERIOD_CURRENT, InpVOBSens + 13, 0, MODE_EMA, PRICE_CLOSE);

   if(hVidyaFast == INVALID_HANDLE || hVidyaSlow == INVALID_HANDLE ||
      hATR == INVALID_HANDLE || hEMA1 == INVALID_HANDLE || hEMA2 == INVALID_HANDLE)
   {
      Print("DMHM FATAL: indicator handle failed. Err=", GetLastError());
      return INIT_FAILED;
   }

   ArraySetAsSeries(g_vidyaFast, true);
   ArraySetAsSeries(g_vidyaSlow, true);
   ArraySetAsSeries(g_atr, true);
   ArraySetAsSeries(g_ema1, true);
   ArraySetAsSeries(g_ema2, true);
   ArraySetAsSeries(g_atrHist, true);

   int tfSec = PeriodSeconds(PERIOD_CURRENT);
   PrintFormat("DMHM v3.1 INIT | Symbol=%s | TF=%d sec | BrokerGMTOffset=%d | Session=%s | MinScore=%d",
               _Symbol, tfSec, InpBrokerGMTOffset, InpSession, InpMinScore);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFormat("=== DMHM SUMMARY === Bars=%d | Signals=%d | Trades=%d | Rej R=%d S=%d VP=%d V=%d A=%d Sess=%d D=%d | Err NA=%d Div=%d",
               g_barsProcessed, g_sigCount, g_tradeCount,
               g_rejRegime, g_rejStruct, g_rejVP, g_rejVolume,
               g_rejATR, g_rejSession, g_rejDupe, g_errNA, g_errDiv);
   IndicatorRelease(hVidyaFast);
   IndicatorRelease(hVidyaSlow);
   IndicatorRelease(hATR);
   IndicatorRelease(hEMA1);
   IndicatorRelease(hEMA2);
   Comment("");
}

//==================================================================
// HELPERS
//==================================================================
bool CopyBuffers()
{
   if(CopyBuffer(hVidyaFast, 0, 0, 10, g_vidyaFast) < 10) return false;
   if(CopyBuffer(hVidyaSlow, 0, 0, 10, g_vidyaSlow) < 10) return false;
   if(CopyBuffer(hATR,      0, 0, 10, g_atr)       < 10) return false;
   if(CopyBuffer(hEMA1,     0, 0, 10, g_ema1)      < 10) return false;
   if(CopyBuffer(hEMA2,     0, 0, 10, g_ema2)      < 10) return false;
   if(g_vidyaSlow[0] == EMPTY_VALUE || g_atr[0] == EMPTY_VALUE) { g_errNA++; return false; }
   return true;
}

bool InSession()
{
   if(InpIgnoreSession) return true;

   MqlDateTime dt;
   datetime utc = TimeCurrent() - (datetime)(InpBrokerGMTOffset * 3600);
   TimeToStruct(utc, dt);
   int h = dt.hour;

   string parts[];
   if(StringSplit(InpSession, '-', parts) != 2) return true;
   string sp[], ep[];
   StringSplit(parts[0], ':', sp);
   StringSplit(parts[1], ':', ep);
   int sH = (int)StringToInteger(sp[0]);
   int eH = (int)StringToInteger(ep[0]);

   bool inside;
   if(sH < eH) inside = (h >= sH && h < eH);
   else        inside = (h >= sH || h < eH);
   return inside;
}

//==================================================================
// VOLUME PROFILE
//==================================================================
void CalcVolumeProfile()
{
   if(Bars(_Symbol, PERIOD_CURRENT) < InpVPLen) return;
   double highs[], lows[], closes[];
   long vols[];
   ArraySetAsSeries(highs, true); ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true); ArraySetAsSeries(vols, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, InpVPLen, highs) < InpVPLen) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, InpVPLen, lows)  < InpVPLen) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, InpVPLen, closes) < InpVPLen) return;
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, InpVPLen, vols) < InpVPLen) return;

   double hh = highs[ArrayMaximum(highs)];
   double ll = lows[ArrayMinimum(lows)];
   double step = (hh - ll) / InpVPBins;
   if(step <= 0) return;

   double binVol[];
   ArrayResize(binVol, InpVPBins);
   ArrayInitialize(binVol, 0.0);
   for(int i = 0; i < InpVPLen; i++)
   {
      int idx = (int)MathFloor((closes[i] - ll) / step);
      if(idx >= 0 && idx < InpVPBins) binVol[idx] += (double)vols[i];
   }
   int pocIdx = ArrayMaximum(binVol);
   g_poc = ll + (pocIdx + 0.5) * step;

   double totalVol = 0; for(int i=0;i<InpVPBins;i++) totalVol += binVol[i];
   double target = totalVol * 0.7;
   double acc = binVol[pocIdx]; int up = pocIdx, dn = pocIdx;
   int safety = 0;
   while(acc < target && (up < InpVPBins-1 || dn > 0) && safety < InpVPBins*2)
   {
      double vUp = (up < InpVPBins-1) ? binVol[up+1] : -1;
      double vDn = (dn > 0) ? binVol[dn-1] : -1;
      if(vUp < 0 && vDn < 0) break;
      if(vUp >= vDn && up < InpVPBins-1) { up++; acc += vUp; }
      else if(dn > 0) { dn--; acc += vDn; }
      else break;
      safety++;
   }
   g_vah = ll + (up + 0.5) * step;
   g_val = ll + (dn + 0.5) * step;
   g_lastVPUpdate = TimeCurrent();
   PrintFormat("DMHM VP: POC=%.2f VAH=%.2f VAL=%.2f", g_poc, g_vah, g_val);
}

//==================================================================
// ORDER BLOCK (valutato su barra chiusa, shift=1)
//==================================================================
void CalcOrderBlock()
{
   int need = InpOBBufLen + InpOBPivot + 5;
   if(Bars(_Symbol, PERIOD_CURRENT) < need) return;
   double high[], low[], open[], close[];
   long vol[];
   ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
   ArraySetAsSeries(open, true); ArraySetAsSeries(close, true);
   ArraySetAsSeries(vol, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, need, high) < need) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, need, low) < need) return;
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 1, need, open) < need) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, need, close) < need) return;
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, need, vol) < need) return;

   double rangeSum = 0;
   for(int i = 0; i < InpOBBufLen; i++) rangeSum += (high[i] - low[i]);
   double avgRange = rangeSum / InpOBBufLen;
   double band = avgRange * InpOBMult;
   double mid = (high[0] + low[0]) / 2.0;
   double upperBand = mid + band;
   double lowerBand = mid - band;
   int trend = (close[0] > upperBand) ? 1 : (close[0] < lowerBand ? -1 : 0);

   bool pivotLow = false, pivotHigh = false;
   int lb = InpOBPivot;
   if(Bars(_Symbol, PERIOD_CURRENT) > 2*lb+2)
   {
      double pl = low[lb], ph = high[lb];
      bool isL = true, isH = true;
      for(int i = 1; i <= lb; i++)
      {
         if(low[lb-i] < pl || low[lb+i] < pl) isL = false;
         if(high[lb-i] > ph || high[lb+i] > ph) isH = false;
      }
      pivotLow = isL; pivotHigh = isH;
   }
   double bv = 0, sv = 0;
   for(int i = 0; i <= InpOBPivot; i++)
   {
      if(close[i] >= open[i]) bv += (double)vol[i];
      else sv += (double)vol[i];
   }
   double tv = bv + sv;
   g_obBuyRatio = (tv > 0) ? bv/tv : 0.5;

   if(trend == 1 && pivotLow)
   {
      g_obTop = MathMin(open[InpOBPivot], close[InpOBPivot]);
      g_obBot = g_obTop - band;
      g_obTrend = 1;
   }
   else if(trend == -1 && pivotHigh)
   {
      g_obBot = MathMax(open[InpOBPivot], close[InpOBPivot]);
      g_obTop = g_obBot + band;
      g_obTrend = -1;
   }
}

//==================================================================
// FVG (valutato su barre chiuse, shift=1)
//==================================================================
void CalcFVG()
{
   double high[], low[];
   ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, 5, high) < 5) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, 5, low) < 5) return;

   bool bullGap = (high[2] < low[0]);
   bool bearGap = (low[2]  > high[0]);
   double avgR = (high[0]-low[0] + high[1]-low[1] + high[2]-low[2]) / 3.0;
   double gSize = bullGap ? (low[0] - high[2]) : (low[2] - high[0]);
   bool sizeOk = (avgR > 0 && (gSize / avgR * 100.0) > InpFVGMinSize);

   if(bullGap && sizeOk)
   {
      FVGLevel f; f.top = low[0]; f.bot = high[2]; f.isBull = true; f.time = TimeCurrent();
      int n = ArraySize(g_fvgs); ArrayResize(g_fvgs, n+1); g_fvgs[n] = f;
   }
   if(bearGap && sizeOk)
   {
      FVGLevel f; f.top = low[2]; f.bot = high[0]; f.isBull = false; f.time = TimeCurrent();
      int n = ArraySize(g_fvgs); ArrayResize(g_fvgs, n+1); g_fvgs[n] = f;
   }
   while(ArraySize(g_fvgs) > InpFVGMaxCount)
   {
      for(int i=0;i<ArraySize(g_fvgs)-1;i++) g_fvgs[i] = g_fvgs[i+1];
      ArrayResize(g_fvgs, ArraySize(g_fvgs)-1);
   }
}

//==================================================================
// VOB
//==================================================================
void CalcVOB()
{
   if(ArraySize(g_ema1) < 2 || ArraySize(g_ema2) < 2) return;
   bool crossUp   = (g_ema1[1] <= g_ema2[1] && g_ema1[0] > g_ema2[0]);
   bool crossDown = (g_ema1[1] >= g_ema2[1] && g_ema1[0] < g_ema2[0]);

   if(crossUp)
   {
      VOBLevel v; v.upper = iHigh(_Symbol, PERIOD_CURRENT, 1);
      v.lower = iLow(_Symbol, PERIOD_CURRENT, 1);
      v.isBull = true; v.time = TimeCurrent();
      int n = ArraySize(g_vobBulls); ArrayResize(g_vobBulls, n+1); g_vobBulls[n] = v;
      if(ArraySize(g_vobBulls) > 15) ArrayRemove(g_vobBulls, 0, 1);
   }
   if(crossDown)
   {
      VOBLevel v; v.upper = iHigh(_Symbol, PERIOD_CURRENT, 1);
      v.lower = iLow(_Symbol, PERIOD_CURRENT, 1);
      v.isBull = false; v.time = TimeCurrent();
      int n = ArraySize(g_vobBears); ArrayResize(g_vobBears, n+1); g_vobBears[n] = v;
      if(ArraySize(g_vobBears) > 15) ArrayRemove(g_vobBears, 0, 1);
   }
}

//==================================================================
// ATR PERCENTILE
//==================================================================
bool AtrFilterOk(double currentAtr, double &pctVal)
{
   pctVal = 0.0;
   if(InpATRPctLen <= 0) return true;
   if(CopyBuffer(hATR, 0, 0, InpATRPctLen, g_atrHist) < InpATRPctLen) return true;
   double sorted[];
   ArrayResize(sorted, InpATRPctLen);
   for(int i = 0; i < InpATRPctLen; i++) sorted[i] = g_atrHist[i];
   ArraySort(sorted);
   int pctIdx = (int)MathFloor(InpATRPctLen * (InpATRPctMin / 100.0));
   if(pctIdx < 0) pctIdx = 0;
   if(pctIdx >= InpATRPctLen) pctIdx = InpATRPctLen - 1;
   pctVal = sorted[pctIdx];
   return currentAtr > pctVal;
}

//==================================================================
// LOT
//==================================================================
double CalcLot(double slDist)
{
   if(slDist <= 0) return 0.0;
   double riskCash = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPct / 100.0);
   double qty = riskCash / (slDist * InpContractSize);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step > 0) qty = MathFloor(qty / step) * step;
   qty = MathMax(minL, MathMin(maxL, qty));
   return NormalizeDouble(qty, 2);
}

//==================================================================
// DIAG
//==================================================================
void PrintDiag(int scoreL, int scoreS, bool rB, bool rS, bool sL, bool sS,
               bool vp, bool vol, bool atr, bool sess, double atrVal, double atrPctVal,
               double curVol, double volSma)
{
   PrintFormat("DMHM DIAG bar=%d close=%.3f | score L=%d S=%d | R L=%s S=%s | Struct L=%s S=%s | VP=%s | Vol=%.0f>%.0f=%s | ATR=%.4f>%.4f=%s | Sess=%s",
               g_barsProcessed, iClose(_Symbol, PERIOD_CURRENT, 1),
               scoreL, scoreS,
               rB?"Y":"N", rS?"Y":"N",
               sL?"Y":"N", sS?"Y":"N",
               vp?"Y":"N",
               curVol, volSma, vol?"Y":"N",
               atrVal, atrPctVal, atr?"Y":"N", sess?"Y":"N");
}

//==================================================================
// TRADE
//==================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      g_tradeCount++;
      PrintFormat("DMHM TRADE | Symbol=%s Type=%d Vol=%.2f Price=%.5f Deal=%I64u",
                  trans.symbol, trans.deal_type, trans.volume, trans.price, trans.deal);
   }
}

//==================================================================
// ONTICK
//==================================================================
void OnTick()
{
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBar == lastBar) return;
   lastBar = curBar;
   g_barsProcessed++;

   if(!CopyBuffers()) return;

   // --- Update moduli (tempo in secondi del TF)
   int tfSec = PeriodSeconds(PERIOD_CURRENT);
   if(InpUseVP && (TimeCurrent() - g_lastVPUpdate > InpVPUpdateN * tfSec))
      CalcVolumeProfile();
   if(InpUseOB)  CalcOrderBlock();
   if(InpUseFVG) CalcFVG();
   if(InpUseVOB) CalcVOB();

   // ============ FIX FONDAMENTALE: shift=1 su tutti gli indicatori ============
   double atrVal = g_atr[1];
   if(atrVal <= 0) { g_errDiv++; return; }
   double atrPctVal = 0;
   bool atrOk = AtrFilterOk(atrVal, atrPctVal);

   // Volume: barra chiusa (1) e media delle ultime N barre chiuse (1..N)
   double curVol = (double)iVolume(_Symbol, PERIOD_CURRENT, 1);
   double volSma = 0;
   for(int i = 1; i <= InpVolSMALen; i++)
      volSma += (double)iVolume(_Symbol, PERIOD_CURRENT, i);
   volSma /= InpVolSMALen;
   bool volOk = (curVol > volSma);

   bool sessOk = InSession();

   // Regime: barra chiusa
   bool rB = false, rS = false;
   if(InpUseVIDYA)
   {
      int sl = MathMin(InpSlopeLen, ArraySize(g_vidyaFast)-1);
      double slope = g_vidyaFast[1] - g_vidyaFast[1 + sl];
      double c = iClose(_Symbol, PERIOD_CURRENT, 1);
      rB = (c > g_vidyaSlow[1] && slope > 0);
      rS = (c < g_vidyaSlow[1] && slope < 0);
   }
   else { rB = true; rS = true; }

   // VP confluence
   bool vpOkL = true, vpOkS = true;
   if(InpUseVP && g_vah > 0 && g_val > 0)
   {
      double c = iClose(_Symbol, PERIOD_CURRENT, 1);
      vpOkL = (c >= g_val && c <= g_vah);
      vpOkS = vpOkL;
   }

   // Structure
   bool obBull = (g_obTrend == 1 && g_obBuyRatio >= InpOBMinPct/100.0);
   bool obBear = (g_obTrend == -1 && (1.0-g_obBuyRatio) >= InpOBMinPct/100.0);
   bool fvgBull = false, fvgBear = false;
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].isBull) fvgBull = true; else fvgBear = true;
   }
   bool vobBull = (ArraySize(g_vobBulls) > 0);
   bool vobBear = (ArraySize(g_vobBears) > 0);
   bool structL = (obBull || fvgBull || vobBull);
   bool structS = (obBear || fvgBear || vobBear);

   // Score
   int scoreL = 0, scoreS = 0;
   scoreL += (InpUseVIDYA ? (rB ? 1 : 0) : 1);
   scoreL += structL ? 1 : 0;
   scoreL += volOk  ? 1 : 0;
   scoreL += atrOk  ? 1 : 0;
   scoreL += sessOk ? 1 : 0;
   if(InpUseVPInScore) scoreL += vpOkL ? 1 : 0;

   scoreS += (InpUseVIDYA ? (rS ? 1 : 0) : 1);
   scoreS += structS ? 1 : 0;
   scoreS += volOk  ? 1 : 0;
   scoreS += atrOk  ? 1 : 0;
   scoreS += sessOk ? 1 : 0;
   if(InpUseVPInScore) scoreS += vpOkS ? 1 : 0;

   int maxScore = 5 + (InpUseVPInScore ? 1 : 0);
   int minReq   = MathMin(InpMinScore, maxScore);
   bool rawL = (scoreL >= minReq);
   bool rawS = (scoreS >= minReq);
   bool sigL = rawL && !rawS;
   bool sigS = rawS && !rawL;

   if(InpDebugEnabled && InpDebugLogs && (g_barsProcessed - g_lastDiagBar >= InpDebugEveryN))
   {
      g_lastDiagBar = g_barsProcessed;
      PrintDiag(scoreL, scoreS, rB, rS, structL, structS, vpOkL, volOk, atrOk, sessOk,
                atrVal, atrPctVal, curVol, volSma);
   }

   if(!sigL && !sigS)
   {
      if(InpUseVIDYA && !(rB || rS)) g_rejRegime++;
      else if(!structL && !structS)  g_rejStruct++;
      else if(!volOk)                g_rejVolume++;
      else if(!atrOk)                g_rejATR++;
      else if(!sessOk)               g_rejSession++;
      else if(InpUseVPInScore && !(vpOkL || vpOkS)) g_rejVP++;
      return;
   }

   if(g_lastSignalTime > 0 && (TimeCurrent() - g_lastSignalTime) < 5*tfSec)
   {
      g_rejDupe++;
      return;
   }

   g_sigCount++;
   PrintFormat("DMHM SIGNAL %s | score L=%d S=%d | close=%.3f | atr=%.4f>%.4f | vol=%.0f>%.0f | sess=%s | struct=%s | regime=%s",
               sigL?"LONG":"SHORT", scoreL, scoreS,
               iClose(_Symbol, PERIOD_CURRENT, 1),
               atrVal, atrPctVal, curVol, volSma,
               sessOk?"Y":"N", (sigL?structL:structS)?"Y":"N",
               (sigL?rB:rS)?"Y":"N");

   if(sigL && PositionsTotal() == 0)
   {
      double slD = atrVal * InpAtrSLMult;
      double tpD = atrVal * InpAtrTPMult;
      double lot = CalcLot(slD);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ask - slD, tp = ask + tpD;
      if(lot > 0 && trade.Buy(lot, _Symbol, ask, sl, tp, "DMHM LONG"))
      {
         g_lastSignalTime = TimeCurrent();
         PrintFormat("DMHM LONG ENTRY | lot=%.2f ask=%.5f SL=%.5f TP=%.5f", lot, ask, sl, tp);
      }
      else PrintFormat("DMHM LONG FAIL | lot=%.2f err=%d ret=%d", lot, GetLastError(), trade.ResultRetcode());
   }
   else if(sigS && PositionsTotal() == 0)
   {
      double slD = atrVal * InpAtrSLMult;
      double tpD = atrVal * InpAtrTPMult;
      double lot = CalcLot(slD);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = bid + slD, tp = bid - tpD;
      if(lot > 0 && trade.Sell(lot, _Symbol, bid, sl, tp, "DMHM SHORT"))
      {
         g_lastSignalTime = TimeCurrent();
         PrintFormat("DMHM SHORT ENTRY | lot=%.2f bid=%.5f SL=%.5f TP=%.5f", lot, bid, sl, tp);
      }
      else PrintFormat("DMHM SHORT FAIL | lot=%.2f err=%d ret=%d", lot, GetLastError(), trade.ResultRetcode());
   }

   // Time / max bars
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==DMHM_MAGIC)
      {
         int barsIn = iBarShift(_Symbol, PERIOD_CURRENT, posInfo.Time());
         if(barsIn >= InpTimeStopBars || barsIn >= InpMaxBars)
         {
            trade.PositionClose(posInfo.Ticket());
            PrintFormat("DMHM TIME EXIT ticket=%I64u barsIn=%d", posInfo.Ticket(), barsIn);
         }
      }
   }

   // Dashboard
   if(InpDebugTable)
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent() - (datetime)(InpBrokerGMTOffset*3600), dt);
      string c = StringFormat("DMHM v3.1 | Bar %d | UTC %02d:%02d\n", g_barsProcessed, dt.hour, dt.min);
      c += StringFormat("Score L=%d/%d S=%d/%d (min %d)\n", scoreL, maxScore, scoreS, maxScore, minReq);
      c += StringFormat("R=%s/%s Struct=%s/%s Vol=%.0f>%.0f=%s\n",
         rB?"Y":"N", rS?"Y":"N", structL?"Y":"N", structS?"Y":"N",
         curVol, volSma, volOk?"Y":"N");
      c += StringFormat("ATR=%.4f>%.4f=%s Sess=%s\n", atrVal, atrPctVal, atrOk?"Y":"N", sessOk?"Y":"N");
      c += StringFormat("VP=%s POC=%.2f VAH=%.2f VAL=%.2f\n",
         (vpOkL||vpOkS)?"Y":"N", g_poc, g_vah, g_val);
      c += StringFormat("OB trend=%d ratio=%.1f%% FVG=%d VOB=%d/%d\n",
         g_obTrend, g_obBuyRatio*100, ArraySize(g_fvgs), ArraySize(g_vobBulls), ArraySize(g_vobBears));
      c += StringFormat("SIGNAL: %s | signals=%d trades=%d\n",
         sigL?"LONG":(sigS?"SHORT":"-"), g_sigCount, g_tradeCount);
      c += StringFormat("REJ R=%d S=%d V=%d A=%d Sess=%d Dup=%d\n",
         g_rejRegime, g_rejStruct, g_rejVolume, g_rejATR, g_rejSession, g_rejDupe);
      c += StringFormat("ERR NA=%d Div=%d", g_errNA, g_errDiv);
      Comment(c);
   }
}
