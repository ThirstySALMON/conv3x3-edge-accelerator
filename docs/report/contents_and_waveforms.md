## Contents

This report follows the order of the deliverables listed in the competition announcement.

| Section | Covers |
|---|---|
| 1. Accelerator Architecture | What the core does, the control/datapath split, interface, and the three decisions taken to serve the Figure of Merit |
| 2. Block Diagram | Top-level structure and the signals crossing between control and datapath |
| 3. Datapath | The arithmetic chain: nine multipliers, the adder tree, the three pipeline stages, and the measured slack in each |
| 4. Control FSM | The five states, frame bookkeeping, the registered edge flags, and how stalls are handled |
| 5. Memory Organization | Where every bit of state lives, and why no block RAM is used anywhere |
| 6. Line-Buffer and Window-Generation Method | The two line buffers, the nine taps, zero padding, and where the 34-cycle fill latency comes from |
| 7. Fixed-Point Bit-Width Analysis | Why each width is what it is, and how overflow is handled |
| 8. RTL Implementation Details | File-by-file inventory, coding decisions, and the build scripts |
| 9. Testbench and Verification | The four testbenches, the 22-run regression, and the comparison against the reference model |
| 10. Golden Reference Model | What the Python model computes and how the expected outputs are generated |
| 11. Waveform Screenshots | Simulation evidence for latency, throughput, stalls, padding and the frame sequence |
| 12. FPGA Synthesis and Implementation Results | Utilization, how zero DSP and zero BRAM were achieved, reproducibility |
| 13. Timing Report | Slack, maximum frequency, the critical path, and why I/O paths are excluded |
| 14. Power Report | Static, dynamic and total power, and the switching-activity methodology behind them |
| 15. Discussion of Design Tradeoffs | The alternatives considered, including one change that was reverted |
| 16. Figure of Merit | The calculation, the interpretations it rests on, and the required summary table |
| 17. Assumptions | Everything assumed where the specification was silent |
| 18. Bonus Features | Which bonuses are claimed, with the evidence, and which is not |
| 19. Conclusion | Results, what the design does well, and what was learned |
| Appendix A | The submitted files and how to reproduce the results |
