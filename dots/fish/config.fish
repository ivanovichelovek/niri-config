# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != linux
        starship init fish | source
        enable_transience
    end

    # Colors — noctalia writes terminal sequences via its template system
    # (`noctalia msg templates-apply`). Was iNiR's quickshell path before.
    if test -f ~/.local/state/noctalia/templates/terminal/sequences.txt
        cat ~/.local/state/noctalia/templates/terminal/sequences.txt
    end

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    if test "$TERM" != linux
        alias ls 'eza --icons'
    end
    if test "$TERM" = xterm-kitty
        alias ssh 'kitten ssh'
    end
end

# Secrets (API keys, tokens) live in a file that is NOT tracked by git.
# See conf.d/secrets.fish.example — copy it to ~/.config/fish/conf.d/secrets.fish
# and fill it in. Never put a key in this file: it is committed and pushed.
if test -f ~/.config/fish/conf.d/secrets.fish
    source ~/.config/fish/conf.d/secrets.fish
end
