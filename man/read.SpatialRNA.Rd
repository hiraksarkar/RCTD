% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/SpatialRNA.R
\name{read.SpatialRNA}
\alias{read.SpatialRNA}
\title{Creates a SpatialRNA object from a directory}
\usage{
read.SpatialRNA(datadir, count_file = "MappedDGEForR.csv")
}
\arguments{
\item{datadir}{(string) the directory of the SpatialRNA dataset}

\item{count_file}{(optional, string) the file location for the DGE}
}
\value{
Returns a \code{\linkS4class{SpatialRNA}} object containing the coordinates and counts
from the input files
}
\description{
Given a SpatialRNA directory folder with 2 files: \code{BeadLocationsForR.csv} and \code{MappedDGEForR.csv}.
and returns a SpatialRNA object.
}
\section{Input file format (contained in datadir)}{

\enumerate{
\item \code{BeadLocationsForR.csv} # a CSV file (with 3 columns, with headers "barcodes", "xcoord", and "ycoord") containing the spatial locations
of the pixels.
\item \code{MappedDGEForR.csv} # a DGE (gene counts by barcodes) CSV file. Represents raw counts at each pixel.
}
}

