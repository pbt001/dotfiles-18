#/bin/bash

_msg() {
    printf "$1" >&2
}

_msg_info() {
    _msg "\e[1;94m==>\e[1;0m ${1}"
}

function gdbs(){

    possible=()
    paths=()

    list=$(find "$DOTFILE_PATH/gdb/inits" -name "*.gdbinit" -type f  -maxdepth 2)
    for filepath in $list; do
        filename=$(basename $filepath)
        name="${filename%.*}"
        possible=("${possible[@]}" ${name})
        paths=("${paths[@]}" ${filepath})
    done

    possible=("${possible[@]}" "legacy")

    select op in ${possible[@]} exit; do
       case $op in
          legacy)
                _msg_info "Starting gdb (legacy)"
                echo "" > $HOME/.gdbinit
                break ;;
          exit) echo "Exiting"
                break ;;
             *)
                _msg_info "Starting gdb with $op"
                path=$(IFS=$'\n'; echo "${paths[*]}" | grep $op)
                cat $path > $HOME/.gdbinit
                break ;;
       esac
    done

    gdb "$@"
}
