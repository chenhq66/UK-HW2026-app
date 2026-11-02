# 00_prep_app_data.R ----
# Data preparation pipeline for UKHW2026 Shiny application.
# Generates optimized .parquet tables and pre-joined, simplified spatial .rds files.

# 1. Setup and Configurations ----

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(sf)
  library(rmapshaper)
  library(dplyr)
})

app_data_dir <- "./app_data"
if (!dir.exists(app_data_dir)) dir.create(app_data_dir, recursive = TRUE)

# Input paths
path_lsoa_gpkg <- "//storageondemand/VOLQ/AGteam/ONS/geography/geopkg/LSOA_Dec_2011_Boundaries_Generalised_Clipped_BGC_EW_V3_-8900651938344784411.gpkg"
path_lad_gpkg  <- "//storageondemand/VOLQ/AGteam/ONS/geography/geopkg/Local_Authority_Districts_December_2011_GB_BGC_2022_6395663385981883839.gpkg"
path_lookup    <- "//storageondemand/VOLQ/AGteam/ONS/geography/lookup/Lower_Layer_Super_Output_Area__2011__to_Built-up_Area_Sub-division_to_Built-up_Area_to_Local_Authority_District_to_Region__December_2011__Lookup_in_England_and_Wales.csv"

# Clean period mapping and labels
period_map <- c(
  "1 May-30 Sept"      = "study_period",
  "HW1: 22 May-28 May" = "hw1",
  "HW2: 18 Jun-28 Jun" = "hw2",
  "HW3: 06 Jul-17 Jul" = "hw3",
  "HW4: 29 Jul-05 Aug" = "hw4",
  "HW5: 11 Aug-15 Aug" = "hw5"
)

period_label_map <- c(
  "study_period" = "1 May–30 September 2026",
  "hw1"          = "Heatwave 1 (22–28 May)",
  "hw2"          = "Heatwave 2 (18–28 June)",
  "hw3"          = "Heatwave 3 (6–17 July)",
  "hw4"          = "Heatwave 4 (29 July–5 August)",
  "hw5"          = "Heatwave 5 (11–15 August)"
)

# 2. Tabular Parquet Datasets ----

## Process summary estimates ----
cat("Preparing summary_estimates.parquet...\n")

nat_age <- fread("./data/national_age_period.csv")
reg_age <- fread("./data/region_age_period.csv")
nat_75p <- fread("./data/national_75plus_period.csv")
reg_75p <- fread("./data/region_75plus_period.csv")

nat_combined <- rbindlist(list(nat_age, nat_75p), use.names = TRUE)
nat_combined[, `:=`(
  geo_level = "national",
  rgn11cd   = "EW",
  rgn11nm   = "England & Wales"
)]

reg_combined <- rbindlist(list(reg_age, reg_75p), use.names = TRUE)
reg_combined[, `:=`(
  geo_level = "region",
  rgn11cd   = RGN11CD,
  rgn11nm   = region
)]
reg_combined[, c("RGN11CD", "region") := NULL]

summary_dt <- rbindlist(list(nat_combined, reg_combined), use.names = TRUE)
summary_dt[, period_key := period_map[period]]
summary_dt[, period_label := period_label_map[period_key]]
summary_dt[, period := period_key]
summary_dt[, period_key := NULL]

# Order columns logically
setcolorder(summary_dt, c("geo_level", "rgn11cd", "rgn11nm", "agegr", "age", "period", "period_label"))
write_parquet(summary_dt, file.path(app_data_dir, "summary_estimates.parquet"))
cat("Saved summary_estimates.parquet (", nrow(summary_dt), "rows)\n")

## Process daily series ----
cat("Preparing daily_series.parquet...\n")

nat_daily <- fread("./data/national_daily.csv")
nat_t2m   <- fread("./data/national_t2m_daily.csv")

daily_dt <- merge(nat_daily, nat_t2m, by = "date", all.x = TRUE)
daily_dt[, date := as.IDate(date)]

# Tag heatwave event per date
daily_dt[, hw_event := "none"]
daily_dt[date >= as.IDate("2026-05-22") & date <= as.IDate("2026-05-28"), hw_event := "hw1"]
daily_dt[date >= as.IDate("2026-06-18") & date <= as.IDate("2026-06-28"), hw_event := "hw2"]
daily_dt[date >= as.IDate("2026-07-06") & date <= as.IDate("2026-07-17"), hw_event := "hw3"]
daily_dt[date >= as.IDate("2026-07-29") & date <= as.IDate("2026-08-05"), hw_event := "hw4"]
daily_dt[date >= as.IDate("2026-08-11") & date <= as.IDate("2026-08-15"), hw_event := "hw5"]

