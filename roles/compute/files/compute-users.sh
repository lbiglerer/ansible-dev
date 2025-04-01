#!/bin/bash

# The home dir these sessions should be dropped into
RHOME=/sci-it/compute-users
# This directory will contain the only commands this shell can run
RBIN=$RHOME/bin
ALLOWED_COMMANDS=$( find -L $RBIN -maxdepth 1 -type f -executable -exec basename {} \; | sort)

# Deal with both interactive and non-interactive sessions
if [ -n "$SSH_ORIGINAL_COMMAND" ]; then
    CMD=$( echo "$SSH_ORIGINAL_COMMAND" | awk '{ print $1 }')
    if [[ -x $RBIN/$SSH_ORIGINAL_COMMAND ]]; then
        $RBIN/$SSH_ORIGINAL_COMMAND
        exit $?
    else
        echo "Command not allowed: $CMD"
        echo "Allowed commands: $ALLOWED_COMMANDS"
        exit 1
    fi
else
    # No command; start restricted shell
    export HOME=$RHOME
    export PATH=$RBIN
    export SHELL=/bin/rbash
    readonly HOME
    readonly PATH
    readonly SHELL
    echo "This is a restricted shell. Allowed commands are:"
    echo $ALLOWED_COMMANDS
    cd $HOME && exec /bin/rbash
fi
