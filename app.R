# app.R ----
# UK Heatwave 2026 Mortality Shiny Application
# Fast, modern bslib dashboard exploring 2026 England & Wales heat-related excess mortality.

# 1. Setup and Initialization ----

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(arrow)
  library(data.table)
  library(sf)
  library(mapgl)
  library(plotly)
  library(reactable)
  library(htmltools)
})

# Source modular components and helpers
source("R/utils_ui.R")
source("R/mod_map.R")
source("R/mod_plots.R")
source("R/mod_tables.R")

# Load pre-aggregated summary estimates into memory
summary_dt <- as.data.table(arrow::read_parquet("app_data/summary_estimates.parquet"))

# 2. User Interface Definition ----

ui <- bslib::page_sidebar(
  theme = app_theme,
  title = shiny::tagList(
    shiny::tags$span(class = "app-header-title", "UK Heatwave 2026"),
    shiny::tags$span(class = "text-muted fs-6 fw-normal ms-2 d-none d-md-inline", "| Excess Mortality Explorer"),
    shiny::tags$span(class = "badge bg-danger-subtle text-danger ms-2 border border-danger-subtle small", "Modelled Estimates")
  ),
  
  # Inject custom stylesheet
  shiny::tags$head(
    shiny::tags$link(rel = "stylesheet", type = "text/css", href = "styles.css")
  ),
  
  # Sidebar Controls ----
  sidebar = bslib::sidebar(
    width = 320,
    open = "desktop",
    title = shiny::tagList(
      shiny::icon("sliders", class = "text-danger me-2"),
      "Analysis Controls"
    ),
    
    shiny::selectInput(
      "period",
      label = "Analytical Period",
      choices = c(
        "Full Season (1 May–30 Sep)" = "study_period",
        "HW1: 22–28 May"            = "hw1",
        "HW2: 18–28 June"           = "hw2",
        "HW3: 6–17 July"            = "hw3",
        "HW4: 29 July–5 August"     = "hw4",
        "HW5: 11–15 August"         = "hw5"
      ),
      selected = "study_period"
    ),
    
    shiny::radioButtons(
      "metric",
      label = "Display Metric",
      choices = c(
        "Excess Deaths per Million (Rate)" = "rate",
        "Excess Deaths (Count)"           = "estimate"
      ),
      selected = "rate"
    ),
    
    shiny::radioButtons(
      "geo_level",
      label = "Map Geography Level",
      choices = c(
        "Region (10)"                   = "region",
        "Local Authority (348)"         = "lad",
        "Small Area / LSOA (34,753)"    = "lsoa"
      ),
      selected = "region"
    ),
    
    shiny::selectInput(
      "age_group",
      label = "Age Breakdown",
      choices = c(
        "All Ages"                     = "all",
        "75+ Combined (High Risk)"     = "age75plus",
        "0–64"                         = "age064",
        "65–74"                        = "age6574",
        "75–84"                        = "age7584",
        "85 and above"                 = "age85plus"
      ),
      selected = "all"
    ),
    
    shiny::tags$hr(class = "my-2 text-muted"),
    
    # Active Region Filter Status and Reset Button
    shiny::tags$div(
      class = "mb-2",
      shiny::tags$label(class = "form-label small text-muted text-uppercase fw-bold", "Geographic Filter:"),
      shiny::uiOutput("ui_region_badge")
    ),
    
    shiny::actionButton(
      "btn_reset_region",
      "Reset Region Filter",
      class = "btn-sm btn-outline-secondary w-100 mb-2",
      icon = shiny::icon("rotate-left")
    ),
    
    shiny::actionButton(
      "btn_about",
      "About Study & Methods",
      class = "btn-sm btn-outline-danger w-100",
      icon = shiny::icon("circle-info")
    )
  ),
  
  # Main Content ----
  
  ## Top Row: Reactive Metric Value Boxes ----
  bslib::layout_columns(
    col_widths = c(4, 4, 4),
    
    bslib::value_box(
      title = "Total Excess Deaths",
      value = shiny::textOutput("vb_excess_deaths"),
      showcase = shiny::icon("bed-pulse", class = "text-danger"),
      theme = "white",
      shiny::tags$p(class = "text-muted small mb-0", shiny::textOutput("vb_excess_deaths_ci"))
    ),
    
    bslib::value_box(
      title = "Excess Rate per Million",
      value = shiny::textOutput("vb_excess_rate"),
      showcase = shiny::icon("chart-line", class = "text-danger"),
      theme = "white",
      shiny::tags$p(class = "text-muted small mb-0", shiny::textOutput("vb_excess_rate_ci"))
    ),
    
    bslib::value_box(
      title = "Share in 75+ Age Group",
      value = shiny::textOutput("vb_elderly_share"),
      showcase = shiny::icon("users-line", class = "text-danger"),
      theme = "white",
      shiny::tags$p(class = "text-muted small mb-0", shiny::textOutput("vb_elderly_counts"))
    )
  ),
  
  ## Center Grid: Map & Interactive Visualisation Tabs ----
  bslib::layout_columns(
    col_widths = c(7, 5),
    
    # Left Column: Map Card
    mod_map_ui("map"),
    
    # Right Column: Tabbed Visualisations & Tables
    bslib::navset_card_underline(
      title = shiny::tagList(
        shiny::icon("chart-simple", class = "text-danger me-1"),
        "Impact Breakdown"
      ),
      bslib::nav_panel(
        title = "Visualisations",
        icon = shiny::icon("chart-area"),
        mod_plots_ui("plots")
      ),
      bslib::nav_panel(
        title = "Data Table",
        icon = shiny::icon("table"),
        mod_tables_ui("tables")
      )
    )
  )
)

