function _tide_item_docker
    set -l context default
    if set -q DOCKER_CONTEXT
        set context $DOCKER_CONTEXT
    else if test -e ~/.docker/config.json
        read -lz content <~/.docker/config.json
        string match -qr '"currentContext"\s*:\s*"(?<context>[^"]+)"' -- $content
    end
    contains -- "$context" $tide_docker_default_contexts ||
        _tide_print_item docker $tide_docker_icon' ' $context
end
