# Patrick Wieland's 15-Minute Opening Range Strategy — Coded & Backtested

**Free TradingView indicator + MT5 Expert Advisor by [Backtest the Hype](https://www.youtube.com/@backtestthehype)**

I coded Patrick Wieland's 15-minute opening range breakout strategy from his video *"Simple Day Trading Strategy for Market Open! 15 MINUTE RANGE!"* and ran almost six years of real tick data through it, on three markets, with real spreads and commission.

**Result: his exact rules made money on all three markets.**

| Market | His exact rules (V1) |
|---|---|
| NAS100 | **+17.6R** |
| US500 (S&P 500) | **+26.9R** |
| US30 (Dow) | **+85.7R** |
| **All three combined** | **+130.2R** (= +130% at 1% risk per trade, no compounding) |

▶️ **Watch the video:** https://www.youtube.com/@backtestthehype

> The strategy idea belongs to Patrick Wieland. The code, the exact definitions and the backtests are by Backtest the Hype. This is for education and entertainment, not financial advice.

---

## What's in this repo

| File | What it is |
|---|---|
| `BTH_Patrick_15m_ORB.pine` | **TradingView indicator.** Draws the opening range, every breakout trade (risk/reward zones like the position tool), the trailing stop, and a results panel for the history loaded on your chart. |
| `BTH_Patrick_15m_ORB_EA.mq5` | **MetaTrader 5 Expert Advisor.** The real backtest engine used in the video. Same rules as the indicator. Includes all 7 test versions. |
| `Strategy_Rules.txt` | The rules in plain English, no code. |

---

## The strategy in plain English

### His rules (what Patrick says in his video)
1. **The box.** At 9:30 New York the market opens. Mark the high and the low of the **first 15-minute candle** (9:30–9:45). That's the opening range.
2. **Do nothing inside the box.** No trades until that candle closes, and none while price is still inside it.
3. **The breakout decides the day.** Break above the high → only look for **longs**. Break below the low → only look for **shorts**. Stay on that side for the day.
4. **Entry** on the lower timeframe (1- to 5-minute chart) in the breakout direction.
5. **Stop** on the other end of the candle you enter on (the low for longs, the high for shorts). Size your position to that stop.
6. **No fixed target.** Trail the stop behind each new higher low (longs) or lower high (shorts) and let the move run.
7. **News.** If numbers come out at 9:45 or 10:00, wait for them.

### Our definitions (how we made it exact — these are NOT his words)
A strategy has to be 100% mechanical to be coded, so a few things had to be decided. Every one of these is a setting you can change.

- **Breakout** = a 1-minute candle **closes** outside the box. A wick through the level doesn't count.
- **Fresh break only** = the previous candle closed inside the box and this one closes outside.
- **Entry** = the open of the next candle (market order at the real bid/ask).
- **Stop** = the breakout candle's opposite extreme, no buffer.
- **Trailing stop** = each new confirmed swing (2 candles each side, ties don't count). The stop only moves in the trade's favour.
- **Direction** is locked by the first break after the box closes.
- **Entry window** 9:45–12:00 New York. **Everything closed by 15:55** New York.
- **One trade at a time**, max 1 trade per day (setting). A re-entry needs price to close back inside the box first.
- **News:** the MT5 economic calendar doesn't work in the Strategy Tester, so "wait for the 10:00 numbers" is tested as *Earliest entry = 10:00* (V7).
- **1R** = the money lost if the first stop is hit (from the real fill and real lot size). Results under ±0.01R count as break-even.

---

## The tournament: 7 versions × 3 markets = 21 backtests

V1 is his exact rules. Every other version changes **one** thing.

| Version | What changes |
|---|---|
| **V1** | His rules: trail swings, breakout-candle stop, 1-minute close, entries from 9:45 |
| **V2** | Fixed 2R target instead of the trail |
| **V3** | Fixed 3R target instead of the trail |
| **V4** | Trail, but capped at 2R |
| **V5** | Classic ORB stop: other side of the box |
| **V6** | Breakout confirmed by a 5-minute candle close |
| **V7** | Wait until 10:00 every day (our delay test, not his exact news rule) |

### Results — total R (max drawdown in brackets)

| Version | NAS100 | US500 | US30 |
|---|---|---|---|
| V1 His rules | **+17.6** (68.6) | **+26.9** (40.9) | **+85.7** (57.4) |
| V2 Fixed 2R | −80.9 (100.2) | +13.3 (40.5) | +23.7 (56.5) |
| V3 Fixed 3R | −86.6 (109.6) | +7.5 (45.4) | +63.1 (67.9) |
| V4 Trail + 2R cap | −90.1 (108.6) | +14.2 (26.4) | +17.0 (54.8) |
| V5 Range stop | −19.5 (32.4) | +31.7 (19.3) | +26.4 (**14.2**) |
| V6 5-min close | +0.8 (41.6) | +14.7 (47.9) | **+75.8 (28.7)** |
| V7 10:00 delay | −91.5 (102.2) | −43.3 (62.5) | −94.3 (109.3) |

**Test details:** Fusion Markets CFDs · real ticks ("Every tick based on real ticks") · real spread + commission · January 2021 to October 2026 · $1,000 risk per trade = 1R · 21 backtests, 28,703 simulated trades. Max drawdown = deepest peak-to-trough fall, in R (at 1% risk, 1R = 1% of the starting balance).

### What the data showed
- 👑 **Best result:** his exact rules on the Dow, +85.7R.
- 👑 **Best balance:** the 5-minute version on the Dow, +75.8R with a 28.7R max drawdown.
- **Smoothest ride:** the range stop on the Dow, the smallest drawdown of all 21 tests (14.2R).
- **Mistake 1 — taking profit early.** On the Nasdaq, fixed targets turned +17.6R into −80.9R (2R), −86.6R (3R) and −90.1R (trail capped at 2R). The trailing stop is the edge.
- **Mistake 2 — waiting for the open to settle.** Waiting until 10:00 every day was the worst version on every market: −229.1R combined.
- **Mistake 3 — skipping days.** On the Nasdaq, his 5 best days made +73.5R. Without them, the other 1,384 trades lost 55.9R. On the Dow, +85.7R becomes +10.0R. The Nasdaq account also went **1,284 days** (April 2021 → October 2024) without a new high.
- **Running all three together:** +130.2R, but with a deepest drop of 123.8R along the way. This is not a smooth ride.

### What if you traded it on a prop firm?
Simulated challenge: 1% risk per trade, pass at +8%, fail at −10%, start again after each result.

- **NAS100, his rules:** 23 passes, 24 fails. Close to a coin flip.
- **US30, range stop (V5):** 3 passes, 0 fails, but about 515 days per pass.

Even the smoothest version dropped 14R at some point. At 1% risk that's 14%, and most prop firms cut you off at 10%. Know that going in.

---

## How to use the TradingView indicator
1. Open TradingView → **Pine Editor** (bottom of the chart).
2. Delete everything in the editor, paste the whole of `BTH_Patrick_15m_ORB.pine`, click **Save**, then **Add to chart**.
3. Use a **1-minute chart** of NAS100 / US500 / US30 (or NQ, ES, YM, QQQ, SPY).
4. Open the indicator settings to switch exit style, stop, confirmation timeframe, entry window and more.
5. The results panel covers only the history loaded on your chart, so use the MT5 EA for the full multi-year numbers.

## How to use the MT5 EA
1. In MetaTrader 5: **File → Open Data Folder → MQL5 → Experts**. Copy `BTH_Patrick_15m_ORB_EA.mq5` there.
2. Open it in **MetaEditor** and press **Compile** (F7).
3. Open the **Strategy Tester** (Ctrl+R) and choose the EA, then:
   - Symbol: NAS100, US500 or US30
   - Timeframe: **M1**
   - Modelling: **Every tick based on real ticks**
   - Dates: e.g. 2021.01.01 → today
4. In **Inputs**:
   - **Test version:** pick V1–V7 to run each version from the video, or "Use the settings below" to build your own.
   - **Server time minus New York time:** 7 for most brokers, including Fusion Markets (server GMT+2/+3). Check your broker.
   - **Risk per trade:** default $1,000 = 1R.
5. Every trade is written to a CSV in MetaTrader's **Common\Files** folder if you want to analyse it yourself.

> ⚠️ Run the EA in the Strategy Tester or on a demo account first. Backtests are not a promise of future results.

---

## Want to test YOUR strategy like this?
I run **1-on-1 sessions** where I walk you through my exact workflow: breaking down the rules, coding them into an indicator & EA (no coding experience needed), and reading the backtest like a pro.

👉 **Book here:** https://backtestthehype.ayomi2807.workers.dev/

## More from Backtest the Hype
- YouTube: https://www.youtube.com/@backtestthehype
- JadeCap's Daily Sweep strategy: https://github.com/spice2807/Daily-Sweep-Strategy-by-JadeCap
- The Rumers' Pattern Scalp strategy: https://github.com/spice2807/Pattern-Scalp-Strategy-by-TheRumers
- Fib Sweep strategy: https://github.com/spice2807/Fib-Sweep-Strategy

---

**Disclaimer:** Educational and entertainment content only. Not financial advice. Trading involves substantial risk of loss. Past and backtested performance does not guarantee future results. The strategy concept belongs to Patrick Wieland; this repository is an independent interpretation and is not affiliated with or endorsed by him.

© Backtest the Hype. The Pine Script is released under the Mozilla Public License 2.0.
