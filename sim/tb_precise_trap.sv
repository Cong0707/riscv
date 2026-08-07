`timescale 1ns/1ps

module tb_precise_trap;
  localparam logic [63:0] RESET_PC = 64'h0000_0000_8000_0000;

  logic clk_i;
  logic rst_ni;
  logic i_valid_o;
  logic [63:0] i_addr_o;
  logic i_ready_i;
  logic [31:0] i_rdata_i;
  logic d_valid_o;
  logic d_write_o;
  logic [63:0] d_addr_o;
  logic [63:0] d_wdata_o;
  logic [7:0] d_wstrb_o;
  logic d_ready_i;
  logic [63:0] d_rdata_i;
  logic [63:0] debug_pc_o;
  logic halted_o;
  logic trap_valid_o;
  logic [63:0] trap_cause_o;
  logic [63:0] trap_tval_o;
  integer cycle_count;
  integer data_count;

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
    case (i_addr_o - RESET_PC)
      64'h0: i_rdata_i = 32'h07b0_0293; // ADDI x5, x0, 123
      64'h4: i_rdata_i = 32'hffff_ffff; // Illegal instruction
      64'h8: i_rdata_i = 32'h0050_3023; // Younger SD must be flushed
      default: i_rdata_i = 32'h0000_0013;
    endcase
    d_ready_i = d_valid_o;
    d_rdata_i = 64'b0;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      data_count <= 0;
    end else if (d_valid_o && d_ready_i) begin
      data_count <= data_count + 1;
      $fatal(1, "younger instruction issued data transaction: write=%b addr=%h data=%h strobe=%h",
             d_write_o, d_addr_o, d_wdata_o, d_wstrb_o);
    end
  end

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    cycle_count = 0;
    data_count = 0;

    repeat (5) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    while ((trap_valid_o !== 1'b1) && cycle_count < 20) begin
      @(posedge clk_i);
      cycle_count = cycle_count + 1;
    end
    #1;

    if (halted_o !== 1'b1 || trap_valid_o !== 1'b1 ||
        trap_cause_o !== 64'd2 || trap_tval_o !== 64'hffff_ffff)
      $fatal(1, "unexpected trap: halted=%b valid=%b cause=%h tval=%h pc=%h",
             halted_o, trap_valid_o, trap_cause_o, trap_tval_o, debug_pc_o);
    if (dut.regfile.regs[5] !== 64'd123)
      $fatal(1, "trap became visible before older WB retired: x5=%h",
             dut.regfile.regs[5]);
    if (data_count != 0)
      $fatal(1, "younger instruction produced %0d data transactions", data_count);

    $display("Precise trap PASS: cycles=%0d x5=%0d cause=%0d tval=%h data=%0d",
             cycle_count, dut.regfile.regs[5], trap_cause_o,
             trap_tval_o, data_count);
    $finish;
  end
endmodule
