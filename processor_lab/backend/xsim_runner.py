"""
Hardened XSim invocation for lab_runner.py.

ROOT CAUSE (confirmed via manual repro): xsim's Tcl layer treats backslash
as an escape character. A raw Windows path (C:\\Users\\...) passed to
-tclbatch/-log gets silently mangled -- e.g. "\\b" is interpreted as an
actual backspace character -- producing a corrupted, nonexistent path.
When `source` on that mangled path fails, xsim does NOT exit; it drops
into its interactive "xsim%" prompt and waits on stdin forever. That wait
is what was being misread as a 45-second hang. Forward slashes avoid the
mangling entirely, and closing stdin is a defensive backstop so that even
if xsim ever ends up at that prompt again for some other reason, it hits
EOF and exits immediately instead of hanging.

Secondary hardening (kept as a backstop, not the primary fix):
  - A previously-killed/hung run can leave a stale .Xil lock directory in
    sim_dir, which can make a *new* xsim invocation hang before it even
    opens its log. Cleared before every run.
  - RDI_DATADIR is set explicitly in the subprocess's own environment
    rather than relying on inheritance.
  - On an actual timeout (should be rare now), the whole process tree is
    killed via `taskkill /T /F`, since a plain subprocess timeout only
    terminates the immediate cmd.exe child, not xsim.exe/xsimk.exe
    underneath it.
  - program.mem backup/restore is wrapped in try/finally.

Drop `run_simulation(...)` in place of the current XSim call in
lab_runner.py.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Optional


class SimulationTimeout(Exception):
    """XSim did not finish within the allotted time and was force-killed."""


class SimulationError(Exception):
    """XSim ran and exited, but with a non-zero return code."""


def _to_tcl_path(path: Path) -> str:
    """Convert a Windows path to forward slashes for safe use in any
    xsim argument that flows through its Tcl layer (-tclbatch, -log)."""
    return str(path).replace("\\", "/")


# ---- process cleanup -------------------------------------------------

def _kill_process_tree(pid: int) -> None:
    """Kill a process and all descendants on Windows. Best-effort: never
    raises, since this is already cleanup code running after a failure."""
    try:
        subprocess.run(
            ["taskkill", "/PID", str(pid), "/T", "/F"],
            capture_output=True,
            timeout=10,
        )
    except Exception:
        pass
    # Fallback sweep: xsimk.exe sometimes detaches from the tree taskkill
    # /T sees, especially under cmd.exe /d /c wrapping.
    for name in ("xsim.exe", "xsimk.exe"):
        try:
            subprocess.run(
                ["taskkill", "/F", "/IM", name],
                capture_output=True,
                timeout=10,
            )
        except Exception:
            pass


def _clear_stale_xsim_state(sim_dir: Path) -> None:
    """Remove lock/scratch artifacts a previously killed run may have left
    behind. A stale .Xil directory is a common cause of a *new* xsim
    invocation hanging before it ever opens its log."""
    xil_dir = sim_dir / ".Xil"
    if xil_dir.exists():
        shutil.rmtree(xil_dir, ignore_errors=True)
    for stale_name in ("xsim_run.log", "xsim_run.jou", "xsim_run_stdout.log", "run_and_exit.tcl"):
        stale_path = sim_dir / stale_name
        if stale_path.exists():
            try:
                stale_path.unlink()
            except OSError:
                pass


def _extract(pattern: str, text: str) -> Optional[str]:
    m = re.search(pattern, text, re.IGNORECASE)
    return m.group(1) if m else None


# ---- program.mem backup/restore --------------------------------------

def _backup_program_mem(program_mem_path: Path) -> Optional[Path]:
    if not program_mem_path.exists():
        return None
    backup_path = program_mem_path.with_suffix(program_mem_path.suffix + ".bak")
    shutil.copy2(program_mem_path, backup_path)
    return backup_path


def _restore_program_mem(program_mem_path: Path, backup_path: Optional[Path]) -> None:
    try:
        if backup_path and backup_path.exists():
            shutil.copy2(backup_path, program_mem_path)
            backup_path.unlink()
    except Exception:
        # Restoration failing shouldn't mask the original simulation result/error.
        pass


# ---- main entry point --------------------------------------------------

def run_simulation(
    sim_dir: Path,
    xsim_bat: Path,
    vivado_data_dir: Path,
    program_mem_path: Path,
    sim_top: str = "tb_program_behav",
    run_time_ns: int = 1000,
    timeout_s: int = 45,
) -> dict:
    """
    Runs the existing tb_program_behav XSim simulation and returns a dict:
        { "stdout": str, "log": str, "x10": str|None, "pc": str|None }

    Raises SimulationTimeout or SimulationError on failure. In both cases,
    as much diagnostic log content as could be captured is included in the
    exception message. program.mem is always restored from backup before
    this function returns or raises.
    """
    sim_dir = Path(sim_dir)
    log_path = sim_dir / "xsim_run.log"
    tcl_path = sim_dir / "run_and_exit.tcl"

    backup_path = _backup_program_mem(program_mem_path)

    try:
        _clear_stale_xsim_state(sim_dir)
        tcl_path.write_text(f"run {run_time_ns}ns\nexit\n", encoding="ascii")

        env = os.environ.copy()
        env["RDI_DATADIR"] = str(vivado_data_dir)

        # Forward slashes are required here -- see module docstring. Using
        # str(path) directly (Windows backslashes) is what caused xsim to
        # silently fail to source the tclbatch file and drop into its
        # interactive prompt instead of exiting.
        args = [
            "cmd.exe", "/d", "/c",
            str(xsim_bat), sim_top,
            "-tclbatch", _to_tcl_path(tcl_path),
            "-log", _to_tcl_path(log_path),
        ]

        stdout_path = sim_dir / "xsim_run_stdout.log"
        with open(stdout_path, "w", encoding="utf-8", errors="ignore") as out_f:
            proc = subprocess.Popen(
                args,
                cwd=str(sim_dir),
                env=env,
                stdout=out_f,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,  # backstop: EOF instead of hanging
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,  # Windows only
            )

            try:
                proc.wait(timeout=timeout_s)
            except subprocess.TimeoutExpired:
                _kill_process_tree(proc.pid)
                time.sleep(0.5)  # let Windows release the log file handle
                log_tail = (
                    log_path.read_text(errors="ignore")[-4000:]
                    if log_path.exists()
                    else "(no log file was created before the timeout)"
                )
                raise SimulationTimeout(
                    f"XSim did not finish within {timeout_s} seconds and was stopped.\n"
                    f"--- last log contents ---\n{log_tail}"
                )

        stdout_text = stdout_path.read_text(errors="ignore") if stdout_path.exists() else ""

        if proc.returncode != 0:
            log_tail = log_path.read_text(errors="ignore")[-4000:] if log_path.exists() else ""
            raise SimulationError(
                f"xsim exited with code {proc.returncode}.\n"
                f"--- stdout ---\n{stdout_text}\n"
                f"--- log ---\n{log_tail}"
            )

        log_text = log_path.read_text(errors="ignore") if log_path.exists() else stdout_text

        return {
            "stdout": stdout_text,
            "log": log_text,
            "x10": _extract(r"x10\s*=\s*([0-9a-fA-Fx]+)", log_text),
            "pc": _extract(r"PC\s*=\s*([0-9a-fA-Fx]+)", log_text),
        }

    finally:
        _restore_program_mem(program_mem_path, backup_path)
