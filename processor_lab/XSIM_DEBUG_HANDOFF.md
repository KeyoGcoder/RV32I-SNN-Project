# XSim Integration Debug Handoff — RV32I Processor Lab

## Goal

Run a user-submitted bare-metal C program on an existing RV32I Vivado/XSim simulation from a Python FastAPI backend. Compilation succeeds. XSim starts but the backend invocation times out after 45 seconds without producing useful output.

## Project locations

```text
Project root:
C:\Users\Asus\Documents\RV32I_SNN_Project

Lab backend:
C:\Users\Asus\Documents\RV32I_SNN_Project\processor_lab\backend\lab_runner.py

Existing XSim simulation directory:
C:\Users\Asus\Documents\RV32I_SNN_Project\RISC_V_SNN\RISC_V_SNN.sim\sim_1\behav\xsim

Existing simulation top:
tb_program_behav
```

## What already works

- The frontend reaches the FastAPI backend.
- `riscv-none-elf-gcc` compiles supplied C with `-march=rv32i -mabi=ilp32`.
- The backend produces valid disassembly and a 32-bit-word, hex-per-line `program.mem`.
- `program.mem` is compatible with the Verilog instruction memory.
- The existing testbench reports `x10` (C return value) and PC after a 1,000 ns run.
- The backend backs up and restores the Vivado project `program.mem` after each run.

## Processor/testbench details

`rtl/instruction_memory.v` loads:

```verilog
$readmemh("C:/Users/Asus/Documents/RV32I_SNN_Project/RISC_V_SNN/program.mem", memory);
```

`tb_program.v` drives reset, waits 1,000 ns, then prints:

```verilog
$display("PROGRAM EXECUTION COMPLETE");
$display("x10 = %h", dut.u_register_file.registers[10]);
$display("PC  = %h", dut.u_pc.pc_out);
$finish;
```

The generated Vivado `tb_program.tcl` contains only:

```tcl
run 1000ns
```

## Vivado installation found

```text
D:\2025.2\Vivado\settings64.bat
D:\2025.2\Vivado\bin\xsim.bat
D:\2025.2\Vivado\bin\unwrapped\win64.o\xsim.exe
D:\2025.2\Vivado\data
```

`where /r D:\ xsim.exe` found only the unwrapped executable path above.

## Environment/backend start used

```bat
cd C:\Users\Asus\Documents\RV32I_SNN_Project\processor_lab
call D:\2025.2\Vivado\settings64.bat
set "XSIM=D:\2025.2\Vivado\bin\xsim.bat"
python -m uvicorn main:app --app-dir backend --reload
```

Earlier, calling the unwrapped executable required manually setting:

```bat
set "RDI_DATADIR=D:\2025.2\Vivado\data"
```

Without this it emitted: `ERROR: The RDI_DATADIR environment variable is not set.`

## Current backend behavior

The relevant current simulation logic is:

```python
def command(args: list[str], cwd: Path) -> str:
    completed = subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=45)
    if completed.returncode:
        raise RuntimeError((completed.stdout + completed.stderr).strip())
    return completed.stdout + completed.stderr

# The backend writes this temporary Tcl file:
tcl.write_text("run 1000ns\nexit\n", encoding="ascii")

xsim_args = ["tb_program_behav", "-tclbatch", str(tcl), "-log", str(run_dir / "xsim.log")]
simulator_command = ["cmd.exe", "/d", "/c", xsim, *xsim_args]
output = command(simulator_command, sim_dir)
```

`sim_dir` is the XSim simulation directory listed above. `xsim` is set to `D:\2025.2\Vivado\bin\xsim.bat`.

## Current failure

The frontend status response is:

```json
{
  "status": "failed",
  "message": "Command '['D:\\\\2025.2\\\\Vivado\\\\bin\\\\unwrapped\\\\win64.o\\\\xsim.exe', 'tb_program_behav', '-tclbatch', 'C:\\\\Users\\\\Asus\\\\Documents\\\\RV32I_SNN_Project\\\\processor_lab\\\\runs\\\\run-o1e3pdx0\\\\run_and_exit.tcl', '-log', 'C:\\\\Users\\\\Asus\\\\Documents\\\\RV32I_SNN_Project\\\\processor_lab\\\\runs\\\\run-o1e3pdx0\\\\xsim.log']' timed out after 45 seconds"
}
```

Before switching to the `.bat` wrapper, the raw executable invocation timed out in the same way. In both cases, the generated run folder contained compilation artifacts but `xsim.log` was empty or absent. The Uvicorn process can hang while waiting for the spawned simulator; terminating it may require closing the terminal or running `taskkill /F /IM xsim.exe`.

## Important notes

- Do **not** modify verified RTL modules or testbench interfaces unless absolutely necessary.
- Prefer a backend-only change.
- The normal Vivado-generated `simulate.bat` in `sim_dir` calls:

```bat
call xsim tb_program_behav -key {Behavioral:sim_1:Functional:tb_program} -tclbatch tb_program.tcl -view C:/Users/Asus/Documents/RV32I_SNN_Project/RISC_V_SNN/tb_program_behav1.wcfg -log simulate.log
```

- A manual/automated solution must capture simulator stdout or logs, return the testbench `x10` and PC, and reliably terminate.

## Requested diagnosis/fix

Please determine the correct, reliable Windows command/subprocess invocation for Vivado 2025.2 XSim in this situation. In particular:

1. Why does XSim appear to start but hang without writing a log under this Python-launched batch invocation?
2. Should the backend call `simulate.bat`, `xsim.bat`, `xsim` through PATH, `vivado -mode batch`, or a different command pattern?
3. What exact command should be tested manually from `sim_dir` first?
4. Provide a minimal, safe Python implementation that has a finite timeout, kills child processes on timeout, and captures useful diagnostics.
5. Preserve the existing Vivado project and restore `RISC_V_SNN/program.mem` after each run.
