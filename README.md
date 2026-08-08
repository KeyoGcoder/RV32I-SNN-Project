# RV32I SNN FPGA Project

Incremental development workspace for an RV32I RISC-V processor in Verilog, targeting Vivado-based FPGA implementation. The planned architecture is a five-stage pipeline, extended later with the `SPIKE.ACC` and `EVENT.SKIP` instructions for spiking-neural-network inference.

## Repository layout

| Folder | Purpose |
| --- | --- |
| `rtl/` | Synthesizable Verilog source. The initial module shells live here. |
| `tb/` | Simulation-only Verilog testbench shells, one per RTL module. |
| `constraints/` | FPGA pin, clock, and timing constraint files (for example, `.xdc`). |
| `docs/` | Architecture notes, ISA-extension specifications, and verification plans. |
| `images/` | Diagrams and figures used by documentation. |
| `programs/` | RV32I assembly programs, test binaries, and memory initialization images. |
| `reports/` | Synthesis, implementation, timing, and simulation reports. |
| `scripts/` | Reproducible Vivado, simulation, and build automation scripts. |

## Initial RTL shells

The source files intentionally contain only empty module declarations. They establish stable module boundaries before functionality is added incrementally.

| Module | Role to be implemented later |
| --- | --- |
| `top` | Top-level processor and FPGA integration. |
| `pc` | Program-counter state and next-PC selection. |
| `instruction_memory` | Instruction storage and fetch interface. |
| `register_file` | RV32I integer register storage and ports. |
| `alu` | Integer arithmetic and logical operations. |
| `immediate_generator` | Immediate decoding for RV32I instruction formats. |
| `control_unit` | Instruction decode and pipeline control signals. |
| `data_memory` | Load/store data-memory interface. |

Each module has a corresponding `tb/tb_<module>.v` testbench shell. Add interfaces and behavior only when implementing that module's dedicated milestone.
