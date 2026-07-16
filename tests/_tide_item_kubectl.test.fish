# RUN: %fish %s
_tide_parent_dirs

function _kubectl
    _tide_decolor (_tide_item_kubectl)
end

set -lx tide_kubectl_icon ⎈

# -------- no kubeconfig file: falls back to the kubectl CLI --------
mock kubectl "config view --minify --output" "echo error: current-context must exist in order to minify >&2; false"
_kubectl # CHECK:

mock kubectl "config view --minify --output" "echo curr-context/default"
_kubectl # CHECK: ⎈ curr-context

mock kubectl "config view --minify --output" "echo curr-context/"
_kubectl # CHECK: ⎈ curr-context

mock kubectl "config view --minify --output" "echo curr-context/curr-namespace"
_kubectl # CHECK: ⎈ curr-context/curr-namespace

# -------- single-file kubeconfig: parsed without forking kubectl --------
set -l tmpdir (mktemp -d)
set -lx HOME $tmpdir
set -e KUBECONFIG
mkdir -p $tmpdir/.kube

echo 'current-context: dev
contexts:
- context:
    cluster: dev-cluster
  name: dev
- context:
    cluster: prod-cluster
    namespace: production
  name: prod' >$tmpdir/.kube/config

_kubectl # CHECK: ⎈ dev

echo 'current-context: prod
contexts:
- context:
    cluster: dev-cluster
  name: dev
- context:
    cluster: prod-cluster
    namespace: production
  name: prod' >$tmpdir/.kube/config

_kubectl # CHECK: ⎈ prod/production

# -------- $KUBECONFIG with multiple paths: falls back to the CLI --------
set -lx KUBECONFIG "$tmpdir/.kube/config:$tmpdir/.kube/other"
mock kubectl "config view --minify --output" "echo merged-context/merged-ns"
_kubectl # CHECK: ⎈ merged-context/merged-ns

command rm -r $tmpdir
