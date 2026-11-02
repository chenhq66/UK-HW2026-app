# R/mod_tables.R ----
# Interactive Filterable Data Tables Module (reactable / htmltools) for UKHW2026-app.

# 1. Module UI ----

mod_tables_ui <- function(id) {
  ns <- shiny::NS(id)
  
  shiny::tags$div(
    class = "p-2",
    
    # Table Toolbar: Filters Sync Toggle & Download Button ----
    shiny::tags$div(
      class = "d-flex justify-content-between align-items-center mb-3 pb-2 border-bottom",
      shiny::tags$div(
        class = "d-flex align-items-center gap-3",
        shiny::checkboxInput(
          ns("chk_sync_filters"),
          label = "Sync table with sidebar period & geography filters",
          value = TRUE
        ),
        shiny::uiOutput(ns("ui_filter_count_badge"), inline = TRUE)
      ),
      shiny::downloadButton(
        ns("btn_download_csv"),
        "Export CSV",
        class = "btn-sm btn-outline-danger",
        icon = shiny::icon("download")
      )
    ),
    
    # Responsive Reactable Table ----
    reactable::reactableOutput(ns("summary_table")),
    
    # Methodology Footnote ----
    shiny::tags$div(
      class = "text-muted small mt-2 pt-2 border-top",
      shiny::icon("circle-info", class = "me-1 text-danger"),
      "Figures are modelled excess deaths and 95% empirical confidence intervals (eCIs) derived from 500 Monte Carlo draws. Columns sort numerically by point estimate."
    )
  )
}

# 2. Module Server ----

