# EKS Module Variables
# @author Shanaka Jayasundera - shanakaj@gmail.com

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "cluster_role_arn" {
  description = "IAM role ARN for EKS cluster"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for EKS nodes"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for EKS cluster"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnet IDs for EKS nodes (defaults to subnet_ids)"
  type        = list(string)
  default     = null
}

variable "cluster_security_group_ids" {
  description = "Additional security group IDs for cluster"
  type        = list(string)
  default     = []
}

variable "endpoint_private_access" {
  description = "Enable private API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API endpoint"
  type        = bool
  default     = true
}

# System Node Pool
variable "system_node_count" {
  description = "Number of system nodes (when autoscaling disabled)"
  type        = number
  default     = 2
}

variable "system_node_instance_type" {
  description = "Instance type for system nodes"
  type        = string
  default     = "t3.medium"
}

variable "system_node_disk_size" {
  description = "Disk size for system nodes (GB)"
  type        = number
  default     = 50
}

variable "system_node_min_count" {
  description = "Minimum system nodes (when autoscaling enabled)"
  type        = number
  default     = 1
}

variable "system_node_max_count" {
  description = "Maximum system nodes (when autoscaling enabled)"
  type        = number
  default     = 3
}

variable "system_node_taint" {
  description = "Apply taint to system nodes so only system pods run there"
  type        = bool
  default     = true
}

# User Node Pool
variable "enable_user_node_pool" {
  description = "Enable separate user node pool"
  type        = bool
  default     = false
}

variable "user_node_count" {
  description = "Number of user nodes (when autoscaling disabled)"
  type        = number
  default     = 2
}

variable "user_node_instance_type" {
  description = "Instance type for user nodes"
  type        = string
  default     = "t3.medium"
}

variable "user_node_disk_size" {
  description = "Disk size for user nodes (GB)"
  type        = number
  default     = 50
}

variable "user_node_min_count" {
  description = "Minimum user nodes (when autoscaling enabled)"
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Maximum user nodes (when autoscaling enabled)"
  type        = number
  default     = 5
}

# Autoscaling
variable "enable_autoscaling" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = false
}

variable "capacity_type" {
  description = "Capacity type (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

# Logging
variable "enable_logging" {
  description = "Enable EKS control plane logging"
  type        = bool
  default     = false
}

variable "cluster_log_types" {
  description = "EKS cluster log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "tags" {
  description = "Tags for resources"
  type        = map(string)
  default     = {}
}
