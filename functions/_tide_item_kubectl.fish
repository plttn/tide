function _tide_item_kubectl
    set -l kubeconfig $HOME/.kube/config
    set -q KUBECONFIG && set kubeconfig $KUBECONFIG

    set -l ctx
    set -l namespace
    if string match -qv '*:*' -- $kubeconfig; and test -e $kubeconfig
        read -lz content <$kubeconfig
        string match -qr '(?m)^current-context:\s*[\'"]?(?<ctx>[^\'"\n]+?)[\'"]?\s*$' -- $content
        if test -n "$ctx"
            string match -qr '(?s)- context:\n(?<block>(?:(?!\n- context:).)*?)\n  name: '(string escape --style=regex -- $ctx)'(?:\n|$)' -- $content
            test -n "$block" && string match -qr 'namespace: *(?<namespace>\S+)' -- $block
        end
    end

    if test -z "$ctx"
        # $KUBECONFIG lists multiple merged files, the default file doesn't
        # exist, or the file didn't parse as expected -- let kubectl itself
        # figure it out.
        kubectl config view --minify --output 'jsonpath={.current-context}/{..namespace}' 2>/dev/null | read -l context &&
            _tide_print_item kubectl $tide_kubectl_icon' ' (string replace -r '/(|default)$' '' $context)
        return
    end

    if test -n "$namespace"
        _tide_print_item kubectl $tide_kubectl_icon' ' "$ctx/$namespace"
    else
        _tide_print_item kubectl $tide_kubectl_icon' ' $ctx
    end
end
