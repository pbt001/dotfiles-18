#!/bin/bash

DOTFILE_REPO="https://github.com/fr0zn/dotfiles.git"
DOTFILE_DESTINATION="$HOME/.dotfiles"
DOTFILE_BACKUP="$HOME/.dotfiles-backup"
DB_SYNC=0
OS_TYPE=""

STEPS="pre backup symlink install post"

DEBUG=1

msg() {
    printf '%b\n' "$1" >&2
}

msg_info() {
    msg "\33[34m[*]\33[0m ${1}"
}

msg_debug() {
    if [[ "$DEBUG" == "1" ]]; then
        msg "\33[36m[d]\33[0m ${1}"
    fi
}

msg_ok() {
    msg "\33[32m[+]\33[0m ${1}"
}

msg_error() {
    msg "\33[31m[-]\33[0m ${1}: ${2}"
}

lnif() {
    if [ -e "$1" ]; then
        ln -sf "$1" "$2"
        if [[ ! -L ${2} ]]; then
            return 1
        fi
        return 0
    fi
}

has_sudo() {
    local prompt

    prompt=$(sudo -nv 2>&1)
    if [ $? -eq 0 ]; then
    echo "has_sudo__pass_set"
    elif echo $prompt | grep -q '^sudo:'; then
    echo "has_sudo__needs_pass"
    else
    echo "no_sudo"
    fi
}

sudo_run(){
    if [[ "$UID" == "0" ]]; then
        ${@}
        return $?
    else
        HAS_SUDO=$(has_sudo)

        case "$HAS_SUDO" in
        has_sudo__pass_set)
            sudo bash <<EOF
            $@
EOF
            ;;
        has_sudo__needs_pass)
            msg_info "Please supply your user password for the following command: \"${@}\""
            sudo bash <<EOF
            $@
EOF
            ;;
        *)
            msg_info "Please supply root password for the following command: \"${@}\""
            su -c "${@}"
            ;;
        esac
        return $?
    fi
}

sync_database() {
    if [[ "$DB_SYNC" == "0"  ]]; then
        msg_info "Updating database packages"
        case "${OS_TYPE}" in
            "macos")
                brew update
                ;;
            "ubuntu" | "debian" | "rpi")
                sudo_run apt update
                ;;
            "arch")
                sudo_run pacman -Syu --noconfirm
                ;;
        esac
        if [[ "$?" == "0" ]]; then
            msg_ok "Database synced"
            DB_SYNC=1
        else
            msg_error "Error syncing and updating packages"
            exit 1
        fi
    fi
}

install_cask() {
    sync_database
    msg_info "Installing cask ${@} (${OS_TYPE})"
    case "${OS_TYPE}" in
        "macos")
            brew cask install "${@}"
            ;;
        *)
            msg_error "brew cask not supported" "${OS_TYPE}"
            return 1
    esac
    if [[ $? -ne 0 ]];then
        msg_error "Error auto-installing ${@}" "no permission, wrong package, or already installed"
        return 1
    fi
    return 0
}

install_package() {

    sync_database
    msg_info "Installing ${@} (${OS_TYPE})"

    case "${OS_TYPE}" in
        "macos")
            brew install "${@}"
            ;;
        "ubuntu" | "debian" | "rpi")
            sudo_run apt -y install ${@}
            ;;
        "arch")
            sudo_run pacman -S --noconfirm ${@}
            ;;
        *)
            msg_error "Auto-Installation not supported" "${OS_TYPE}"
            return 1
    esac
    if [[ $? -ne 0 ]];then
        msg_error "Error auto-installing ${@}" "no permission, wrong package, or already installed"
        return 1
    fi
    return 0
}

is_app_installed() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        if [ -d "/Applications/${1}.app" ]; then
            return 0
        fi
        return 1
    else
        msg_info "Not a macOS, can't check if .app is installed"
        return 1
    fi
}

program_exists() {

    local ret='0'
    command -v $1 >/dev/null 2>&1 || { local ret='1'; }

    # fail on non-zero return value
    if [ "$ret" -ne 0 ]; then
        return 1
    fi

    return 0
}

program_must_exist() {
    program_exists $1
    if [[ $? -ne 0 ]]; then
        msg_error "Not Found" "You must have '$1' installed to continue."
        exit 1
    fi
}

symlink_file(){
    local path=$(dirname ${2})
    if [ ! -d "$path" ]; then
        mkdir -p $path 2> /dev/null
    fi
    lnif "$DOTFILE_DESTINATION/$1" "$2"
    return $?
}

