#!/usr/bin/env bash


# Sourcing log functions
wget https://raw.githubusercontent.com/arghpy/functions/main/log_functions.sh
if source log_functions.sh; then
    log_info "sourced log_functions.sh"
else
    echo "Error! Could not source log_functions.sh"
    exit -1
fi

# Preparing environment
prep_env() {
    log_info "Preparing environment"
    source /etc/profile
    export PS1="(chroot) ${PS1}"
    log_ok "DONE"
}



prep_env
