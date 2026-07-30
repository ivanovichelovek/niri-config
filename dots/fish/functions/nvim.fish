function nvim
    # A new kitty window, so nvim never blocks the shell it was launched from.
    #
    # --detach instead of `... & disown`: a backgrounded kitty keeps the parent's
    # stdout, so its own warnings land in the terminal you typed `nvim` in. That
    # is where "[PARSE ERROR] Escape codes to resize text area are not supported"
    # comes from — kitty deliberately does not implement the XTWINOPS resize
    # sequence, something in nvim sends it, and the complaint surfaces in the
    # wrong window. --detached-log sends it nowhere instead.
    kitty --detach --detached-log=/dev/null \
        --class nvim --title nvim /usr/bin/nvim $argv
end
