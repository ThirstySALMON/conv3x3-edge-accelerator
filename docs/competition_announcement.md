## Solid-State Circuits Society (SSCS)

## Egypt Chapter

## 2026 Student Design Competition

The IEEE Solid State Circuit Society - Egypt Chapter is organizing a student design competition in the summer of 2026. This contest asks students to design an FPGA-based Edge-AI vision accelerator with the specifications given below. The accelerator should perform NxN CNN convolution for a small grayscale image or feature map. Monetary awards will be provided for the top three designs. The registration deadline is July 25th, 2026. Register your team (1-4 students) by filling the form before the deadline in: https://forms.gle/qQUpg3hM5ZgPPDgw8 [URL 🔗](https://forms.gle/qQUpg3hM5ZgPPDgw8)

## Eligibility Criteria

The competition is particularly intended for undergraduate students from public, private, or national universities within Egypt. Students graduating this year are not qualified to enter the competition. Each team may include 1-4 students. A team may use Verilog, SystemVerilog, VHDL, or any HDL; however, the submitted report must clearly explain the digital architecture and implementation decisions.

## Competition Technical Details

This competition aims to design, verify, synthesize, and optionally demonstrate a NxN CNN convolution accelerator for Edge-AI vision applications. The accelerator designs will be compared based on correctness, digital design quality, FPGA resource usage, latency, throughput, timing closure, and power estimate, given that all mandatory specifications are met. Target applications include edge smart devices.

## Required Specifications for the FPGA-Based Edge-AI Vision Accelerator

- 1. Input image size: The accelerator should support a minimum input image or feature-map size of 32 × 32 pixels. Larger input sizes are allowed. The input is assumed to be a grayscale image or a single-channel feature map.

- 2. Input precision: The input pixel or activation values should be represented using fixed point unsigned data. Teams must justify the chosen precision in the report.

- 3. Kernel size: The accelerator should implement an N × N convolution kernel. The kernel coefficients should be programmable or configurable.

- 4. Kernel precision: The kernel coefficients should be represented using 8-bit signed fixed-point or integer values.

- 5. Stride: The convolution should use a stride of 1.


- 6. Output precision: The output feature-map values should use a minimum precision of 16-bit signed data. Wider output precision is allowed. Teams must explain how overflow, truncation, saturation, or rounding is handled.

- 7. Activation function: ReLU activation is optional and will be considered a bonus feature. It may be used as a simple post-processing step for edge-AI vision applications.

- 8. Verification: The design must be verified against a golden reference model implemented in Python, MATLAB, or C. The report should include test cases, expected outputs, hardware outputs, and a comparison showing correctness.

- 9. FPGA implementation results: Teams must provide FPGA synthesis and implementation results, including LUTs, FFs, DSPs, BRAMs, maximum frequency, timing status, and estimated power. A board demonstration is optional and will be treated as a bonus.

- 10. Figure of Merit: Teams should report the following Figure of Merit:

where throughput is measured in output pixels per cycle. A higher FoM indicates a more efficient design.

## Instructions

- 1. Clearly describe the datapath, control FSM, memory/buffer organization, window generation, and/or fixed- point arithmetic.

- 2. Verify the RTL against a Python, MATLAB, or C++ golden reference model using multiple test cases.

- 3. Report FPGA utilization, timing, maximum frequency, latency, throughput, power estimate, and FoM.

- 4. Assume any missing information, but state all assumptions clearly in the report.

## Deliverables

You should submit a report that demonstrates your ability in digital design. The report must include the accelerator architecture, block diagram, datapath, FSM state diagram, memory organization, line-buffer or window-generation method, fixed-point bit-width analysis, RTL implementation details, testbench, golden model, waveform screenshots, FPGA synthesis results, timing report, power report, and discussion of design tradeoffs. The table should look like Table 2.

*Table 1. Required Table Format*

| Parameter | Specification | Team Result | Units | Comments |
| --- | --- | --- | --- | --- |
| Input image size |   |   |   |   |
| Input precision |   |   |   |   |
| Kernel precision |   |   |   |   |
| Architecture type |   |   |   |   |
| Multipliers / MACs |   |   |   |   |
| Pipeline stages |   |   |   |   |


|   | Latency |   |   |   |   |   |
| --- | --- | --- | --- | --- | --- | --- |
|   | Throughput |   |   |   |   |   |
|   | FPGA utilization |   |   |   |   |   |
|   | Maximum frequency |   |   |   |   |   |
|   | Power estimate |   |   |   |   |   |
|   | Verification status |   |   |   |   |   |
|   | FOM |   |   |   |   |   |

In addition to the report, each team should submit the RTL source files, the testbench, the golden model, input test images or feature maps, expected output files, FPGA reports, and a short presentation. Optional bonus items include a board demonstration, one-output-pixel-per-cycle pipelined architecture, support for multiple kernels, ReLU activation, or a simple edge-detection/industrial-inspection demo.

## Timeline for submission

Students should submit a report summarizing their designs by September 15, 2026. The winners will be announced by September 30, 2026.

## Awards

Gold Award: 350 USD

Silver Award: 250 USD

Bronze Award: 150 USD
