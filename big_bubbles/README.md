# BIG BUBBLES — Volume Bubbles per MT5

Replica della strategia Volume Bubbles (QuantAlgo, Pine v6) in MQL5.

## Funzionamento breve
- Cluster di volume: confronta volume corrente contro percentili rolling su finestre `ShortLen/MidLen/LongLen` e calcola un punteggio `vol` e `delta`.
- Consenso: un segnale scatta quando almeno 2 su 3 lookback superano la soglia `MediumPct`/`BigPct`.
- Filtri configurabili:
  - sessione oraria (`SessionStartHour`–`SessionEndHour`)
  - trend EMA (`TrendLen`)
  - volatilità ATR quantile rolling (`ATRPeriod`, `ATRQuantile`, `ATRQWindow`)
- Trade management:
  - SL buffer oltre estremo bubble (`SlBufferPips`)
  - TP a rapporto rischio/rendimento (`TpRR`)
  - BreakEven opzionale (`BeR`)

## File
- `BIGBUBBLES.mq5` — codice EA MT5 v1.20.
- `docs/schema.md` — mappatura concetti chiave.
- `prove/` — appunti e test locali.

## Note
- Ordini solo LONG/SHORT su chiusura barra.
- Delta proxy: +50% volume se candela rialzista, -50% se ribassista.
- ATR calcolato su barre chiuse per evitare ripittura.
