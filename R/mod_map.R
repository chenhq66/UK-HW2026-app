# R/mod_map.R ----
# High-Performance WebGL Map Module (mapgl / MapLibre GL JS) for UKHW2026-app.

# 1. Spatial Assets and Helper Functions ----

# Load pre-simplified spatial boundaries into module memory once
geo_region <- readRDS("app_data/geo_region.rds")
geo_lad    <- readRDS("app_data/geo_lad.rds")
geo_lsoa   <- readRDS("app_data/geo_lsoa.rds")

## Color palette and interpolation breaks generator ----
get_map_palette <- function(geo_level, metric, period) {
  stops <- c("#fef0d9", "#fdcc8a", "#fc8d59", "#e34a33", "#b30000")
  
  if (metric == "rate") {
    values <- c(0, 25, 60, 120, 200)
    legend_title <- "Deaths per Million"
  } else {
    legend_title <- "Excess Deaths"
    if (geo_level == "lsoa") {
      values <- if (period == "study_period") c(0, 0.2, 0.6, 1.5, 3.0) else c(0, 0.05, 0.15, 0.4, 1.0)
    } else if (geo_level == "lad") {
      values <- if (period == "study_period") c(0, 5, 15, 30, 60) else c(0, 2, 6, 12, 25)
    } else {
      values <- if (period == "study_period") c(0, 100, 300, 700, 1200) else c(0, 25, 75, 150, 300)
    }
  }
  list(values = values, stops = stops, title = legend_title)
}

## Resolve active column name on spatial sf layers ----
get_active_col <- function(geo_level, metric, period) {
  prefix <- if (metric == "rate") "rate_" else "estimate_"
  if (geo_level == "lsoa") {
    col_suffix <- if (period == "study_period") "total_hw" else period
  } else if (geo_level == "lad") {
    col_suffix <- if (period == "study_period") "study_period" else period
  } else {
    col_suffix <- period
  }
  paste0(prefix, col_suffix)
}

# 2. Module UI ----

mod_map_ui <- function(id) {
  ns <- shiny::NS(id)
  
  bslib::card(
    full_screen = TRUE,
    bslib::card_header(
      class = "d-flex justify-content-between align-items-center py-2 px-3",
      shiny::tags$span(
        class = "fw-semibold text-dark",
        shiny::icon("map-location-dot", class = "text-danger me-2"),
        "Spatial Heat Mortality Distribution"
      ),
      shiny::uiOutput(ns("badge_geo_status"), inline = TRUE)
    ),
    bslib::card_body(
      class = "p-0 position-relative",
      style = "height: 640px; min-height: 520px;",
      
      # WebGL Maplibre container
      mapgl::maplibreOutput(ns("map"), height = "100%", width = "100%"),
      
      # Floating Granularity Guardrail Banner
      shiny::uiOutput(ns("ui_guardrail_banner")),
      
      # Floating Interactive Legend
      shiny::uiOutput(ns("ui_map_legend"))
    ),
    bslib::card_footer(
      class = "py-2 px-3 bg-light text-muted small d-flex justify-content-between align-items-center",
      shiny::uiOutput(ns("ui_click_hint")),
      shiny::tags$span(
        class = "badge bg-white text-secondary border",
        shiny::icon("bolt", class = "text-warning me-1"),
        "WebGL Accelerated (34,753 LSOAs)"
      )
    )
  )
}

# 3. Module Server ----

