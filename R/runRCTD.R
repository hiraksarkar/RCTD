test_single_beads <- function(puck, gene_list, cell_type_info, trust_model = FALSE, constrain = T, OLS = F) {
  cell_type_names = cell_type_info[[2]]; n_cell_types = cell_type_info[[3]]
  beads = t(as.matrix(puck@counts[gene_list,]))
  weights = decompose_batch(puck@nUMI, cell_type_info[[1]], beads, gene_list, constrain = constrain, OLS = OLS)
  pred_labels = unlist(lapply(weights,function(x) which.max(x$weights)))
  cell_type_lev = factor(1:n_cell_types)
  cell_type_map = data.frame(cindex = 1:n_cell_types, row.names = cell_type_names)
  if(trust_model)
    true_labels = pred_labels
  else
    true_labels = lapply(puck@cell_labels, function(x) cell_type_map[as.character(x),"cindex"])
  conf_mat = caret::confusionMatrix(factor(pred_labels,cell_type_lev),factor(true_labels,cell_type_lev))
  rownames(conf_mat$table) = cell_type_names; colnames(conf_mat$table) = cell_type_names
  return(list(conf_mat,weights,pred_labels))
}

#' Runs RCTD in full mode on \code{puck}
#'
#' Renormalizes \code{cell_type_means} to have average the same as the puck
#' if \code{proportions} is given. Then, computes cell type proportions for each pixel
#' in \code{puck}.
#'
#' @param proportions (optional) If given, a named list (for each cell type) of proportion of the cell type on the bulk dataset
#' (not constrained to sum to 1)
#' @param gene_list a list of genes to be used for RCTD
#' @param puck an object of type \linkS4class{SpatialRNA}, the target dataset
#' @param cell_type_info cell type information and profiles of each cell, calculated from the scRNA-seq
#' reference (see \code{\link{get_cell_type_info}})
#' @param constrain logical whether to constrain the weights to sum to one on each pixel
#' @return Returns \code{test_results}, a list of three items:
#' (1) \code{conf_mat} a confusion matrix (not relevant) (2) \code{weights}
#' a dataframe of predicted weights (3) a named list of predicted cell types
#' @export
process_data <- function(puck, gene_list, cell_type_info, proportions = NULL, trust_model = FALSE, constrain = T, OLS = F) {
  cell_type_info_renorm = cell_type_info
  if(!is.null(proportions)) {
    cell_type_info_renorm[[1]] = get_norm_ref(puck, cell_type_info[[1]], gene_list, proportions)
  }
  test_results <- test_single_beads(puck, gene_list, cell_type_info_renorm, trust_model = trust_model, constrain = constrain, OLS = OLS)
  return(test_results)
}


#' Runs RCTD in doublet mode on \code{puck}
#'
#' Then, computes cell type proportions for each pixel in \code{puck}.
#' Classifies each pixel as 'singlet' or 'doublet' and searches for the cell types
#' on the pixel
#'
#' @param class_df A dataframe returned by \code{\link{get_class_df}} to map cell types to
#' classes
#' @param gene_list a list of genes to be used for RCTD
#' @param puck an object of type \linkS4class{SpatialRNA}, the target dataset
#' @param cell_type_info cell type information and profiles of each cell, calculated from the scRNA-seq
#' reference (see \code{\link{get_cell_type_info}})
#' @param constrain logical whether to constrain the weights to sum to one on each pixel
#' @param max_cores number of cores to use (will use parallel processing if more than one).
#' @return Returns \code{results}, a list of RCTD results for each pixel, which can be organized by
#' feeding into \code{\link{gather_results}}
#' @export
process_beads_batch <- function(cell_type_info, gene_list, puck, class_df = NULL, constrain = T, MAX_CORES = 8) {
  beads = t(as.matrix(puck@counts[gene_list,]))
  #out_file = "logs/process_beads_log.txt"
  #if (file.exists(out_file))
  #  file.remove(out_file)
  if(MAX_CORES > 1) {
    numCores = parallel::detectCores();
    if(parallel::detectCores() > MAX_CORES)
      numCores <- MAX_CORES
    cl <- parallel::makeCluster(numCores,outfile="") #makeForkCluster
    doParallel::registerDoParallel(cl)
    environ = c('decompose_full','decompose_sparse','solveIRWLS.weights','solveOLS','solveWLS','Q_mat','X_vals','K_val', 'delta')
    results <- foreach::foreach(i = 1:(dim(beads)[1]), .export = environ) %dopar% { #.packages = c("quadprog"),
      #if(i %% 100 == 0)
      #  cat(paste0("Finished sample: ",i,"\n"), file=out_file, append=TRUE)
      assign("Q_mat",Q_mat, envir = globalenv()); assign("X_vals",X_vals, envir = globalenv())
      assign("K_val",K_val, envir = globalenv());
      result = process_bead_doublet(cell_type_info, gene_list, puck@nUMI[i], beads[i,], class_df = class_df, constrain = constrain)
      result
    }
    parallel::stopCluster(cl)
  } else {
    #not parallel
    results <- list()
    for(i in 1:(dim(beads)[1])) {
      results[[i]] <- process_bead_doublet(cell_type_info, gene_list, puck@nUMI[i], beads[i,], class_df = class_df, constrain = constrain)
    }
  }
  return(results)
}

