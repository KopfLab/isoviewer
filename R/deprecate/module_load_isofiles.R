# Isofiles load module ====

#' Isofiles Load Server
#' @inheritParams fileSelectorServer
#' @param data_dir the directory for local data files
#' @param extensions which extensions to allow
#' @param load_func the loading function (as character!)
#' @param load_params the loading checkboxes (parameter names and labels)
#' @param post_load function to run after loading a file list/creating the dataset is completed
#' @param allow_data_upload whether to allow uploading of data
#' @param allow_folder_creation whether to allow creation of folders on the server
#' @param store_data whether data files (including .rds exports) are stored permanently (TRUE) or just temporarily (FALSE)
#' @family isofiles load module functions
isofilesLoadServer <- function(
  input, output, session, data_dir, extensions,
  load_func, load_params = c(), post_load = NULL,
  allow_data_upload = FALSE, allow_folder_creation = FALSE, store_data = TRUE) {

  # namespace, and top level params
  ns <- session$ns
  root <- if (!isAbsolutePath(data_dir)) filePath(getwd(), data_dir) else  data_dir

  # file patterns
  pattern <-
    sprintf("(%s)", stringr::str_replace_all(extensions, "\\.", "\\\\.")) %>%
    paste(collapse = "|") %>%
    { sprintf("(%s)$", .)}

  # reactive values
  values <- reactiveValues(
    load_list = tibble::tibble(path = character(), path_rel = character(), label = character()),
    load_list_selected = c(),
    loaded_isofiles = NULL,
    loaded_dataset = NULL,
    saved_datasets = c() # vector of saved datasets with rel. paths as names
  )

  # File selector module ====
  root_name <- "Data"
  files_select <- callModule(
    fileSelectorServer, "files", pattern = pattern,
    root = data_dir, root_name = root_name, multiple = TRUE, start_sort_desc = TRUE,
    enable_recent = TRUE, start_recent = FALSE, start_n_recent = 20)

  # Upload module ====
  temp_dir <- tempdir()
  upload_folder <- if (store_data) files_select$path else reactive({ temp_dir })
  if (allow_data_upload) {
    show_folder <- if(store_data) reactive({ file.path(root_name, files_select$path_relative()) }) else NULL
    upload_files <- callModule(dataUploadServer, "upload", folder = upload_folder, show_folder = show_folder,
                               pattern = pattern)
  } else {
    upload_files <- list(last_upload = reactive({ c() }))
  }

  # upload UI
  output$upload_wrap <- renderUI({
    store_data_msg <-
      if (store_data) {
        "Upload data to the following folder. These data will be visible to everybody else with access to this server."
      } else {
        "Add data files from your local hard drive to the load list. Uploaded files will only be stored temporarily and are not available to anybody else."
      }
    store_data_msg <- stringr::str_c(store_data_msg,
                            " Uploaded zip archives (.zip) are automatically extracted.",
                            " Only appropriate file types (", stringr::str_c(extensions, collapse = ", "), ") are used. All files are added to the load list.")
    if (allow_data_upload) {
      dataUploadUI(ns("upload"),
                   dialog_text = store_data_msg,
                   accept = c("application/octet-stream", stringr::str_c(".", extensions), "application/zip", ".zip"))
    } else NULL
  })

  # Folder creation ===
  output$folder_creation_wrap <- renderUI({
    if (allow_folder_creation) {
      tooltipInput(actionButton, ns("create_folder_dialog"), "Create folder", icon = icon("folder"),
                   tooltip = "Create a sub directory in the current folder.")
    } else NULL
  })

  # the modal dialog
  folder_modal <- reactive({
    show_folder <- file.path(root_name, files_select$path_relative())
    modalDialog(
      title = "Create folder",
      "Create a new subdirectory at the following location:",
      h4(show_folder),
      textInput(ns("folder_name"), NULL, placeholder = "Enter name of new folder"),
      footer = tagList(
        actionButton(ns("create_folder"), "Create"),
        modalButton("Close")),
      fade = FALSE, easyClose = TRUE, size = "s"
    )
  })

  observeEvent(input$create_folder_dialog, showModal(folder_modal()))
  observeEvent(input$create_folder, {
    if (!is.null(input$folder_name) && input$folder_name != "") {
      new_folder <- stringr::str_replace_all(input$folder_name, "[^0-9A-Za-z_-]", "")
      new_folder <- file.path(files_select$path(), new_folder)
      if (!file.exists(new_folder)) {
        module_message(ns, "info", "Creating new sub folder: ", basename(new_folder))
        dir.create(new_folder)
      } else {
        module_message(ns, "info", "Already exists: ", basename(new_folder))
      }
    }
    removeModal()
  })

  # Manage load list =====
  # addition to load list
  add_to_load_list <- function(path, path_relative) {
    already_listed <- path %in% values$load_list$path
    if (length(path[!already_listed]) > 0) {
      module_message(ns, "debug", "adding files to load list: ", stringr::str_c(path_relative[!already_listed], collapse = ", "))
      new <- tibble::tibble(
        path = path[!already_listed],
        path_rel = path_relative[!already_listed])
      values$load_list <- bind_rows(values$load_list, new)
    }
    # update directory information
    values$load_list <- dplyr::mutate(
      values$load_list,
      isdir = dir.exists(path),
      n_files = ifelse(
        isdir,
        sapply(path, function(d) {
          length(list.files(d, pattern = pattern, recursive = TRUE, include.dirs = FALSE))
        }), 1L),
      label = ifelse(isdir, sprintf("[%s] (%d files)", path_rel, n_files), path_rel)
    )
  }
  observe({
    req(input$add_files)
    isolate({ add_to_load_list(path = files_select$selection(), path_relative = files_select$selection_relative()) })
  })
  observe({ # enable/disable add to load list button depending on selectoin
    if (length(files_select$selection()) > 0) enable("add_files")
    else disable("add_files")
  })
  observe({
    req(upload_files$upload_batch())
    isolate({
      uploaded_files_rel <- upload_files$last_upload_path_relative()
      if (length(uploaded_files_rel) > 0) {
        uploaded_folder <- if (store_data) files_select$path_relative() else "temp"
        if(nchar(uploaded_folder) > 0) uploaded_files_rel <- file.path(uploaded_folder, uploaded_files_rel)
        add_to_load_list(path = upload_files$last_upload_path(), path_relative = uploaded_files_rel)
      }
    })
  })

  # remove from load list
  remove_from_load_list <- function(remove_path) {
    values$load_list <- dplyr::filter(values$load_list, !path %in% remove_path)
  }
  observe({
    req(input$remove_files)
    isolate({ remove_from_load_list(input$load_files_list) })
  })

  # update load list
  observe({
    values$load_list # trigger whenever there is a change to the load list values
    isolate({
      options <- dplyr::select(values$load_list, label, path) %>% arrange(label) %>% deframe()
      values$load_list_selected <- options[options %in% values$load_list_selected]
      updateSelectInput(session, "load_files_list", choices = options, selected = values$load_list_selected)
    })
  })

  # keep track of load list selection (to keep it the same after reload)
  observe({
    req(input$load_files_list)
    isolate({ values$load_list_selected <- input$load_files_list })
  })

  # Load list ====
  datasets_dir <- if (store_data) get_datasets_path(data_dir) else setNames(temp_dir, "temp")
  datasets_ext <- stringr::str_subset(extensions, "rds")

  # observe load files button push
  observeEvent(input$load_files, {

    # make sure dataset name is entered
    dataset_name <- input$dataset_name
    if (is.null(dataset_name) || nchar(input$dataset_name) == 0) {
      showModal(modalDialog(title = "Missing dataset name",
                            p("Please enter a name for the dataset first"),
                            footer = modalButton("Close"), fade = FALSE, easyClose = TRUE))
      return(NULL)
    }

    # ask user about overwrite
    dataset_name <- stringr::str_c(dataset_name, ".", datasets_ext)
    if (file.exists(file.path(datasets_dir, dataset_name))) {
      module_message(ns, "info", "asking whether to overwrite dataset file '", dataset_name, "'")
      # modal dialog to ask
      showModal(
        modalDialog(
          h4("A dataset named ", strong(dataset_name), " already exists"),
          p("Do you want to overwrite/update the existing collection of data files?"),
          p("Choose ", strong("Yes"), "to overwrite/update."),
          p("Choose ", strong("Cancel"), "to return to the load list and enter a different name for the new dataset."),
          footer = tagList(
            actionButton(ns("overwrite"), "Yes"),
            modalButton("Cancel")
          ), fade = FALSE, size = "s"
        ))
    } else {
      # load dataset straight away
      create_dataset()
    }
  })

  # modal dialog yes pressed for overwrite
  observeEvent(input$overwrite, create_dataset())

  # create dataset
  create_dataset <- function() {

    # dataset
    dataset_name <- stringr::str_c(input$dataset_name, ".", datasets_ext)
    dataset_path <- file.path(datasets_dir, dataset_name)
    dataset_path_rel <- file.path(names(datasets_dir), dataset_name)
    module_message(ns, "info", "loading file list and storing in dataset file '", dataset_path_rel, "'")

    # retrieve paths for safety check that they point to valid files
    files <- NULL
    tryCatch({
      files <- isoreader::iso_expand_paths(path = values$load_list$path, extensions = extensions)
    }, error = function(e) {
      error_msg <- e$message %>%
        # make sure root directory replaced
        stringr::str_replace_all(fixed(root), root_name) %>%
        # list files in an HTML list
        stringr::str_replace("\n", "<ul><li>") %>% stringr::str_replace_all("\n", "</li><li>") %>% stringr::str_c("</li></ul>")
      showModal(modalDialog(title = "Error",
                            HTML(stringr::str_c("This list of files/folders cannot be loaded because ", error_msg)),
                            footer = modalButton("Close"), fade = FALSE, easyClose = TRUE))
    })
    n_files <- length(files)
    if (n_files == 0) {
      module_message(ns, "debug", "no files to load, aborting load")
      return()
    }

    # arguments for read files
    args <- c(
      list(values$load_list$path),
      as.list(setNames(names(load_params) %in% input$selected_params,
                       names(load_params))),
      list(cache = TRUE, quiet = TRUE))

    # read files
    showModal(modalDialog(
      h4("Reading files to create dataset ", dataset_name),
      p("This may take a few seconds per file for data files loaded for the first time."),
      footer = NULL, fade = FALSE, size = "s"))

    withProgress(message = 'Loading file list', value = 0, {

      # set read file event expression (executed in the local environment of the read) to update the progress bar
      isoreader:::set_read_file_event_expr(
        { incProgress(1/(nrow(files) + 1), message = sprintf("Reading '%s'...", basename(filepath))) })

      # read the files
      isofiles <- do.call(load_func, args = args)
      isoreader:::set_read_file_event_expr(NULL)

      # finalize and save
      values$loaded_isofiles <- iso_as_file_list(isofiles)
      setProgress(value = 1, detail = "",
                  message = sprintf("Saving dataset %s", dataset_name))
      iso_save(values$loaded_isofiles, filepath = dataset_path, quiet = TRUE)
      values$loaded_dataset <- dataset_path
      values$saved_datasets <- c(values$saved_datasets, setNames(dataset_path, dataset_path_rel))
    })

    # done reading
    removeModal()

    # problems
    if (nrow(isoreader::iso_get_problems(values$loaded_isofiles)) > 0) {
      load_problems$show_problems()
    }

    # post load
    if (is.function(post_load)) post_load()
  }

  # enable load files and remove button only if at least one file is selected
  observe({
    if (nrow(values$load_list) > 0) enable("load_files")
    else disable("load_files")
  })

  # loading parameters UI
  output$parameters <- renderUI({
    tagList(
      checkboxGroupInput(ns("selected_params"), NULL, inline = TRUE,
                         choices = setNames(names(load_params), load_params),
                         selected = names(load_params))
    )
  })


  # Problems ====
  load_problems <- callModule(
    problemsServer, "load_problems",
    dataset = reactive(values$loaded_isofiles), dataset_path = reactive(values$loaded_dataset)
  )


  # Code update ====
  code_update <- reactive({
    # trigger code update for any of the below variables changing
    req(values$load_list)
    req(input$selected_params)

    function(rmarkdown = TRUE, front_matter = rmarkdown) {
      module_message(ns, "debug", "generating updated code for isofiles load")
      code(
        generate_file_header_code(
          title = stringr::str_c("Loading ", input$dataset_name),
          setup = TRUE, caching_on = TRUE,
          rmarkdown = rmarkdown, front_matter = front_matter),
        generate_load_list_code(
          read_paths = values$load_list$path_rel,
          read_func = load_func,
          read_params = setNames(names(load_params) %in% input$selected_params, names(load_params)),
          save_file = input$dataset_name,
          rmarkdown = rmarkdown
        ),
        "" # final new line
      )
    }
  })
  code_preview <- callModule(
    code_preview_server, "code_preview", code_func_reac = code_update,
    download_file = reactive({ stringr::str_c("LOAD ", input$dataset_name) }))


  # Return reactive functions ====
  list(
    get_file_browser = files_select,
    get_loaded_dataset = reactive(values$loaded_dataset),
    get_saved_datasets = reactive(values$saved_datasets)
  )
}