mod_map_server <- function(id, state) {
  shiny::moduleServer(id, function(input, output, session) {
    
    ## Initial Basemap & Layer Rendering (Executed ONLY ONCE) ----
    output$map <- mapgl::renderMaplibre({
      init_pal  <- get_map_palette("region", "rate", "study_period")
      init_expr <- mapgl::interpolate(
        column = "rate_study_period",
        values = init_pal$values,
        stops  = init_pal$stops,
        na_color = "#cccccc"
      )
      
      mapgl::maplibre(
        style = mapgl::carto_style("positron"),
        bounds = c(-5.8, 50.0, 1.8, 55.8)
      ) |>
        mapgl::add_fill_layer(
          id = "region_layer",
          source = geo_region,
          fill_color = init_expr,
          fill_opacity = 0.78,
          fill_outline_color = "#1e293b",
          visibility = "visible",
          tooltip = "tip_study_period"
        ) |>
        mapgl::add_fill_layer(
          id = "lad_layer",
          source = geo_lad,
          fill_color = init_expr,
          fill_opacity = 0.78,
          fill_outline_color = "#64748b",
          visibility = "none",
          tooltip = "tip_study_period"
        ) |>
        mapgl::add_fill_layer(
          id = "lsoa_layer",
          source = geo_lsoa,
          fill_color = init_expr,
          fill_opacity = 0.82,
          visibility = "none",
          tooltip = "tip_study_period"
        )
    })
    
    ## Zero-Redraw Reactive Proxy Updates ----
    shiny::observe({
      req(state$geo_level, state$period, state$metric)
      
      geo_lvl <- state$geo_level
      period  <- state$period
      metric  <- state$metric
      
      active_layer <- paste0(geo_lvl, "_layer")
      active_col   <- get_active_col(geo_lvl, metric, period)
      active_tip   <- paste0("tip_", period)
      
      pal <- get_map_palette(geo_lvl, metric, period)
      color_expr <- mapgl::interpolate(
        column   = active_col,
        values   = pal$values,
        stops    = pal$stops,
        na_color = "#cccccc"
      )
      
      # Zero-redraw client-side paint property update via MapLibre proxy
      mapgl::maplibre_proxy("map") |>
        mapgl::set_layout_property("region_layer", "visibility", if (geo_lvl == "region") "visible" else "none") |>
        mapgl::set_layout_property("lad_layer", "visibility", if (geo_lvl == "lad") "visible" else "none") |>
        mapgl::set_layout_property("lsoa_layer", "visibility", if (geo_lvl == "lsoa") "visible" else "none") |>
        mapgl::set_paint_property(active_layer, "fill-color", color_expr) |>
        mapgl::set_tooltip(active_layer, active_tip)
    })
    
    ## Feature Click Event Listener (Updates Shared State) ----
    shiny::observeEvent(input$map_feature_click, {
      click <- input$map_feature_click
      props <- click$properties
      
      if (!is.null(props$rgn11cd) && nzchar(props$rgn11cd)) {
        state$selected_region      <- props$rgn11cd
        state$selected_region_name <- props$rgn11nm
      }
    })
    
    ## Header Status Badge ----
    output$badge_geo_status <- shiny::renderUI({
      geo_text <- switch(
        state$geo_level,
        "region" = "Region Level (10)",
        "lad"    = "Local Authority Level (348)",
        "lsoa"   = "Small Area / LSOA (34,753)"
      )
      shiny::tags$span(class = "badge bg-danger-subtle text-danger border border-danger-subtle", geo_text)
    })
    
    ## Granularity Guardrail Floating Banner ----
    output$ui_guardrail_banner <- shiny::renderUI({
      alerts <- list()
      
      # Guardrail 1: Non-all ages selected while in LAD or LSOA view
      if (state$age_group != "all" && state$geo_level %in% c("lad", "lsoa")) {
        alerts[[length(alerts) + 1]] <- shiny::tags$div(
          class = "alert alert-warning py-1 px-3 mb-1 shadow-sm small border d-flex align-items-center",
          style = "background: rgba(254, 243, 199, 0.95); backdrop-filter: blur(4px);",
          shiny::icon("triangle-exclamation", class = "text-warning me-2"),
          shiny::tags$span(
            "Map displays ", shiny::tags$strong("all-age point estimates"), " at LSOA/LAD scale. Regional and national age breakdowns are shown in the charts and tables."
          )
        )
      }
      
      # Guardrail 2: Heatwave period selected while in LAD view
      if (state$geo_level == "lad" && state$period != "study_period") {
        alerts[[length(alerts) + 1]] <- shiny::tags$div(
          class = "alert alert-info py-1 px-3 mb-0 shadow-sm small border d-flex align-items-center",
          style = "background: rgba(224, 242, 254, 0.95); backdrop-filter: blur(4px);",
          shiny::icon("circle-info", class = "text-info me-2"),
          shiny::tags$span(
            "LAD heatwave values are aggregated from small-area estimates; the primary study model provides full-summer totals at LAD scale."
          )
        )
      }
      
      if (length(alerts) == 0) return(NULL)
      
      shiny::tags$div(
        class = "mapgl-guardrail-banner",
        alerts
      )
    })
    
    ## Floating Interactive Legend ----
    output$ui_map_legend <- shiny::renderUI({
      pal <- get_map_palette(state$geo_level, state$metric, state$period)
      
      # Generate CSS gradient bar from palette stops
      grad_stops <- paste(
        sapply(seq_along(pal$stops), function(i) {
          pct <- round((i - 1) / (length(pal$stops) - 1) * 100)
          paste0(pal$stops[i], " ", pct, "%")
        }),
        collapse = ", "
      )
      
      shiny::tags$div(
        class = "mapgl-legend-glass",
        shiny::tags$div(class = "fw-bold small text-dark mb-1", pal$title),
        shiny::tags$div(
          style = sprintf("height: 12px; border-radius: 3px; background: linear-gradient(to right, %s); border: 1px solid rgba(0,0,0,0.1);", grad_stops)
        ),
        shiny::tags$div(
          class = "d-flex justify-content-between text-muted mt-1",
          style = "font-size: 10px; font-weight: 600;",
          shiny::tags$span(pal$values[1]),
          shiny::tags$span(pal$values[3]),
          shiny::tags$span(paste0(pal$values[5], "+"))
        )
      )
    })
    
    ## Footer Click Hint and Status UI ----
    output$ui_click_hint <- shiny::renderUI({
      if (state$selected_region == "All") {
        shiny::tags$span(
          shiny::icon("hand-pointer", class = "me-1 text-danger"),
          "Click any area to filter analysis and charts to its Region."
        )
      } else {
        shiny::tags$span(
          class = "text-danger fw-semibold",
          shiny::icon("location-dot", class = "me-1"),
          paste("Filtering by Region:", state$selected_region_name)
        )
      }
    })
    
  })
}