#' Runs the RCTD algorithm
#'
#' If in doublet mode, fits at most two cell types per pixel. It classifies each pixel as 'singlet' or 'doublet' and searches for the cell types
#' on the pixel. If in full mode, can fit any number of cell types on each pixel.
#'
#' @param RCTD an \code{\linkS4class{RCTD}} object after running the \code{\link{choose_sigma_c}} function.
#' @param doublet_mode \code{logical} of whether RCTD should be run in doublet_mode.
#' @return an \code{\linkS4class{RCTD}} object containing the results of the RCTD algorithm.
#' @export
fitPixels <- function(RCTD, doublet_mode = T) {
  set_likelihood_vars(RCTD@internal_vars$Q_mat, RCTD@internal_vars$X_vals)
  cell_type_info <- RCTD@cell_type_info$renorm
  if(doublet_mode) {
    results = process_beads_batch(cell_type_info, RCTD@internal_vars$gene_list_reg, RCTD@spatialRNA, class_df = RCTD@internal_vars$class_df,
                                  constrain = F, MAX_CORES = RCTD@config$max_cores)
    return(gather_results(RCTD, results))
  } else {
    beads = t(as.matrix(RCTD@spatialRNA@counts[RCTD@internal_vars$gene_list_reg,]))
    results = decompose_batch(RCTD@spatialRNA@nUMI, cell_type_info[[1]], beads, RCTD@internal_vars$gene_list_reg, constrain = F, max_cores = RCTD@config$max_cores)
    weights = Matrix(0, nrow = length(results), ncol = RCTD@cell_type_info$renorm[[3]])
    rownames(weights) = colnames(RCTD@spatialRNA@counts); colnames(weights) = RCTD@cell_type_info$renorm[[2]];
    for(i in 1:dim(weights)[1])
      weights[i,] = results[[i]]$weights
    RCTD@results <- list(weights = weights)
    return(RCTD)
  }
}

decompose_batch <- function(nUMI, cell_type_means, beads, gene_list, constrain = T, OLS = F, max_cores = 8) {
  #out_file = "logs/decompose_batch_log.txt"
  #if (file.exists(out_file))
  #  file.remove(out_file)
  if(max_cores > 1) {
    numCores = parallel::detectCores()
    if(parallel::detectCores() > max_cores)
      numCores <- max_cores
    cl <- parallel::makeCluster(numCores,outfile="") #makeForkCluster
    doParallel::registerDoParallel(cl)
    environ = c('decompose_full','solveIRWLS.weights',
                'solveOLS','solveWLS', 'Q_mat', 'K_val','X_vals','delta')
    #for(i in 1:100) {
    weights <- foreach::foreach(i = 1:(dim(beads)[1]), .packages = c("quadprog"), .export = environ) %dopar% {
      #if(i %% 100 == 0)
      #  cat(paste0("Finished sample: ",i,"\n"), file=out_file, append=TRUE)
      assign("Q_mat",Q_mat, envir = globalenv()); assign("X_vals",X_vals, envir = globalenv())
      assign("K_val",K_val, envir = globalenv());
      decompose_full(data.matrix(cell_type_means[gene_list,]*nUMI[i]), nUMI[i], beads[i,], constrain = constrain, OLS = OLS)
    }
    parallel::stopCluster(cl)
  } else {
    weights <- list()
    for(i in 1:(dim(beads)[1])) {
      weights[[i]] <- decompose_full(data.matrix(cell_type_means[gene_list,]*nUMI[i]), nUMI[i], beads[i,], constrain = constrain, OLS = OLS)
    }
  }
  return(weights)
}


