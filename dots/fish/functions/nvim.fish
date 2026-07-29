function nvim
    kitty --class nvim --title nvim /usr/bin/nvim $argv &
    disown
end
