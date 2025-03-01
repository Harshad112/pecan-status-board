library(rpecanapi)
library(dplyr)
library(tidyr)
library(tibble)
library(purrr)
library(httr)
library(glue)

# Modify for your target machine and authentication
server <- connect("http://141.142.217.168/", "ashiklom", "admin")

# List all available models
models <- GET(
  file.path(server$url, "api", "availableModels/"),
  authenticate(server$user, server$password)
) %>%
  content() %>%
  bind_rows()

default_start_date <- "2004-01-01"
default_end_date <- "2004-12-31"

#' Convert test list columns to `input` lists
configure_inputs <- function(met, model_name, ...) {
  # TODO: Add more inputs.
  input <- list(met = list(source = met))
  if (grepl("ED2", model_name)) {
    # TODO: Get these IDs from the database or from user input. Though they are
    # unlikely to change.
    input <- modifyList(input, list(
      lu = list(id = 294),
      thsum = list(id = 295),
      veg = list(id = 296),
      soil = list(id = 297)
    ))
  }
  input
}

test_list <- read.csv("inst/test-data/integration-test-list.csv", comment.char = "#",
                      na.strings = "") %>%
  as_tibble() %>%
  # Only test models that are available on the target machine
  inner_join(models, c("model_name", "revision")) %>%
  mutate(
    start_date = if_else(is.na(start_date), default_start_date, as.character(start_date)),
    end_date = if_else(is.na(end_date), default_end_date, as.character(end_date)),
    # TODO: Add more inputs here
    inputs = pmap(., configure_inputs),
    pfts = strsplit(as.character(pfts), "|", fixed = TRUE),
    # ED2-specific customizations
    workflow_list_mods = if_else(
      model_name == "ED2.2",
      list(list(model = list(phenol.scheme = 0,
                             ed_misc = list(output_month = 12),
                             edin = "ED2IN.r2.2.0"))),
      list(list())
    )
  )

test_runs <- test_list %>%
   select_if(colnames(.) %in% names(formals(submit.workflow))) %>%
  mutate(submit = pmap(., submit.workflow, server = server))

#Interactively check the status of runs
finished <- FALSE
while (!finished) {
  # Print a summary table
  Sys.sleep(10)
  message(Sys.time())
  run_status <- test_runs %>%
    mutate(workflow_id = map_chr(submit, "workflow_id"),
           status = map(workflow_id, possibly(get.workflow.status,
                                              list(NA, "Not started")),
                        server = server))
  stages <- run_status %>%
    mutate(stage = map(status, 2) %>% map_chr(tail, 1))
  finished <- !any(stages$stage == "Not started")
  stages %>%
    select(workflow_id, stage) %>%
    print(n = Inf)
}

stages$success_status <-ifelse(grepl("DONE", stages$stage), TRUE, FALSE)
models_name <- search.models(server)
sites_name <- search.sites(server)
stages$model_name <- models_name$models$model_name[match(stages$model_id, models_name$models$model_id)]
stages$site_name <- sites_name$sites$sitename[match(stages$site_id, sites_name$sites$id)]
stages$met <- test_list$met[match(stages$inputs, test_list$inputs)]

# Generate Data 

stages <- apply(stages,2,as.character)
if ((weekdays(Sys.Date())) == "Monday") {
  write.csv(stages, "data/overall-test/monday.csv")
} else if ((weekdays(Sys.Date())) == "Tuesday") {
  write.csv(stages, "data/overall-test/tuesday.csv")
} else if ((weekdays(Sys.Date())) == "Wednesday") {
  write.csv(stages, "data/overall-test/wednesday.csv")
} else if ((weekdays(Sys.Date())) == "Thursday") {
  write.csv(stages, "data/overall-test/thursday.csv")
} else if ((weekdays(Sys.Date())) == "Friday") {
  write.csv(stages, "data/overall-test/friday.csv")
} else if ((weekdays(Sys.Date())) == "Saturday") {
  write.csv(stages, "data/overall-test/saturday.csv")
} else if ((weekdays(Sys.Date())) == "Sunday") {
  write.csv(stages, "data/overall-test/sunday.csv")
} else {
  write.csv(stages, "data/overall-test/test_results.csv")
}

