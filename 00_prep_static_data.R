# 00_prep_static_data.R ----
# Export web-ready static data files (CSV, GeoJSON) for Quarto Dashboard and Observable JS ({ojs}).
# Converts pre-processed Parquet tables and RDS spatial layers into lightweight web assets.

# 1. Setup and Configurations ----

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(sf)
})

app_data_dir <- "./app_data"
if (!dir.exists(app_data_dir)) dir.create(app_data_dir, recursive = TRUE)

# 2. Export Tabular CSV & Parquet Datasets from ./data ----

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

std_ages <- c("age064", "age6574", "age7584", "age85plus", "all")

## Export summary_estimates.csv ----
cat("Exporting summary_estimates.csv...\n")
nat_age <- fread("./data/national_age_period.csv")[agegr %in% std_ages]
reg_age <- fread("./data/region_age_period.csv")[agegr %in% std_ages]

nat_combined <- copy(nat_age)[, `:=`(
  geo_level = "national",
  rgn11cd   = "EW",
  rgn11nm   = "England & Wales"
)]

reg_combined <- copy(reg_age)[, `:=`(
  geo_level = "region",
  rgn11cd   = RGN11CD,
  rgn11nm   = region
)][, c("RGN11CD", "region") := NULL]

summary_dt <- rbindlist(list(nat_combined, reg_combined), use.names = TRUE)
summary_dt[, period_key := period_map[period]]
summary_dt[, period_label := period_label_map[period_key]]
summary_dt[, period := period_key][, period_key := NULL]
setcolorder(summary_dt, c("geo_level", "rgn11cd", "rgn11nm", "agegr", "age", "period", "period_label"))
write_parquet(summary_dt, file.path(app_data_dir, "summary_estimates.parquet"))

num_cols_sum <- c("estimate", "lower", "upper", "rate", "ratelow", "ratehigh")
summary_dt[, (num_cols_sum) := lapply(.SD, round, 2), .SDcols = num_cols_sum]
csv_summary_path <- file.path(app_data_dir, "summary_estimates.csv")
fwrite(summary_dt, csv_summary_path)
cat(sprintf("Saved %s (%d rows, %.2f KB)\n", basename(csv_summary_path), nrow(summary_dt), file.info(csv_summary_path)$size / 1024))

## Export daily_series.csv ----
cat("Exporting daily_series.csv...\n")
nat_daily <- fread("./data/national_mort_daily.csv")[agegr %in% std_ages]
nat_t2m   <- fread("./data/national_t2m_daily.csv")

daily_export <- merge(nat_daily, nat_t2m, by = "date", all.x = TRUE)
daily_export[, date := as.IDate(date)]
daily_export[, hw_event := "none"]
daily_export[date >= as.IDate("2026-05-22") & date <= as.IDate("2026-05-28"), hw_event := "hw1"]
daily_export[date >= as.IDate("2026-06-18") & date <= as.IDate("2026-06-28"), hw_event := "hw2"]
daily_export[date >= as.IDate("2026-07-06") & date <= as.IDate("2026-07-17"), hw_event := "hw3"]
daily_export[date >= as.IDate("2026-07-29") & date <= as.IDate("2026-08-05"), hw_event := "hw4"]
daily_export[date >= as.IDate("2026-08-11") & date <= as.IDate("2026-08-15"), hw_event := "hw5"]
setcolorder(daily_export, c("date", "hw_event", "agegr", "age", "meantemp", "population", "estimate", "lower", "upper", "rate", "ratelow", "ratehigh"))
setorder(daily_export, date, agegr)
write_parquet(daily_export, file.path(app_data_dir, "daily_series.parquet"))

num_cols_day <- c("meantemp", "estimate", "lower", "upper", "rate", "ratelow", "ratehigh")
daily_export[, (num_cols_day) := lapply(.SD, round, 2), .SDcols = num_cols_day]

csv_daily_path <- file.path(app_data_dir, "daily_series.csv")
fwrite(daily_export, csv_daily_path)
cat(sprintf("Saved %s (%d rows, %.2f KB)\n", basename(csv_daily_path), nrow(daily_export), file.info(csv_daily_path)$size / 1024))

# 3. Export Spatial GeoJSON Datasets ----

## Export geo_region.geojson ----
cat("Exporting geo_region.geojson...\n")
geo_region <- readRDS(file.path(app_data_dir, "geo_region.rds"))
geo_region_export <- geo_region[, !grepl("^tip_", names(geo_region))]
geojson_region_path <- file.path(app_data_dir, "geo_region.geojson")
st_write(
  geo_region_export,
  geojson_region_path,
  driver = "GeoJSON",
  delete_dsn = TRUE,
  layer_options = "COORDINATE_PRECISION=5",
  quiet = TRUE
)
cat(sprintf("Saved %s (%d features, %.2f MB)\n", basename(geojson_region_path), nrow(geo_region_export), file.info(geojson_region_path)$size / (1024^2)))

## Export geo_lad.geojson ----
cat("Exporting geo_lad.geojson...\n")
geo_lad <- readRDS(file.path(app_data_dir, "geo_lad.rds"))
geo_lad_export <- geo_lad[, !grepl("^tip_", names(geo_lad))]
geojson_lad_path <- file.path(app_data_dir, "geo_lad.geojson")
st_write(
  geo_lad_export,
  geojson_lad_path,
  driver = "GeoJSON",
  delete_dsn = TRUE,
  layer_options = "COORDINATE_PRECISION=5",
  quiet = TRUE
)
cat(sprintf("Saved %s (%d features, %.2f MB)\n", basename(geojson_lad_path), nrow(geo_lad_export), file.info(geojson_lad_path)$size / (1024^2)))

## Export geo_lsoa.geojson ----
cat("Exporting geo_lsoa.geojson...\n")
geo_lsoa <- readRDS(file.path(app_data_dir, "geo_lsoa.rds"))

# Exclude heavy pre-rendered HTML tooltip strings to optimize file size for web rendering
geo_lsoa_export <- geo_lsoa[, !grepl("^tip_", names(geo_lsoa))]

geojson_lsoa_path <- file.path(app_data_dir, "geo_lsoa.geojson")
st_write(
  geo_lsoa_export,
  geojson_lsoa_path,
  driver = "GeoJSON",
  delete_dsn = TRUE,
  layer_options = "COORDINATE_PRECISION=5",
  quiet = TRUE
)
cat(sprintf("Saved %s (%d features, %.2f MB)\n", basename(geojson_lsoa_path), nrow(geo_lsoa_export), file.info(geojson_lsoa_path)$size / (1024^2)))

# 4. Summary Verification ----

cat("\n======================================================\n")
cat("STATIC ASSETS EXPORT SUMMARY:\n")
cat("======================================================\n")

static_files <- c(
  "summary_estimates.csv",
  "daily_series.csv",
  "geo_region.geojson",
  "geo_lad.geojson",
  "geo_lsoa.geojson"
)

for (f in static_files) {
  fp <- file.path(app_data_dir, f)
  if (file.exists(fp)) {
    sz_mb <- file.info(fp)$size / (1024^2)
    cat(sprintf("%-28s : %6.2f MB\n", f, sz_mb))
  } else {
    cat(sprintf("%-28s : MISSING\n", f))
  }
}
cat("\nStatic export pipeline completed successfully!\n")
