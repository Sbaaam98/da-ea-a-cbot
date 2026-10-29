# Schema rapido BIG BUBBLES

## MQL5 → cTrader (concetti)
- `OnInit/OnTick` → `OnStart/OnBar`
- `CopyTickVolume/CopyClose/...` → `Bars` + indicatori/volume API cTrader
- `Percentile/PercentileAbs` → logica custom in C#
- `OrderSend` → `ExecuteMarketOrder` / `ModifyPosition`
- `PositionsTotal/PositionGet...` → `Positions` + LINQ

## Struttura cBot consigliata
- Parametri input corrispondenti a tutti gli `input` MQL5.
- Calcolo bubble in `Calculate()` o in helper deterministico.
- Filtri applicati in ordine: sessione → trend → ATR → bubble.
- Gestione BE e TP/RR su evento barra chiusa.

## TODO
- Validare percentili su storico reale con same-bar vs next-bar fill.
- Verificare costo dello slippage su XAUUSD/XTIUSD H1/M5.
