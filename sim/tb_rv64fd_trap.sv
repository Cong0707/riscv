`timescale 1ns/1ps

// Core-level precision checks for floating-point exceptions and misalignment.
module tb_rv64fd_trap;
  localparam logic [63:0] RESET_PC = 64'h0000_0000_8000_0000;
  localparam logic [63:0] MISALIGNED_ADDR = RESET_PC + 64'd257;

  logic clk_i;
  logic rst_ni;
  logic i_valid_o, i_ready_i;
  logic [63:0] i_addr_o;
  logic [31:0] i_rdata_i;
  logic d_valid_o, d_write_o, d_ready_i;
  logic [63:0] d_addr_o, d_wdata_o, d_rdata_i;
  logic [7:0] d_wstrb_o;
  logic [63:0] debug_pc_o;
  logic halted_o, trap_valid_o;
  logic [63:0] trap_cause_o, trap_tval_o;

  integer scenario;
  integer cycle_count;
  integer data_count;
  integer completed;

  rv64_core #(.RESET_PC(RESET_PC)) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .i_valid_o(i_valid_o),
    .i_addr_o(i_addr_o),
    .i_ready_i(i_ready_i),
    .i_rdata_i(i_rdata_i),
    .d_valid_o(d_valid_o),
    .d_write_o(d_write_o),
    .d_addr_o(d_addr_o),
    .d_wdata_o(d_wdata_o),
    .d_wstrb_o(d_wstrb_o),
    .d_ready_i(d_ready_i),
    .d_rdata_i(d_rdata_i),
    .debug_pc_o(debug_pc_o),
    .halted_o(halted_o),
    .trap_valid_o(trap_valid_o),
    .trap_cause_o(trap_cause_o),
    .trap_tval_o(trap_tval_o)
  );

  always #5 clk_i = ~clk_i;

  always_comb begin
    i_ready_i = i_valid_o;
    i_rdata_i = 32'h0000_0013; // NOP
    case (scenario)
      1: begin // Reserved dynamic frm must trap before the FADD starts.
        case (i_addr_o - RESET_PC)
          64'h00: i_rdata_i = 32'h3f80_00b7; // LUI x1, 0x3f800
          64'h04: i_rdata_i = 32'hf000_80d3; // FMV.W.X f1, x1
          64'h08: i_rdata_i = 32'h0022_d073; // CSRRWI x0, frm, 5
          64'h0c: i_rdata_i = 32'h0010_f153; // FADD.S f2, f1, f1, dyn
          64'h10: i_rdata_i = 32'hf000_8253; // Younger FMV.W.X f4, x1
          default: begin end
        endcase
      end
      2: begin // Older FDIV result and DZ flag must retire before younger trap.
        case (i_addr_o - RESET_PC)
          64'h00: i_rdata_i = 32'h3f80_00b7; // LUI x1, 0x3f800
          64'h04: i_rdata_i = 32'hf000_80d3; // FMV.W.X f1, x1
          64'h08: i_rdata_i = 32'hf000_0153; // FMV.W.X f2, x0
          64'h0c: i_rdata_i = 32'h1820_81d3; // FDIV.S f3, f1, f2, RNE
          64'h10: i_rdata_i = 32'hffff_ffff; // Illegal instruction
          64'h14: i_rdata_i = 32'hf000_8253; // Younger FMV.W.X f4, x1
          default: begin end
        endcase
      end
      3, 4, 5, 6: begin
        case (i_addr_o - RESET_PC)
          64'h00: i_rdata_i = 32'h0000_0097; // AUIPC x1, 0
          64'h04: i_rdata_i = 32'h1010_8093; // ADDI x1, x1, 257
          64'h08: begin
            case (scenario)
              3: i_rdata_i = 32'h0000_a087; // FLW f1, 0(x1)
              4: i_rdata_i = 32'h0000_b087; // FLD f1, 0(x1)
              5: i_rdata_i = 32'h0000_a027; // FSW f0, 0(x1)
              6: i_rdata_i = 32'h0000_b027; // FSD f0, 0(x1)
              default: begin end
            endcase
          end
          default: begin end
        endcase
      end
      default: begin end
    endcase

    d_ready_i = d_valid_o;
    d_rdata_i = 64'b0;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      data_count <= 0;
    end else if (d_valid_o && d_ready_i) begin
      data_count <= data_count + 1;
      $fatal(1,
             "scenario %0d issued a data transaction before its trap: write=%b addr=%h data=%h strobe=%h",
             scenario, d_write_o, d_addr_o, d_wdata_o, d_wstrb_o);
    end
  end

  task automatic run_scenario(
    input integer selected,
    input logic [63:0] expected_cause,
    input logic [63:0] expected_tval
  );
    begin
      @(negedge clk_i);
      scenario = selected;
      rst_ni = 1'b0;
      repeat (5) @(posedge clk_i);
      @(negedge clk_i);
      rst_ni = 1'b1;

      cycle_count = 0;
      while ((trap_valid_o !== 1'b1) && (cycle_count < 200)) begin
        @(posedge clk_i);
        cycle_count = cycle_count + 1;
      end
      #1;

      if ((halted_o !== 1'b1) || (trap_valid_o !== 1'b1) ||
          (trap_cause_o !== expected_cause) ||
          (trap_tval_o !== expected_tval))
        $fatal(1,
               "scenario %0d trap mismatch: halted=%b valid=%b cause=%h tval=%h pc=%h cycles=%0d",
               selected, halted_o, trap_valid_o, trap_cause_o, trap_tval_o,
               debug_pc_o, cycle_count);
      if (data_count != 0)
        $fatal(1, "scenario %0d produced %0d data transactions",
               selected, data_count);

      case (selected)
        1: begin
          if (dut.frm_q !== 3'd5)
            $fatal(1, "reserved frm write did not retire: frm=%b", dut.frm_q);
          if (dut.fregfile.regs[1] !== 64'hffff_ffff_3f80_0000)
            $fatal(1, "older FMV.W.X did not retire: f1=%h",
                   dut.fregfile.regs[1]);
          if ((dut.fregfile.regs[2] !== 64'b0) ||
              (dut.fregfile.regs[4] !== 64'b0) || (dut.fflags_q !== 5'b0))
            $fatal(1, "faulting/younger FP state changed: f2=%h f4=%h flags=%b",
                   dut.fregfile.regs[2], dut.fregfile.regs[4], dut.fflags_q);
        end
        2: begin
          if (dut.fregfile.regs[3] !== 64'hffff_ffff_7f80_0000)
            $fatal(1, "older FDIV result did not retire: f1=%h f2=%h f3=%h flags=%b",
                   dut.fregfile.regs[1], dut.fregfile.regs[2],
                   dut.fregfile.regs[3], dut.fflags_q);
          if (dut.fflags_q !== 5'b0_1000)
            $fatal(1, "older FDIV DZ flag did not retire: flags=%b",
                   dut.fflags_q);
          if (dut.fregfile.regs[4] !== 64'b0)
            $fatal(1, "younger FP result survived the trap: f4=%h",
                   dut.fregfile.regs[4]);
        end
        3, 4: begin
          if (dut.fregfile.regs[1] !== 64'b0)
            $fatal(1, "misaligned FP load wrote f1: scenario=%0d f1=%h",
                   selected, dut.fregfile.regs[1]);
        end
        default: begin end
      endcase

      completed = completed + 1;
    end
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    scenario = 0;
    cycle_count = 0;
    completed = 0;

    run_scenario(1, 64'd2, 64'h0000_0000_0010_f153);
    run_scenario(2, 64'd2, 64'h0000_0000_ffff_ffff);
    run_scenario(3, 64'd4, MISALIGNED_ADDR);
    run_scenario(4, 64'd4, MISALIGNED_ADDR);
    run_scenario(5, 64'd6, MISALIGNED_ADDR);
    run_scenario(6, 64'd6, MISALIGNED_ADDR);

    $display("RV64F/D precise trap PASS: completed=%0d", completed);
    $finish;
  end
endmodule
