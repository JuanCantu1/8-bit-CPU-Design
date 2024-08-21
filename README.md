# 8-bit CPU Design

## Overview
This project demonstrates the design and implementation of a simple 8-bit CPU using Verilog. The CPU architecture is composed of key components including an Arithmetic Logic Unit (ALU), Control Unit, Register File, and Data Memory. This project is an educational tool designed to provide insights into the fundamental operations and structure of a CPU.

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

- **PC:** 
  - This does...
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/ProgramCounter/PC%20Simulation1.jpg" alt="Program Counter Results">
  </div>

- **IM:** 
  - This does...
  
  <div align="center">
    <img src="https://github.com/JuanCantu1/8-bit-CPU-Design/blob/main/CPU%20Design/InstructionMemory/InstructionMemory%20Simulation1.jpg" alt="Instruction Memory Results">
  </div>
  
## Simulations and Testing
Each component was rigorously tested through simulations to verify functionality and ensure correct operation within the CPU design. The simulation results, as shown above, provide detailed insights into the behavior and performance of individual components.

## Conclusion
This 8-bit CPU design project offers a comprehensive exploration of CPU architecture, serving as a practical example for those interested in digital system design and computer architecture. The project showcases the integration of various components into a cohesive system capable of executing basic instructions.
