# R/mod_plots.R ----
# Synchronized Interactive Plotly Visualizations Module for UKHW2026-app.

# 1. Module UI ----

mod_plots_ui <- function(id) {
  ns <- shiny::NS(id)
  
  bslib::navset_card_pill(
    title = NULL,
    
    # Sub-Tab 1: Daily Time Series & Temperature ----
    bslib::nav_panel(
      title = "Daily Time Series",
      icon = shiny::icon("chart-line"),
      shiny::tags$div(
        class = "pt-2",
        shiny::tags$div(
          class = "d-flex justify-content-between align-items-center mb-2 px-1 text-muted small",
          shiny::tags$span(
            shiny::icon("circle-info", class = "me-1 text-danger"),
            "Daily excess deaths (red bars) and ERA5 mean temperature (°C, orange line). Shaded bands denote the 5 heatwaves."
          ),
          shiny::uiOutput(ns("ts_zoom_badge"), inline = TRUE)
        ),
        plotly::plotlyOutput(ns("plot_timeseries"), height = "440px")
      )
    ),
    
    # Sub-Tab 2: Regional Ranking ----
    bslib::nav_panel(
      title = "Regional Comparison",
      icon = shiny::icon("ranking-star"),
      shiny::tags$div(
        class = "pt-2",
        shiny::tags$div(
          class = "d-flex justify-content-between align-items-center mb-2 px-1 text-muted small",
          shiny::tags$span(
            shiny::icon("circle-info", class = "me-1 text-danger"),
            "Regional distribution with 95% empirical confidence intervals (eCIs). Active map selection is highlighted."
          ),
          shiny::uiOutput(ns("rgn_highlight_badge"), inline = TRUE)
        ),
        plotly::plotlyOutput(ns("plot_regional"), height = "440px")
      )
    ),
    
    # Sub-Tab 3: Demographic Gradient ----
    bslib::nav_panel(
      title = "Age Gradient",
      icon = shiny::icon("users-rectangle"),
      shiny::tags$div(
        class = "pt-2",
        shiny::tags$div(
          class = "mb-2 px-1 text-muted small",
          shiny::icon("circle-info", class = "me-1 text-danger"),
          "Mortality burden across age groups showing the steep exponential increase in older adults."
        ),
        plotly::plotlyOutput(ns("plot_age_gradient"), height = "440px")
      )
    )
  )
}

# 2. Module Server ----

