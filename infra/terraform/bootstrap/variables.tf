variable "kubeconfig_path" {
  description = "Kubeconfig that holds the lab cluster context."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubectl context of the lab cluster."
  type        = string
  default     = "k3d-igaming-lab"
}

variable "repo_url" {
  description = "Git repository Argo CD syncs from."
  type        = string
  default     = "https://github.com/HovhannesHovakimyan/igaming-platform-lab.git"
}

variable "repo_revision" {
  description = "Branch, tag or commit Argo CD tracks."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo/argo-cd Helm chart version."
  type        = string
  default     = "10.10.5"
}

variable "argocd_apps_chart_version" {
  description = "argo/argocd-apps Helm chart version."
  type        = string
  default     = "2.0.7"
}

variable "localstack_auth_token" {
  description = "LocalStack auth token (free Hobby plan). Supplied via TF_VAR_localstack_auth_token, never committed."
  type        = string
  sensitive   = true
}
