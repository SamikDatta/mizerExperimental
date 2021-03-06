#' Launch shiny gadget for tuning parameters
#'
#' The function opens a shiny gadget, an interactive web page. This page has
#' a side panel with controls for various model parameters and a main panel
#' with tabs for various diagnostic plots.
#'
#' This gadget is meant for tuning a model to steady state. It is not meant for
#' tuning the dynamics of the model. That should be done in a second step using
#' functions like `setRmax()` or `changeResource()`.
#'
#' There is an "Instructions" button near the top left of the gadget that
#' gives you a quick overview of the user interface.
#'
#' After you click the "Done" button in the side panel, the function will return
#' the parameter object in the state at that time, with `Rmax` set to `Inf`
#' and `erepro` set to the value it had after the last run to steady state.
#'
#' At any time the gadget allows the user to download the current params object
#' as an .rds file via the "Download" button in the "File" section, or to
#' upload a params object from an .rds file.
#'
#' # Undo functionality
#'
#' The gadget keeps a log of all steady states you create while working with
#' the gadget. You can go back to the last steady state by hitting the "Undo"
#' button. You can go back an arbitrary number of states and also go forward
#' again. There is also a button to go right back to the initial steady state.
#'
#' When you leave the gadget by hitting the "Done" button, this log is cleared.
#' If you stop the gadget from RStudio by hitting the "Stop" button, then the
#' log is left behind. You can then restart the gadget by calling `tuneParams()`
#' without a `params` argument and it will re-instate the states from the log.
#'
#' The log is stored in the tempdir of your current R session, as given by
#' `tempdir()`. For each steady state you calculate the params objects is in a
#' file named according to the pattern
#'
#' # Customisation
#'
#' You can customise which functionality is included in the app via the
#' `controls` and `tabs` arguments. You can remove some of the controls and
#' tabs by providing shorter lists to those arguments. You can also add your
#' own controls and tabs.
#'
#' For an entry "foo" in the `controls` list there needs to be a function
#' "fooControlUI" that defines the input elements and a function "fooControl"
#' that processes those inputs to change the params object. You can model your
#' own control sections on the existing ones that you find in the file
#' `R/tuneParams_controls.R`.
#'
#' For any entry "foo" in the `tabs` list there needs to be a function
#' "fooTabUI" that defines the tab layout and a function "fooTab"
#' that calculates the outputs to be displayed on the tab. You can model your
#' own tabs on the existing ones that you find in the file
#' `R/tuneParams_tabs.R`.
#'
#' # Limitations
#'
#' The fishing control currently assumes that each species is selected by only
#' one gear. It allows the user to change the parameters for that gear. It also
#' enforces the same effort for all gears. It sets all efforts to that for the
#' first gear and then allows the user to change that single effort value.
#'
#' @param p MizerParams object to tune. If missing, the gadget tries to recover
#'   information from log files left over from aborted previous runs.
#' @param controls A list with the names of input parameter control sections
#'   that should be displayed in the sidebar. See "Customisation" below.
#' @param tabs A list with the names of the tabs that should be displayed in
#'   the main section. See "Customisation" below.
#' @param ... Other params needed by individual tabs.
#'
#' @return The tuned MizerParams object
#' @md
#' @export
tuneParams <- function(p,
                       controls = list("egg",
                                       "predation",
                                       "fishing",
                                       "reproduction",
                                       "other",
                                       "interaction",
                                       "resource"),
                       tabs = list("Spectra",
                                   "Biomass",
                                   "Growth",
                                   "Repro",
                                   "Catch",
                                   "Rates",
                                   "Prey",
                                   "Diet",
                                   "Death",
                                   "Resource",
                                   "Sim"),
                       ...) {
    # Define some local variables to avoid "no visible bindings for global
    # variable" warnings in CMD check
    wpredator <- wprey <- Nprey <- weight_kernel <- L_inf <-
        Legend <- w_mat <- erepro <- Type <- Abundance <- Catch <-
        Kernel <- Numbers <- Cause <- psi <- Predator <- Density <- NULL

    # Flags to skip certain observers ----
    flags <- new.env()

    # Prepare logs for undo/redo functionality ----
    logs <- new.env()
    logs$files <- vector(mode = "character")
    logs$idx <- 0

    if (missing(p)) {
        # Try to recover old log files ----
        logs$files <- sort(list.files(path = tempdir(),
                                pattern = "mizer_params_...._.._.._at_.._.._..\\.rds",
                                full.names = TRUE))
        logs$idx <- length(logs$files)
        if (logs$idx == 0) {
            stop("You need to specify a MizerParams object. ",
                 "There are no temporary parameter files to recover.")
        }
        p <- readRDS(logs$files[logs$idx])
    } else {
        validObject(p)
        p <- prepare_params(p)
    }

    # User interface ----
    ui <- fluidPage(
        shinyjs::useShinyjs(),
        introjsUI(),

        sidebarLayout(

            ## Sidebar ####
            sidebarPanel(
                introBox(
                    actionButton("sp_steady", "Steady"),
                    actionButton("undo", "", icon = icon("undo")),
                    actionButton("redo", "", icon = icon("redo")),
                    actionButton("undo_all", "", icon = icon("fast-backward")),
                    data.step = 5,
                    data.intro = "Each time you change a parameter, the spectrum of the selected species is immediately recalculated. However this does not take into account the effect on the other species. It therefore also does not take into account the second-order effect on the target species that is induced by the changes in the other species. To calculate the true multi-species steady state you have to press the 'Steady' button. You should do this frequently, before changing the parameters too much. Otherwise there is the risk that the steady state can not be found any more. Another advantage of calculating the steady-state frequently is that the app keeps a log of all steady states. You can go backwards and forwards among the previously calculated steady states with the 'Undo' and 'Redo' buttons. The last button winds back all the way to the initial state."
                ),
                introBox(
                    actionButton("done", "Done", icon = icon("check"),
                                 onclick = "setTimeout(function(){window.close();},500);"),
                    data.step = 8,
                    data.intro = "When you press this button, the gadget will close and the current params object will be returned. The undo log will be cleared."
                ),
                introBox(
                    actionButton("help", "Instructions"),
                    data.step = 9,
                    data.intro = "You can always run this introduction again by clicking here. You can find further information on the tuneParams() documentation page."
                ),
                tags$br(),
                introBox(uiOutput("sp_sel"),
                         data.step = 2,
                         data.position = "right",
                         data.intro = "Here you select the species whose parameters you want to change or whose properties you want to concentrate on."),
                introBox(
                    introBox(
                        # Add links to input sections
                        lapply(controls, function(section) {
                            list("->",
                                 tags$a(section, href = paste0("#", section)))
                        }),
                        "->",
                        tags$a("File", href = "#file"),
                        data.step = 4,
                        data.intro = "There are many parameters, organised into sections. To avoid too much scrolling you can click on a link to jump to a section."),
                    tags$br(),
                    tags$div(id = "params",
                             uiOutput("sp_params"),
                             introBox(
                                 uiOutput("file_management"),
                                 data.step = 7,
                                 data.intro = "At any point you can download the current state of the params object or upload a new params object to work on."
                             )
                    ),
                    tags$head(tags$style(
                        type = 'text/css',
                        '#params { max-height: 60vh; overflow-y: auto; }'
                    )),
                    data.step = 3,
                    data.intro = "Here you find controls for changing model parameters. The controls for species-specific parameters are for the species you have chosen above. Many of the controls are sliders that you can move by dragging or by clicking. As you change parameters, the plots in the main panel will immediately update."
                    ),
                width = 3
            ),  # endsidebarpanel

            ## Main panel ####
            mainPanel(
                introBox(uiOutput("tabs"),
                         data.step = 1,
                         data.intro = "This main panel has tabs that display various aspects of the steady state of the model.")
            )  # end mainpanel
        )  # end sidebarlayout
    )

    server <- function(input, output, session) {
        hintjs(session)
        ## Store params object as a reactive value ####
        params <- reactiveVal(p)
        tuneParams_add_to_logs(logs, p)  # This allows us to get back to the initial state
        if (logs$idx == length(logs$files)) shinyjs::disable("redo")
        if (logs$idx <= 1) {
            shinyjs::disable("undo")
        }

        # The file name will be empty until the user uploads a params file
        output$filename <- renderText("")

        # Define a reactive value for triggering an update of species sliders
        trigger_update <- reactiveVal(0)

        ## UI for side bar ####
        # Drop-down menu for selecting active species
        output$sp_sel <- renderUI({
            p <- isolate(params())
            species <- as.character(p@species_params$species[!is.na(p@A)])
            selectInput("sp", "Species:", species)
        })
        # Sliders for the species parameters
        output$sp_params <- renderUI({
            # The parameter sliders get updated whenever the species selector
            # changes
            req(input$sp)
            # or when the trigger is set somewhere
            trigger_update()
            # but not each time the params change
            p <- isolate(params())
            sp <- p@species_params[input$sp, ]

            lapply(controls,
                   function(section) {
                       do.call(paste0(section, "ControlUI"),
                               list(p = p, sp = sp))
                   })
        })

        fileManagement(input, output, session, params, logs)

        # Serve controls ####
        for (section in controls) {
            fun <- paste0(section, "Control")
            do.call(fun, list(input = input,
                              output = output,
                              session = session,
                              params = params,
                              flags = flags))
        }

        ## UI for tabs ####
        output$tabs <- renderUI({
            tablist <- lapply(tabs, function(tab) {
                tabPanel(tab, do.call(paste0(tolower(tab), "TabUI"), list()))
            })
            args <- c(id = "mainTabs", type = "tabs", tablist)
            do.call(tabsetPanel, args)
        })

        ## Serve tabs ####
        for (tab in tabs) {
            fun <- paste0(tolower(tab), "Tab")
            do.call(fun, list(input = input,
                              output = output,
                              session = session,
                              params = params,
                              logs = logs, ...))
        }

        # Help button ----
        observeEvent(
            input$help,
            introjs(session)
        )

        ## Steady ####
        # triggered by "Steady" button in sidebar
        observeEvent(input$sp_steady, {
            tuneParams_run_steady(params(), params = params,
                       logs = logs, session = session)
        })

        ## Undo ####
        observeEvent(input$undo, {
            if (logs$idx <= 1) return()
            p_new <- readRDS(logs$files[logs$idx])
            p_old <- params()
            # if the params have not changed, go to the previous one
            if (all(p_old@species_params == p_new@species_params, na.rm = TRUE)) {
                logs$idx <- logs$idx - 1
                shinyjs::enable("redo")
                p_new <- readRDS(logs$files[logs$idx])
                if (logs$idx == 1) {
                    shinyjs::disable("undo")
                }
            }
            params(p_new)
            # Trigger an update of sliders
            rm(list = ls(flags), pos = flags)
            trigger_update(runif(1))
        })
        ## Redo ####
        observeEvent(input$redo, {
            if (logs$idx >= length(logs$files)) return()
            logs$idx <- logs$idx + 1
            params(readRDS(logs$files[logs$idx]))
            # Trigger an update of sliders
            rm(list = ls(flags), pos = flags)
            trigger_update(runif(1))
            shinyjs::enable("undo")
            shinyjs::enable("undo_all")
            if (logs$idx == length(logs$files)) shinyjs::disable("redo")
        })
        ## Undo All ####
        observeEvent(input$undo_all, {
            if (logs$idx > 1) shinyjs::enable("redo")
            shinyjs::disable("undo")
            logs$idx <- 1
            params(readRDS(logs$files[logs$idx]))
            # Trigger an update of sliders
            rm(list = ls(flags), pos = flags)
            trigger_update(runif(1))
        })

        ## Done ####
        # When the user hits the "Done" button we want to clear the logs and
        # return with the latest params object
        observeEvent(input$done, {
            file.remove(logs$files)
            stopApp(params())
        })

    } #the server

    runGadget(ui, server, viewer = browserViewer())
}