function clone(){
    FROM=$1
    WHERE=$2

    if [ ! -e "$WHERE" ]; then
        mkdir -p "$WHERE" 2> /dev/null
        ERROR=$(git clone "$FROM" "$WHERE" 2>&1 > /dev/null)
        if [[ $? -ne 0 ]]; then
            msg_error "Error on clone" "$WHERE"
            return 1
        else
            msg_ok "Cloned $WHERE"
            return 0
        fi
    else
        ERROR=$(cd "$WHERE" && git pull origin 2>&1 > /dev/null)
        if [[ $? -ne 0 ]]; then
            msg_error "Pull error" "$WHERE"
            return 1
        else
            msg_ok "Pulled $WHERE"
            return 0
        fi
    fi
    return

}

_function_exists() {
    declare -f -F $1 > /dev/null
    return $?
}

backup_file() {
    mkdir -p $DOTFILE_BACKUP 2> /dev/null
    local file_name
    today=`date +%Y%m%d_%s`
    for i in "$@"; do
        file_name=$(basename $i)
        [ -e "$i" ] && cp "$i" "${DOTFILE_BACKUP}/${file_name}.${today}" 2>/dev/null 2>&1;
        if [[ ! -f "${DOTFILE_BACKUP}/${file_name}.${today}" ]]; then
            msg_error "Backup file ${i}"
            exit 1
        fi
    done
    return 0
}

# Loads all install.sh script from the dotfiles folder
_load() {
    list=$(find "$DOTFILE_DESTINATION" -maxdepth 2 -name install.sh)
    for element in $list; do
        . $element
    done
}

_template() {
    if _function_exists "${1}_${2}_$OS_TYPE"; then
        msg_debug "${2}: ${1} ($OS_TYPE)"
        $"${1}_${2}_$OS_TYPE"
    elif _function_exists "${1}_${2}"; then
        msg_debug "${2}: ${1} (generic)"
        $"${1}_${2}"
    else
        msg_debug "${2}: Tried to run ${1}_${2}, but it doesn't exist"
        return 0
    fi
    return $?
}

install() {
    local steps
    steps=$STEPS
    if [[ ! -z "$2" ]]; then
        msg_info "$1: Custom steps installation, steps: ${@:2}"
        steps="${@:2}"
    fi

    for step in $steps; do
        _template "$step" "$1"
        if [[ $? -ne 0 ]]; then
            msg_error "$1: Error installing" "In step: $step"
            return 1
        fi
    done

    msg_ok "$1: Done installing"
    return 0
}

run_level() {
    list=$(find $DOTFILE_DESTINATION/install -maxdepth 1 -name "${1}*")
    for element in $list; do
        msg_debug "Running `basename $element`"
        . $element
    done
}

install_brew_macos(){
    program_exists "brew"
    if [[ $? -ne 0 ]]; then
        msg_info "Brew not found, installing ..."
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi
    program_exists "brew"
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    return 0
}

_pre_run() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        if ! is_app_installed "Xcode"; then
          msg_error "Not Found" "You must have Xcode installed to continue."
          exit 1
        fi

        if xcode-select --install 2>&1 | grep installed > /dev/null; then
          msg_ok "Xcode CLI tools installed";
        else
          msg_error "Xcode CLI tools not installed" "Installing..."
        fi

        install "brew"
    fi

    program_exists "git"
    if [[ $? -ne 0 ]]; then
        install_package "git"
        program_must_exist "git"
    fi

    clone $DOTFILE_REPO $DOTFILE_DESTINATION
}

_get_os(){
    uname_out=`uname`

    if [[ "$uname_out" == "Darwin" ]]; then
        OS_TYPE="macos"
    elif [[ "$uname_out" == "Linux" ]]; then
        OS_TYPE="linux"
        if type lsb_release >/dev/null 2>&1 ; then
            distro=$(lsb_release -i -s)
            if [[ "$distro" == "Debian" ]]; then
                OS_TYPE="debian"
            elif [[ "$distro" == "Ubuntu" ]]; then
                OS_TYPE="ubuntu"
            elif [[ "$distro" == "Raspbian" ]]; then
                OS_TYPE="rpi"
            fi
        elif [ -f "/etc/arch-release" ]; then
            OS_TYPE="arch"
        fi
    fi

    msg_info "Running installation for OS: ${OS_TYPE}"
}

_run(){
    . "$DOTFILE_DESTINATION/install/all.sh"
    if [[ -f "$DOTFILE_DESTINATION/install/$OS_TYPE.sh" ]]; then
        . "$DOTFILE_DESTINATION/install/$OS_TYPE.sh"
    fi
    msg_ok "Done installing dotfiles!"
}

_get_os
_pre_run
_load # Load all installation files
_run

# vim: set sw=4 ts=4 sts=4 et tw=78 foldmarker={,} foldlevel=0 foldmethod=marker :
