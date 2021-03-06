#' Dual Inlet Raw Data
#' @inheritParams fileInfoServer
#' @family dual inlet raw data module functions
diRawDataServer <- function(input, output, session, isofiles, dataset_name, visible = NULL) {

  # namespace
  ns <- session$ns

  # masses and ratios ====

  #FIXME: determine these dynamically
  ratios <-
    tibble::tibble(
      ratio = c("29/28", "30/28", "45/44", "46/44", "32/30", "33/32", "34/32", "36/32", "3/2")
    ) %>%
    dplyr::mutate(
      top = sub("(\\d+)/(\\d+)", "\\1", ratio),
      bot = sub("(\\d+)/(\\d+)", "\\2", ratio)
    )

  # mass and ratio selector
  mass_ratio_selector <- callModule(
    selector_table_server, "selector", id_column = "column", col_headers = c("Data", "Type"),
    hot_mods = function(hot) hot_col(hot, col = c("Data", "Type"), halign = "htCenter"))

  # generate selector list
  observe({
    req(length(isofiles()) > 0)
    masses <- isoreader::iso_get_raw_data(isofiles(), gather = TRUE, quiet = TRUE)$data %>% unique()
    if (length(masses) > 0) {
      ratios <- dplyr::filter(ratios, top %in% masses, bot %in% masses)$ratio
      mass_ratio_selector$set_table(
        bind_rows(
          tibble::tibble(column = masses, type = "mass"),
          tibble::tibble(column = ratios, type = "ratio")
        ))
    }
  })

  # functions
  get_ratios <- reactive({
    mass_ratio_selector$get_selected() %>% { .[. %in% ratios$ratio] }
  })

  # show mass/ratio selector list box
  observe({
    if (is.function(visible)) {
      toggle("selector_box", condition = visible() & length(isofiles()) > 0 )
      toggle("settings_box", condition = visible() & length(isofiles()) > 0 )
      toggle("plot_div", condition = visible() & length(isofiles()) > 0 )
    } else {
      toggle("selector_box", condition = length(isofiles()) > 0)
      toggle("settings_box", condition = length(isofiles()) > 0)
      toggle("plot_div", condition = length(isofiles()) > 0 )
    }
  })

  # visibility of plot buttons  ====
  observe({
    toggle("plot_actions", condition =
             length(isofiles()) > 0 & length(mass_ratio_selector$get_selected()) > 0)
    toggle("plot_messages", condition =
             length(isofiles()) == 0 | length(mass_ratio_selector$get_selected()) == 0)
  })

  # plot messages
  output$plot_message <- renderText({
    validate(
      need(length(isofiles()) > 0, "Please select a dataset and at least one data file.") %then%
        need(length(mass_ratio_selector$get_selected()) > 0, "Please select at least one mass or ratio.")
    )
  })

  # generate  plot ====
  get_plot_params <- reactive({
    c(
      panel = input$panel_by,
      color = input$color_by,
      linetype = input$linetype_by,
      shape = input$shape_by
    )
  })

  refresh_plot <- reactive({
    # all plot referesh triggers
    input$render_plot
    input$selector_refresh
    input$settings_refresh
  })

  generate_plot <- reactive({

    # update triggers
    dataset_name()
    refresh_plot()

    # rest is isolated
    isolate({
      req(length(isofiles()) > 0)
      req(length(mass_ratio_selector$get_selected()) > 0)
      module_message(ns, "debug", "rendering dual inlet raw data plot")

      # prep data
      plot_isofiles <- isofiles()
      if (input$scale_signal != "<NONE>") {
        plot_isofiles <- iso_convert_signals(plot_isofiles, to = input$scale_signal)
      }
      if (length(get_ratios()) > 0) {
        plot_isofiles <- iso_calculate_ratios(plot_isofiles, get_ratios())
      }

      # plot data
      args <-
        c(list(iso_files = plot_isofiles, data = mass_ratio_selector$get_selected()),
          as.list(get_plot_params()) %>%
            sapply(function(x) if (x=="NULL") NULL else sym(x)))

      p <- do.call(iso_plot_dual_inlet_data, args = args) +
        theme(text = element_text(size = 18))

      # legend position
      if (input$legend_position == "bottom") {
        p <- p + theme(legend.position = "bottom", legend.direction="vertical")
      } else if (input$legend_position == "hide") {
        p <- p + theme(legend.position = "none")
      }

      return(p)
    })
  })

  output$plot <- renderPlot(
    generate_plot(),
    height = reactive({ refresh_plot(); isolate(input$plot_height) }))

  # plot download ====
  download_handler <- callModule(
    plotDownloadServer, "plot_download",
    plot_func = generate_plot,
    filename_func = reactive({ stringr::str_c(dataset_name(), ".pdf") }))

  # code update ====
  code_update <- reactive({

    theme_extra <-
      if (input$legend_position == "bottom") 'legend.position = "bottom", legend.direction = "vertical"'
      else if (input$legend_position == "hide") 'legend.position = "none"'
      else NULL

    function(rmarkdown = TRUE) {
      code(
        generate_di_processing_code(
          scale_signal = input$scale_signal,
          ratios = get_ratios(),
          rmarkdown = rmarkdown
        ),
        generate_plot_code(
          data = mass_ratio_selector$get_selected(),
          plot_params = get_plot_params() %>% { setNames(sprintf("%s",.), names(.))  },
          theme1 = "text = element_text(size = 18)",
          theme2 = theme_extra,
          rmarkdown = rmarkdown
        )
      )
    }
  })

  # return functions
  list(
    get_code_update = code_update
  )
}


