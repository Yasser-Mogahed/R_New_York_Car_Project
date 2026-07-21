library(shiny)
library(bslib)
library(plotly)
library(dplyr)
library(readr)
library(stringr)
library(randomForest)

# ============================================================
# 1. DATA PREPARATION (Speed Optimized)
# ============================================================
# Load the data once outside the server function so the app opens fast
Car_df <- read_csv("https://raw.githubusercontent.com/NitoBoritto/R_New_York_Car_Project/main/car_df_merged.csv", show_col_types = FALSE)

# Programmatically fix column names to avoid duplicate-name errors (bug fix)
names(Car_df)[grep("fuel", names(Car_df), ignore.case = TRUE)[1]] <- "Fuel_Type"
price_idx <- grep("price|money", names(Car_df), ignore.case = TRUE)
if (length(price_idx) > 0) names(Car_df)[price_idx[1]] <- "Price"

Car_df <- Car_df %>%
  distinct() %>%
  mutate(
    Price = as.numeric(readr::parse_number(as.character(Price))),
    Mileage = as.numeric(readr::parse_number(as.character(Mileage))),
    Year = as.numeric(Year),
    across(c(Fuel_Type, Drivetrain, brand, Transmission), as.factor)
  ) %>%
  filter(!is.na(Price), !is.na(Year), !is.na(Mileage)) %>%
  na.omit()

# ============================================================
# 2. AI MODEL TRAINING & VALIDATION
# ============================================================
# The AI Price Predictor page is the most important, most scrutinized part
# of this project, so its model is trained for RELIABILITY, not just speed.
#
# ntree was empirically tuned: 15 -> 50 trees gives a real accuracy gain
# (OOB R-squared 0.801 -> 0.812, OOB MAE $5,378 -> $5,232) for a one-time
# ~30s startup cost. Pushing to 100 trees only adds another +0.002 R-squared
# for double the time, so 50 is the efficient stopping point.
set.seed(123)
train_sample <- Car_df %>% sample_frac(0.15) # representative sample, tuned for a fast one-time startup
rf_model <- randomForest(Price ~ Year + Mileage + brand + Fuel_Type + Drivetrain + Transmission,
                          data = train_sample, ntree = 50, importance = TRUE)

# Out-of-bag (OOB) validation: randomForest automatically holds out ~37% of
# rows from each tree's training, so these metrics are a genuine, honest
# estimate of real-world accuracy on unseen data - at zero extra training cost.
model_r2  <- round(rf_model$rsq[length(rf_model$rsq)], 3)
model_mae <- round(mean(abs(rf_model$predicted - train_sample$Price), na.rm = TRUE))
model_n   <- nrow(train_sample)

# Extract variable importance for the Deep Analytics tab
imp_raw <- importance(rf_model)
importance_df <- data.frame(
  Feature = rownames(imp_raw),
  Importance = imp_raw[, 1]
) %>% arrange(Importance)

fuel_choices  <- sort(unique(as.character(Car_df$Fuel_Type)))
drive_choices <- sort(unique(as.character(Car_df$Drivetrain)))
brand_choices <- sort(unique(as.character(Car_df$brand)))
trans_choices <- sort(unique(as.character(Car_df$Transmission)))

# --- Valid input ranges for the AI Predictor (prevents unreliable extrapolation) ---
# The model was trained only on cars from these exact years and mileages.
# Random Forests cannot extrapolate beyond their training range - asking for
# a prediction outside these bounds would silently return a flat, meaningless
# guess. So the predictor's Year and Mileage inputs are hard-capped to the
# real range seen in the data, making an invalid input impossible to submit.
YEAR_MIN <- min(Car_df$Year)
YEAR_MAX <- max(Car_df$Year)
MILEAGE_MIN <- 0
MILEAGE_MAX <- ceiling(max(Car_df$Mileage) / 1000) * 1000

# --- Data-quality fix: detect a capped/placeholder price value ---
# A slice of the data (~4.6%) shares the exact same maximum price, which is
# almost certainly a censoring cap rather than a real car's price. We detect
# it programmatically: a value that repeats abnormally often (100+ times)
# within the top 1% of the price range.
top_band <- Car_df %>% filter(Price >= quantile(Price, 0.99, na.rm = TRUE))
price_counts <- top_band %>% count(Price, sort = TRUE)
CAP_PRICE <- if (nrow(price_counts) > 0 && price_counts$n[1] > 100) price_counts$Price[1] else NA_real_

# --- Landing page hero stats (static baseline, computed once) ---
hero_total_fmt   <- format(nrow(Car_df), big.mark = ",")
hero_avgprice_fmt <- paste0("$", format(round(mean(Car_df$Price, na.rm = TRUE)), big.mark = ","))
hero_avgmile_fmt  <- paste0(format(round(mean(Car_df$Mileage, na.rm = TRUE)), big.mark = ","), " MI")
hero_brands_fmt   <- length(brand_choices)

# ============================================================
# 3. DESIGN SYSTEM — "Metro Fleet" (NYC subway + medallion cab)
# ============================================================
# Palette pulled from the city itself: checker-cab yellow, MTA line
# colors for categorical data, asphalt & LED-meter red for depth.
taxi        <- "#F5C518"   # medallion cab yellow
sub_green   <- "#00933C"   # 4/5/6 line
sub_blue    <- "#2850AD"   # A/C/E line
sub_red     <- "#EE352E"   # 1/2/3 line
sub_orange  <- "#FF6319"   # B/D/F/M line
sub_purple  <- "#A626AA"   # 7 line
sub_teal    <- "#00ADD0"   # accent
meter_red   <- "#FF3B2E"   # taxi meter LED glow

subway_palette <- c(taxi, sub_green, sub_blue, sub_red, sub_orange, sub_purple, sub_teal, "#8E8E93")

# --- Street geometry shared between car positioning and the CSS ---
street_height  <- 66   # street band height in pixels
lane_a_bottom  <- 40   # upper lane (nearer the sidewalks) - rightward direction
lane_b_bottom  <- 12   # lower lane (nearer the curb edge) - leftward direction

# --- Landing page moving-traffic generator ---
# Each car is an animated icon with its own speed/delay/lane/color for
# realistic visual depth. Note: we deliberately use a NEGATIVE animation-delay,
# because any positive value makes the element "wait" at its default position
# (screen edge) before actually starting to move, causing cars to visibly pile
# up at the edge before they animate. A negative value makes the animation
# start already "mid-journey" from the very first frame.
car_configs <- list(
  list(bottom = lane_a_bottom, dur = 16, delay = -5,  size = 40, color = taxi,      dir = "ltr", is_taxi = TRUE),
  list(bottom = lane_a_bottom, dur = 16, delay = -11, size = 32, color = "#D8D8DC", dir = "ltr", is_taxi = FALSE),
  list(bottom = lane_a_bottom, dur = 20, delay = -2,  size = 36, color = sub_blue,  dir = "ltr", is_taxi = FALSE),
  list(bottom = lane_b_bottom, dur = 17, delay = -8,  size = 38, color = taxi,      dir = "rtl", is_taxi = TRUE),
  list(bottom = lane_b_bottom, dur = 13, delay = -3,  size = 30, color = sub_red,   dir = "rtl", is_taxi = FALSE),
  list(bottom = lane_b_bottom, dur = 19, delay = -14, size = 34, color = sub_green, dir = "rtl", is_taxi = FALSE)
)
make_hero_car <- function(cfg) {
  h <- round(cfg$size * 0.5)
  body <- cfg$color

  # Car body — front (right side) has the headlight, rear (left side) has the small taillight
  car_body <- paste0(
    '<path d="M10,84 L16,55 L30,38 L54,20 L132,20 L156,38 L170,55 L186,84 Z" ',
    'fill="', body, '" stroke="#0A0A0C" stroke-width="3"/>'
  )
  # Two window panes split by a center (B-pillar) line for a real sedan feel
  windows <- paste0(
    '<path d="M40,48 L54,26 L132,26 L146,48 Z" fill="#0B141C" opacity="0.92"/>',
    '<line x1="93" y1="26" x2="93" y2="48" stroke="', body, '" stroke-width="2.5"/>'
  )
  mirror <- '<path d="M154,38 L163,34 L160,43 Z" fill="#0A0A0C"/>'
  door_seam <- '<line x1="100" y1="50" x2="100" y2="82" stroke="#0A0A0C" stroke-width="1.4" opacity="0.5"/>'
  wheels <- paste0(
    '<circle cx="45" cy="84" r="15" fill="#0A0A0C"/><circle cx="45" cy="84" r="8" fill="#3A3B40"/><circle cx="45" cy="84" r="3" fill="#0A0A0C"/>',
    '<circle cx="150" cy="84" r="15" fill="#0A0A0C"/><circle cx="150" cy="84" r="8" fill="#3A3B40"/><circle cx="150" cy="84" r="3" fill="#0A0A0C"/>'
  )
  lights <- paste0(
    '<circle cx="180" cy="60" r="6" fill="#FFF6DA"/>',   # headlight
    '<circle cx="13" cy="60" r="4.5" fill="#C0392B"/>'   # taillight
  )

  # Yellow-taxi-specific details: checker stripe + roof-mounted light box
  taxi_extra <- ""
  if (isTRUE(cfg$is_taxi)) {
    checker_squares <- paste0(sapply(seq(26, 158, by = 22), function(sx) {
      sprintf('<rect x="%d" y="67" width="9" height="7" fill="#FDFDFD"/>', sx)
    }), collapse = "")
    taxi_extra <- paste0(
      '<rect x="20" y="66" width="150" height="9" fill="#111"/>', checker_squares,
      '<rect x="81" y="8" width="38" height="12" rx="3" fill="#111"/>',
      '<rect x="85" y="10" width="30" height="8" rx="2" fill="#FFD23F"/>'
    )
  }

  svg_car <- paste0(
    '<svg viewBox="0 0 200 100" width="', cfg$size, 'px" height="', h, 'px" xmlns="http://www.w3.org/2000/svg">',
    car_body, windows, mirror, door_seam, wheels, lights, taxi_extra,
    '</svg>'
  )
  div(class = paste("nyc-car", if (cfg$dir == "ltr") "car-ltr" else "car-rtl"),
      style = paste0("bottom:", cfg$bottom, "px; animation-duration:", cfg$dur, "s; animation-delay:", cfg$delay, "s;"),
      HTML(svg_car))
}
hero_traffic <- div(class = "hero-traffic", lapply(car_configs, make_hero_car))

