# Bootstrap: Terraform installs Argo CD and the root Application.
# Everything else in the cluster is owned by Argo CD (gitops/).

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  values     = [file("${path.module}/values/argocd.yaml")]
  wait       = true
  timeout    = 600
}

# Secrets that Argo CD-managed apps need but that must never live in git.
# Their namespaces are created here; Argo CD adopts them via CreateNamespace=true.

resource "kubernetes_namespace_v1" "localstack" {
  metadata {
    name = "localstack"
  }
}

resource "kubernetes_secret_v1" "localstack_auth" {
  metadata {
    name      = "localstack-auth"
    namespace = kubernetes_namespace_v1.localstack.metadata[0].name
  }
  data = {
    LOCALSTACK_AUTH_TOKEN = var.localstack_auth_token
  }
}

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

# LocalStack accepts any credentials; these only need to be well-formed.
resource "kubernetes_secret_v1" "localstack_aws_creds" {
  metadata {
    name      = "localstack-aws-creds"
    namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
  }
  data = {
    access-key-id     = "test"
    secret-access-key = "test"
  }
}

resource "helm_release" "root_app" {
  name       = "root-app"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace  = "argocd"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = "default"
        source = {
          repoURL        = var.repo_url
          targetRevision = var.repo_revision
          path           = "gitops/bootstrap"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.localstack_auth,
    kubernetes_secret_v1.localstack_aws_creds,
  ]
}