setcolorder(daily_dt, c("date", "hw_event", "agegr", "age", "meantemp", "population", "estimate", "lower", "upper", "rate"))
write_parquet(daily_dt, file.path(app_data_dir, "daily_series.parquet"))
cat("Saved daily_series.parquet (", nrow(daily_dt), "rows)\n")

# 3. Spatial Processing: LADs and Regions ----

cat("Loading lookup table...\n")
lu_dt <- fread(path_lookup)
lu_dt[grepl("^W", LAD11CD), `:=`(RGN11CD = "W92000004", RGN11NM = "Wales")]

lu_lads <- unique(lu_dt[, .(
  lad11cd = LAD11CD,
  lad11nm = LAD11NM,
  rgn11cd = RGN11CD,
  rgn11nm = RGN11NM
)])

cat("Loading and simplifying LAD boundaries...\n")
lads_raw <- st_read(path_lad_gpkg, layer = "Local_Authority_Districts_December_2011_GB_BGC", quiet = TRUE)
lads_ew  <- lads_raw[grepl("^[EW]", lads_raw$lad11cd), ]
lads_sim <- ms_simplify(lads_ew, keep = 0.10, keep_shapes = TRUE)
lads_wgs84 <- st_transform(lads_sim, 4326)

# Join lookup identifiers
lads_sf <- lads_wgs84 %>%
  select(lad11cd) %>%
  left_join(lu_lads, by = "lad11cd")

## Add LAD estimates ----
lad_study <- fread("./data/lad_study_period.csv")
lsoa_dt   <- fread("./data/lsoa_hw_period.csv")

# Study period point estimates
lad_study_clean <- lad_study[, .(
  lad11cd = LAD11CD,
  population = population,
  estimate_study_period = round(estimate, 2),
  rate_study_period     = round(rate, 2)
)]

# Aggregate LSOA heatwaves to LAD
lad_hw <- lsoa_dt[, .(estimate = sum(estimate)), by = .(lad11cd = LAD11CD, event = tolower(event))]
lad_hw_wide <- dcast(lad_hw, lad11cd ~ event, value.var = "estimate")
setnames(lad_hw_wide, c("hw1", "hw2", "hw3", "hw4", "hw5"), paste0("estimate_", c("hw1", "hw2", "hw3", "hw4", "hw5")))

lad_metrics <- merge(lad_study_clean, lad_hw_wide, by = "lad11cd", all.x = TRUE)
lad_metrics[, estimate_total_hw := round(estimate_hw1 + estimate_hw2 + estimate_hw3 + estimate_hw4 + estimate_hw5, 2)]

# Compute heatwave rates per million
for (hw in c("hw1", "hw2", "hw3", "hw4", "hw5", "total_hw")) {
  est_col  <- paste0("estimate_", hw)
  rate_col <- paste0("rate_", hw)
  lad_metrics[, (est_col) := round(get(est_col), 2)]
  lad_metrics[, (rate_col) := round((get(est_col) / population) * 1e6, 2)]
}

# Precompute HTML tooltips for LAD across periods
for (p in c("study_period", "hw1", "hw2", "hw3", "hw4", "hw5")) {
  tip_col  <- paste0("tip_", p)
  est_col  <- if (p == "study_period") "estimate_study_period" else paste0("estimate_", p)
  rate_col <- if (p == "study_period") "rate_study_period" else paste0("rate_", p)
  lbl      <- period_label_map[p]
  
  lad_metrics[, (tip_col) := sprintf(
    "<div style='font-family: Inter, system-ui; font-size: 13px; line-height: 1.4;'><div style='font-weight: 700; font-size: 14px;'>%s <span style='font-weight: 400; color: #64748b;'>(%s)</span></div><div style='color: #64748b; font-size: 11px; margin-bottom: 4px;'>Region: %s</div><div>Excess Deaths: <b>%s</b></div><div>Rate per Million: <b>%s</b></div><div style='color: #94a3b8; font-size: 10px; margin-top: 3px;'>%s</div></div>",
    lads_sf$lad11nm[match(lad11cd, lads_sf$lad11cd)], lad11cd, lads_sf$rgn11nm[match(lad11cd, lads_sf$lad11cd)],
    formatC(get(est_col), format = "f", digits = 1, big.mark = ","),
    formatC(get(rate_col), format = "f", digits = 1, big.mark = ","),
    lbl
  )]
}

geo_lad <- lads_sf %>%
  left_join(lad_metrics, by = "lad11cd")

saveRDS(geo_lad, file.path(app_data_dir, "geo_lad.rds"), compress = "gzip")
cat("Saved geo_lad.rds (", nrow(geo_lad), "features)\n")

