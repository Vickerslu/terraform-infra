variable "tenant_id" {
  description = "The tenant ID of the Azure subscription"
  type        = string
  default     = ""  # Replace with your Azure Tenant ID or leave empty to prompt for it
}

variable "deployment_name" {
  description = "Used to uniquely name resources"
  type = string
  default = "lukes"
}