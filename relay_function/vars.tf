variable "name" {
  type = string
}

variable "description" {
  type = string
}

variable "project" {
  type = string
}

variable "location" {
  type = string
}

variable "source_bucket" {
  type = string
}

variable "source_object" {
  type = string
}

variable "source_sha" {
  type = string
}

variable "aws_bus_arn" {
  type = string
}

variable "aws_role_arn" {
  type = string
}

variable "debug" {
  type = bool
}

variable "cpu" {
  type = string
}

variable "memory" {
  type = string
}

variable "service_account_email" {
  type = string
}

variable "relay_detail_type" {
  type = string
}

variable "pubsub_topic_id" {
  type = string
}

variable "event_max_age_s" {
  type = number
}
