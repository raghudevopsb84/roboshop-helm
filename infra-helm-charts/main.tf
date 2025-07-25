resource "null_resource" "kubeconfig" {
  triggers = {
    time = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOF
az login --service-principal --username $ARM_CLIENT_ID --password $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID
az aks get-credentials --name ${var.name} --resource-group ${var.rg_name} --overwrite-existing
EOF
  }
}

resource "helm_release" "external-secrets" {
  depends_on = [
    null_resource.kubeconfig
  ]

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "devops"
  create_namespace = true
  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
}

resource "null_resource" "external-secrets-secret-store" {
  depends_on = [
    helm_release.external-secrets
  ]
  provisioner "local-exec" {
    command = <<TF
kubectl apply -f - <<KUBE
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: roboshop-${var.env}
spec:
  provider:
    vault:
      server: "http://vault-int.rdevopsb84.online:8200"
      path: "roboshop-${var.env}"
      version: "v2"
      auth:
        tokenSecretRef:
          name: "vault-token"
          key: "token"
          namespace: devops
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: devops
data:
  token: ${base64encode(var.token)}
KUBE
TF
  }
}

# Direct Helm Chart is a Problem - https://github.com/kubernetes/ingress-nginx/issues/10863

resource "null_resource" "nginx-ingress" {
  depends_on = [null_resource.kubeconfig]
  provisioner "local-exec" {
    command = <<EOF
 kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
EOF
  }
}


resource "helm_release" "argocd" {
  depends_on = [
    null_resource.kubeconfig,
    null_resource.nginx-ingress
  ]

  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  set = [
    {
      name  = "server.ingress.hostname"
      value = "argocd-${var.env}.rdevopsb84.online"
    }
  ]
  values = [
    file("${path.module}/helm-values/argocd.yml")
  ]
}

## Filebeat Helm Chart
resource "helm_release" "filebeat" {

  depends_on = [
    null_resource.kubeconfig,
    null_resource.nginx-ingress
  ]
  name       = "filebeat"
  repository = "https://helm.elastic.co"
  chart      = "filebeat"
  namespace  = "devops"
  wait       = "false"
  create_namespace = true

  values = [
    file("${path.module}/helm-values/filebeat.yml")
  ]
}

## Prometheus Stack Helm Chart
resource "helm_release" "prometheus" {

  depends_on = [
    null_resource.kubeconfig,
    null_resource.nginx-ingress
  ]
  name       = "prom-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "devops"
  wait       = "false"
  create_namespace = true

  values = [
    file("${path.module}/helm-values/prometheus.yml")
  ]
  set_list = [
    {
      name  = "prometheus.ingress.hosts"
      value = ["prometheus-${var.env}.rdevopsb84.online"]
    }
  ]
}

## External DNS Helm chart
resource "null_resource" "external-dns-secret" {
  depends_on = [
    null_resource.kubeconfig,
    null_resource.nginx-ingress
  ]

  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOF
echo '{
  "tenantId": "'"${data.vault_generic_secret.azure-sp.data["ARM_TENANT_ID"]}"'",
  "subscriptionId": "'"${data.vault_generic_secret.azure-sp.data["ARM_SUBSCRIPTION_ID"]}"'",
  "resourceGroup": "MyDnsResourceGroup",
  "aadClientId": "'"${data.vault_generic_secret.azure-sp.data["ARM_CLIENT_ID"]}"'",
  "aadClientSecret": "'"${data.vault_generic_secret.azure-sp.data["ARM_CLIENT_SECRET"]}"'"
}' >${path.module}/azure.json
EOF
  }

}

# resource "helm_release" "external-dns" {
#
#   depends_on = [
#     null_resource.kubeconfig,
#     null_resource.nginx-ingress
#   ]
#   name       = "external-dns"
#   repository = "https://kubernetes-sigs.github.io/external-dns/"
#   chart      = "external-dns"
#   namespace  = "devops"
#   wait       = "false"
#   create_namespace = true
# }


