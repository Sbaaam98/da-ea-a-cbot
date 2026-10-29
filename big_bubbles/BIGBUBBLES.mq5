//+------------------------------------------------------------------+
//| BIGBUBBLES.mq5 — Volume Bubbles strategy for MT5 v1.20         |
//| Replica di QuantAlgo Volume Bubbles (Pine v6)                   |
//| Filtri configurabili: Sessione, EMA200, RR, SL buffer, BE,      |
//| ATR (entra solo se ATR >= quantile rolling q della finestra)    |
//+------------------------------------------------------------------+
#property copyright "Based on QuantAlgo Volume Bubbles"
#property link      ""
#property version   "1.20"
#property strict

//--- Input parameters
input group "=== Cluster Sensitivity ==="
input double   MediumPct      = 90.0;   // Medium cluster percentile
input double   BigPct         = 97.0;   // Big cluster percentile

input group "=== Lookback & Consensus ==="
input int      ShortLen       = 20;     // Short window
input int      MidLen         = 50;     // Medium window
input int      LongLen        = 100;    // Long window

input group "=== Session Filter ==="
input bool     UseSessionFilter = true; // Filtra per orario sessione
input int      SessionStartHour  = 7;   // Inizio sessione (ora server)
input int      SessionEndHour    = 22;  // Fine sessione (ora server)

input group "=== Trend Filter ==="
input bool     UseTrendFilter    = true; // Filtro EMA trend
input int      TrendLen          = 200;  // Periodo EMA trend

input group "=== ATR Filter ==="
input bool     UseATRFilter    = true;  // Entra solo se ATR >= quantile
input int      ATRPeriod       = 14;    // Periodo ATR
input double   ATRQuantile     = 70.0;  // Quantile ATR (0-100)
input int      ATRQWindow      = 1000;  // Finestra rolling quantile ATR

input group "=== Trade Management ==="
input double   SlBufferPips   = 10.0;  // SL buffer (pips oltre estremo bubble)
input double   TpRR           = 1.5;   // Take Profit = RR × R
input double   BeR            = 0.0;   // BreakEven = BeR×R (0=disabilitato)

input group "=== General ==="
input double   LotSize        = 0.01;  // Lot size
input int      MagicNumber    = 12345; // Magic number