## Dissolve Regions from simplified LADs ----
cat("Dissolving and processing Region boundaries...\n")
geo_region <- geo_lad %>%
  group_by(rgn11cd, rgn11nm) %>%
  summarise(do_union = TRUE, .groups = "drop")

# Pivot All-Ages regional estimates wide with 95% eCIs
reg_all <- summary_dt[geo_level == "region" & agegr == "all"]

reg_wide_est      <- dcast(reg_all, rgn11cd ~ period, value.var = "estimate")
setnames(reg_wide_est, names(reg_wide_est)[-1], paste0("estimate_", names(reg_wide_est)[-1]))

reg_wide_rate     <- dcast(reg_all, rgn11cd ~ period, value.var = "rate")
setnames(reg_wide_rate, names(reg_wide_rate)[-1], paste0("rate_", names(reg_wide_rate)[-1]))

reg_wide_low      <- dcast(reg_all, rgn11cd ~ period, value.var = "lower")
setnames(reg_wide_low, names(reg_wide_low)[-1], paste0("lower_", names(reg_wide_low)[-1]))

reg_wide_upp      <- dcast(reg_all, rgn11cd ~ period, value.var = "upper")
setnames(reg_wide_upp, names(reg_wide_upp)[-1], paste0("upper_", names(reg_wide_upp)[-1]))

reg_wide_ratelow  <- dcast(reg_all, rgn11cd ~ period, value.var = "ratelow")
setnames(reg_wide_ratelow, names(reg_wide_ratelow)[-1], paste0("ratelow_", names(reg_wide_ratelow)[-1]))

reg_wide_ratehigh <- dcast(reg_all, rgn11cd ~ period, value.var = "ratehigh")
setnames(reg_wide_ratehigh, names(reg_wide_ratehigh)[-1], paste0("ratehigh_", names(reg_wide_ratehigh)[-1]))

reg_pop <- unique(reg_all[, .(rgn11cd, population)])
reg_wide <- merge(reg_pop, reg_wide_est, by = "rgn11cd")
reg_wide <- merge(reg_wide, reg_wide_rate, by = "rgn11cd")
reg_wide <- merge(reg_wide, reg_wide_low, by = "rgn11cd")
reg_wide <- merge(reg_wide, reg_wide_upp, by = "rgn11cd")
reg_wide <- merge(reg_wide, reg_wide_ratelow, by = "rgn11cd")
reg_wide <- merge(reg_wide, reg_wide_ratehigh, by = "rgn11cd")

# Precompute HTML tooltips for Region with 95% eCIs
for (p in c("study_period", "hw1", "hw2", "hw3", "hw4", "hw5")) {
  tip_col       <- paste0("tip_", p)
  est_col       <- paste0("estimate_", p)
  rate_col      <- paste0("rate_", p)
  low_col       <- paste0("lower_", p)
  upp_col       <- paste0("upper_", p)
  ratelow_col   <- paste0("ratelow_", p)
  ratehigh_col  <- paste0("ratehigh_", p)
  lbl           <- period_label_map[p]
  
  reg_wide[, (tip_col) := sprintf(
    "<div style='font-family: Inter, system-ui; font-size: 13px; line-height: 1.4;'><div style='font-weight: 700; font-size: 14px;'>%s <span style='font-weight: 400; color: #64748b;'>(%s)</span></div><div style='margin-top: 4px;'>Excess Deaths: <b>%s</b> <span style='color: #64748b; font-size: 11px;'>[95%% eCI: %s – %s]</span></div><div>Rate per Million: <b>%s</b> <span style='color: #64748b; font-size: 11px;'>[95%% eCI: %s – %s]</span></div><div style='color: #94a3b8; font-size: 10px; margin-top: 3px;'>%s</div></div>",
    geo_region$rgn11nm[match(rgn11cd, geo_region$rgn11cd)], rgn11cd,
    formatC(round(get(est_col)), format = "d", big.mark = ","),
    formatC(round(get(low_col)), format = "d", big.mark = ","),
    formatC(round(get(upp_col)), format = "d", big.mark = ","),
    formatC(get(rate_col), format = "f", digits = 1, big.mark = ","),
    formatC(get(ratelow_col), format = "f", digits = 1, big.mark = ","),
    formatC(get(ratehigh_col), format = "f", digits = 1, big.mark = ","),
    lbl
  )]
}

# Round numeric metrics
num_cols <- names(reg_wide)[sapply(reg_wide, is.numeric)]
reg_wide[, (num_cols) := lapply(.SD, round, 2), .SDcols = num_cols]

