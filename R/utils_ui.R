# R/utils_ui.R ----
# UI helper utilities, custom theming, and dialog components for UKHW2026-app.

# 1. Custom Theme Configuration ----

app_theme <- bslib::bs_theme(
  version = 5,
  bootswatch = "litera",
  primary = "#b30000",
  secondary = "#475569",
  success = "#059669",
  info = "#0284c7",
  danger = "#dc2626",
  base_font = bslib::font_google("Inter", local = FALSE),
  heading_font = bslib::font_google("Inter", local = FALSE)
)

# 2. Number and Label Formatters ----

## Integer formatting with thousands separator ----
fmt_int <- function(x) {
  if (is.null(x) || is.na(x)) return("—")
  formatC(round(x), format = "d", big.mark = ",")
}

## Rate formatting with 1 decimal place ----
fmt_rate <- function(x, digits = 1) {
  if (is.null(x) || is.na(x)) return("—")
  formatC(x, format = "f", digits = digits, big.mark = ",")
}

## Confidence interval string ----
fmt_ci_str <- function(low, high, digits = 0) {
  if (is.null(low) || is.na(low) || is.null(high) || is.na(high)) return("—")
  paste0(
    formatC(low, format = "f", digits = digits, big.mark = ","),
    " – ",
    formatC(high, format = "f", digits = digits, big.mark = ",")
  )
}

# 3. About & Methods Modal Dialog ----

show_about_modal <- function() {
  shiny::showModal(
    shiny::modalDialog(
      title = shiny::tagList(
        shiny::icon("circle-info", class = "text-danger me-2"),
        "About the UK 2026 Heat-Related Mortality Study"
      ),
      size = "l",
      easyClose = TRUE,
      footer = shiny::modalButton("Close"),
      
      shiny::tags$div(
        class = "px-2 py-1",
        
        # Background alert
        shiny::tags$div(
          class = "alert alert-secondary mb-3 border-0 bg-light",
          shiny::tags$strong("Important Public Health Notice: "),
          "The figures presented here are ",
          shiny::tags$strong("modelled statistical estimates of heat-related excess mortality"),
          " derived from historical temperature–mortality relationships and reanalysis exposure data, ",
          shiny::tags$em("not"),
          " counts from registered death certificates."
        ),
        
        shiny::tags$h5(class = "fw-bold text-dark mt-3", "Key Findings"),
        shiny::tags$ul(
          shiny::tags$li(
            shiny::tags$strong("5,827 excess deaths"),
            " (95% empirical confidence interval [eCI]: 4,349–6,897) were estimated across England & Wales from 1 May to 30 September 2026 (97.6 deaths per million population)."
          ),
          shiny::tags$li(
            shiny::tags$strong("Episodic concentration: "),
            "91.4% of total heat mortality (5,325 deaths) occurred within five discrete heatwave periods, with the highest burdens in late June (1,808 deaths) and mid-July (1,468 deaths)."
          ),
          shiny::tags$li(
            shiny::tags$strong("Disproportionate impact on older adults: "),
            "People aged 75 years and older accounted for 75.7% of all excess deaths (4,408 deaths), despite comprising only 8.7% of the total population."
          ),
          shiny::tags$li(
            shiny::tags$strong("Geographic variation: "),
            "Excess mortality rates per million were highest in the West Midlands (133.9), South East (133.0), and London (132.4), and lowest in the North East (41.7)."
          )
        ),
        
        shiny::tags$h5(class = "fw-bold text-dark mt-4", "Methodological Framework"),
        shiny::tags$p(
          "This study applied an established small-area health impact framework across all 34,753 Lower Layer Super Output Areas (LSOAs, 2011 boundaries) in England and Wales. ",
          "Daily mean and maximum 2-m temperatures adjusted to local time were derived from ECMWF ERA5-Land and ERA5 reanalyses via Open-Meteo. ",
          "These were coupled to age- and LSOA-specific distributed lag non-linear models (DLNMs, lags 0–21 days) estimated from 2000–2019 mortality data, combined with 2020 small-area populations and 2024 regional baseline mortality rates."
        ),
        
        shiny::tags$h5(class = "fw-bold text-dark mt-4", "Analytical Periods"),
        shiny::tags$ul(
          shiny::tags$li("Heatwave 1 (HW1): 22–28 May 2026 (7 days)"),
          shiny::tags$li("Heatwave 2 (HW2): 18–28 June 2026 (11 days)"),
          shiny::tags$li("Heatwave 3 (HW3): 6–17 July 2026 (12 days)"),
          shiny::tags$li("Heatwave 4 (HW4): 29 July–5 August 2026 (8 days)"),
          shiny::tags$li("Heatwave 5 (HW5): 11–15 August 2026 (5 days)"),
          shiny::tags$li("Full Study Period: 1 May–30 September 2026 (153 days)")
        ),
        
        shiny::tags$div(
          class = "text-muted small mt-4 pt-2 border-top",
          "Study conducted by the Department of Public Health, Environments and Society, London School of Hygiene & Tropical Medicine (LSHTM)."
        )
      )
    )
  )
}
