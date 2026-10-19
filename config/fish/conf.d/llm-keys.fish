# API keys for CLI tools (opencode → ASU Air) from a private file outside any repo
if test -r ~/.config/llm/asu-air.env
    for line in (string match -rv '^\s*(#|$)' < ~/.config/llm/asu-air.env)
        set -gx (string split -m1 = -- $line)
    end
end
