# UK-HW2026

This repository contains the code and analysis inputs for the assessment of
heat-related excess mortality in England and Wales from 1 May to 30 September
2026.

The analysis applies an established small-area temperature-mortality framework
to 34,753 Lower Layer Super Output Areas (2011 boundaries). It estimates daily
and cumulative mortality by age group, region, LSOA and five identified
heatwave periods. Empirical 95% confidence intervals are based on 500 Monte
Carlo samples of the model coefficients.

## Repository contents

- `data-preparation/00.getdata.R` downloads and reshapes public ONS daily
death-occurrence data into `data/mortality_doy.csv`. It is not called by
`run_all.R`.
- `00.pkg.R` loads the required R packages and creates output folders.
- `01.prep.R` reads and validates all inputs, applies the seasonal
mortality weights and prepares the model objects.
- `02a.impact_totals.R` estimates study-period and heatwave-period totals by
region and age, including empirical confidence intervals.
- `02b.daily_timeseries.R` estimates daily results by age and the England
all-age series used in the UKHSA comparisons.
- `02c.lsoa_impacts.R` estimates daily LSOA point estimates used in Figure 2.
- `03.output.R` creates unformatted national, regional, daily, LSOA and LAD
output files, including the national and regional 75+ results.
- `04.tables.R` creates manuscript Table 1 and Table S2.
- `05.figures.R` creates Figures 1 and 2 from files in `output/`.
- `06.external_comparison.R` creates Table S1.
- `07.exposure_summary.R` creates the temperature statistics reported in the
Results and Figure S1.
- `run_all.R` runs the complete analysis in order.
- `data/` contains model, population, mortality and geography inputs.
- `download/` contains the analysis-ready temperature files and the downloaded
ONS workbook used by the optional data-preparation script.
- `data-preparation/` contains the ONS preparation script and the two
temperature-retrieval notebooks.
- `temp/` contains intermediate model results.
- `output/` contains numeric, machine-readable results without presentation
formatting or individual simulation draws.
- `tables/` and `figures/` contain the generated outputs.

## Software requirements

Run the analysis in R with the following packages installed:
  
  `dlnm`, `mixmeta`, `data.table`, `dplyr`, `tidyr`, `foreach`, `doParallel`,
`MASS`, `abind`, `ggplot2`, `sf`, `patchwork`, `arrow`, `pbs`, and `splines`.

Regenerating `data/mortality_doy.csv` from the ONS workbook additionally
requires `readxl` and `lubridate`.

The temperature extraction notebooks require Python with `pandas`, `pyarrow`,
`requests`, and `timezonefinder`.

## Analysis inputs

The mortality analysis uses:
  
  - previously estimated LSOA- and age-specific model parameters in `data/`;
- 2020 LSOA population data in `data/population_2020.zip`;
- 2024 regional age-specific mortality rates in
`data/deathrates_2024.zip`;
- region-, age- and day-specific mortality counts in
`data/mortality_doy.csv`, reshaped from public ONS death-occurrence data for
2010-2019;
- daily mean 2-m temperature in
`download/LSOA_daily_ERA5_2026m2s_t2m.parquet`.

`01.prep.R` fits the cyclic seasonal models and normalises the resulting daily
weights to a mean of one within each region and age group. The weights therefore
redistribute annual expected mortality across 365 days without changing its
annual total. The supplied CSV is sufficient to run the analysis. To reproduce
it from the ONS source, run:
  
```r
source("data-preparation/00.getdata.R")
```

The script downloads the ONS dataset [*Daily deaths occurrences, England and
  Wales, 1981 and 2020*](https://www.ons.gov.uk/peoplepopulationandcommunity/birthsdeathsandmarriages/deaths/adhocs/14173dailydeathsoccurrencesenglandandwales1981and2020)
(reference 14173), retains 2010-2019 and derives the daily ratios using
periodic B-spline models.

Daily maximum 2-m temperature in
`download/LSOA_daily_ERA5_2026m2s_tmax.parquet` is used only for the
descriptive exposure statistics and Figure S1. Both temperature files cover
every LSOA and date from 1 May to 30 September 2026. They were retrieved at
LSOA centroids through the Open-Meteo Historical Weather API, using its
historical best-match series: ERA5-Land where available and ERA5 where
ERA5-Land was unavailable. Dates were adjusted to Europe/London local time.

The supplied parquet files are sufficient to reproduce the analysis. The
notebooks
`data-preparation/extract_era5_lsoa_open_meteo_daily_t2m_2026.ipynb` and
`data-preparation/extract_era5_lsoa_open_meteo_daily_tmax_2026.ipynb`
document the extraction of the daily mean and daily maximum temperature files,
respectively. They use relative project paths and require the user's own
Open-Meteo customer API key in the `OPEN_METEO_API_KEY` environment variable.
They are kept separate from the R analysis so that routine reproduction does
not make thousands of API calls.

## Identified heatwave periods

The same five analytical windows are applied across all LSOAs:

1. 22-28 May 2026
2. 18-28 June 2026
3. 6-17 July 2026
4. 29 July-5 August 2026
5. 11-15 August 2026

The periods were informed by UKHSA heat-health alerts and corresponding peaks
in the LSOA-averaged temperature series. They are analytical periods rather
than official UK-wide heatwave definitions.

## Running the analysis

Open `UK-HW2026.Rproj` and run:

```r
source("run_all.R")
```

Alternatively, source scripts `00` through `07` in numerical order. Run the
three `02` scripts sequentially because each uses parallel processing. Script
`07` depends only on objects prepared by `01` and may be run separately after
`00` and `01`.

The simulation seed is fixed in `01.prep.R`. The three `02`
scripts are the computationally intensive part of the workflow. After one
complete local run, intermediate RDS files in `temp/` allow `03.output.R` and
later scripts to be rerun without repeating those calculations. The `temp/`
folder is excluded from version control.

## Machine-readable outputs

`03.output.R` creates numeric CSV files without thousands separators or the
500 individual simulation draws:

- `output/national_age_period.csv`: national results by age and period;
- `output/region_age_period.csv`: regional results by age and period;
- `output/national_75plus_period.csv`: national 75+ results by period;
- `output/region_75plus_period.csv`: regional 75+ results by period;
- `output/national_daily.csv`: daily national results by age;
- `output/national_t2m_daily.csv`: the national mean-temperature series;
- `output/lsoa_hw_period.csv`: non-negative LSOA point estimates for each
  heatwave period, used in Figure 2;
- `output/lad_study_period.csv`: all-age LAD point estimates for the complete
  study period, prepared for the Press request. LAD empirical intervals are
  not available because `temp/daylsoa.rds` contains point estimates only.

## Manuscript outputs

Figures:

- `figures/Fig1_daily_ts.png`
- `figures/Fig2_map_excpd.png`
- `figures/FigS1_tmax_extremes.png`

Tables:

- `tables/Table1_summary.csv`
- `tables/TableS1_external_comparison.csv`
- `tables/TableS2_region_age.csv`

The `tables/` folder contains only the three manuscript-facing tables listed
above. Intermediate results are retained as R objects or in `temp/` and are
recreated by the analysis scripts when needed.

## Interpretation

The results are modelled heat-related excess deaths rather than deaths
identified from complete 2026 mortality registrations. The analysis uses
temperature-mortality functions estimated from 2000-2019 data, 2020
population data and 2024 regional mortality rates. Negative LSOA point
estimates are set to zero when calculating the mapped period-specific values;
this does not alter national or regional estimates. Comparisons with Barnes et
al. and UKHSA are descriptive because the assessments differ in data and
methods.
