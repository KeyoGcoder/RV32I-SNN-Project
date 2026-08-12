"""Compile bare-metal RV32I C and optionally execute the existing XSim model."""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(os.environ.get("RV32I_PROJECT_ROOT", r"C:\Users\Asus\Documents\RV32I_SNN_Project"))
GCC = os.environ.get("RISCV_GCC", "riscv-none-elf-gcc")
OBJDUMP = os.environ.get("RISCV_OBJDUMP", "riscv-none-elf-objdump")
OBJCOPY = os.environ.get("RISCV_OBJCOPY", "riscv-none-elf-objcopy")


def command(args: list[str], cwd: Path) -> str:
    # Vivado's Windows launcher can spawn child processes. subprocess.run()
    # only terminates its immediate parent on timeout, leaving xsim alive and
    # the web request stuck while its output pipes remain open.
    process = subprocess.Popen(
        args,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        stdin=subprocess.DEVNULL,
    )
    try:
        stdout, stderr = process.communicate(timeout=45)
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, text=True)
        else:
            process.kill()
        stdout, stderr = process.communicate()
        raise RuntimeError("XSim did not finish within 45 seconds and was stopped. See the backend terminal/log for details.")
    if process.returncode:
        raise RuntimeError((stdout + stderr).strip() or f"Command failed with exit code {process.returncode}.")
    return stdout + stderr


def make_mem(binary: bytes) -> str:
    if len(binary) > 1024:
        raise ValueError("Program is too large: instruction memory holds at most 1024 bytes.")
    binary += b"\0" * (-len(binary) % 4)
    return "\n".join(f"{int.from_bytes(binary[i:i + 4], 'little'):08x}" for i in range(0, len(binary), 4)) + "\n"


def xsim_path() -> str | None:
    configured = os.environ.get("XSIM")
    if configured and Path(configured).exists():
        return configured
    return shutil.which("xsim")


def run_simulation(mem: str, run_dir: Path) -> dict:
    xsim = xsim_path()
    project_mem = PROJECT_ROOT / "RISC_V_SNN" / "program.mem"
    if not xsim:
        return {"status": "not_run", "message": "XSim was not found on PATH. Set XSIM to Vivado's xsim executable, then run again."}
    if not project_mem.exists():
        return {"status": "not_run", "message": f"Expected Vivado memory image is missing: {project_mem}"}
    backup = project_mem.read_bytes()
    try:
        project_mem.write_text(mem, encoding="ascii")
        sim_dir = PROJECT_ROOT / "RISC_V_SNN" / "RISC_V_SNN.sim" / "sim_1" / "behav" / "xsim"
        # The Vivado-generated tb_program.tcl only issues `run 1000ns`.
        # Add `exit` so a batch invocation does not remain open after $finish.
        tcl = run_dir / "run_and_exit.tcl"
        # Use "run -all" instead of a fixed "run 1000ns": tb_program.v calls
        # $finish itself once it's done, so this runs exactly until that
        # point rather than risking a fixed window cutting off the
        # testbench's own $display output (x10/PC) right at the boundary.
        tcl.write_text("run -all\nexit\n", encoding="ascii")
        # xsim's Tcl layer treats backslash as an escape character, so a raw
        # Windows path here (C:\Users\...) gets silently mangled -- e.g. "\b"
        # becomes an actual backspace -- producing a corrupted path. `source`
        # then fails and xsim drops into its interactive "xsim%" prompt
        # instead of exiting, which is what was showing up as a 45s hang.
        # Forward slashes avoid the mangling entirely.
        tcl_arg = str(tcl).replace("\\", "/")
        log_arg = str(run_dir / "xsim.log").replace("\\", "/")
        xsim_args = ["tb_program_behav", "-tclbatch", tcl_arg, "-log", log_arg]
        # On Windows, launch Vivado's supported .bat wrapper through cmd.exe.
        # Calling it directly from subprocess can leave its loader detached/hung.
        simulator_command = (["cmd.exe", "/d", "/c", xsim, *xsim_args]
                             if xsim.lower().endswith(".bat") else [xsim, *xsim_args])
        output = command(simulator_command, sim_dir)
        match = re.search(r"x10\s*=\s*([0-9a-fA-F]+).*?PC\s*=\s*([0-9a-fA-F]+)", output, re.S)
        result = {"status": "completed", "log": output}
        if match:
            result.update({"x10_hex": "0x" + match.group(1), "x10_decimal": int(match.group(1), 16), "pc": "0x" + match.group(2)})
        return result
    except Exception as exc:
        return {"status": "failed", "message": str(exc)}
    finally:
        project_mem.write_bytes(backup)


def run_program(source: str) -> dict:
    if not shutil.which(GCC):
        return {"status": "failed", "error": f"Compiler not found: {GCC}"}
    runs = PROJECT_ROOT / "processor_lab" / "runs"
    runs.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=runs))
    source_file, elf, binary = run_dir / "program.c", run_dir / "program.elf", run_dir / "program.bin"
    source_file.write_text(source, encoding="utf-8")
    startup, linker = PROJECT_ROOT / "build" / "startup.s", PROJECT_ROOT / "build" / "link.ld"
    try:
        command([GCC, "-march=rv32i", "-mabi=ilp32", "-O0", "-ffreestanding", "-fno-builtin", "-nostdlib", "-nostartfiles", "-Wl,-T," + str(linker), "-Wl,--gc-sections", "-o", str(elf), str(startup), str(source_file)], run_dir)
        assembly = command([OBJDUMP, "-d", "-M", "no-aliases,numeric", str(elf)], run_dir)
        command([OBJCOPY, "-O", "binary", "-j", ".text", str(elf), str(binary)], run_dir)
        mem = make_mem(binary.read_bytes())
        (run_dir / "program.mem").write_text(mem, encoding="ascii")
        simulation = run_simulation(mem, run_dir)
        return {"status": "compiled", "run_directory": str(run_dir), "assembly": assembly, "machine_code": mem, "simulation": simulation}
    except Exception as exc:
        return {"status": "failed", "run_directory": str(run_dir), "error": str(exc)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run C code on the RV32I XSim testbench")
    parser.add_argument("source", type=Path, help="Bare-metal C source containing main()")
    args = parser.parse_args()
    import json
    print(json.dumps(run_program(args.source.read_text(encoding="utf-8")), indent=2))
