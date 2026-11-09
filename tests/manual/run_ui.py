#!/usr/bin/env python3
"""Opt-in integration probe with an attached Neovim UI and a 45s phase deadline.

Requires the test-only msgpack package and separately installed config, scope and
Catppuccin checkouts. Never loads private local configuration or installs plugins.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import tempfile
import threading
import time

import msgpack

ROOT = Path(__file__).resolve().parents[2]


def run_phase(nvim, phase, env, cwd):
    replies, grids = queue.Queue(), {}
    deadline = time.monotonic() + 45
    with tempfile.TemporaryFile() as errors, subprocess.Popen(
        [nvim, '--embed', '--headless', '--noplugin', '-u', 'NONE', '-i', 'NONE'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
        env=env, cwd=cwd, bufsize=0, start_new_session=os.name != 'nt',
    ) as process:
        def read():
            try:
                for packet in msgpack.Unpacker(process.stdout, raw=False, read_size=4096):
                    if packet[0] == 1:
                        replies.put(packet)
                    elif packet[:2] == [2, 'redraw']:
                        for event in packet[2]:
                            for args in event[1:]:
                                if event[0] == 'grid_resize':
                                    grid, width, height = args
                                    grids[grid] = [[' '] * width for _ in range(height)]
                                elif event[0] == 'grid_line':
                                    grid, row, col, cells = args[:4]
                                    for cell in cells:
                                        for _ in range(cell[2] if len(cell) > 2 else 1):
                                            grids[grid][row][col] = cell[0]
                                            col += 1
                                elif event[0] == 'grid_clear':
                                    for row in grids[args[0]]:
                                        row[:] = [' '] * len(row)
                replies.put(RuntimeError('Neovim exited before replying'))
            except Exception as error:
                replies.put(error)

        thread = threading.Thread(target=read, daemon=True)
        thread.start()
        serial = 0

        def rpc(method, args):
            nonlocal serial
            serial += 1
            process.stdin.write(msgpack.packb([0, serial, method, args]))
            reply = replies.get(timeout=max(0.01, deadline - time.monotonic()))
            if isinstance(reply, Exception):
                raise reply
            if reply[1] != serial or reply[2] is not None:
                raise RuntimeError(str(reply))
            return reply[3]

        try:
            rpc('nvim_ui_attach', [180, 60, {'ext_linegrid': True}])
            result = rpc('nvim_exec_lua', [
                'local path, phase = ...; arg = {phase}; return dofile(path)',
                [str(ROOT / 'tests/manual/ui_probe.lua'), phase],
            ])
            if result.get('mouse_probe'):
                rpc('nvim_input_mouse', ['right', 'press', '', 0, 0, result['column']])
                # Let Neovim's normal input loop dispatch the queued mouse event.
                for _ in range(20):
                    time.sleep(0.02)
                    if rpc('nvim_exec_lua', ['return vim.api.nvim_win_get_config(0).relative == "editor"', []]):
                        break
                rpc('nvim_ui_try_resize', [48, 20])
                result = rpc('nvim_exec_lua', ['return finish_bufferline_ui_probe()', []])
            result['screen'] = [''.join(row).rstrip() for row in grids.get(1, [])]
            return result
        finally:
            if process.poll() is None:
                if os.name == 'nt':
                    process.kill()
                else:
                    os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
            thread.join(timeout=1)
            errors.seek(0)
            stderr = errors.read().decode(errors='replace')
            if stderr:
                print(stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--nvim', required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--scope', type=Path, required=True)
    parser.add_argument('--theme', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--phases', default='scoped,global,save,restore')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.pop('NVIM', None)
    env['NVIM_APPNAME'] = 'nvim'
    env.update(BUFFERLINE_ROOT=str(ROOT), BUFFERLINE_CONFIG_ROOT=str(args.config.resolve()),
               BUFFERLINE_SCOPE=str(args.scope.resolve()), BUFFERLINE_THEME=str(args.theme.resolve()),
               BUFFERLINE_ICONS=str(ROOT / '.tests/site/pack/deps/start/nvim-web-devicons'))
    with tempfile.TemporaryDirectory(prefix='bufferline-ui-') as directory:
        root = Path(directory)
        env['BUFFERLINE_PROBE_DIR'] = directory
        env['NVIM_LOG_FILE'] = str(root / 'nvim.log')
        for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            path = root / kind
            path.mkdir()
            env['XDG_' + kind + '_HOME'] = str(path)
        for phase in args.phases.split(','):
            result = run_phase(args.nvim, phase, env, args.config)
            (args.output / (phase + '.json')).write_text(json.dumps(result, ensure_ascii=False, indent=2))
            print(json.dumps({k: v for k, v in result.items() if k != 'screen'}), flush=True)


if __name__ == '__main__':
    main()