//--- Global variables
long   g_vol_raw[];
double g_vol_array[];
double g_delta_array[];
double g_closes[];
double g_opens[];
double g_highs[];
double g_lows[];
double g_atr[];
int    g_bars_needed;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== BIGBUBBLES v1.20 ===");
   Print("Session: ", UseSessionFilter ? "ON" : "OFF", " (", SessionStartHour, "-", SessionEndHour, "h)");
   Print("Trend: ", UseTrendFilter ? "ON" : "OFF", " (EMA", TrendLen, ")");
   Print("ATR filter: ", UseATRFilter ? "ON" : "OFF",
         " (ATR", ATRPeriod, " >= q", ATRQuantile, " su ", ATRQWindow, " barre)");
   Print("SL buf: ", SlBufferPips, " pips  TP: ", TpRR, "R  BE: ", BeR, "R");
   
   g_bars_needed = MathMax(120, MathMax(TrendLen + 2, ATRQWindow + ATRPeriod + 2));

   ArraySetAsSeries(g_vol_raw, true);
   ArraySetAsSeries(g_vol_array, true);
   ArraySetAsSeries(g_delta_array, true);
   ArraySetAsSeries(g_closes, true);
   ArraySetAsSeries(g_opens, true);
   ArraySetAsSeries(g_highs, true);
   ArraySetAsSeries(g_lows, true);
   ArraySetAsSeries(g_atr, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("BIGBUBBLES v1.20 deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime last_bar_time = 0;
   
   datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current_time == last_bar_time) return;
   last_bar_time = current_time;
   
   int avail = iBars(_Symbol, PERIOD_CURRENT);
   if(avail < g_bars_needed) return;
   
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, g_bars_needed, g_vol_raw) < g_bars_needed) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, g_bars_needed, g_closes) < g_bars_needed) return;
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 0, g_bars_needed, g_opens) < g_bars_needed) return;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, g_bars_needed, g_highs) < g_bars_needed) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, g_bars_needed, g_lows) < g_bars_needed) return;
   
   ArrayResize(g_vol_array, g_bars_needed);
   ArrayResize(g_delta_array, g_bars_needed);
   ArrayResize(g_atr, g_bars_needed);
   for(int i = 0; i < g_bars_needed; i++) {
      g_vol_array[i] = (double)g_vol_raw[i];
      // Delta proxy: +50% volume se candela rialzista, -50% se ribassista
      // (identico ai backtest Python validati — NON body/range)
      g_delta_array[i] = (g_closes[i] >= g_opens[i]) ? g_vol_array[i] * 0.5
                                                     : -g_vol_array[i] * 0.5;
      g_atr[i] = 0.0;
   }

   // ATR su barre chiuse: atr[i] = media TR su ATRPeriod barre ending at i
   for(int i = 1; i <= ATRQWindow && i + ATRPeriod < g_bars_needed; i++) {
      double sum = 0.0;
      for(int j = i; j < i + ATRPeriod; j++) {
         double tr = MathMax(g_highs[j] - g_lows[j],
                    MathMax(MathAbs(g_highs[j] - g_closes[j + 1]),
                            MathAbs(g_lows[j]  - g_closes[j + 1])));
         sum += tr;
      }
      g_atr[i] = sum / ATRPeriod;
   }

   int i = 1;

   double v_med_s = Percentile(g_vol_array, i, ShortLen, MediumPct);
   double v_med_m = Percentile(g_vol_array, i, MidLen, MediumPct);
   double v_med_l = Percentile(g_vol_array, i, LongLen, MediumPct);
   double v_big_s = Percentile(g_vol_array, i, ShortLen, BigPct);
   double v_big_m = Percentile(g_vol_array, i, MidLen, BigPct);
   double v_big_l = Percentile(g_vol_array, i, LongLen, BigPct);

   double d_med_s = PercentileAbs(g_delta_array, i, ShortLen, MediumPct);
   double d_med_m = PercentileAbs(g_delta_array, i, MidLen, MediumPct);
   double d_med_l = PercentileAbs(g_delta_array, i, LongLen, MediumPct);
   double d_big_s = PercentileAbs(g_delta_array, i, ShortLen, BigPct);
   double d_big_m = PercentileAbs(g_delta_array, i, MidLen, BigPct);
   double d_big_l = PercentileAbs(g_delta_array, i, LongLen, BigPct);

   int vol_med_count = (g_vol_array[i] >= v_med_s ? 1 : 0) +
                       (g_vol_array[i] >= v_med_m ? 1 : 0) +
                       (g_vol_array[i] >= v_med_l ? 1 : 0);
   int vol_big_count = (g_vol_array[i] >= v_big_s ? 1 : 0) +
                       (g_vol_array[i] >= v_big_m ? 1 : 0) +
                       (g_vol_array[i] >= v_big_l ? 1 : 0);
   int delt_med_count = (MathAbs(g_delta_array[i]) >= d_med_s ? 1 : 0) +
                        (MathAbs(g_delta_array[i]) >= d_med_m ? 1 : 0) +
                        (MathAbs(g_delta_array[i]) >= d_med_l ? 1 : 0);
   int delt_big_count = (MathAbs(g_delta_array[i]) >= d_big_s ? 1 : 0) +
                        (MathAbs(g_delta_array[i]) >= d_big_m ? 1 : 0) +
                        (MathAbs(g_delta_array[i]) >= d_big_l ? 1 : 0);
   
   bool vol_big   = vol_big_count >= 2;
   bool vol_med   = !vol_big && vol_med_count >= 2;
   bool delta_big = delt_big_count >= 2;
   bool delta_med = !delta_big && delt_med_count >= 2;
   
   bool is_big = vol_big || delta_big;
   bool is_med = !is_big && (vol_med || vol_big || delta_med || delta_big);
   
   bool is_buy  = (g_closes[i] >= g_opens[i]) && (g_delta_array[i] > 0);
   bool is_sell = (g_closes[i] < g_opens[i]) && (g_delta_array[i] < 0);
   
   bool bubble_long  = (is_med || is_big) && is_buy;
   bool bubble_short = (is_med || is_big) && is_sell;
   
   // Controlla posizione esistente + BreakEven
   bool has_pos = false;
   for(int j = 0; j < PositionsTotal(); j++) {
      if(PositionGetSymbol(j) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         has_pos = true;
         
         if(BeR > 0) {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            long type = PositionGetInteger(POSITION_TYPE);
            double risk = MathAbs(open_price - sl);
            
            if(risk > 0) {
               MqlTradeRequest req = {};
               MqlTradeResult res = {};
               req.action = TRADE_ACTION_SLTP;
               req.position = PositionGetInteger(POSITION_TICKET);
               req.symbol = _Symbol;
               req.tp = tp;
               
               if(type == POSITION_TYPE_BUY) {
                  if(g_closes[0] - open_price >= BeR * risk && sl < open_price) {
                     req.sl = open_price;
                  if(!OrderSend(req, res)) {
                     Print("BE set failed: GetLastError=", GetLastError());
                  }
                  }
               } else if(type == POSITION_TYPE_SELL) {
                  if(open_price - g_closes[0] >= BeR * risk && (sl > open_price || sl == 0)) {
                     req.sl = open_price;
                  if(!OrderSend(req, res)) {
                     Print("BE set failed: GetLastError=", GetLastError());
                  }
                  }
               }
            }
         }
         break;
      }
   }
   
   if(has_pos) return;
   if(!bubble_long && !bubble_short) return;
   
   // Filtro sessione
   MqlDateTime dt;
   TimeCurrent(dt);
   if(UseSessionFilter) {
      if(dt.hour < SessionStartHour || dt.hour >= SessionEndHour) return;
   }
   
   // Filtro trend
   double ema = CalcEMA(g_closes, TrendLen, 1);
   if(UseTrendFilter) {
      if(bubble_long && g_closes[1] <= ema) return;
      if(bubble_short && g_closes[1] >= ema) return;
   }
   
   // Filtro ATR: entra solo se ATR(barra segnale) >= quantile rolling
   if(UseATRFilter) {
      double atr_q = Percentile(g_atr, 1, ATRQWindow, ATRQuantile);
      if(g_atr[1] < atr_q) return;
   }
   
   double high1  = g_highs[1];
   double low1   = g_lows[1];
   double buf    = SlBufferPips * _Point * 10;

   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = LotSize;
   req.deviation = 10;
   req.magic = MagicNumber;
   
   if(bubble_long) {
      req.type = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      req.sl = low1 - buf;
      req.tp = req.price + TpRR * (req.price - req.sl);
      if(!OrderSend(req, res)) {
         Print("OrderSend BUY failed: ", GetLastError());
      }
   } else {
      req.type = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      req.sl = high1 + buf;
      req.tp = req.price - TpRR * (req.sl - req.price);
      if(!OrderSend(req, res)) {
         Print("OrderSend SELL failed: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Percentile su finestra [i .. i+len-1] (serie: i=piu' recente)     |
//+------------------------------------------------------------------+
double Percentile(double &arr[], int i, int len, double pct)
{
   double temp[];
   ArrayResize(temp, len);
   for(int j = 0; j < len; j++) temp[j] = arr[i + len - 1 - j];
   ArraySort(temp);
   int idx = (int)MathRound((pct / 100.0) * (len - 1));
   return temp[idx];
}

//+------------------------------------------------------------------+
//| Percentile assoluto su finestra [i .. i+len-1]                    |
//+------------------------------------------------------------------+
double PercentileAbs(double &arr[], int i, int len, double pct)
{
   double temp[];
   ArrayResize(temp, len);
   for(int j = 0; j < len; j++) temp[j] = MathAbs(arr[i + len - 1 - j]);
   ArraySort(temp);
   int idx = (int)MathRound((pct / 100.0) * (len - 1));
   return temp[idx];
}

//+------------------------------------------------------------------+
//| EMA semplice su array                                             |
//+------------------------------------------------------------------+
double CalcEMA(double &arr[], int len, int shift)
{
   double k = 2.0 / (len + 1);
   double ema = arr[shift + len - 1];
   for(int j = shift + len - 2; j >= shift; j--) {
      ema = arr[j] * k + ema * (1 - k);
   }
   return ema;
}
//+------------------------------------------------------------------+
