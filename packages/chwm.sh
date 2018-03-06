install_chwm_macos(){
    if [[ ! -d "/System/Library/ScriptingAdditions/CHWMInjector.osax" ]]; then
        clone https://github.com/koekeishiya/chwm-sa.git $DOTFILE_SRC/chwm
        cd $DOTFILE_SRC/chwm
        ./build.sh
        if [[ "$?" == "0" ]]; then
            sudo cp -r bin/CHWMInjector.osax /System/Library/ScriptingAdditions/
        fi
    fi

    cd $DOTFILE_SRC/chwm/inject_test
    ./build.sh
    cp -f bin/inject $DOTFILE_BIN/inject
}

post_chwm_macos(){
    msg_info "You will need to restart the mac"
}
