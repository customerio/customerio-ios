#!/usr/bin/env bash

# Autohook
# A very, very small Git hook manager with focus on automation
# Author:   Nik Kantar <http://nkantar.com>
# Version:  2.1.1
# Website:  https://github.com/nkantar/Autohook
# fork by: https://github.com/levibostian/Autohook


echo() {
    builtin echo "[Autohook] $@";
}


install() {
    hook_types=(
        "applypatch-msg"
        "commit-msg"
        "post-applypatch"
        "post-checkout"
        "post-commit"
        "post-merge"
        "post-receive"
        "post-rewrite"
        "post-update"
        "pre-applypatch"
        "pre-auto-gc"
        "pre-commit"
        "pre-push"
        "pre-rebase"
        "pre-receive"
        "prepare-commit-msg"
        "update"
    )

    repo_root=$(git rev-parse --show-toplevel)
    hooks_dir="$repo_root/.git/hooks"
    autohook_linktarget="../../hooks/autohook.sh"
    for hook_type in "${hook_types[@]}"
    do
        hook_symlink="$hooks_dir/$hook_type"
        ln -s $autohook_linktarget $hook_symlink
    done
    echo "Scripts installed into .git/hooks"

    script="$repo_root/hooks/post-install.sh"
    if [[ -f "$script" ]]; then
        eval $script
    fi
}

main() {
    calling_file=$(basename $0)

    if [[ $calling_file == "autohook.sh" ]]
    then
        command=$1
        if [[ $command == "install" ]]
        then
            install
        fi
    else
        repo_root=$(git rev-parse --show-toplevel)
        hook_type=$calling_file
        script="$repo_root/hooks/$hook_type.sh"
        if [[ -f "$script" ]]; 
        then
            echo "Running git hook, $hook_type"
            
            hook_exit_code=0
            scriptname=$(basename $script)
            
            eval $script 
            script_exit_code=$?
            if [[ $script_exit_code != 0 ]]
            then
                hook_exit_code=$script_exit_code
            fi
            
            if [[ $hook_exit_code != 0 ]]
            then
              echo "FAILED Script: $scriptname. exit code $hook_exit_code"
              exit $hook_exit_code
            fi
        else 
            echo "No git hook to run for $hook_type"
        fi
    fi
}

main "$@"