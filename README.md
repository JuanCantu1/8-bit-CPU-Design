# 8-bit CPU Design

## Overview
This project implements a simple 8-bit CPU using Verilog. It features an ALU, Control Unit, Register File, and Memory units, capable of performing basic arithmetic and logical operations. The design is intended as an educational tool for understanding the fundamental components and operation of a CPU.

## Architecture
The CPU is designed with a modular approach, each component handling specific tasks within the system. The primary components include the ALU, Control Unit, Register File, and Data Memory.

![CPU Block Diagram](https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/Schematic.jpg)

### Key Components

- **ALU (Arithmetic Logic Unit):** 
  - Responsible for performing arithmetic and logic operations.
    ![ALU Simulation Results](https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/ALU/ALU%20Simulation2%20.jpg)

- **Control Unit:** 
  - Manages instruction decoding and the control signals necessary for executing operations within the CPU.
    ![Control Unit Simulation Results](https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/ControlUnit/ControlUnit%20Simulation1.jpg)

- **Register File:** 
  - Stores temporary data for use by the ALU and other components during CPU operations.
    ![Register File Simulation Results](https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/RegisterFile/RegFile%20Simulation1.jpg)

- **Data Memory:** 
  - Holds data for load/store operations, interfacing with the CPU for memory-related instructions.
    ![Data Memory Simulation Results](https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/DataMemory/DataMemory%20Simulation1.jpg)
