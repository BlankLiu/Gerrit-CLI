#!/bin/bash -e

export PS4='+ [$(basename ${BASH_SOURCE})] [${LINENO}] '

ERROR_CODE_CONFIG_NOT_FOUND=1
ERROR_CODE_SSH_KEY_NOT_MATCH=2
ERROR_CODE_COMMAND_NOT_SUPPORTED=3
ERROR_CODE_BRANCH_CREATION_FAILURE=4

declare -A CMD_USAGE_MAPPING
declare -A CMD_OPTION_MAPPING
declare -A CMD_FUNCTION_MAPPING
GERRIT_CLI=


function log_i() {
    echo -e "Info : $*"
}

function log_e() {
    echo -e "Error: $*"
}

function __check_config() {
    local _CONFIG_FILE=
    local _GERRIT_HOST=
    local _GERRIT_PORT=
    local _GERRIT_USER=
    local _RET_VALUE=

    _CONFIG_FILE="$HOME/.gerrit/config.json"
    _RET_VALUE=0

    if [[ ! -f "$_CONFIG_FILE" ]]; then
        _RET_VALUE=$ERROR_CODE_CONFIG_NOT_FOUND
    else
        _GERRIT_HOST=$(cat "$_CONFIG_FILE" | jq -r ".host")
        _GERRIT_PORT=$(cat "$_CONFIG_FILE" | jq -r ".port")
        _GERRIT_USER=$(cat "$_CONFIG_FILE" | jq -r ".user")

        ssh -p $_GERRIT_PORT $_GERRIT_USER@$_GERRIT_HOST 2> /dev/null || \
        if [[ "$?" -ne "127" ]]; then
            log_e "SSH private key not matched with user $_GERRIT_USER"
            _RET_VALUE=$ERROR_CODE_SSH_KEY_NOT_MATCH
        else
            GERRIT_CLI="ssh -p $_GERRIT_PORT $_GERRIT_USER@$_GERRIT_HOST gerrit"
        fi
    fi

    return $_RET_VALUE
}

function __print_usage_of_create_branch() {
    local _RET_VALUE=

    _RET_VALUE=0
    cat << EOU
SYNOPSIS
    1. gerrit-cli.sh create-branch -p <PROJECT> -b <BRANCH> -r <REVISION>
    2. gerrit-cli.sh create-branch -f <BATCH_FILE>

DESCRIPTION
    Creates new branches for projects with given revision.

    The 1st format
        Creates a new branch <BRANCH> basing on given revision <REVISION> for
        specified project <PROJECT>.

    The 2nd format
        Creates new branches by batch basing on given file <BATCH_FILE>.
        Formats for file <BATCH_FILE>:
            - Each line must contain three fields which represent <PROJECT>,
              <BRANCH> and <REVISION>
            - Uses a whitespace to separate fields in each line
        Essentially, it uses the 1st format to create branches after extracting
        these fields.
OPTIONS
    -p|--project <PROJECT>
        Specify project's name.

    -b|--branch <BRANCH>
        Specify new branch's name.

    -r|--revision <REVISION>
        Specify an initial revision for the new branch. Could be a branch name
        or a SHA-1 value.

    -f|--file <BATCH_FILE>
        A file which contains required information to create new branches.

EXAMPLES
    1. Creates a branch called 'dev' from branch 'master' for project
       'devops/ci'.
       $ gerrit-cli.sh create-branch -p devops/ci -b dev -r master

    2. Creates new branches using batch file named 'batch.file'
       $ gerrit-cli.sh create-branch -f batch.file
EOU

    return $_RET_VALUE
}