mod_tables_server <- function(id, state) {
  shiny::moduleServer(id, function(input, output, session) {
    
    # Load summary dataset
    summary_dt <- as.data.table(arrow::read_parquet("app_data/summary_estimates.parquet"))
    
    ## 2.1 Reactive Filtered Dataset ----
    table_data <- shiny::reactive({
      d <- copy(summary_dt)
      
      # If sync toggle is enabled, apply active sidebar filters
      if (isTRUE(input$chk_sync_filters)) {
        if (!is.null(state$period)) {
          d <- d[period == state$period]
        }
        
        if (state$selected_region != "All") {
          d <- d[geo_level == "region" & rgn11cd == state$selected_region]
        }
      }
      
      d
    })
    
    ## 2.2 Record Count Badge ----
    output$ui_filter_count_badge <- shiny::renderUI({
      n <- nrow(table_data())
      shiny::tags$span(class = "badge bg-light text-secondary border", paste(n, "records"))
    })
    
    ## 2.3 Reactable Table Rendering ----
    output$summary_table <- reactable::renderReactable({
      d <- table_data()
      req(nrow(d) > 0)
      
      max_est  <- max(d$estimate, na.rm = TRUE)
      max_rate <- max(d$rate, na.rm = TRUE)
      if (!is.finite(max_est) || max_est <= 0) max_est <- 1
      if (!is.finite(max_rate) || max_rate <= 0) max_rate <- 1
      
      reactable::reactable(
        data = d[, .(geo_level, rgn11nm, period_label, age, population, estimate, lower, upper, rate, ratelow, ratehigh)],
        searchable = TRUE,
        sortable   = TRUE,
        striped    = TRUE,
        highlight  = TRUE,
        compact    = TRUE,
        defaultPageSize = 10,
        showPageSizeOptions = TRUE,
        pageSizeOptions = c(10, 20, 50, 100),
        defaultSorted = list(rate = "desc"),
        
        theme = reactable::reactableTheme(
          borderColor = "#e2e8f0",
          stripedColor = "#f8fafc",
          highlightColor = "#fef2f2",
          headerStyle = list(
            backgroundColor = "#f1f5f9",
            fontWeight = 600,
            fontSize = "12px",
            textTransform = "uppercase",
            letterSpacing = "0.03em"
          )
        ),
        
        columns = list(
          # Scope Badge
          geo_level = reactable::colDef(
            name = "Scope",
            width = 85,
            cell = function(value) {
              if (value == "national") {
                htmltools::span(class = "badge bg-dark", "National")
              } else {
                htmltools::span(class = "badge bg-secondary", "Region")
              }
            }
          ),
          
          # Geography Name
          rgn11nm = reactable::colDef(
            name = "Geography",
            minWidth = 140,
            style = list(fontWeight = 500)
          ),
          
          # Period
          period_label = reactable::colDef(
            name = "Period",
            minWidth = 135
          ),
          
          # Age Group
          age = reactable::colDef(
            name = "Age Group",
            minWidth = 95
          ),
          
          # Population
          population = reactable::colDef(
            name = "Population",
            minWidth = 105,
            format = reactable::colFormat(separators = TRUE)
          ),
          
          # Excess Deaths with Inline Background Bar
          estimate = reactable::colDef(
            name = "Excess Deaths (95% eCI)",
            minWidth = 185,
            cell = function(value, index) {
              row <- d[index]
              txt <- sprintf(
                "%s (%s – %s)",
                formatC(round(row$estimate), format = "d", big.mark = ","),
                formatC(round(row$lower), format = "d", big.mark = ","),
                formatC(round(row$upper), format = "d", big.mark = ",")
              )
              pct <- sprintf("%.1f%%", min(100, max(0, (value / max_est) * 100)))
              
              htmltools::div(
                style = "position: relative; width: 100%; display: flex; align-items: center;",
                htmltools::div(
                  style = sprintf("position: absolute; left: 0; top: 2px; bottom: 2px; width: %s; background-color: #b30000; opacity: 0.18; border-radius: 3px;", pct)
                ),
                htmltools::span(
                  style = "position: relative; z-index: 2; padding-left: 4px; font-variant-numeric: tabular-nums; font-size: 12px;",
                  txt
                )
              )
            }
          ),
          
          # Rate per Million with Inline Background Bar
          rate = reactable::colDef(
            name = "Rate / Million (95% eCI)",
            minWidth = 185,
            cell = function(value, index) {
              row <- d[index]
              txt <- sprintf("%.1f (%.1f – %.1f)", row$rate, row$ratelow, row$ratehigh)
              pct <- sprintf("%.1f%%", min(100, max(0, (value / max_rate) * 100)))
              
              htmltools::div(
                style = "position: relative; width: 100%; display: flex; align-items: center;",
                htmltools::div(
                  style = sprintf("position: absolute; left: 0; top: 2px; bottom: 2px; width: %s; background-color: #dc2626; opacity: 0.18; border-radius: 3px;", pct)
                ),
                htmltools::span(
                  style = "position: relative; z-index: 2; padding-left: 4px; font-variant-numeric: tabular-nums; font-size: 12px;",
                  txt
                )
              )
            }
          ),
          
          # Hidden raw interval columns (used for rendering cells)
          lower    = reactable::colDef(show = FALSE),
          upper    = reactable::colDef(show = FALSE),
          ratelow  = reactable::colDef(show = FALSE),
          ratehigh = reactable::colDef(show = FALSE)
        )
      )
    })
    
    ## 2.4 CSV Download Handler ----
    output$btn_download_csv <- shiny::downloadHandler(
      filename = function() {
        paste0("UK_Heatwave_2026_Mortality_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        export_dt <- table_data()[, .(
          geo_level,
          rgn11cd,
          rgn11nm,
          period,
          period_label,
          agegr,
          age,
          population,
          estimate = round(estimate, 2),
          lower = round(lower, 2),
          upper = round(upper, 2),
          rate = round(rate, 2),
          ratelow = round(ratelow, 2),
          ratehigh = round(ratehigh, 2)
        )]
        data.table::fwrite(export_dt, file)
      }
    )
    
  })
}
