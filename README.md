<div align="center">

# 🚕 NYC Car Market — Metro Fleet

### From 174,858 raw listings to a live AI-powered valuation engine.

**A full data science pipeline in R, ending in a cinematic, neon-lit Shiny dashboard that prices a used car the way New York City never sleeps.**

![R](https://img.shields.io/badge/R-276DC3?style=for-the-badge&logo=r&logoColor=white)
![Shiny](https://img.shields.io/badge/Shiny-0C4C8A?style=for-the-badge&logo=rstudio&logoColor=white)
![Random Forest](https://img.shields.io/badge/Model-Random%20Forest-2E8B57?style=for-the-badge)
![Plotly](https://img.shields.io/badge/Viz-Plotly-3F4F75?style=for-the-badge&logo=plotly&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active-F5C518?style=for-the-badge)

[Overview](#-overview) • [The Dashboard](#-the-dashboard--metro-fleet) • [The Pipeline](#-the-data-science-pipeline) • [Model Results](#-model-performance) • [Getting Started](#-getting-started) • [Team](#-team)

</div>

<br>

> *Add a screenshot or a short GIF of the landing page here — the night skyline, the two-way street traffic, the taxi meter valuation card. It's the single most convincing thing in this repo; lead with it.*

---

## 📍 Overview

**NYC Car Market** is an end-to-end data science project that takes a raw, messy scrape of ~175,000 New York City used-car listings and turns it into a fully interactive, AI-driven market intelligence platform.

The project has two halves, built by one team:

1. **The Analysis** — a rigorous R pipeline covering data cleaning, multi-method imputation, exploratory data analysis, iterative regression modeling, and a validated Random Forest predictor.
2. **The Product** — a production-grade, four-page Shiny dashboard ("Metro Fleet") that turns that analysis into something a real person can actually use: filter the live market, explore what drives price, and get an AI valuation for their own car — wrapped in an NYC-at-night visual identity designed from scratch.

This isn't a notebook full of plots. It's a dataset that became a decision-making tool.

---

## ✨ The Dashboard — "Metro Fleet"

The dashboard is a single-page R Shiny application with four distinct experiences, unified by one design language: taxi-cab yellow, MTA subway-line colors, deep asphalt black, and neon glow — New York, at night, rendered entirely in CSS and SVG.

### 🌃 Home — The Landing Experience
An animated hero scene built from scratch, with **zero external image or video assets**:
- A pseudo-3D CSS skyline — each building has a lit front face and an extruded, shaded side wall
- A real two-way street at street level, complete with a dashed yellow centerline and a traffic light that genuinely **cycles green → yellow → red** on a synchronized loop
- Custom hand-drawn SVG traffic — yellow NYC taxis (checker stripe, roof light, the works) and civilian sedans, correctly oriented and driving in their own lane, already in motion the instant the page loads
- A twinkling star field and a glowing moon above the skyline
- A live stats ticker scrolling real numbers pulled straight from the dataset
- Three call-to-action buttons that route directly into the other three tabs

### 📊 Dashboard Overview
- Four live KPI tiles (avg. price, top price tier, avg. mileage, total inventory) that recompute on every filter change
- Fuel-type donut, top-10-brand bar chart, and a price-vs-mileage density heatmap
- A sidebar filter system (fuel, drivetrain, model year) shared across every data tab, debounced for smooth interaction on 170K+ rows

### 🔎 Deep Analytics
- **Live Random Forest feature importance** — retrains a lightweight model on whatever's currently filtered, so you can watch what actually drives price shift between, say, Diesel and Hybrid segments
- Average price trend by model year, price distribution by drivetrain, and a brand "market map" (price vs. mileage vs. listing volume)

### 🤖 AI Price Predictor — the flagship page
This page was built to be the most *reliable* part of the entire project, not just the flashiest:

| Safeguard | What it does |
|---|---|
| **Bounded inputs** | Year and mileage sliders are hard-capped to the exact range the model was trained on (2012–2023) — it is structurally impossible to request a prediction the model would have to extrapolate |
| **Validated accuracy** | The model's R² and MAE are computed via out-of-bag validation (data the model never saw during training) and displayed live on the page — not a claimed number, a measured one |
| **Data-quality correction** | Detected and corrected a real artifact in the source data: 8,037 listings (4.6%) shared an identical price of $74,909.38, a censoring cap rather than a genuine price. Left uncorrected, it silently broke every "top price" statistic in the dashboard |
| **Ensemble confidence range** | Rather than one point estimate, the page shows the spread of all 50 individual trees' predictions — genuine model uncertainty, not decoration |
| **Partial dependence charts** | Two charts hold the user's exact car spec fixed and sweep only the year, then only the mileage, showing how the AI's valuation moves — a real explainability technique, not just a chart for its own sake |
| **Market position** | The prediction is plotted against a histogram of real listings for the same brand, so the estimate is always seen next to the market it came from |

The valuation itself is presented as a working **taxi meter** — LED-red glowing digits inside a black meter housing — because a generic number box didn't feel like it belonged in this dashboard.

---

## 🔬 The Data Science Pipeline

### Data
Two raw sources — a New York City used-car listings scrape and a companion ratings dataset — were merged, deduplicated, and engineered into a single analytical table.

- **174,858 rows × 31 engineered features** after cleaning
- Source files merged from [`New_York_cars.csv`](https://github.com/NitoBoritto/R_New_York_Car_Project) and [`Car_Rates.csv`](https://github.com/NitoBoritto/R_New_York_Car_Project)

### Cleaning & Imputation
A deliberately multi-method approach, matched to what each column actually needed:

- Brand-name unification and duplicate removal
- **Mode imputation** for low-missingness categorical fields (Drivetrain)
- **kNN imputation** for `Fuel_Type`, using Drivetrain and encoded fuel type as predictors
- **MICE (Multiple Imputation by Chained Equations)** for the review/rating columns (`Num_of_reviews`, `General_rate`, `Comfort`, `Interior Design`, `Performance`, `Value for the Money`, `Exterior Styling`, `Reliability`)
- Mean imputation for `Mileage`, outlier-aware parsing for `MPG` (values above realistic bounds treated as missing)
- Binary encoding of accident history, clean title, one-owner, and personal-use flags
- **Winsorization** to control extreme outliers ahead of modeling

### Exploratory Data Analysis
Univariate and bivariate analysis across price, mileage, fuel type, transmission, drivetrain, and brand — repeated pre- and post-log-transform to check which relationships needed it. Correlation matrices (Year, Price, Mileage, and the full numeric feature set) guided which interactions were worth testing in modeling.

### Statistical Simulation
A Monte Carlo–style validation step: synthetic data was sampled from fitted distributions for both numerical and categorical features and compared against the real proportions (e.g., New vs. Used, Drivetrain mix) to confirm the cleaned dataset's distributions were realistic and not artifacts of the imputation process.

### Modeling — an iterative progression

| Model | Approach | Result |
|---|---|---|
| 1 | Baseline multiple linear regression | R² = 0.670 |
| 2 | Log-transformed target + brand interaction (no age control) | R² = 0.453 *(regression, not progress — informed model 3)* |
| 3 | Feature engineering: `Age²`, log-mileage × brand interaction | R² = 0.693 |
| 4 | **Random Forest** (`Age`, `Mileage`, `Engine Size`, `MPG`, brand & transmission dummies, 100 trees) | **93.1% variance explained** · **MAE ≈ $3,116** · **RMSE ≈ $4,537** |

The Random Forest's dramatic jump in explanatory power over every linear specification is what made it the clear choice to power the live AI Price Predictor. The version deployed in the dashboard is a separately tuned instance (50 trees, empirically chosen as the point of diminishing returns) validated with out-of-bag error rather than a held-out test split, so it can be revalidated live, on demand, inside the app itself.

---

## 🛠️ Tech Stack

| Layer | Tools |
|---|---|
| Language | R |
| Data wrangling | `tidyverse`, `dplyr`, `readr`, `stringr`, `reshape2` |
| Imputation | `mice`, `DMwR2` (kNN), `modeest` |
| Modeling | `randomForest`, `car` (VIF), `caret`, `ggfortify` |
| Visualization (analysis) | `ggplot2`, `GGally`, `ggcorrplot`, `ggthemes`, `gridExtra` |
| Dashboard framework | `shiny`, `bslib` |
| Dashboard visualization | `plotly` |
| Design | Hand-written CSS (custom design system), inline SVG (no image assets) |

---

## 📂 Project Structure

```
R_New_York_Car_Project/
├── New_York_cars.csv              # Raw scraped listings
├── Car_Rates.csv                  # Companion ratings dataset
├── car_df_merged.csv              # Cleaned, merged, feature-engineered dataset
├── R_New_York_Car_Project.ipynb   # Full analysis notebook (cleaning → EDA → modeling → simulation)
├── nyc_car_market_dashboard.R     # The Metro Fleet Shiny dashboard
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites
- R (≥ 4.2 recommended) and RStudio
- Internet access on first run — the dashboard pulls the cleaned dataset directly from this repo

### Installation

```r
install.packages(c(
  "shiny", "bslib", "plotly", "dplyr", "readr",
  "stringr", "randomForest"
))
```

### Run the dashboard

```r
shiny::runApp("nyc_car_market_dashboard.R")
```

> **Note:** the AI Price Predictor's model is trained fresh on every app launch (not saved to disk), and is tuned for validated accuracy over raw speed — expect roughly 30–40 seconds of one-time startup while it trains and self-validates. This is intentional: it's the most important page in the project, and it earns its numbers on every run rather than trusting a stale saved model.

### Explore the analysis

```r
# Open in Jupyter with the R kernel, or in RStudio
R_New_York_Car_Project.ipynb
```

---

## 📈 Model Performance

The deployed AI Price Predictor reports its own accuracy live, computed via out-of-bag validation:

- **R² ≈ 0.81** — the model explains about 81% of the variance in price for data it never trained on
- **Mean Absolute Error ≈ $5,200** — on average, how far off a single prediction is
- Trained on **26,000+ real listings**, restricted to the actual 2012–2023 model-year range present in the data

*(The larger 93.1%-variance-explained Random Forest reported in the analysis notebook was trained on the full cleaned dataset with 100 trees for the offline research phase; the dashboard's live model is a separately tuned, self-validating instance built for interactive deployment.)*

---

## 👥 Team

This project was built by a team of four for a university data science course, combining statistical rigor with a genuine product mindset.

| Member | Role |
|---|---|
| **Yasser Mogahed** — *Team Lead* | End-to-end Shiny dashboard design & development: UI/UX, data visualization, the AI Price Predictor, and all interactive analytics |
| Ahmed Walid | Data cleaning & preprocessing |
| Mohanad Ibrahim | Exploratory data analysis & Regression modeling & the Random Forest predictor |
| Abdallah Ali | Simulation |



---

## 🗺️ Roadmap

- [ ] Deploy the dashboard publicly (shinyapps.io / Posit Connect) and link it above
- [ ] Add a model comparison toggle (Random Forest vs. tuned linear model) inside the predictor
- [ ] Historical price-trend forecasting beyond the current partial-dependence view
- [ ] Export a PDF valuation report from the AI Predictor

---

## 📄 License

*Add your chosen license here (MIT is a common, permissive default for academic projects).*

---

<div align="center">

**Built with R, Shiny, and an unreasonable amount of care for New York City at night.**

</div>
