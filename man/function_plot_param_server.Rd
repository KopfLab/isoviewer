% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/module_function_plot_param.R
\name{function_plot_param_server}
\alias{function_plot_param_server}
\title{function plot parameter server}
\usage{
function_plot_param_server(
  input,
  output,
  session,
  settings,
  get_variable,
  type = c("expression", "logical"),
  get_value_options,
  default_value,
  reset_trigger = reactive({ })
)
}
\arguments{
\item{get_variable}{reactive function for the variable}

\item{type}{what type of parameter it is}

\item{get_value_options}{reactive function with available value options}

\item{reset_trigger}{reactive function to trigger a reset to the default value (if necessary)}

\item{func_formals}{formals of the relevant function (to determine default)}
}
\description{
function plot parameter server
}