geo_region <- geo_region %>%
  left_join(reg_wide, by = "rgn11cd")

saveRDS(geo_region, file.path(app_data_dir, "geo_region.rds"), compress = "gzip")
cat("Saved geo_region.rds (", nrow(geo_region), "features)\n")

# 4. Spatial Processing: LSOAs ----

cat("Loading and simplifying LSOA boundaries...\n")
lsoa_raw   <- st_read(path_lsoa_gpkg, layer = "LSOA_2011_EW_BGC_V3", quiet = TRUE)
lsoa_sim   <- ms_simplify(lsoa_raw, keep = 0.05, keep_shapes = TRUE)
lsoa_wgs84 <- st_transform(lsoa_sim, 4326)

# Lookup mapping for LSOA
lu_lsoa <- unique(lu_dt[, .(
  lsoa11cd = LSOA11CD,
  lsoa11nm = LSOA11NM,
  lad11cd  = LAD11CD,
  lad11nm  = LAD11NM,
  rgn11cd  = RGN11CD,
  rgn11nm  = RGN11NM
)])

geo_lsoa_base <- lsoa_wgs84 %>%
  select(lsoa11cd = LSOA11CD) %>%
  left_join(lu_lsoa, by = "lsoa11cd")

## Pivot LSOA heatwave metrics wide ----
cat("Pivoting LSOA metrics wide...\n")
lsoa_dt[, event_clean := tolower(event)]

lsoa_wide_est <- dcast(lsoa_dt, LSOA11CD + population ~ event_clean, value.var = "estimate")
setnames(lsoa_wide_est, c("hw1", "hw2", "hw3", "hw4", "hw5"), paste0("estimate_", c("hw1", "hw2", "hw3", "hw4", "hw5")))

lsoa_wide_est[, estimate_total_hw := estimate_hw1 + estimate_hw2 + estimate_hw3 + estimate_hw4 + estimate_hw5]

for (hw in c("hw1", "hw2", "hw3", "hw4", "hw5", "total_hw")) {
  est_col  <- paste0("estimate_", hw)
  rate_col <- paste0("rate_", hw)
  lsoa_wide_est[, (rate_col) := round((get(est_col) / population) * 1e6, 2)]
  lsoa_wide_est[, (est_col) := round(get(est_col), 3)]
}

setnames(lsoa_wide_est, "LSOA11CD", "lsoa11cd")

geo_lsoa <- geo_lsoa_base %>%
  left_join(lsoa_wide_est, by = "lsoa11cd")

# Precompute HTML tooltips for LSOA across periods
for (p in c("study_period", "hw1", "hw2", "hw3", "hw4", "hw5")) {
  tip_col  <- paste0("tip_", p)
  est_col  <- if (p == "study_period") "estimate_total_hw" else paste0("estimate_", p)
  rate_col <- if (p == "study_period") "rate_total_hw" else paste0("rate_", p)
  lbl      <- period_label_map[p]
  
  geo_lsoa[[tip_col]] <- sprintf(
    "<div style='font-family: Inter, system-ui; font-size: 12px; line-height: 1.4;'><div style='font-weight: 700; font-size: 13px;'>%s <span style='font-weight: 400; color: #64748b;'>(%s)</span></div><div style='color: #64748b; font-size: 11px; margin-bottom: 3px;'>%s | %s</div><div>Excess Deaths: <b>%s</b></div><div>Rate per Million: <b>%s</b></div><div style='color: #94a3b8; font-size: 10px; margin-top: 3px;'>%s</div></div>",
    geo_lsoa$lsoa11nm, geo_lsoa$lsoa11cd, geo_lsoa$lad11nm, geo_lsoa$rgn11nm,
    formatC(geo_lsoa[[est_col]], format = "f", digits = 2, big.mark = ","),
    formatC(geo_lsoa[[rate_col]], format = "f", digits = 1, big.mark = ","),
    lbl
  )
}

cat("Saving geo_lsoa.rds...\n")
saveRDS(geo_lsoa, file.path(app_data_dir, "geo_lsoa.rds"), compress = "gzip")
cat("Saved geo_lsoa.rds (", nrow(geo_lsoa), "features)\n")

# 5. Verification and Diagnostics ----

cat("\n======================================================\n")
cat("GENERATED APP ASSETS VERIFICATION:\n")
cat("======================================================\n")

assets <- list.files(app_data_dir, full.names = TRUE)
for (a in assets) {
  sz_mb <- round(file.info(a)$size / (1024^2), 2)
  cat(sprintf("%-30s : %6.2f MB\n", basename(a), sz_mb))
}
cat("\nETL Pipeline completed successfully!\n")
