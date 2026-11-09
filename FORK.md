# Maintenance fork

This is a narrow maintenance fork of [akinsho/bufferline.nvim](https://github.com/akinsho/bufferline.nvim)
for [abhi-k9/nvim-config](https://github.com/abhi-k9/nvim-config). The base is
`655133c3b4c3e5e05ec549b9f8cc2894ac6f51b3` (v4.9.1). Upstream history,
authorship, README and GPL-3.0 license are retained. The diagnostic cache and its
regressions were adapted from abhi-k9/nvim-config. No runtime dependency is added.

The support target is Neovim >= 0.12.0; 0.12.0 and 0.12.6 were tested on Linux.
This is not a UI redesign or a general feature fork. Pinning, visual ordering,
commands, click callbacks, theming, icons and diagnostic formatting retain their
existing contracts. Safe deletion remains the config's responsibility; its shared
helpers are not moved here. Inherited force-closing group commands remain unchanged
and must not replace the config's safe-close mappings.

## Patch ledger

| Area | Patch scope |
| --- | --- |
| Pin persistence | Versioned JSON filename list; validate the complete payload; exact name index; repeated SessionLoadPost; owned autocmd group; stale pins cleared independently of other groups; invalid IDs, unnamed buffers, renames and wipes handled. |
| Public API | `is_pinned(bufnr)` on bufferline and bufferline.groups, without requiring a redraw. |
| Staged sessions | `restore_pins()` after a loader recreates hidden buffers. SessionLoadPost alone runs before the config's scope hook. Missing names remain available for this explicit second pass. |
| Diagnostics | Opt-in `diagnostics_cache`, default false. Exact severity summaries per namespace/buffer, live enable filters, event invalidation and provider-specific insert snapshots. No diagnostic getter interception. |
| Neovim compatibility | Backport [#1051](https://github.com/akinsho/bufferline.nvim/pull/1051), original commit `2ce76b44f9476ccd9b1a53ca932b86bf425dd9b6`, preserving Maria Solano's authorship. `vim.nonnil` when available, `vim.F.if_nil` otherwise. |
| CI | Read-only push/PR/manual checks; full action SHAs; exact Neovim/formatter/test-dependency revisions; job, process and per-file deadlines. No format commits, pushes, release automation or scheduled stress jobs. |

The invalid-buffer guard proposed in [#963](https://github.com/akinsho/bufferline.nvim/pull/963)
is covered by the pin implementation. [#1010](https://github.com/akinsho/bufferline.nvim/pull/1010)
was deliberately not adopted: dropping all diagnostics at 1,024 items violates
exact-count semantics. The open-PR list was reviewed for compatibility work;
sort insertion #1056, closing behavior #1015 and other feature changes are outside
this patch scope. Neovim 0.13/nightly has not been validated. The nonnil branch is
also covered by an injected API test; the tested 0.12 builds use the fallback.

## Sessions and migration

See `:help bufferline-pinning`, `:help bufferline.is_pinned()`,
`:help bufferline.restore_pins()` and `:help bufferline-diagnostics-cache`.

- Keep `sessionoptions+=globals` and startup loading before auto-session.
- Unambiguous single-filename legacy pin data is restored literally. Comma-separated
  legacy data cannot distinguish separators from commas in filenames; it is rejected
  with a warning. Re-pin and save those sessions. Never guess their old boundaries.
- Neovim 0.12-generated session files emit SessionLoadPre. Re-save older session
  scripts, or make a custom loader emit that event before restoring globals. A
  script without it and without pin metadata cannot distinguish an inherited global.
- In nvim-config, call `require('bufferline').restore_pins()` after both scope
  restoration and its visibility reconciliation. This does not create or list buffers.
- Replace the guarded config boundary's private query with `is_pinned(bufnr)`;
  retain its snapshot validation, deduplication, visibility checks and safe deletion.
- Map `ui.bufferline_diagnostic_cache` to `options.diagnostics_cache`; remove
  `config.bufferline_diagnostics` and its getter-override setup/disposal hook only
  with the fork pin. Keep the existing opt-out setting and indicator formatter.
- Prepare repository/spec and lockfile changes together. Do not combine a rollback
  to upstream with the adapter removals: restore the old config integration too.
  Back up sessions before adoption, since upstream cannot decode the new pin format.

The config integration, based on `c287c4e` (including `e09c9a6`), was published
and adopted after explicit authorization on 2026-11-09. Both `main` branches
were fast-forwarded: this fork to `4e964066ed10eb61f7b42b634f9b0877047eccdd`
and nvim-config to `6d5a6dba83650e7663b70195758003ab1e05b77f`. The config pins
that published fork revision. No force-push or PR was used. The verification
below records the checks performed before publication.

## Verification (2026-11-09)

Four pin regressions failed on the original revision before fixes: pattern lookup,
comma-fragment mispinning, repeated session restore, duplicate setup handlers.
An attached-UI fresh-process probe subsequently reproduced loss of a hidden scoped
pin; the staged restore API and config hook address that ordering defect.

- Final complete suite: **109 passed, 0 failures/errors** on each of Neovim
  **0.12.0** and **0.12.6**. Runs are sequential, with 10s per file and 120s overall.
- Config integration: **27 focused tests passed** using isolated module initialization:
  public pin boundary (5), cache option (2), safe deletion (4), menu splits (4),
  scope/session persistence (9), session debugger cleanup (3).
- Attached Neovim UI (`nvim_ui_attach`, ext_linegrid), 0.12.6/Linux: scoped/global
  modes, pinned-first/manual order, first/last/cycle and letter navigation, all four
  severities, keyboard menu, real Neovim mouse-input dispatch, unsaved text protection,
  Catppuccin's four flavors, icons on/off, Neo-tree filetype/window offsets, 180/48-column
  layouts, and fresh-process session restore followed by A -> B -> A with a hidden pin.
- StyLua 2.3.1 read-only checks, shell syntax, YAML/action-pin inspection and
  `git diff --check` passed. GitHub-hosted Actions were not run (nothing was pushed).

The normal suite was run at the initial completed implementation and once again
after the UI probe exposed the staged-session issue. Intervening checks were focused.
No benchmark or recurring stress workload was added.

### Reproduce

```sh
bash scripts/bootstrap-tests.sh
NVIM_BIN=/path/to/nvim bash scripts/test.sh
NVIM_BIN=/path/to/nvim bash scripts/test.sh tests/pins_spec.lua
stylua --check lua tests
```

Test dependencies are Plenary `74b06c6c75e4eeb3108ec01852001636d85a932b` and
Devicons `ec309a0eaff6ea967e58c275996155ab5c16938d`. The bootstrap does not
replace existing checkouts at unexpected revisions; tests never download plugins.

The optional UI runner requires test-only Python `msgpack` (available in the
validation environment), the prepared config integration, scope.nvim
`01cc3d5bb794e6d7afbb1b02a7e941ddf736d9ea`, and Catppuccin
`edefef779ab08ce1a4a404713e3012b0d202bd35`. It does not install or load private config.
Each UI process has a 45s deadline and isolated XDG directories:

```sh
python3 tests/manual/run_ui.py --nvim /path/to/nvim \
  --config /path/to/nvim-config-integration --scope /path/to/scope.nvim \
  --theme /path/to/catppuccin --output /tmp/bufferline-ui-results
```

### Limits

Native Windows/macOS, terminal fonts/encodings, physical mouse/keyboard interaction,
clipboard integration, terminal-buffer shutdown and complete Neo-tree/auto-session
plugin startup are not newly verified here. The UI probe uses actual scope/theme/icon
plugins and config callbacks, but models Neo-tree by its window/filetype boundary and
sources native sessions through the config hooks. It does not bootstrap the full Lazy
plugin set. CoC delegation is tested with its API stub, not a running CoC service.
At 48 columns with multiple tabs/diagnostic labels, buffer labels may be clipped out;
the probe verifies retained navigation state, not a new compact layout. Superscript
numbers still precede pinned sorting and can differ from positional navigation.
Embedded UI checks do not establish manual visual acceptance in a real terminal.

## Upstream reconciliation

Keep `upstream` pointed at akinsho/bufferline.nvim. On a deliberate update, compare
upstream changes against this ledger, rerun the focused regressions on the proposed
base, then the bounded complete suite and affected UI probes. Prefer upstream's
implementation when it supplies equivalent behavior and public contracts. Drop
superseded patches individually after parity verification; migrate session formats
and config hooks explicitly. Send fixes upstream only when authorized. Do not merge
unrelated feature/ordering changes or silently follow moving branches/nightly builds.
