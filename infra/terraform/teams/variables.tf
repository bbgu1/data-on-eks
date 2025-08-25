#---------------------------------------------------------------
# Teams Module Variables
#---------------------------------------------------------------

variable "teams" {
  description = "Map of team configurations for Pod Identity"
  type = map(object({
    name                = string
    namespace           = string
    service_account     = string
    iam_policy_arns     = list(string)
    additional_policies = optional(map(string), {})
    tags                = optional(map(string), {})
  }))

  validation {
    condition = alltrue([
      for team_name, team_config in var.teams :
      can(regex("^[a-z0-9-]+$", team_config.name)) &&
      can(regex("^[a-z0-9-]+$", team_config.namespace)) &&
      can(regex("^[a-z0-9-]+$", team_config.service_account))
    ])
    error_message = "Team name, namespace, and service_account must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "Cluster name cannot be empty."
  }
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "data-on-eks"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.name_prefix))
    error_message = "Name prefix must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
}