mod_plots_server <- function(id, state) {
  shiny::moduleServer(id, function(input, output, session) {
    
    # Load required data assets
    daily_dt <- as.data.table(arrow::read_parquet("app_data/daily_series.parquet"))
    summary_dt <- as.data.table(arrow::read_parquet("app_data/summary_estimates.parquet"))
    
    # Heatwave date windows
    hw_windows <- list(
      hw1 = c("2026-05-22", "2026-05-28"),
      hw2 = c("2026-06-18", "2026-06-28"),
      hw3 = c("2026-07-06", "2026-07-17"),
      hw4 = c("2026-07-29", "2026-08-05"),
      hw5 = c("2026-08-11", "2026-08-15")
    )
    
    ## 2.1 Daily Time Series Plot ----
    output$plot_timeseries <- plotly::renderPlotly({
      req(state$age_group, state$period)
      
      # Filter daily data by age group (supporting 75+ combined)
      d <- if (state$age_group == "age75plus") {
        daily_dt[agegr %in% c("age7584", "age85plus"), .(
          estimate   = sum(estimate),
          lower      = sum(lower),
          upper      = sum(upper),
          meantemp   = mean(meantemp),
          population = sum(population)
        ), by = .(date, hw_event)]
      } else {
        target_age <- if (state$age_group %in% c("all", "age064", "age6574", "age7584", "age85plus")) state$age_group else "all"
        daily_dt[agegr == target_age]
      }
      
      # Configure vertical shaded rectangles for heatwave periods
      shapes <- lapply(names(hw_windows), function(hw) {
        b <- hw_windows[[hw]]
        is_active <- (state$period == hw)
        list(
          type = "rect",
          fillcolor = if (is_active) "rgba(179, 0, 0, 0.22)" else "rgba(220, 38, 38, 0.08)",
          line = list(
            color = if (is_active) "#b30000" else "transparent",
            width = if (is_active) 1.5 else 0,
            dash = "dot"
          ),
          x0 = b[1],
          x1 = b[2],
          xref = "x",
          y0 = 0,
          y1 = 1,
          yref = "paper"
        )
      })
      
      # Determine x-axis zoom range based on selected period
      x_range <- if (state$period %in% names(hw_windows)) {
        b <- hw_windows[[state$period]]
        c(as.character(as.IDate(b[1]) - 3), as.character(as.IDate(b[2]) + 3))
      } else {
        c("2026-05-01", "2026-09-30")
      }
      
      p <- plotly::plot_ly(data = d, x = ~as.Date(date)) %>%
        plotly::add_bars(
          y = ~estimate,
          name = "Excess Deaths",
          marker = list(color = "#b30000", opacity = 0.85),
          hoverinfo = "text",
          text = ~sprintf(
            "<b>%s</b><br>Excess Deaths: <b>%s</b> [95%% eCI: %s – %s]<br>Mean Temp: <b>%.1f °C</b>",
            format(as.Date(date), "%d %B %Y"),
            formatC(round(estimate), format = "d", big.mark = ","),
            formatC(round(lower), format = "d", big.mark = ","),
            formatC(round(upper), format = "d", big.mark = ","),
            meantemp
          ),
          yaxis = "y"
        ) %>%
        plotly::add_lines(
          y = ~meantemp,
          name = "Mean Temp (°C)",
          line = list(color = "#d97706", width = 2),
          hoverinfo = "skip",
          yaxis = "y2"
        ) %>%
        plotly::layout(
          shapes = shapes,
          xaxis = list(
            title = "",
            range = x_range,
            showgrid = FALSE
          ),
          yaxis = list(
            title = "Daily Excess Deaths",
            zeroline = TRUE,
            zerolinecolor = "#cbd5e1"
          ),
          yaxis2 = list(
            title = "Mean Temperature (°C)",
            overlaying = "y",
            side = "right",
            showgrid = FALSE
          ),
          legend = list(
            orientation = "h",
            x = 0.5,
            xanchor = "center",
            y = 1.12
          ),
          margin = list(t = 30, r = 50, b = 40, l = 50)
        )
      
      plotly::config(p, displayModeBar = FALSE)
    })
    
    output$ts_zoom_badge <- shiny::renderUI({
      if (state$period == "study_period") {
        shiny::tags$span(class = "badge bg-light text-dark border", "Full Season View")
      } else {
        shiny::tags$span(class = "badge bg-danger-subtle text-danger border border-danger-subtle", paste("Zoomed to", toupper(state$period)))
      }
    })
    
    ## 2.2 Regional Ranking Plot ----
    output$plot_regional <- plotly::renderPlotly({
      req(state$period, state$metric)
      
      # Use all-ages or active age group
      target_age <- if (state$age_group %in% unique(summary_dt$agegr)) state$age_group else "all"
      
      d <- summary_dt[geo_level == "region" & period == state$period & agegr == target_age]
      if (nrow(d) == 0) return(NULL)
      
      # Sort regions by chosen metric
      if (state$metric == "rate") {
        setorder(d, rate)
        x_val   <- d$rate
        arr_max <- d$ratehigh - d$rate
        arr_min <- d$rate - d$ratelow
        x_title <- "Excess Deaths per Million Population"
      } else {
        setorder(d, estimate)
        x_val   <- d$estimate
        arr_max <- d$upper - d$estimate
        arr_min <- d$estimate - d$lower
        x_title <- "Total Excess Deaths (Count)"
      }
      
      d[, rgn_factor := factor(rgn11nm, levels = rgn11nm)]
      
      # Highlight active region from map click
      sel_rgn <- state$selected_region
      d[, bar_color := if (sel_rgn == "All") "#b30000" else ifelse(rgn11cd == sel_rgn, "#b30000", "#cbd5e1")]
      
      p <- plotly::plot_ly(
        data = d,
        y = ~rgn_factor,
        x = x_val,
        type = "bar",
        orientation = "h",
        marker = list(color = ~bar_color),
        error_x = list(
          type = "data",
          symmetric = FALSE,
          array = arr_max,
          arrayminus = arr_min,
          color = "#475569",
          thickness = 1.2
        ),
        hoverinfo = "text",
        text = ~sprintf(
          "<b>%s</b><br>Rate: <b>%.1f</b> [95%% eCI: %.1f – %.1f]<br>Deaths: <b>%s</b> [95%% eCI: %s – %s]",
          rgn11nm, rate, ratelow, ratehigh,
          formatC(round(estimate), format = "d", big.mark = ","),
          formatC(round(lower), format = "d", big.mark = ","),
          formatC(round(upper), format = "d", big.mark = ",")
        )
      ) %>%
        plotly::layout(
          xaxis = list(title = x_title),
          yaxis = list(title = ""),
          margin = list(l = 150, r = 20, t = 10, b = 40)
        )
      
      plotly::config(p, displayModeBar = FALSE)
    })
    
    output$rgn_highlight_badge <- shiny::renderUI({
      if (state$selected_region != "All") {
        shiny::tags$span(class = "badge bg-danger-subtle text-danger border border-danger-subtle", paste("Highlighted:", state$selected_region_name))
      } else {
        shiny::tags$span(class = "badge bg-light text-dark border", "All 10 Regions")
      }
    })
    
    ## 2.3 Demographic Gradient Plot ----
    output$plot_age_gradient <- plotly::renderPlotly({
      req(state$period, state$metric)
      
      # Filter to 4 primary age groups for active geographic scope
      d_scope <- if (state$selected_region == "All") {
        summary_dt[geo_level == "national" & period == state$period & agegr %in% c("age064", "age6574", "age7584", "age85plus")]
      } else {
        summary_dt[geo_level == "region" & rgn11cd == state$selected_region & period == state$period & agegr %in% c("age064", "age6574", "age7584", "age85plus")]
      }
      
      if (nrow(d_scope) == 0) return(NULL)
      
      # Ensure canonical age ordering
      d_scope[, age_order := factor(age, levels = c("0-64", "65-74", "75-84", "85 and above"))]
      setorder(d_scope, age_order)
      
      if (state$metric == "rate") {
        y_val   <- d_scope$rate
        arr_max <- d_scope$ratehigh - d_scope$rate
        arr_min <- d_scope$rate - d_scope$ratelow
        y_title <- "Excess Deaths per Million"
      } else {
        y_val   <- d_scope$estimate
        arr_max <- d_scope$upper - d_scope$estimate
        arr_min <- d_scope$estimate - d_scope$lower
        y_title <- "Excess Deaths (Count)"
      }
      
      # Gradient colors by age severity
      age_colors <- c("#fca5a5", "#f87171", "#ef4444", "#b30000")
      
      p <- plotly::plot_ly(
        data = d_scope,
        x = ~age_order,
        y = y_val,
        type = "bar",
        marker = list(color = age_colors),
        error_y = list(
          type = "data",
          symmetric = FALSE,
          array = arr_max,
          arrayminus = arr_min,
          color = "#334155",
          thickness = 1.2
        ),
        hoverinfo = "text",
        text = ~sprintf(
          "<b>Age %s</b> (%s)<br>Rate: <b>%.1f</b> [95%% eCI: %.1f – %.1f]<br>Deaths: <b>%s</b> [95%% eCI: %s – %s]",
          age, if (state$selected_region == "All") "National" else state$selected_region_name,
          rate, ratelow, ratehigh,
          formatC(round(estimate), format = "d", big.mark = ","),
          formatC(round(lower), format = "d", big.mark = ","),
          formatC(round(upper), format = "d", big.mark = ",")
        )
      ) %>%
        plotly::layout(
          xaxis = list(title = "Age Group"),
          yaxis = list(title = y_title),
          margin = list(t = 20, r = 20, b = 40, l = 60)
        )
      
      plotly::config(p, displayModeBar = FALSE)
    })
    
  })
}
