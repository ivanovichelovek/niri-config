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

    # No terminal-colour sequences are catted here on purpose. iNiR shipped a
    # file of escape codes for the shell to echo at startup; noctalia does not
    # work that way — it renders ~/.config/kitty/themes/noctalia.conf from a
    # template and signals running kitty instances with SIGUSR1. kitty.conf
    # includes that file, so colours arrive without the shell's help.

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    if test "$TERM" != linux
        # --icons takes an optional WHEN value, so it must be written with "="
        # — bare `--icons` swallows the next argument (`ls Documents/` would
        # try to parse "Documents/" as the WHEN and error out).
        alias ls 'eza --icons=auto'
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
