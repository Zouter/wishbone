#' Execute Wishbone
#'
#' @param counts Counts
#' @param start_cell_id ID of start cell
#' @param knn k nearest neighbours for diffusion
#' @param n_diffusion_components number of diffusion components
#' @param n_pca_components number of pca components
#' @param markers markers to use
#' @param branch whether or not to branch or linear
#' @param k k param
#' @param num_waypoints number of waypoints
#' @param normalize whether or not to normalize
#' @param epsilon epsilon param
#' @param verbose whether or not to print the wishbone output
#' @param num_cores number of cores to use
#'
#' @importFrom jsonlite toJSON read_json
#' @importFrom glue glue
#' @importFrom tibble tibble
#' @importFrom purrr %>%
#' @importFrom dplyr rename rename_if
#' @importFrom utils write.table read.csv
#'
#'
#' @export
Wishbone <- function(
  counts,
  start_cell_id,
  knn = 10,
  n_diffusion_components = 2,
  n_pca_components = 15,
  markers = "~",
  branch = TRUE,
  k = 15,
  num_waypoints = 50,
  normalize = TRUE,
  epsilon = 1,
  verbose = FALSE,
  num_cores = 1
) {
  # create temporary folder
  temp_folder <- tempfile()
  dir.create(temp_folder, recursive = TRUE)

  tryCatch({
    # write counts to temporary folder
    counts_df <- data.frame(counts, check.names = FALSE, stringsAsFactors = FALSE)
    utils::write.table(counts_df, paste0(temp_folder, "/counts.tsv"), sep="\t")

    # write parameters to temporary folder
    params <- tibble::lst(
      start_cell_id,
      knn,
      n_diffusion_components,
      n_pca_components,
      markers,
      branch,
      k,
      num_waypoints,
      normalize,
      epsilon,
      verbose,
      components_list = seq_len(n_diffusion_components)-1
    )

    write(
      jsonlite::toJSON(params, auto_unbox = TRUE),
      paste0(temp_folder, "/params.json")
    )

    if (!is.null(num_cores)) {
      num_cores_str <- glue::glue(
        "export MKL_NUM_THREADS={num_cores};",
        "export NUMEXPR_NUM_THREADS={num_cores};",
        "export OMP_NUM_THREADS={num_cores}"
      )
    } else {
      num_cores_str <- "echo 'no cores'"
    }

    # execute python script
    commands <- glue::glue(
      "cd {find.package('Wishbone')}/venv",
      "source bin/activate",
      "{num_cores_str}",
      "python {find.package('Wishbone')}/wrapper.py {temp_folder}",
      .sep = ";"
    )
    output <- processx::run("/bin/bash", c("-c", commands), echo=TRUE)

    # read output
    branch_filename <- paste0(temp_folder, "/branch.json")
    trajectory_filename <- paste0(temp_folder, "/trajectory.json")
    dimred_filename <- paste0(temp_folder, "/dm.csv")

    # read in branch assignment
    branch_assignment <- jsonlite::read_json(branch_filename) %>%
      unlist() %>%
      {tibble::tibble(branch = ., cell_id = names(.))}

    # read in trajectory
    trajectory <- jsonlite::read_json(trajectory_filename) %>%
      unlist() %>%
      {tibble::tibble(time = ., cell_id = names(.))}

    # read in dim red
    space <- utils::read.csv(
      dimred_filename,
      check.names = FALSE,
      header = FALSE,
      stringsAsFactors = FALSE,
      skip = 1
    )
    colnames(space) <- c("cell_id", paste0("Comp", seq_len(ncol(space)-1)))

  }, finally = {
    # remove temporary output
    unlink(temp_folder, recursive = TRUE)
  })

  list(
    branch_assignment = branch_assignment,
    trajectory = trajectory,
    space = space
  )
}