function __create_branch() {
    local _SUB_CMD=
    local _PROJECT=
    local _BRANCH=
    local _REVISION=
    local _BATCH_FILE=
    local _CLI_CMD=
    local _RET_VALUE=

    _SUB_CMD="create-branch"
    _RET_VALUE=0

    if [[ $# -eq 0 ]]; then
        eval "${CMD_USAGE_MAPPING[$_SUB_CMD]}"
        return $_RET_VALUE
    fi

    _ARGS=$(getopt ${CMD_OPTION_MAPPING[$_SUB_CMD]} -- $@)
    eval set -- "$_ARGS"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                _PROJECT=$2
                ;;
            -b|--branch)
                _BRANCH=$2
                ;;
            -r|--revision)
                _REVISION=$2
                ;;
            -f|--file)
                _BATCH_FILE=$2
                ;;
            --)
                shift
                break
                ;;
        esac
        shift
    done

    if [[ ! -e "$_BATCH_FILE" ]]; then
        _CLI_CMD="$GERRIT_CLI $_SUB_CMD $_PROJECT $_BRANCH $_REVISION"
        log_i "creating branch '$_BRANCH' for project '$_PROJECT'"\
            "using revision '$_REVISION'"

        if eval "$_CLI_CMD"; then
            log_i "new branch created: $_BRANCH"
        else
            log_e "fail to create new branch: $_BRANCH"
            _RET_VALUE=$ERROR_CODE_BRANCH_CREATION_FAILURE
        fi
    else
        #set -x
        while read _PROJECT _BRANCH _REVISION; do
            _CLI_CMD="$GERRIT_CLI $_SUB_CMD $_PROJECT $_BRANCH $_REVISION"
            log_i "creating branch '$_BRANCH' for project '$_PROJECT'"\
                "using revision '$_REVISION'"

            # As ssh reads from standard input, it eats all remaining lines,
            # there are two ways to avoid this issue:
            # 1. redirects standard input to null bucket for ssh
            # 2. uses option -n for ssh
            if eval "$_CLI_CMD" < /dev/null; then
                log_i "new branch created: $_BRANCH"
            else
                log_e "fail to create new branch: $_BRANCH"
                _RET_VALUE=$ERROR_CODE_BRANCH_CREATION_FAILURE
            fi

            echo
        done < "$_BATCH_FILE"
    fi

    return $_RET_VALUE
}

function __init_command_context() {
    # Maps sub-command to its usage
    CMD_USAGE_MAPPING["create-branch"]="__print_usage_of_create_branch"

    # Maps sub-command to its options
    CMD_OPTION_MAPPING["create-branch"]="-o p:b:r:f:\
        -l project:,branch:,revision:,file:"

    # Maps sub-command to the implementation of its function
    CMD_FUNCTION_MAPPING["create-branch"]="__create_branch"
}

function __print_cli_usage() {
    cat << EOU
Usage: gerrit-cli.sh <SUB_COMMAND> [<args>]

These are sub-commands wrapped in the script. Each one has a corresponding
Gerrit command whose official document can be found wihin a Gerrit release.
1. create-branch
   Creates a new branch for a project.

To show usage of a <SUB_COMMAND>, use following command:
   gerrit-cli.sh help <SUB_COMMAND>
   gerrit-cli.sh <SUB_COMMAND> --help
EOU
}

function __run_cli() {
    local _SUB_CMD=
    local _FOUND=
    local _RET_VALUE=

    _FOUND="false"
    _RET_VALUE=0

    #set -x
    _SUB_CMD="$1"
    if [[ -z "$_SUB_CMD" ]]; then
        __print_cli_usage
    elif [[ "$_SUB_CMD" == "--help" ]]; then
        __print_cli_usage
    else
        for I in ${!CMD_OPTION_MAPPING[@]}; do
            if [[ "$_SUB_CMD" = $I ]]; then
                _FOUND="true"
                break
            fi
        done

        if eval "$_FOUND"; then
            if __check_config; then
                shift
                eval ${CMD_FUNCTION_MAPPING["$_SUB_CMD"]} $*
            else
                $_RET_VALUE=$?
            fi
        else
            if [[ "$_SUB_CMD" == "help" ]]; then
                shift
                _SUB_CMD="$1"

                _FOUND="false"
                for I in ${!CMD_OPTION_MAPPING[@]}; do
                    if [[ "$_SUB_CMD" = $I ]]; then
                        _FOUND="true"
                        break
                    fi
                done

                if eval "$_FOUND"; then
                    eval ${CMD_USAGE_MAPPING[$_SUB_CMD]}
                else
                    if [[ -z "$_SUB_CMD" ]]; then
                        __print_cli_usage
                    else
                        _RET_VALUE=$ERROR_CODE_COMMAND_NOT_SUPPORTED
                        log_e "unsupported sub-command: '$_SUB_CMD'"
                    fi
                fi
            else
                _RET_VALUE=$ERROR_CODE_COMMAND_NOT_SUPPORTED
                log_e "unsupported sub-command: '$_SUB_CMD'"
            fi
        fi
    fi

    return $_RET_VALUE
}

############# ENTRY POINT #############
__init_command_context
__run_cli $*

# vim: set shiftwidth=4 tabstop=4 expandtab