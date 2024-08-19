# 8-bit CPU Design

## Overview
This project implements a simple 8-bit CPU using Verilog. The design includes an ALU, Control Unit, Register File, and Memory units, enabling the CPU to perform basic arithmetic and logical operations. This project serves as an educational tool for understanding the fundamental components and operations of a CPU.

## Architecture
The CPU is designed with a modular approach, with each component responsible for a specific task. The primary components include the ALU, Control Unit, Register File, and Data Memory.

<div align="center">
  <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/Schematic.jpg" alt="CPU Block Diagram">
</div>

### Key Components

- **ALU (Arithmetic Logic Unit):** 
  - Responsible for performing arithmetic and logic operations.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/ALU/ALU%20Simulation2%20.jpg" alt="ALU Simulation Results">
  </div>

- **Control Unit:** 
  - Manages instruction decoding and generates control signals for CPU operations.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/ControlUnit/ControlUnit%20Simulation1.jpg" alt="Control Unit Simulation Results">
  </div>

- **Register File:** 
  - Stores temporary data for the ALU and other components during CPU operations.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/RegisterFile/RegFile%20Simulation1.jpg" alt="Register File Simulation Results">
  </div>

- **Data Memory:** 
  - Holds data for load/store operations, interfacing with the CPU for memory-related instructions.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/DataMemory/DataMemory%20Simulation1.jpg" alt="Data Memory Simulation Results">
  </div>