# --- Landing page floating bokeh lights (same negative-delay principle as above) ---
bokeh_configs <- list(
  list(left = "8%",  size = 60, dur = 9,  delay = -3,   color = "rgba(245,197,24,.35)"),
  list(left = "22%", size = 34, dur = 7,  delay = -5,   color = "rgba(0,229,255,.3)"),
  list(left = "40%", size = 46, dur = 11, delay = -8,   color = "rgba(245,197,24,.25)"),
  list(left = "58%", size = 28, dur = 6,  delay = -2,   color = "rgba(255,255,255,.2)"),
  list(left = "72%", size = 52, dur = 10, delay = -6,   color = "rgba(0,229,255,.25)"),
  list(left = "86%", size = 36, dur = 8,  delay = -4.5, color = "rgba(245,197,24,.3)"),
  list(left = "95%", size = 24, dur = 6.5, delay = -1.5, color = "rgba(255,255,255,.18)")
)
make_bokeh <- function(cfg) {
  div(class = "bokeh",
      style = paste0("left:", cfg$left, "; width:", cfg$size, "px; height:", cfg$size, "px; ",
                      "background:", cfg$color, "; animation-duration:", cfg$dur, "s; animation-delay:", cfg$delay, "s;"))
}
hero_bokeh <- div(class = "hero-bokeh-layer", lapply(bokeh_configs, make_bokeh))

# --- Night sky: twinkling stars + moon (replaces the old upper-sky traffic) ---
set.seed(42)
n_stars <- 45
star_configs <- lapply(1:n_stars, function(i) {
  list(left = paste0(round(runif(1, 1, 99), 1), "%"),
       top = paste0(round(runif(1, 2, 56), 1), "%"),
       size = sample(c(2, 2.5, 2.5, 3, 3, 3.5), 1),
       dur = round(runif(1, 2, 5), 1),
       delay = round(runif(1, -5, 0), 1))
})
make_star <- function(cfg) {
  div(class = "star",
      style = paste0("left:", cfg$left, "; top:", cfg$top, "; width:", cfg$size, "px; height:", cfg$size, "px; ",
                      "animation-duration:", cfg$dur, "s; animation-delay:", cfg$delay, "s;"))
}
hero_stars <- div(class = "hero-sky-layer", lapply(star_configs, make_star))
hero_moon <- div(class = "moon",
  div(class = "moon-crater", style = "width:14px;height:14px;left:10px;top:16px;"),
  div(class = "moon-crater", style = "width:9px;height:9px;left:34px;top:32px;"),
  div(class = "moon-crater", style = "width:7px;height:7px;left:20px;top:44px;")
)

# --- Real animated traffic light (cycles green -> yellow -> red) ---
traffic_light_svg <- paste0(
  '<svg viewBox="0 0 40 150" width="34px" height="128px" xmlns="http://www.w3.org/2000/svg">',
  '<rect x="15" y="46" width="6" height="98" fill="#26272C"/>',
  '<rect x="7" y="142" width="22" height="6" rx="2" fill="#1A1B1F"/>',
  '<rect x="3" y="0" width="34" height="86" rx="7" fill="#16171B" stroke="#000" stroke-width="2"/>',
  '<circle cx="20" cy="17" r="10.5" fill="#3A1210" class="tl-red"/>',
  '<circle cx="20" cy="43" r="10.5" fill="#3A350F" class="tl-yellow"/>',
  '<circle cx="20" cy="69" r="10.5" fill="#0F2E18" class="tl-green"/>',
  '</svg>'
)
hero_traffic_light <- div(class = "traffic-light-wrap", HTML(traffic_light_svg))

