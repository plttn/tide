# RUN: %fish %s
_tide_parent_dirs

function _docker
    _tide_decolor (_tide_item_docker)
end

set -l tmpdir (mktemp -d)
cd $tmpdir
set -lx HOME $tmpdir
mkdir -p $tmpdir/.docker

set -lx tide_docker_icon

# No config.json and no $DOCKER_CONTEXT -- falls back to the implicit
# "default" context, filtered by tide_docker_default_contexts same as the
# shipped default config (functions/tide/configure/configs/*.fish).
set -lx tide_docker_default_contexts default colima
_docker # CHECK:

# currentContext read from config.json, still filtered
echo '{"currentContext": "colima"}' >$tmpdir/.docker/config.json
_docker # CHECK:

# currentContext read from config.json, not filtered
echo '{"currentContext": "curr-context"}' >$tmpdir/.docker/config.json
_docker # CHECK:  curr-context

set -lx tide_docker_default_contexts curr-context
_docker # CHECK:
set -e tide_docker_default_contexts

# $DOCKER_CONTEXT overrides config.json
set -lx DOCKER_CONTEXT overridden
_docker # CHECK:  overridden

command rm -r $tmpdir