#' Isofiles Load UI
#'
#' @param id the module id
#' @param label what to label boxes with
#' @family isofiles load module functions
isofilesLoadUI <- function(id, label = NULL) {
  ns <- NS(id)
  label <- if(!is.null(label)) stringr::str_c(label, " ")

  tagList(
    # file/folder selection
    default_box(title = stringr::str_c(label, "File and Folder Selection"), width = 12,
                fileSelectorUI(ns("files"), size = 9),
                footer = div(
                  tooltipInput(actionButton, ns("add_files"), "Add to load list", icon = icon("plus"),
                               tooltip = "Add selected files and folders to the load list"),
                  spaces(1),
                  inline(uiOutput(ns("upload_wrap"))),
                  spaces(1),
                  inline(uiOutput(ns("folder_creation_wrap")))
                )
    ),

    # load list
    default_box(title = stringr::str_c(label, "Load List"), width = 6,
                inlineInput(textInput, ns("dataset_name"), label = "Name:", placeholder = "Please enter a name for the dataset",
                            value = "", width = "250px"), # or default date/time: format(Sys.time(), format = "%Y-%m-%d dataset")
                selectInput(ns("load_files_list"), label = NULL, multiple = TRUE, size = 8, selectize = FALSE,
                            choices = c(),
                            selected = c()),
                footer = div(
                  tooltipInput(actionButton, ns("remove_files"), "Remove", icon = icon("remove"),
                               tooltip = "Remove selected files and folders from the load list"),
                  spaces(1),
                  tooltipInput(actionButton, ns("load_files"), "Create dataset", icon = icon("cog"),
                               tooltip = "Load the files and folders in the load list and store as named dataset"),
                  spaces(1),
                  #jumping directly to dataset view makes problems button obsolete here
                  #problemsButton(ns("load_problems"), tooltip = "Show problems encountered during the previous \"Load list\" operation."),
                  br(),
                  h4("Read Parameters:", id = ns("read_params_header")),
                  bsTooltip(ns("read_params_header"), "Which information to read from the data files."),
                  uiOutput(ns("parameters"))
                )
    ),

    # code preview
    code_preview_ui(ns("code_preview"), width = 6, height = "305px")
  )
}