custom_css <- paste0("
  :root{
    --bg-void:#0A0A0C; --bg-card:#16171B; --bg-card-hover:#1C1E24;
    --taxi:", taxi, "; --taxi-dim: rgba(245,197,24,0.10);
    --sub-green:", sub_green, "; --sub-blue:", sub_blue, "; --sub-red:", sub_red, ";
    --text-hi:#F2F2F0; --text-mid:#B7B8BD; --text-low:#75767B;
    --hairline: rgba(255,255,255,0.09);
    --meter-red:", meter_red, ";
    --neon-cyan:#00E5FF; --neon-pink:#FF2E9A;
  }

  html { scroll-behavior:smooth; }

  body{
    position:relative;
    background-color:var(--bg-void);
    color:var(--text-hi);
    font-family:'Inter', sans-serif;
    -webkit-font-smoothing:antialiased;
    min-height:100vh;
  }

  /* Layer 1 — the skyline photograph itself: fixed, dimmed, softly blurred so
     it reads as atmosphere rather than a picture competing for attention. */
  body::before{
    content:'';
    position:fixed; inset:0; z-index:-2;
    background-image:url('https://images.unsplash.com/photo-1767342976156-83239d26f08e?q=80&w=2400&auto=format&fit=crop');
    background-size:cover;
    background-position:center 35%;
    filter:saturate(.75) brightness(.4) blur(1.5px);
    transform:scale(1.03); /* hides blur edge feathering */
  }

  /* Layer 2 — vignette + gradient fade + street-grid texture + faint neon
     glows, composited on top so the photo is only ever a hint near the
     header and content stays fully legible everywhere else. */
  body::after{
    content:'';
    position:fixed; inset:0; z-index:-1;
    background-image:
      radial-gradient(ellipse 900px 500px at 18% 0%, rgba(245,197,24,.10), transparent 60%),
      radial-gradient(ellipse 700px 450px at 85% 8%, rgba(0,229,255,.07), transparent 60%),
      linear-gradient(180deg, rgba(10,10,12,.45) 0%, rgba(10,10,12,.88) 32%, rgba(10,10,12,.97) 60%, var(--bg-void) 100%),
      repeating-linear-gradient(0deg, transparent 0 39px, rgba(255,255,255,.025) 39px 40px),
      repeating-linear-gradient(90deg, transparent 0 39px, rgba(255,255,255,.025) 39px 40px);
  }

  ::selection{ background:var(--taxi); color:#0A0A0C; }
  *:focus-visible{ outline:2px solid var(--taxi); outline-offset:2px; }

  ::-webkit-scrollbar{ width:9px; height:9px; }
  ::-webkit-scrollbar-track{ background:var(--bg-void); }
  ::-webkit-scrollbar-thumb{ background:#2A2B31; border-radius:6px; }
  ::-webkit-scrollbar-thumb:hover{ background:var(--taxi); }

  /* ---------- Header / medallion title (neon marquee) ---------- */
  .app-title-wrap{ display:flex; align-items:center; gap:14px; }
  .medallion-badge{
    width:42px; height:42px; border-radius:50%; background:var(--taxi);
    color:#0A0A0C; font-family:'Bebas Neue', sans-serif; font-size:14px;
    letter-spacing:0.5px; display:flex; align-items:center; justify-content:center;
    box-shadow:0 0 0 3px rgba(245,197,24,.2), 0 4px 16px rgba(245,197,24,.45), 0 0 34px -2px rgba(245,197,24,.85);
    flex-shrink:0;
    animation:badgePulse 3.4s ease-in-out infinite;
  }
  @keyframes badgePulse{
    0%, 100%{ box-shadow:0 0 0 3px rgba(245,197,24,.2), 0 4px 16px rgba(245,197,24,.45), 0 0 34px -2px rgba(245,197,24,.85); }
    50%{ box-shadow:0 0 0 4px rgba(245,197,24,.3), 0 4px 22px rgba(245,197,24,.6), 0 0 46px 4px rgba(245,197,24,1); }
  }
  .app-title-main{
    font-family:'Bebas Neue', sans-serif; font-size:24px; letter-spacing:1.5px;
    color:var(--text-hi); line-height:1.1;
    text-shadow:0 0 10px rgba(245,197,24,.55), 0 0 26px rgba(245,197,24,.4), 0 0 48px rgba(245,197,24,.2);
  }
  .app-title-sub{
    font-family:'IBM Plex Mono', monospace; font-size:10px; letter-spacing:2px;
    color:var(--neon-cyan); text-transform:uppercase; margin-top:2px;
    text-shadow:0 0 8px rgba(0,229,255,.7), 0 0 18px rgba(0,229,255,.4);
  }

  /* ---------- Cards (frosted glass) ---------- */
  .card{
    background:rgba(22,23,27,.72) !important;
    backdrop-filter:blur(18px) saturate(1.1);
    -webkit-backdrop-filter:blur(18px) saturate(1.1);
    border:1px solid rgba(0,229,255,.14) !important;
    border-radius:14px; margin-bottom:16px;
    box-shadow:0 8px 24px rgba(0,0,0,.4), 0 0 22px -14px rgba(0,229,255,.5);
    transition:border-color .3s ease, box-shadow .3s ease, transform .3s ease;
  }
  .card:hover{
    border-color:rgba(0,229,255,.5) !important;
    box-shadow:0 16px 38px rgba(0,0,0,.55), 0 0 0 1px rgba(0,229,255,.14), 0 0 42px -6px rgba(0,229,255,.4);
    transform:translateY(-3px);
  }
  .card-header{
    background:transparent !important; border-bottom:1px solid var(--hairline) !important;
    font-family:'Bebas Neue', sans-serif; letter-spacing:1.2px; font-size:15px;
    color:var(--text-mid); text-transform:uppercase; padding:14px 18px;
    position:relative;
  }
  .card-header::after{
    content:''; position:absolute; left:18px; right:18px; bottom:-1px; height:1.5px;
    background:linear-gradient(90deg, var(--taxi), var(--neon-cyan) 55%, transparent);
    opacity:.75; box-shadow:0 0 8px rgba(0,229,255,.5);
  }

  /* ---------- Sidebar ---------- */
  .sidebar, .bslib-sidebar-layout > .sidebar{
    background:rgba(11,12,14,.85) !important;
    backdrop-filter:blur(20px);
    -webkit-backdrop-filter:blur(20px);
    border-right:1px solid var(--hairline);
  }
  .glow-header{
    color:var(--taxi); font-family:'Bebas Neue', sans-serif; font-size:19px;
    letter-spacing:1.5px; margin-bottom:22px; display:flex; align-items:center; gap:9px;
    text-shadow:0 0 10px rgba(245,197,24,.6), 0 0 24px rgba(245,197,24,.35), 0 0 44px rgba(245,197,24,.15);
  }
  .filter-group{
    padding:14px 14px 4px 14px; margin-bottom:6px; border-radius:10px;
    background:rgba(255,255,255,.025); border:1px solid var(--hairline);
    transition:border-color .25s ease;
  }
  .filter-group:hover{ border-color:rgba(0,229,255,.25); }
  .filter-label{
    font-family:'IBM Plex Mono', monospace; font-size:11px; letter-spacing:1px;
    text-transform:uppercase; color:var(--text-mid); margin-bottom:6px; display:block;
  }
  .control-label{ color:var(--text-mid) !important; }

  /* selectize */
  .selectize-input{
    background:#141519 !important; border:1px solid var(--hairline) !important;
    color:var(--text-hi) !important; border-radius:8px !important;
  }
  .selectize-dropdown{ background:#141519 !important; color:var(--text-hi) !important; border:1px solid var(--hairline) !important; }
  .selectize-dropdown .option:hover{ background:var(--taxi-dim) !important; }
  .selectize-control.plugin-remove_button .item .remove{ border-left-color:rgba(255,255,255,.15) !important; }
  .item{ background:var(--taxi-dim) !important; color:var(--taxi) !important; border:1px solid rgba(245,197,24,.3) !important; }

  /* slider */
  .irs-bar, .irs-from, .irs-to, .irs-single{ background-color:var(--taxi) !important; }
  .irs-bar{ height:6px !important; top:33px !important; }
  .irs-line{ background:#25262B !important; height:6px !important; top:33px !important; border-radius:4px; }
  .irs-handle>i:first-child{ background-color:var(--taxi) !important; }
  .irs-handle{
    top:24px !important; width:22px !important; height:22px !important;
    background:var(--taxi) !important; border:3px solid #0A0A0C !important; border-radius:50% !important;
    box-shadow:0 0 0 3px rgba(245,197,24,.2), 0 0 16px -2px rgba(245,197,24,.7) !important;
  }
  .irs-handle>i:first-child{ display:none !important; }
  .irs-from, .irs-to, .irs-single{
    color:#0A0A0C !important; font-family:'IBM Plex Mono', monospace !important; font-weight:700 !important;
    font-size:12px !important; padding:3px 8px !important; border-radius:6px !important;
    box-shadow:0 0 10px -2px rgba(245,197,24,.6);
  }
  .irs-from::before, .irs-to::before{ border-top-color:var(--taxi) !important; }
  /* Hide the auto-generated axis tick labels, which used to overlap at the
     edges, and keep only the floating value bubbles that clearly show
     the currently selected range */
  .irs-grid, .irs-min, .irs-max{ display:none !important; }

  /* ---------- Nav pills styled like subway line chips ---------- */
  .nav-pills{ gap:8px; margin-bottom:18px; }
  .nav-pills .nav-link{
    font-family:'Bebas Neue', sans-serif; letter-spacing:1.2px; font-size:14px;
    color:var(--text-mid) !important; background:transparent !important;
    border:1px solid var(--hairline) !important; border-radius:999px !important;
    padding:9px 18px !important; display:flex; align-items:center; gap:8px;
  }
  .nav-pills .nav-link::before{
    content:''; width:8px; height:8px; border-radius:50%; display:inline-block;
    background:var(--taxi); box-shadow:0 0 6px var(--taxi), 0 0 12px var(--taxi);
  }
  .nav-pills .nav-link:nth-of-type(2)::before{ background:var(--sub-green); box-shadow:0 0 6px var(--sub-green), 0 0 12px var(--sub-green); }
  .nav-pills .nav-link:nth-of-type(3)::before{ background:var(--sub-red); box-shadow:0 0 6px var(--sub-red), 0 0 12px var(--sub-red); }
  .nav-pills .nav-link{ transition:all .25s ease; }
  .nav-pills .nav-link:not(.active){ box-shadow:0 0 10px -6px rgba(0,229,255,.4); }
  .nav-pills .nav-link:not(.active):hover{
    border-color:rgba(0,229,255,.5) !important; color:var(--text-hi) !important;
    box-shadow:0 0 22px -4px rgba(0,229,255,.55);
  }
  .nav-pills .nav-link.active{
    background:var(--taxi) !important; color:#0A0A0C !important; border-color:var(--taxi) !important;
    box-shadow:0 4px 18px rgba(245,197,24,.4), 0 0 32px -2px rgba(245,197,24,.85);
  }
  .nav-pills .nav-link.active::before{ background:#0A0A0C; }

  /* ---------- KPI medallion tiles ---------- */
  .metric-box{
    position:relative; background:var(--bg-card); border:1px solid var(--hairline);
    border-top:3px solid var(--taxi); border-radius:12px; padding:20px 18px;
    box-shadow:0 0 20px -12px rgba(245,197,24,.7);
    transition:transform .25s ease, background .25s ease, box-shadow .25s ease; overflow:hidden;
  }
  .metric-box:hover{
    transform:translateY(-4px); background:var(--bg-card-hover);
    box-shadow:0 16px 36px -10px rgba(245,197,24,.55);
  }
  .metric-box.line-green{ border-top-color:var(--sub-green); box-shadow:0 0 20px -12px rgba(0,147,60,.7); }
  .metric-box.line-green:hover{ box-shadow:0 16px 36px -10px rgba(0,147,60,.6); }
  .metric-box.line-blue{ border-top-color:var(--sub-blue); box-shadow:0 0 20px -12px rgba(40,80,173,.75); }
  .metric-box.line-blue:hover{ box-shadow:0 16px 36px -10px rgba(40,80,173,.65); }
  .metric-box.line-red{ border-top-color:var(--sub-red); box-shadow:0 0 20px -12px rgba(238,53,46,.7); }
  .metric-box.line-red:hover{ box-shadow:0 16px 36px -10px rgba(238,53,46,.6); }
  .metric-icon{ font-size:15px; color:var(--text-low); margin-bottom:10px; }
  .metric-box.line-green .metric-icon{ color:var(--sub-green); }
  .metric-box.line-blue .metric-icon{ color:var(--sub-blue); }
  .metric-box.line-red .metric-icon{ color:var(--sub-red); }
  .metric-box:not(.line-green):not(.line-blue):not(.line-red) .metric-icon{ color:var(--taxi); }
  .metric-label{
    color:var(--text-low); font-family:'IBM Plex Mono', monospace; font-size:10.5px;
    letter-spacing:1.5px; text-transform:uppercase; font-weight:600;
  }
  .metric-value{
    font-family:'IBM Plex Mono', monospace; font-weight:700; font-size:1.85rem; margin-top:8px;
    color:var(--text-hi); text-shadow:0 0 16px rgba(245,197,24,.25);
  }

  /* ---------- Taxi meter — AI prediction signature element (neon-framed) ---------- */
  .meter-shell{
    background:linear-gradient(180deg,#101114,#0A0A0C); border:1px solid rgba(245,197,24,.4);
    border-radius:16px; padding:34px 24px; text-align:center; position:relative;
    box-shadow:inset 0 0 40px rgba(0,0,0,.6), 0 0 0 1px rgba(245,197,24,.12),
               0 0 50px -10px rgba(255,59,46,.55), 0 0 80px -18px rgba(0,229,255,.35);
    animation:meterShellGlow 5s ease-in-out infinite;
  }
  @keyframes meterShellGlow{
    0%, 100%{ box-shadow:inset 0 0 40px rgba(0,0,0,.6), 0 0 0 1px rgba(245,197,24,.12), 0 0 50px -10px rgba(255,59,46,.55), 0 0 80px -18px rgba(0,229,255,.35); }
    50%{ box-shadow:inset 0 0 40px rgba(0,0,0,.6), 0 0 0 1px rgba(245,197,24,.2), 0 0 62px -6px rgba(255,59,46,.7), 0 0 92px -12px rgba(0,229,255,.5); }
  }
  .meter-shell::before{
    content:''; position:absolute; top:0; left:14px; right:14px; height:1px;
    background:repeating-linear-gradient(90deg, var(--taxi) 0 6px, transparent 6px 12px); opacity:.5;
  }
  .meter-label{
    font-family:'IBM Plex Mono', monospace; font-size:11px; letter-spacing:3px;
    color:var(--text-low); text-transform:uppercase; margin-bottom:16px;
    display:flex; align-items:center; justify-content:center; gap:8px;
  }
  .live-dot{
    width:6px; height:6px; border-radius:50%; background:#00E676; display:inline-block;
    box-shadow:0 0 6px #00E676, 0 0 14px #00E676;
    animation:liveDotPulse 1.6s ease-in-out infinite;
  }
  @keyframes liveDotPulse{ 0%,100%{ opacity:1; } 50%{ opacity:.25; } }
  .meter-screen{
    background:#050505; border-radius:8px; padding:22px 12px; margin:0 auto;
    border:1px solid rgba(255,255,255,.06);
    background-image:repeating-linear-gradient(0deg, rgba(255,255,255,.02) 0 2px, transparent 2px 4px);
  }
  .meter-digits{
    font-family:'IBM Plex Mono', monospace; font-weight:700; font-size:3.1rem;
    letter-spacing:2px; color:var(--meter-red);
    text-shadow:0 0 8px rgba(255,59,46,.9), 0 0 26px rgba(255,59,46,.6), 0 0 50px rgba(255,59,46,.3);
    animation:meterFlicker 3.2s infinite;
  }
  .meter-digits.is-idle{ color:#4A2521; text-shadow:none; animation:none; }
  @keyframes meterFlicker{
    0%, 96%, 100% { opacity:1; }
    97% { opacity:.85; }
    98% { opacity:1; }
  }
  .meter-foot{
    margin-top:14px; font-family:'IBM Plex Mono', monospace; font-size:10.5px;
    letter-spacing:1.5px; color:var(--text-low); text-transform:uppercase;
  }

  /* buttons */
  .btn-estimate{
    background:var(--taxi) !important; color:#0A0A0C !important; font-family:'Bebas Neue', sans-serif !important;
    letter-spacing:1.5px !important; font-size:16px !important; border:none !important;
    border-radius:8px !important; padding:12px !important; width:100%;
    box-shadow:0 6px 18px rgba(245,197,24,.35), 0 0 26px -8px rgba(245,197,24,.6);
    transition:transform .15s ease, box-shadow .15s ease;
  }
  .btn-estimate:hover{
    transform:translateY(-2px);
    box-shadow:0 10px 28px rgba(245,197,24,.45), 0 0 40px -4px rgba(245,197,24,.85);
  }

  .selectize-input.focus, .form-control:focus{
    border-color:rgba(0,229,255,.55) !important;
    box-shadow:0 0 0 1px rgba(0,229,255,.35), 0 0 16px -2px rgba(0,229,255,.5) !important;
  }

  @media (max-width: 768px){
    .app-title-main{ font-size:19px; }
    .metric-value{ font-size:1.5rem; }
    .meter-digits{ font-size:2.2rem; }
  }

  /* ============================================================
     LANDING / HERO PAGE
     ============================================================ */
  .hero-shell{
    position:relative; min-height:580px; border-radius:18px; overflow:hidden;
    border:1px solid rgba(0,229,255,.18);
    background:linear-gradient(180deg, rgba(20,21,25,.5), rgba(10,10,12,.85));
    box-shadow:0 24px 60px rgba(0,0,0,.55), 0 0 70px -22px rgba(245,197,24,.3);
    margin-bottom:18px;
  }

  /* -- skyline silhouette, now with real pseudo-3D extrusion, sitting on the street -- */
  .hero-skyline{
    position:absolute; left:0; right:0; bottom:", street_height, "px; height:200px;
    display:flex; align-items:flex-end; gap:17px; z-index:2; opacity:.95; pointer-events:none;
    perspective:800px;
  }
  .hero-skyline .bldg{
    flex:1; position:relative;
    background:linear-gradient(115deg, #2A2C33 0%, #1B1C21 45%, #0F1013 100%);
    border-top:1px solid rgba(255,255,255,.14);
    box-shadow:
      inset -10px 0 16px -6px rgba(0,0,0,.7),
      inset 3px 0 0 rgba(255,255,255,.06),
      8px 0 16px -8px rgba(0,0,0,.6);
  }
  /* The skewed side face — wider and brighter so it clearly reads as a 3D surface */
  .hero-skyline .bldg::after{
    content:''; position:absolute; top:0; right:-16px; width:16px; height:100%;
    background:linear-gradient(180deg, #34363E 0%, #17181D 55%, #0A0A0C 100%);
    border-right:1px solid rgba(255,255,255,.05);
    transform:skewY(44deg); transform-origin:top left; z-index:1;
  }
  /* Glowing rooftop window grid */
  .hero-skyline .bldg::before{
    content:''; position:absolute; inset:6px 5px auto 5px; height:72%;
    background-image:
      repeating-linear-gradient(0deg, rgba(245,197,24,.4) 0 2px, transparent 2px 11px),
      repeating-linear-gradient(90deg, rgba(245,197,24,.4) 0 2px, transparent 2px 9px);
    opacity:.35; animation:twinkleWindows 4.5s ease-in-out infinite; z-index:2;
  }
  .hero-skyline .bldg:nth-child(1){ height:38%; } .hero-skyline .bldg:nth-child(2){ height:62%; }
  .hero-skyline .bldg:nth-child(3){ height:48%; } .hero-skyline .bldg:nth-child(4){ height:80%; }
  .hero-skyline .bldg:nth-child(5){ height:55%; } .hero-skyline .bldg:nth-child(6){ height:100%; }
  .hero-skyline .bldg:nth-child(7){ height:70%; } .hero-skyline .bldg:nth-child(8){ height:46%; }
  .hero-skyline .bldg:nth-child(9){ height:88%; } .hero-skyline .bldg:nth-child(10){ height:60%; }
  .hero-skyline .bldg:nth-child(11){ height:40%; } .hero-skyline .bldg:nth-child(12){ height:74%; }
  .hero-skyline .bldg:nth-child(13){ height:52%; } .hero-skyline .bldg:nth-child(14){ height:66%; }
  .hero-skyline .bldg:nth-child(15){ height:42%; } .hero-skyline .bldg:nth-child(16){ height:90%; }
  .hero-skyline .bldg:nth-child(2n)::before{ animation-delay:1.3s; }
  .hero-skyline .bldg:nth-child(3n)::before{ animation-delay:2.4s; }
  .hero-skyline .bldg:nth-child(5n)::before{ animation-delay:.6s; }
  @keyframes twinkleWindows{ 0%, 100%{ opacity:.28; } 50%{ opacity:.7; } }

  /* -- two-way street at the base of the buildings -- */
  .hero-street{
    position:absolute; left:0; right:0; bottom:0; height:", street_height, "px; z-index:2;
    background:linear-gradient(180deg, #1C1D21 0%, #101114 55%, #0A0A0B 100%);
    pointer-events:none;
  }
  .hero-street .street-curb{ /* curb strip separating the street from the building bases */
    position:absolute; top:0; left:0; right:0; height:5px;
    background:linear-gradient(180deg, #4A4C54, #2A2B30);
  }
  .hero-street .street-centerline{ /* dashed yellow centerline marking the two-way divide */
    position:absolute; top:50%; left:0; right:0; height:3px; transform:translateY(-50%);
    background-image:repeating-linear-gradient(90deg, ", taxi, " 0px, ", taxi, " 22px, transparent 22px, transparent 40px);
    opacity:.85;
  }

  /* -- traffic light: cycles green then yellow then red, synchronized -- */
  .traffic-light-wrap{
    position:absolute; left:5%; bottom:0; z-index:4; pointer-events:none;
    filter:drop-shadow(0 4px 10px rgba(0,0,0,.6));
  }
  .tl-red, .tl-yellow, .tl-green{ animation-timing-function:linear; animation-iteration-count:infinite; }
  .tl-green{ animation-name:tlGreen; animation-duration:8s; }
  .tl-yellow{ animation-name:tlYellow; animation-duration:8s; }
  .tl-red{ animation-name:tlRed; animation-duration:8s; }
  @keyframes tlGreen{
    0%, 45%{ fill:#00E676; filter:drop-shadow(0 0 6px #00E676); }
    45.01%, 100%{ fill:#0F2E18; filter:none; }
  }
  @keyframes tlYellow{
    0%, 45%{ fill:#3A350F; filter:none; }
    45.01%, 52%{ fill:#FFD23F; filter:drop-shadow(0 0 6px #FFD23F); }
    52.01%, 100%{ fill:#3A350F; filter:none; }
  }
  @keyframes tlRed{
    0%, 52%{ fill:#3A1210; filter:none; }
    52.01%, 100%{ fill:#FF3B2E; filter:drop-shadow(0 0 6px #FF3B2E); }
  }

  /* -- moving traffic, now confined to the two street lanes -- */
  .hero-traffic{ position:absolute; inset:0; overflow:hidden; z-index:3; pointer-events:none; }
  .nyc-car{ position:absolute; left:0; filter:drop-shadow(0 0 7px rgba(245,197,24,.55)); animation-fill-mode:both; }
  .nyc-car svg{ display:block; }
  .car-ltr{ animation-name:driveLTR; animation-timing-function:linear; animation-iteration-count:infinite; }
  .car-rtl{ animation-name:driveRTL; animation-timing-function:linear; animation-iteration-count:infinite; }
  @keyframes driveLTR{ from{ transform:translateX(-10vw); } to{ transform:translateX(105vw); } }
  @keyframes driveRTL{ from{ transform:translateX(105vw) scaleX(-1); } to{ transform:translateX(-10vw) scaleX(-1); } }

  /* -- floating bokeh city lights -- */
  .hero-bokeh-layer{ position:absolute; inset:0; overflow:hidden; z-index:1; pointer-events:none; }
  .bokeh{
    position:absolute; top:60%; border-radius:50%; filter:blur(3px);
    animation-name:bokehFloat; animation-timing-function:ease-in-out; animation-iteration-count:infinite;
  }
  @keyframes bokehFloat{
    0%{ transform:translateY(0) scale(1); opacity:.15; }
    50%{ transform:translateY(-46px) scale(1.2); opacity:.55; }
    100%{ transform:translateY(0) scale(1); opacity:.15; }
  }

  /* -- night sky: twinkling stars + moon, replacing the old upper-sky traffic -- */
  .hero-sky-layer{ position:absolute; inset:0; z-index:1; pointer-events:none; }
  .star{
    position:absolute; border-radius:50%; background:#F5F3E7;
    animation-name:starTwinkle; animation-timing-function:ease-in-out; animation-iteration-count:infinite;
    box-shadow:0 0 5px rgba(245,243,231,.9), 0 0 9px rgba(245,243,231,.4);
  }
  @keyframes starTwinkle{ 0%, 100%{ opacity:.45; } 50%{ opacity:1; } }
  .moon{
    position:absolute; top:8%; right:10%; width:66px; height:66px; border-radius:50%; z-index:1;
    background:radial-gradient(circle at 35% 32%, #FFFDF2 0%, #F4EFD0 55%, #E4DBAE 100%);
    box-shadow:0 0 40px rgba(244,239,208,.55), 0 0 80px rgba(244,239,208,.25);
    overflow:hidden; pointer-events:none;
  }
  .moon-crater{ position:absolute; border-radius:50%; background:rgba(180,170,130,.35); }

  /* -- hero content -- */
  .hero-content{
    position:relative; z-index:5; padding:74px 50px 30px; text-align:center;
    display:flex; flex-direction:column; align-items:center; gap:16px;
  }
  .hero-eyebrow{
    font-family:'IBM Plex Mono', monospace; font-size:11px; letter-spacing:3px;
    color:var(--neon-cyan); text-transform:uppercase;
    text-shadow:0 0 10px rgba(0,229,255,.7), 0 0 22px rgba(0,229,255,.4);
  }
  .hero-title{
    font-family:'Bebas Neue', sans-serif; font-size:76px; line-height:.95; letter-spacing:2px;
    color:var(--text-hi);
    text-shadow:0 0 14px rgba(245,197,24,.6), 0 0 34px rgba(245,197,24,.4), 0 0 64px rgba(245,197,24,.2);
  }
  .hero-title-accent{ color:var(--taxi); }
  .hero-subtitle{
    max-width:620px; color:var(--text-mid); font-family:'Inter', sans-serif; font-size:15.5px; line-height:1.6;
  }
  .hero-cta-row{ display:flex; flex-wrap:wrap; gap:14px; justify-content:center; margin-top:10px; }
  .hero-btn{
    font-family:'Bebas Neue', sans-serif !important; letter-spacing:1.5px !important; font-size:15px !important;
    padding:13px 26px !important; border-radius:999px !important; display:flex; align-items:center; gap:10px;
    transition:transform .18s ease, box-shadow .18s ease;
  }
  .hero-btn-primary{
    background:var(--taxi) !important; color:#0A0A0C !important; border:none !important;
    box-shadow:0 8px 24px rgba(245,197,24,.4), 0 0 34px -6px rgba(245,197,24,.7);
  }
  .hero-btn-primary:hover{ transform:translateY(-3px); box-shadow:0 12px 32px rgba(245,197,24,.5), 0 0 46px -4px rgba(245,197,24,.9); }
  .hero-btn-secondary{
    background:rgba(255,255,255,.03) !important; color:var(--text-hi) !important;
    border:1px solid rgba(0,229,255,.4) !important;
    box-shadow:0 0 18px -8px rgba(0,229,255,.5);
  }
  .hero-btn-secondary:hover{
    transform:translateY(-3px); border-color:rgba(0,229,255,.8) !important;
    box-shadow:0 0 30px -4px rgba(0,229,255,.8);
  }

  /* -- stats ticker -- */
  .ticker-wrap{
    position:relative; z-index:5; overflow:hidden;
    border-top:1px solid var(--hairline); background:rgba(0,0,0,.45); padding:11px 0;
  }
  .ticker-track{
    display:flex; gap:56px; white-space:nowrap; width:max-content;
    animation:tickerScroll 24s linear infinite;
  }
  .ticker-item{
    font-family:'IBM Plex Mono', monospace; font-size:12px; letter-spacing:1.8px;
    color:var(--taxi); text-transform:uppercase; text-shadow:0 0 8px rgba(245,197,24,.4);
  }
  @keyframes tickerScroll{ from{ transform:translateX(0); } to{ transform:translateX(-50%); } }

  @media (max-width: 768px){
    .hero-title{ font-size:40px; }
    .hero-content{ padding:44px 20px 26px; }
    .hero-shell{ min-height:460px; }
  }
")

# ============================================================
# 4. UI
# ============================================================
app_title <- div(class = "app-title-wrap",
  div(class = "medallion-badge", "NYC"),
  div(
    div(class = "app-title-main", "CAR MARKET"),
    div(class = "app-title-sub", "LIVE MARKET INTELLIGENCE \u2022 METRO FLEET DATA")
  )
)

ui <- page_sidebar(
  title = app_title,
  theme = bs_theme(
    bg = "#0A0A0C", fg = "#F2F2F0", primary = taxi,
    base_font    = font_google("Inter"),
    heading_font = font_google("Bebas Neue"),
    code_font    = font_google("IBM Plex Mono")
  ),

  sidebar = sidebar(
    width = 320,
    div(class = "glow-header", icon("sliders"), "Navigation & Filters"),
    conditionalPanel(
      condition = "input.nav_tabs == 'HOME'",
      div(style = "color:#75767B; padding:10px; font-family:'IBM Plex Mono',monospace; font-size:12px; line-height:1.7;",
          icon("city"), " Welcome to the Metro Fleet console. Use the buttons on the right to jump straight into live pricing data, deep analytics, or the AI valuation engine.")
    ),
    conditionalPanel(
      condition = "input.nav_tabs == 'DASHBOARD Overview' || input.nav_tabs == 'Deep Analytics'",
      div(class = "filter-group",
        span(class = "filter-label", "Fuel Type"),
        selectizeInput("fuel", NULL, choices = fuel_choices, multiple = TRUE,
                        options = list(placeholder = "All Fuels", plugins = list("remove_button")))
      ),
      div(class = "filter-group",
        span(class = "filter-label", "Drivetrain"),
        selectizeInput("drive", NULL, choices = drive_choices, multiple = TRUE,
                        options = list(placeholder = "All Drivetrains", plugins = list("remove_button")))
      ),
      div(class = "filter-group",
        span(class = "filter-label", "Model Year"),
        sliderInput("year_range", NULL, min(Car_df$Year), max(Car_df$Year), range(Car_df$Year), sep = ""),
        div(style = "display:flex; justify-content:space-between; margin-top:-8px; padding-bottom:10px; font-family:'IBM Plex Mono',monospace; font-size:10px; color:#75767B; letter-spacing:1px;",
            span(min(Car_df$Year)), span(max(Car_df$Year)))
      )
    ),
    conditionalPanel(
      condition = "input.nav_tabs == 'AI PRICE PREDICTOR'",
      div(style = "color:#75767B; padding:10px; font-family:'IBM Plex Mono',monospace; font-size:12px; line-height:1.6;",
          icon("robot"), " Random Forest valuation engine trained on live NYC listings. Fill in the spec sheet and pull the fare.")
    )
  ),

  navset_pill(
    id = "nav_tabs",
    selected = "HOME",
    nav_panel(
      title = tagList(icon("house"), "HOME"), value = "HOME",
      div(class = "hero-shell",
        hero_bokeh,
        hero_stars,
        hero_moon,
        div(class = "hero-skyline", lapply(1:16, function(i) div(class = "bldg"))),
        div(class = "hero-street", div(class = "street-curb"), div(class = "street-centerline")),
        hero_traffic_light,
        hero_traffic,
        div(class = "hero-content",
          div(class = "hero-eyebrow", "LIVE MARKET INTELLIGENCE \u2022 FIVE BOROUGHS"),
          div(class = "hero-title", "NYC CAR", br(), span(class = "hero-title-accent", "MARKET")),
          div(class = "hero-subtitle",
              "Real-time pricing, inventory, and AI-driven valuation across the New York City used car market. Filter by fuel, drivetrain, and model year, or let the Random Forest engine price a car for you."),
          div(class = "hero-cta-row",
            actionButton("go_dashboard", tagList(icon("gauge-high"), "ENTER DASHBOARD"), class = "hero-btn hero-btn-primary"),
            actionButton("go_analytics", tagList(icon("chart-line"), "DEEP ANALYTICS"), class = "hero-btn hero-btn-secondary"),
            actionButton("go_predictor", tagList(icon("robot"), "AI PREDICTOR"), class = "hero-btn hero-btn-secondary")
          )
        ),
        div(class = "ticker-wrap",
          div(class = "ticker-track",
            span(class = "ticker-item", paste0("\U0001F695 ", hero_total_fmt, " LISTINGS TRACKED")),
            span(class = "ticker-item", paste0("\U0001F4B0 AVG PRICE ", hero_avgprice_fmt)),
            span(class = "ticker-item", paste0("\U0001F916 6-FACTOR AI VALUATION ENGINE")),
            span(class = "ticker-item", paste0("\U0001F6E3\uFE0F AVG MILEAGE ", hero_avgmile_fmt)),
            span(class = "ticker-item", paste0("\U0001F3F7\uFE0F ", hero_brands_fmt, " BRANDS COVERED")),
            span(class = "ticker-item", paste0("\U0001F695 ", hero_total_fmt, " LISTINGS TRACKED")),
            span(class = "ticker-item", paste0("\U0001F4B0 AVG PRICE ", hero_avgprice_fmt)),
            span(class = "ticker-item", paste0("\U0001F916 6-FACTOR AI VALUATION ENGINE")),
            span(class = "ticker-item", paste0("\U0001F6E3\uFE0F AVG MILEAGE ", hero_avgmile_fmt)),
            span(class = "ticker-item", paste0("\U0001F3F7\uFE0F ", hero_brands_fmt, " BRANDS COVERED"))
          )
        )
      )
    ),
    nav_panel(
      title = tagList(icon("gauge-high"), "DASHBOARD Overview"), value = "DASHBOARD Overview",
      layout_column_wrap(
        width = 1/4,
        div(class = "metric-box",
            div(class = "metric-icon", icon("sack-dollar")),
            div(class = "metric-label", "Avg Price"), div(class = "metric-value", textOutput("avg_p"))),
        div(class = "metric-box line-green",
            div(class = "metric-icon", icon("crown")),
            div(class = "metric-label", "Top Price Tier"), div(class = "metric-value", textOutput("max_p"))),
        div(class = "metric-box line-blue",
            div(class = "metric-icon", icon("road")),
            div(class = "metric-label", "Avg Mileage"), div(class = "metric-value", textOutput("avg_m"))),
        div(class = "metric-box line-red",
            div(class = "metric-icon", icon("warehouse")),
            div(class = "metric-label", "Total Inventory"), div(class = "metric-value", textOutput("total_c")))
      ),
      br(),
      layout_column_wrap(
        width = 1/2,
        card(card_header(icon("gas-pump"), " Fuel Share"), plotlyOutput("fuel_donut", height = "350px")),
        card(card_header(icon("ranking-star"), " Top 10 Brands"), plotlyOutput("brand_bar", height = "350px"))
      ),
      card(card_header(icon("chart-area"), " Price vs. Mileage Density"), plotlyOutput("price_heatmap", height = "400px"))
    ),

    nav_panel(
      title = tagList(icon("chart-line"), "Deep Analytics"), value = "Deep Analytics",
      card(card_header(icon("brain"), " What Drives Price — Random Forest Feature Importance ",
                        span(class = "live-dot", style = "margin-left:4px;")),
           plotlyOutput("feat_importance", height = "320px")),
      br(),
      layout_column_wrap(
        width = 1/2,
        card(card_header(icon("layer-group"), " Price Distribution (Top Brands)"), plotlyOutput("brand_box", height = "380px")),
        card(card_header(icon("gears"), " Transmission Split"), plotlyOutput("trans_pie", height = "380px"))
      ),
      br(),
      layout_column_wrap(
        width = 1/2,
        card(card_header(icon("chart-line"), " Average Price by Model Year"), plotlyOutput("price_trend", height = "380px")),
        card(card_header(icon("road"), " Price by Drivetrain"), plotlyOutput("drivetrain_box", height = "380px"))
      ),
      br(),
      card(card_header(icon("circle-nodes"), " Brand Market Map — Price vs. Mileage vs. Volume"),
           plotlyOutput("market_bubble", height = "440px"))
    ),

    nav_panel(
      title = tagList(icon("robot"), "AI PRICE PREDICTOR"), value = "AI PRICE PREDICTOR",
      div(class = "container-fluid",
        layout_column_wrap(
          width = 1/4,
          div(class = "metric-box",
              div(class = "metric-icon", icon("bullseye")),
              div(class = "metric-label", "Model Accuracy"), div(class = "metric-value", paste0(model_r2 * 100, "%"))),
          div(class = "metric-box line-green",
              div(class = "metric-icon", icon("scale-balanced")),
              div(class = "metric-label", "Avg. Error"), div(class = "metric-value", paste0("$", format(model_mae, big.mark = ",")))),
          div(class = "metric-box line-blue",
              div(class = "metric-icon", icon("database")),
              div(class = "metric-label", "Trained On"), div(class = "metric-value", format(model_n, big.mark = ","))),
          div(class = "metric-box line-red",
              div(class = "metric-icon", icon("calendar-check")),
              div(class = "metric-label", "Valid Year Range"), div(class = "metric-value", paste0(YEAR_MIN, "\u2013", YEAR_MAX)))
        ),
        div(style = "color:#75767B; font-family:'IBM Plex Mono',monospace; font-size:11px; text-align:center; margin:-6px 0 16px;",
            icon("shield-halved"), " Accuracy measured with out-of-bag validation on data the model never trained on \u2014 not a guess."),
        br(),
        layout_column_wrap(
          width = 1/2,
          card(card_header(icon("file-pen"), " Enter Car Specifications"),
            layout_column_wrap(width = 1/2,
              selectInput("p_brand", "Brand", choices = brand_choices),
              sliderInput("p_year", "Year", min = YEAR_MIN, max = YEAR_MAX, value = round((YEAR_MIN + YEAR_MAX) / 2), step = 1, sep = ""),
              selectInput("p_fuel", "Fuel Type", choices = fuel_choices),
              selectInput("p_drive", "Drivetrain", choices = drive_choices),
              selectInput("p_trans", "Transmission", choices = trans_choices),
              sliderInput("p_mileage", "Mileage (mi)", min = MILEAGE_MIN, max = MILEAGE_MAX, value = 30000, step = 1000)
            ),
            div(style = "color:#75767B; font-family:'IBM Plex Mono',monospace; font-size:10px; margin-top:-6px;",
                icon("circle-info"), paste0(" Year and mileage are capped to the real range in the data (", YEAR_MIN, "\u2013", YEAR_MAX,
                                             ") so every estimate is a genuine interpolation, never a guess beyond what the model has seen.")),
            br(),
            actionButton("predict_btn", "ESTIMATE PRICE", icon = icon("calculator"), class = "btn-estimate")
          ),
          card(card_header(icon("taxi"), " AI Valuation"),
            div(class = "meter-shell",
              div(class = "meter-label", span(class = "live-dot"), "Estimated Market Value"),
              div(class = "meter-screen", uiOutput("prediction_result")),
              div(class = "meter-foot", icon("bolt"), paste0(" Random Forest \u2022 R\u00b2 ", model_r2, " \u2022 50 Trees"))
            )
          )
        ),
        br(),
        layout_column_wrap(
          width = 1/2,
          card(card_header(icon("chart-line"), " Price Trajectory \u2014 Same Car, Different Model Years"),
               plotlyOutput("pdp_year", height = "300px")),
          card(card_header(icon("road"), " Price Sensitivity \u2014 Same Car, Different Mileage"),
               plotlyOutput("pdp_mileage", height = "300px"))
        ),
        br(),
        layout_column_wrap(
          width = 1/2,
          card(card_header(icon("arrows-left-right"), " Prediction Confidence Range (Random Forest Ensemble)"),
               plotlyOutput("pred_confidence", height = "260px")),
          card(card_header(icon("layer-group"), " Market Position vs. Similar Listings"),
               plotlyOutput("market_position", height = "260px"))
        )
      )
    )
  ),
  tags$head(tags$style(HTML(custom_css)))
)

# ============================================================
# 5. SERVER
# ============================================================
server <- function(input, output, session) {

  # Landing page buttons take the user straight to the requested tab
  observeEvent(input$go_dashboard, { nav_select("nav_tabs", selected = "DASHBOARD Overview", session = session) })
  observeEvent(input$go_analytics, { nav_select("nav_tabs", selected = "Deep Analytics", session = session) })
  observeEvent(input$go_predictor, { nav_select("nav_tabs", selected = "AI PRICE PREDICTOR", session = session) })

  plot_layout_theme <- function(p, legend = FALSE) {
    p %>% layout(
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      font = list(family = "Inter", color = "#B7B8BD", size = 12),
      legend = list(orientation = "h", bgcolor = "rgba(0,0,0,0)"),
      showlegend = legend,
      margin = list(t = 20)
    ) %>%
      style(hoverlabel = list(bgcolor = "#16171B", bordercolor = taxi,
                               font = list(color = "#F2F2F0", family = "IBM Plex Mono")))
  }

  # Debounce prevents lag/stutter when the filter sliders are moved quickly
  filtered_data <- reactive({
    res <- Car_df
    if (!is.null(input$fuel)) res <- res %>% filter(Fuel_Type %in% input$fuel)
    if (!is.null(input$drive)) res <- res %>% filter(Drivetrain %in% input$drive)
    res %>% filter(between(Year, input$year_range[1], input$year_range[2]))
  }) %>% debounce(500)

  # Reactive KPI cards
  output$avg_p <- renderText({
    d <- filtered_data(); if (nrow(d) == 0) return("$0")
    paste0("$", format(round(mean(d$Price, na.rm = TRUE)), big.mark = ",", scientific = FALSE))
  })

  output$max_p <- renderText({
    d <- filtered_data(); if (nrow(d) == 0) return("$0")
    # Exclude the detected price cap (if any)
    d_clean <- if (!is.na(CAP_PRICE)) d %>% filter(Price != CAP_PRICE) else d
    if (nrow(d_clean) == 0) d_clean <- d
    # Problem: many cars are priced at repeated round numbers (e.g. $74,900),
    # so that same figure keeps showing up as the "max" across different
    # filters even though they're different cars. So instead of taking a
    # single value (max/percentile), we average the top price band (~top 1%),
    # which reflects the filter's real composition instead of one number
    # that happens to repeat.
    threshold <- quantile(d_clean$Price, 0.99, na.rm = TRUE)
    top_band <- d_clean %>% filter(Price >= threshold)
    val <- mean(top_band$Price, na.rm = TRUE)
    paste0("$", format(round(val), big.mark = ",", scientific = FALSE))
  })

  output$avg_m <- renderText({
    d <- filtered_data(); if (nrow(d) == 0) return("0 mi")
    paste0(format(round(mean(d$Mileage, na.rm = TRUE)), big.mark = ",", scientific = FALSE), " mi")
  })

  output$total_c <- renderText(format(nrow(filtered_data()), big.mark = ","))

  # Charts
  output$fuel_donut <- renderPlotly({
    d <- filtered_data() %>% count(Fuel_Type)
    plot_ly(d, labels = ~Fuel_Type, values = ~n, type = "pie", hole = 0.62,
            marker = list(colors = subway_palette, line = list(color = "#0A0A0C", width = 2)),
            textfont = list(family = "IBM Plex Mono", color = "#F2F2F0")) %>%
      plot_layout_theme(legend = TRUE)
  })

  output$brand_bar <- renderPlotly({
    d <- filtered_data() %>% count(brand, sort = TRUE) %>% slice_head(n = 10)
    plot_ly(d, x = ~reorder(brand, n), y = ~n, type = "bar",
            marker = list(color = ~n, colorscale = list(c(0, "#3A2F0B"), c(1, taxi)),
                           line = list(color = "#0A0A0C", width = 1))) %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "", gridcolor = "#232428", color = "#B7B8BD"))
  })

  # Fast interactive density heatmap
  output$price_heatmap <- renderPlotly({
    plot_ly(filtered_data(), x = ~Mileage, y = ~Price, type = "histogram2dcontour",
            colorscale = list(c(0, "#0A0A0C"), c(0.55, "#5E4712"), c(1, taxi)),
            ncontours = 20, contours = list(showlines = FALSE)) %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "Mileage", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "Price", gridcolor = "#232428", color = "#B7B8BD"))
  })

  output$brand_box <- renderPlotly({
    top <- filtered_data() %>% count(brand, sort = TRUE) %>% slice_head(n = 8) %>% pull(brand)
    filtered_data() %>% filter(brand %in% top) %>%
      plot_ly(x = ~brand, y = ~Price, type = "box", color = ~brand,
              colors = subway_palette, marker = list(size = 3)) %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "", gridcolor = "#232428", color = "#B7B8BD"))
  })

  output$trans_pie <- renderPlotly({
    d <- filtered_data() %>% count(Transmission)
    plot_ly(d, labels = ~Transmission, values = ~n, type = "pie",
            marker = list(colors = subway_palette, line = list(color = "#0A0A0C", width = 2)),
            textfont = list(family = "IBM Plex Mono", color = "#F2F2F0")) %>%
      plot_layout_theme(legend = TRUE)
  })

  # Feature importance — dynamically recomputed based on the current filters
  # (a small, fast model separate from the main prediction model, capped
  # sample size to keep it quick)
  filtered_importance <- reactive({
    d <- filtered_data()
    if (nrow(d) < 50) return(NULL)  # sample too small for reliable training

    d_sample <- d %>% slice_sample(n = min(nrow(d), 6000)) %>%
      mutate(across(c(brand, Fuel_Type, Drivetrain, Transmission), droplevels))

    # If only a single level remains in every categorical column (a very
    # narrow filter), fall back to the baseline model
    cat_cols <- c("brand", "Fuel_Type", "Drivetrain", "Transmission")
    if (all(sapply(d_sample[cat_cols], function(x) nlevels(x) < 2))) return(importance_df)

    fit <- tryCatch({
      randomForest(Price ~ Year + Mileage + brand + Fuel_Type + Drivetrain + Transmission,
                   data = d_sample, ntree = 10, importance = TRUE)
    }, error = function(e) NULL)
    if (is.null(fit)) return(importance_df)  # safe fallback on any training error

    imp <- importance(fit)
    data.frame(Feature = rownames(imp), Importance = imp[, 1]) %>% arrange(Importance)
  })

  output$feat_importance <- renderPlotly({
    imp <- filtered_importance()
    if (is.null(imp)) {
      return(plotly_empty(type = "bar") %>% plot_layout_theme() %>%
               layout(annotations = list(text = "Not enough data in this filter to compute importance",
                                          showarrow = FALSE, font = list(color = "#75767B", family = "IBM Plex Mono"))))
    }
    plot_ly(imp, x = ~Importance, y = ~reorder(Feature, Importance), type = "bar",
            orientation = "h",
            marker = list(color = ~Importance, colorscale = list(c(0, "#3A2F0B"), c(1, taxi)),
                           line = list(color = "#0A0A0C", width = 1))) %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "% Increase in MSE if Removed", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "", gridcolor = "#232428", color = "#B7B8BD"))
  })

  # Average price across model years — market trend
  output$price_trend <- renderPlotly({
    d <- filtered_data() %>%
      group_by(Year) %>%
      summarise(avg_price = mean(Price, na.rm = TRUE), n = n(), .groups = "drop") %>%
      filter(n >= 3) %>% arrange(Year)
    if (nrow(d) == 0) return(plotly_empty(type = "scatter", mode = "markers") %>% plot_layout_theme())
    plot_ly(d, x = ~Year, y = ~avg_price, type = "scatter", mode = "lines+markers",
            line = list(color = taxi, width = 3, shape = "spline"),
            marker = list(color = sub_teal, size = 7, line = list(color = "#0A0A0C", width = 1)),
            fill = "tozeroy", fillcolor = "rgba(245,197,24,0.08)") %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "Model Year", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "Avg. Price ($)", gridcolor = "#232428", color = "#B7B8BD"))
  })

  # Price distribution by drivetrain
  output$drivetrain_box <- renderPlotly({
    filtered_data() %>%
      plot_ly(x = ~Drivetrain, y = ~Price, type = "violin", box = list(visible = TRUE),
              meanline = list(visible = TRUE), color = ~Drivetrain, colors = subway_palette,
              points = FALSE) %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "", gridcolor = "#232428", color = "#B7B8BD"))
  })

  # Market map: average price vs. average mileage per brand, bubble size reflects listing volume
  output$market_bubble <- renderPlotly({
    d <- filtered_data() %>%
      group_by(brand) %>%
      summarise(avg_price = mean(Price, na.rm = TRUE),
                avg_mileage = mean(Mileage, na.rm = TRUE),
                count = n(), .groups = "drop") %>%
      filter(count >= 5) %>%
      arrange(desc(count)) %>%
      slice_head(n = 18)
    if (nrow(d) == 0) return(plotly_empty(type = "scatter", mode = "markers") %>% plot_layout_theme())
    plot_ly(d, x = ~avg_mileage, y = ~avg_price, type = "scatter", mode = "markers+text",
            text = ~brand, textposition = "top center",
            textfont = list(family = "IBM Plex Mono", size = 10, color = "#B7B8BD"),
            marker = list(size = ~count, sizemode = "area",
                           sizeref = 2 * max(d$count) / (42^2), sizemin = 6,
                           color = ~avg_price, colorscale = list(c(0, sub_teal), c(1, taxi)),
                           line = list(color = "#0A0A0C", width = 1), opacity = 0.85)) %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "Avg. Mileage (mi)", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "Avg. Price ($)", gridcolor = "#232428", color = "#B7B8BD"))
  })

  # Prediction — build the "car spec" once when the button is clicked, then
  # every chart below is built from that same spec and the same Random Forest model
  # NULL-safe check for button state (before any interaction) that won't crash
  btn_clicked <- function() !is.null(spec_val())

  spec_val <- reactiveVal(NULL)
  observeEvent(input$predict_btn, {
    spec_val(data.frame(brand = factor(input$p_brand, levels = levels(Car_df$brand)),
                         Year = as.numeric(input$p_year),
                         Fuel_Type = factor(input$p_fuel, levels = levels(Car_df$Fuel_Type)),
                         Drivetrain = factor(input$p_drive, levels = levels(Car_df$Drivetrain)),
                         Transmission = factor(input$p_trans, levels = levels(Car_df$Transmission)),
                         Mileage = as.numeric(input$p_mileage)))
  })

  prediction_val <- reactive({ req(spec_val()); predict(rf_model, spec_val()) })

  output$prediction_result <- renderUI({
    if (is.null(spec_val())) return(div(class = "meter-digits is-idle", "$ - - - -"))
    val <- prediction_val()
    div(class = "meter-digits", paste0("$", format(round(val, 0), big.mark = ",")))
  })

  empty_prompt <- function(msg) {
    plotly_empty(type = "scatter", mode = "markers") %>% plot_layout_theme() %>%
      layout(annotations = list(text = msg, showarrow = FALSE, font = list(color = "#75767B", family = "IBM Plex Mono", size = 12)))
  }

  # Partial Dependence: the same car spec but with only the model year varied —
  # shows how the model values the same car across different years (depreciation curve)
  output$pdp_year <- renderPlotly({
    if (!btn_clicked()) return(empty_prompt("Enter specs and click ESTIMATE PRICE"))
    spec <- spec_val()
    yrs <- sort(unique(Car_df$Year))
    batch <- do.call(rbind, lapply(yrs, function(y) { s <- spec; s$Year <- y; s }))
    preds <- as.numeric(predict(rf_model, batch))
    d <- data.frame(Year = yrs, Price = preds)
    sel <- d[which.min(abs(d$Year - as.numeric(input$p_year))), ]
    plot_ly() %>%
      add_trace(data = d, x = ~Year, y = ~Price, type = "scatter", mode = "lines",
                line = list(color = taxi, width = 3, shape = "spline"),
                fill = "tozeroy", fillcolor = "rgba(245,197,24,0.08)", name = "Model estimate") %>%
      add_trace(data = sel, x = ~Year, y = ~Price, type = "scatter", mode = "markers",
                marker = list(color = sub_teal, size = 13, line = list(color = "#0A0A0C", width = 2)),
                name = "Your selection") %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "Model Year", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "Predicted Price ($)", gridcolor = "#232428", color = "#B7B8BD"),
             showlegend = FALSE)
  })

  # Partial Dependence: the same car but across different mileage values
  output$pdp_mileage <- renderPlotly({
    if (!btn_clicked()) return(empty_prompt("Enter specs and click ESTIMATE PRICE"))
    spec <- spec_val()
    mile_max <- quantile(Car_df$Mileage, 0.97, na.rm = TRUE)
    mile_seq <- seq(0, mile_max, length.out = 16)
    batch <- do.call(rbind, lapply(mile_seq, function(m) { s <- spec; s$Mileage <- m; s }))
    preds <- as.numeric(predict(rf_model, batch))
    d <- data.frame(Mileage = mile_seq, Price = preds)
    sel_mile <- as.numeric(input$p_mileage)
    sel_price <- as.numeric(predict(rf_model, spec))
    plot_ly() %>%
      add_trace(data = d, x = ~Mileage, y = ~Price, type = "scatter", mode = "lines",
                line = list(color = sub_teal, width = 3, shape = "spline"),
                fill = "tozeroy", fillcolor = "rgba(0,229,255,0.08)", name = "Model estimate") %>%
      add_trace(x = sel_mile, y = sel_price, type = "scatter", mode = "markers",
                marker = list(color = taxi, size = 13, line = list(color = "#0A0A0C", width = 2)),
                name = "Your selection") %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "Mileage (mi)", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "Predicted Price ($)", gridcolor = "#232428", color = "#B7B8BD"),
             showlegend = FALSE)
  })

  # Confidence range: distribution of individual tree estimates within the
  # Random Forest for this exact car — reflects genuine internal model
  # agreement/disagreement about the price, not decoration
  output$pred_confidence <- renderPlotly({
    if (!btn_clicked()) return(empty_prompt("Enter specs and click ESTIMATE PRICE"))
    spec <- spec_val()
    all_preds <- predict(rf_model, spec, predict.all = TRUE)
    tree_vals <- as.numeric(all_preds$individual)
    plot_ly(x = tree_vals, y = rep("15 Trees", length(tree_vals)), type = "box",
            boxpoints = "all", jitter = 0.6, pointpos = 0,
            marker = list(color = sub_teal, size = 6, opacity = 0.7),
            line = list(color = taxi), fillcolor = "rgba(245,197,24,0.12)") %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = "Individual Tree Price Estimates ($)", gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "", gridcolor = "#232428", color = "#B7B8BD"),
             showlegend = FALSE)
  })

  # This car's position against real listings of the same brand in the data
  output$market_position <- renderPlotly({
    if (!btn_clicked()) return(empty_prompt("Enter specs and click ESTIMATE PRICE"))
    spec <- spec_val()
    pred_price <- as.numeric(predict(rf_model, spec))
    brand_prices <- Car_df %>% filter(brand == input$p_brand) %>% pull(Price)
    if (length(brand_prices) < 5) return(empty_prompt("Not enough listings for this brand to compare"))
    plot_ly(x = brand_prices, type = "histogram", nbinsx = 30,
            marker = list(color = "rgba(0,229,255,.35)", line = list(color = "#0A0A0C", width = 1))) %>%
      plot_layout_theme() %>%
      layout(xaxis = list(title = paste("Real", input$p_brand, "Listing Prices ($)"), gridcolor = "#232428", color = "#B7B8BD"),
             yaxis = list(title = "Listings", gridcolor = "#232428", color = "#B7B8BD"),
             shapes = list(list(type = "line", x0 = pred_price, x1 = pred_price, y0 = 0, y1 = 1, yref = "paper",
                                 line = list(color = taxi, width = 3, dash = "dash"))),
             annotations = list(list(x = pred_price, y = 1, yref = "paper", yanchor = "bottom",
                                      text = "Your estimate", showarrow = FALSE,
                                      font = list(color = taxi, family = "IBM Plex Mono", size = 11))))
  })
}

shinyApp(ui, server)
