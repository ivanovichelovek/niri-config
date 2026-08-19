# Local noctalia plugins

Registered with noctalia as a plugin source of kind `path`:

    noctalia msg plugins source add niri-config path ~/niri-config/dots/noctalia/plugins

noctalia copies (materializes) each plugin from here into
`~/.local/state/noctalia/plugins/materialized/niri-config/`, so after editing a
plugin run `noctalia msg plugins update` — or just `noctalia msg plugins enable
<id>` again — to re-copy it.

- `equals-calc` — arithmetic in the launcher input: `=2+2`, or a bare `2+2`.
  Fills the gap left by noctalia's own calculator, whose trigger is always
  `/calc` and which reads a leading `=` as an equality test.
