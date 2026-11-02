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

# 2. Export Tabular CSV Datasets ----

## Export summary_estimates.csv ----
cat("Exporting summary_estimates.csv...\n")
summary_dt <- as.data.table(read_parquet(file.path(app_data_dir, "summary_estimates.parquet")))
csv_summary_path <- file.path(app_data_dir, "summary_estimates.csv")
fwrite(summary_dt, csv_summary_path)
cat(sprintf("Saved %s (%d rows, %.2f KB)\n", basename(csv_summary_path), nrow(summary_dt), file.info(csv_summary_path)$size / 1024))

## Export daily_series.csv ----
cat("Exporting daily_series.csv...\n")
daily_dt <- as.data.table(read_parquet(file.path(app_data_dir, "daily_series.parquet")))
csv_daily_path <- file.path(app_data_dir, "daily_series.csv")
fwrite(daily_dt, csv_daily_path)
cat(sprintf("Saved %s (%d rows, %.2f KB)\n", basename(csv_daily_path), nrow(daily_dt), file.info(csv_daily_path)$size / 1024))

# 3. Export Spatial GeoJSON Datasets ----

## Export geo_region.geojson ----
cat("Exporting geo_region.geojson...\n")
geo_region <- readRDS(file.path(app_data_dir, "geo_region.rds"))
geojson_region_path <- file.path(app_data_dir, "geo_region.geojson")
st_write(
  geo_region,
  geojson_region_path,
  driver = "GeoJSON",
  delete_dsn = TRUE,
  layer_options = "COORDINATE_PRECISION=5",
  quiet = TRUE
)
cat(sprintf("Saved %s (%d features, %.2f MB)\n", basename(geojson_region_path), nrow(geo_region), file.info(geojson_region_path)$size / (1024^2)))

## Export geo_lad.geojson ----
cat("Exporting geo_lad.geojson...\n")
geo_lad <- readRDS(file.path(app_data_dir, "geo_lad.rds"))
geojson_lad_path <- file.path(app_data_dir, "geo_lad.geojson")
st_write(
  geo_lad,
  geojson_lad_path,
  driver = "GeoJSON",
  delete_dsn = TRUE,
  layer_options = "COORDINATE_PRECISION=5",
  quiet = TRUE
)
cat(sprintf("Saved %s (%d features, %.2f MB)\n", basename(geojson_lad_path), nrow(geo_lad), file.info(geojson_lad_path)$size / (1024^2)))

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
