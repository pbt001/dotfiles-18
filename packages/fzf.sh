install_fzf(){
    SHELL=/bin/zsh
    clone https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all > /dev/null 2>&1
}
