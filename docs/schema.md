# Schema: EA → cBot

Concetti base per la conversione.

## Struttura sorgente
| MQL5 | cTrader/C# | Note |
|------|------------|------|
| OnInit / OnTick | OnStart / OnBar | Init one-shot vs ciclo per tick |
| OrderSend / Modify / Close | ExecuteMarketOrder / ModifyPosition / ClosePosition | API diverse, stesso effetto |
| iATR / iMA | Indicators.ATR / Indicator.MA | proprietà diversa |
| EventSetTimer | cBot.Indicator | timing diverso |
| MagicNumber | Unique ID | non direttamente mappato |

## Struttura dati
- Copiare parametri EA in cBot.Parameters.
- Mappare variabili globali in campi privati.
- Conservare formule esatte (SL, TP, trailing) identiche.

## Pseudo-codice costruttore
```csharp
[Robot]
public class TrumpStructor : Robot
{
    [Parameter("Entry lot size")] public double LotSize { get; set; } = 0.1;
    [Parameter("Stop loss (points)")] public int SLPoints { get; set; } = 15;
    [Parameter("Take profit (points)")] public int TPPoints { get; set; } = 15;

    private IIndicator _maFast;
    private IIndicator _maSlow;

    protected override void OnStart()
    {
        _maFast = Indicators.MovingAverage(Bars, 10);
        _maSlow = Indicators.MovingAverage(Bars, 50);
    }

    protected override void OnBar()
    {
        // Regole EA convertite qui, in C#.
    }
}
```

## Note
- Questo file è vivo: aggiornarlo dopo ogni prova concreta.
- Non tradurre logica; documentare ogni eccezione.
