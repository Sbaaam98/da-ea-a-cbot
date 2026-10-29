"""
Prove esplorative per la conversione EA → cBot.
Qui si testano mapping API e formule, non si fa trading reale.
"""

# Prove: struttura parametri
def build_params(lot=0.1, sl_points=15, tp_points=15):
    return {
        "LotSize": lot,
        "SLPoints": sl_points,
        "TPPoints": tp_points,
    }

# Prove: mapping indicatori MQL5 → cTrader
INDICATORS = {
    "MQL5 iATR": "cTrader Indicators.ATR",
    "MQL5 iMA": "cTrader Indicators.MovingAverage",
    "MQL5 iRSI": "cTrader Indicators.RelativeStrengthIndex",
}

# Prove: formule invarianti
def sl_tp_points_conversion(points, symbol_point=0.00001):
    return points * symbol_point

# Esecuzione test locale
if __name__ == "__main__":
    params = build_params()
    print("Parametri:", params)
    print("Indicatori:", INDICATORS)
    print("SL virtuale (points):", sl_tp_points_conversion(15))
