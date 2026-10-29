# Schema DMHM

## Moduli principali
- VIDYA regime: `iVIDyA`, filtro trend e slope.
- Volume Profile: POC/VAH/VAL calcolati su rolling `InpVPLen`.
- Order Block: pivot su `InpOBPivot` con filtro volume e banda `avgRange * InpOBMult`.
- FVG: gap tra `high[2]` e `low[0]`, dimensione minima `InpFVGMinSize`.
- Volume OB: cross EMA veloce/lenta su barra chiusa.

## Confluence score
- 5 criteri base: regime, struttura, volume, ATR, sessione.
- VP opzionale nel punteggio con `InpUseVPInScore`.

## Note cTrader
- Portare moduli come helper deterministici in C#.
- Calcolare score su `OnBar`.
- Evitare indicatori su barra corrente per prevenire ripittura.
