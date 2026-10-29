# DMHM — Dynamic Multi-Horizon Momentum

Porting MQL5 della strategia VIDYA Regime + SMC Confluence.

## Funzionamento breve
- Moduli attivabili: VIDYA, Volume Profile, Order Block, FVG, Volume OB.
- Regime e struttura valutati su barra chiusa (shift=1) per evitare ripittura.
- Confluence score: somma di regime, struttura, volume, ATR e sessione.
- Entrata LONG/SHORT solo se punteggio >= soglia e non c'è segnale opposto.
- Risk management: SL/TP moltiplicativi ATR, time stop e max barre, sizing per rischio percentuale.
- Debug integrato: log diagnostici e comment dashboard.

## File
- `DMHM.mq5` — codice EA MT5 v3.10.
- `docs/schema.md` — schema concettuale moduli.
- `prove/` — appunti e risultati delle prove.

## Note
- Magic number fisso: `DMHM_MAGIC = 20241028`.
- Time stop e max bars gestiti in `OnTick`.
- Dashboard via `Comment()` solo se debug abilitato.
