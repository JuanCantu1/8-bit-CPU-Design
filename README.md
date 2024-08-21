# 8-bit CPU Design

## Overview
This project showcases the design and implementation of a simple 8-bit CPU using Verilog. The CPU architecture is modular, with key components such as the Arithmetic Logic Unit (ALU), Control Unit, Register File, and Data Memory working together to perform basic arithmetic, logic, and control operations. This project serves as an educational tool for understanding the fundamental operations and structure of a CPU.

## Architecture
The CPU is designed with a modular approach, where each component is responsible for specific tasks that collectively enable the CPU to perform basic arithmetic, logic, and control operations. The following diagram provides a high-level overview of the CPU's architecture:

<div align="center">
  <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/Schematic.jpg" alt="CPU Block Diagram">
</div>

### Key Components

- **ALU (Arithmetic Logic Unit):** 
  - Responsible for performing essential arithmetic (addition, subtraction, etc.) and logic (AND, OR, NOT, etc.) operations. The ALU is a critical component in executing instructions and manipulating data within the CPU.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/ALU/ALU%20Simulation2%20.jpg" alt="ALU Simulation Results">
  </div>

- **Control Unit:** 
  - Decodes instructions and generates the necessary control signals to manage the operations of the CPU. It orchestrates the actions of other components based on the instructions fetched from memory.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/ControlUnit/ControlUnit%20Simulation1.jpg" alt="Control Unit Simulation Results">
  </div>

- **Register File:** 
  - A set of registers used to store intermediate data and operands required by the ALU and other CPU components. It provides quick access to frequently used data, enhancing CPU performance.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/RegisterFile/RegFile%20Simulation1.jpg" alt="Register File Simulation Results">
  </div>

- **Data Memory:** 
  - Interfaces with the CPU to store and retrieve data during load/store operations. It serves as the main memory unit, enabling data persistence across different stages of CPU operations.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/DataMemory/DataMemory%20Simulation1.jpg" alt="Data Memory Simulation Results">
  </div>

- **Program Counter (PC):** 
  - The Program Counter keeps track of the address of the next instruction to be executed. It increments automatically or jumps to a specific address during branch instructions.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/ProgramCounter/PC%20Simulation1.jpg" alt="Program Counter Results">
  </div>

- **IInstruction Memory (IM):** 
  - Instruction Memory stores the instructions to be executed by the CPU. The Control Unit fetches instructions from this memory based on the Program Counter's value.
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/InstructionMemory/InstructionMemory%20Simulation1.jpg" alt="Instruction Memory Results">
  </div>
  
## Simulations and Testing
Each component was thoroughly tested through simulations to verify its functionality and ensure correct integration within the CPU design. The simulation results presented above illustrate the behavior and performance of the individual components.

## Conclusion
This 8-bit CPU design project offers a practical exploration of CPU architecture, making it a valuable resource for those interested in digital system design and computer architecture. The project demonstrates how various components are integrated into a functioning CPU capable of executing basic instructions.