# 3. Server Logic ----

server <- function(input, output, session) {
  
  ## Initialize Shared Reactive State ----
  state <- shiny::reactiveValues(
    period               = "study_period",
    metric               = "rate",
    geo_level            = "region",
    age_group            = "all",
    selected_region      = "All",
    selected_region_name = "England & Wales"
  )
  
  ## Synchronize Sidebar Inputs with Shared State ----
  shiny::observe({
    state$period    <- input$period
    state$metric    <- input$metric
    state$geo_level <- input$geo_level
    state$age_group <- input$age_group
  })
  
  ## Reset Region Filter Observer ----
  shiny::observeEvent(input$btn_reset_region, {
    state$selected_region      <- "All"
    state$selected_region_name <- "England & Wales"
  })
  
  ## About & Methods Modal Dialog ----
  shiny::observeEvent(input$btn_about, {
    show_about_modal()
  })
  
  ## Active Region Badge UI ----
  output$ui_region_badge <- shiny::renderUI({
    if (state$selected_region == "All") {
      shiny::tags$div(
        class = "badge bg-light text-dark border p-2 w-100 text-start",
        shiny::icon("globe", class = "text-muted me-1"),
        "National (England & Wales)"
      )
    } else {
      shiny::tags$div(
        class = "region-badge-active d-flex justify-content-between align-items-center",
        shiny::tags$span(
          shiny::icon("location-dot", class = "me-1"),
          state$selected_region_name
        ),
        shiny::tags$span(class = "badge bg-danger text-white ms-2", "Filtered")
      )
    }
  })
  
  ## Reactive Value Box Calculations ----
  active_summary_dt <- shiny::reactive({
    p <- state$period
    r <- state$selected_region
    
    if (r == "All") {
      summary_dt[geo_level == "national" & period == p]
    } else {
      summary_dt[geo_level == "region" & rgn11cd == r & period == p]
    }
  })
  
  # Value Box 1: Total Excess Deaths
  output$vb_excess_deaths <- shiny::renderText({
    d <- active_summary_dt()[agegr == state$age_group]
    if (nrow(d) == 0) return("—")
    fmt_int(d$estimate)
  })
  
  output$vb_excess_deaths_ci <- shiny::renderText({
    d <- active_summary_dt()[agegr == state$age_group]
    if (nrow(d) == 0) return("—")
    paste0("95% eCI: [", fmt_int(d$lower), " – ", fmt_int(d$upper), "]")
  })
  
  # Value Box 2: Excess Rate per Million
  output$vb_excess_rate <- shiny::renderText({
    d <- active_summary_dt()[agegr == state$age_group]
    if (nrow(d) == 0) return("—")
    fmt_rate(d$rate, 1)
  })
  
  output$vb_excess_rate_ci <- shiny::renderText({
    d <- active_summary_dt()[agegr == state$age_group]
    if (nrow(d) == 0) return("—")
    paste0("95% eCI: [", fmt_rate(d$ratelow, 1), " – ", fmt_rate(d$ratehigh, 1), "]")
  })
  
  # Value Box 3: Share in 75+ Age Group
  output$vb_elderly_share <- shiny::renderText({
    dt_scope <- active_summary_dt()
    d_all <- dt_scope[agegr == "all"]
    d_75p <- dt_scope[agegr == "age75plus"]
    
    if (nrow(d_all) == 0 || nrow(d_75p) == 0 || d_all$estimate == 0) return("—")
    share <- (d_75p$estimate / d_all$estimate) * 100
    paste0(fmt_rate(share, 1), "%")
  })
  
  output$vb_elderly_counts <- shiny::renderText({
    dt_scope <- active_summary_dt()
    d_all <- dt_scope[agegr == "all"]
    d_75p <- dt_scope[agegr == "age75plus"]
    
    if (nrow(d_all) == 0 || nrow(d_75p) == 0) return("—")
    paste0(fmt_int(d_75p$estimate), " of ", fmt_int(d_all$estimate), " total deaths")
  })
  
  ## Module Server Instantiation ----
  mod_map_server("map", state)
  mod_plots_server("plots", state)
  mod_tables_server("tables", state)
}

# 4. App Execution ----
shiny::shinyApp(ui = ui, server = server)
