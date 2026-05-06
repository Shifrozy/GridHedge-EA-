# GridHedge EA v1.0

A professional MT5 Expert Advisor implementing a **Dynamic Grid + Hedging + Progressive Lot Scaling** strategy with optional candlestick pattern filtering and customizable trading controls.

> [!IMPORTANT]
> This EA requires a **hedging account** in MT5. Netting accounts are not supported.

## Features
- **Dynamic Grid & Hedging**: Automatically handles grid expansion and opposite-side hedging.
- **Progressive Lot Scaling**: Incremental lot size increase after failed cycles.
- **16 Candlestick Patterns**: Integrated pattern detection for smarter entries.
- **Time & Spread Filters**: Protects against high volatility and illiquid hours.
- **Real-time Info Panel**: On-chart display of all vital trading stats.

## File Structure
- `GridHedge_EA.mq5`: Main Expert Advisor source code.
- `CandlePatterns.mqh`: Includes all candlestick pattern logic.
- `agent.md` & `claude.md`: AI behavior rules for the project.
- `.cursor/rules/`: IDE-specific rules for the project.

## Installation
1. Copy `GridHedge_EA.mq5` and `CandlePatterns.mqh` to your MT5 `MQL5/Experts/` folder.
2. Compile `GridHedge_EA.mq5` in MetaEditor.
3. Attach to chart and enable "Allow Algo Trading".

---
*Developed for professional MT5 algorithmic trading.*