#' Dual Inlet Raw Data Plot UI
#' @inheritParams isofilesLoadUI
#' @family dual inlet raw data module functions
diRawDataPlotUI <- function(id) {
  ns <- NS(id)
  div(style = "min-height: 500px;",
      div(id = ns("plot_messages"),
          textOutput(ns("plot_message"))),
      div(align = "right", id = ns("plot_actions"),
          tooltipInput(actionButton, ns("render_plot"), "Plot", icon = icon("refresh"),
                       tooltip = "Refresh the plot with the selected files and parameters."),
          spaces(1),
          plotDownloadLink(ns("plot_download"))
      ) %>% hidden(),
      div(id = ns("plot_div"),
          plotOutput(ns("plot"), height = "100%") %>%
            withSpinner(type = 5, proxy.height = "450px")
      )
  )
}


#' Dual Inlet Raw Data Selector UI
#' @inheritParams isofilesLoadUI
#' @param width box width
#' @family dual inlet raw data module functions
diRawDataSelectorUI <- function(id, width = 4, selector_height = "200px") {
  ns <- NS(id)

  # scaling options
  scaling_options <- c("use original" = "<NONE>", "mV" = "mV", "V" = "V",
                       "pA" = "pA", "nA" = "nA", "µA" = "µA", "mA" = "mA")

  div(id = ns("selector_box"),
      default_box(
        title = "Masses and Ratios", width = width,
        fluidRow(
          h4("Scale signals:") %>% column(width = 4),
          selectInput(ns("scale_signal"), NULL, choices = scaling_options) %>% column(width = 8)),
        selector_table_ui(ns("selector"), height = selector_height),
        footer = div(
          #style = "height: 35px;",
          selector_table_buttons_ui(ns("selector")),
          spaces(1),
          tooltipInput(actionButton, ns("selector_refresh"), label = "Plot", icon = icon("refresh"),
                       tooltip = "Refresh plot with new scale, mass and ratio selections."))
      )
  )%>% hidden()
}


#' Dual Inlet Raw Data Settings UI
#' @inheritParams isofilesLoadUI
#' @param width box width
#' @family dual inlet raw data module functions
diRawDataSettingsUI <- function(id, width = 4) {
  ns <- NS(id)

  # options for aesthetics
  aes_options <- c("None" = "NULL", "Masses & Ratios" = "data",
                   "Files" = "file_id", "Standard/Sample" = "type")

  div(id = ns("settings_box"),
      default_box(
        title = "Plot Settings", width = width,
        fluidRow(
          h4("Plot height:") %>% column(width = 4),
          numericInput(ns("plot_height"), NULL, value = 500, min = 100, step = 50) %>% column(width = 8)),
        fluidRow(
          h4("Panel by:") %>% column(width = 4),
          selectInput(ns("panel_by"), NULL, choices = aes_options, selected = "data") %>% column(width = 8)),
        fluidRow(
          h4("Color by:") %>% column(width = 4),
          selectInput(ns("color_by"), NULL, choices = aes_options, selected = "file_id") %>% column(width = 8)
        ),
        fluidRow(
          h4("Linetype by:") %>% column(width = 4),
          selectInput(ns("linetype_by"), NULL, choices = aes_options, selected = "NULL") %>% column(width = 8)
        ),
        fluidRow(
          h4("Shape by:") %>% column(width = 4),
          selectInput(ns("shape_by"), NULL, choices = aes_options, selected = "type") %>% column(width = 8)
        ),
        fluidRow(
          h4("Legend:") %>% column(width = 4),
          selectInput(ns("legend_position"), NULL, choices = c("right", "bottom", "hide"), selected = "right") %>% column(width = 8)
        ),
        footer = tooltipInput(actionButton, ns("settings_refresh"), label = "Plot", icon = icon("refresh"),
                              tooltip = "Refresh plot with new plot settings.")
      )
  )%>% hidden()
}
