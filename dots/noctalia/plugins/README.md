# Local noctalia plugins

Registered with noctalia as a plugin source of kind `path`:

    noctalia msg plugins source add niri-config path ~/niri-config/dots/noctalia/plugins

A `path` source is read in place — noctalia loads the plugin straight out of
this directory (git sources it copies into
`~/.local/state/noctalia/plugins/materialized/` instead) and watches the entry
file, so saving an edit hot-reloads it. `~/.cache/noctalia/noctalia.log` is
where a Luau error shows up; `noctalia plugins lint <dir>` checks the manifest
before that.

- `equals-calc` — arithmetic in the launcher input: `=2+2`, or a bare `2+2`.
  Fills the gap left by noctalia's own calculator, whose trigger is always
  `/calc` and which reads a leading `=` as an equality test.
