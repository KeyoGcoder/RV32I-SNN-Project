# RISC-V Processor Lab

This isolated demo compiles a C file containing `main()` for the existing 256-word RV32I memory, writes the little-endian hexadecimal `program.mem` format used by `rtl/instruction_memory.v`, and runs the existing `tb_program` XSim executable when it is available.

## Command-line smoke test

From this folder, run:

```powershell
python backend/lab_runner.py examples/return_8.c
```

The generated run folder contains `program.c`, ELF, binary, assembly listing, and `program.mem`. The runner restores the original Vivado `RISC_V_SNN/program.mem` after each simulation.

## Web UI

Install the backend packages in an environment with Python, then run `uvicorn main:app --app-dir backend --reload`. Serve `frontend` with any static HTTP server and open it in a browser. Configure `XSIM` to the full path of `xsim.exe` if Vivado has not added it to PATH.

Only the instructions implemented by the current processor are reliable; the compiler may emit unsupported instructions for complex C programs.
