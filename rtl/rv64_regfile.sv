`timescale 1ns/1ps

module rv64_regfile (
  input  logic        clk,
  input  logic        rst,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [63:0] wdata,
  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [63:0] rdata1,
  output logic [63:0] rdata2
);

  logic [63:0] regs [0:31];
  integer i;

  // Synchronous reset and write; x0 is hard-wired to zero.
  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < 32; i = i + 1) begin
        regs[i] <= 64'b0;
      end
    end else begin
      if (we && (waddr != 5'd0)) begin
        regs[waddr] <= wdata;
      end
      regs[0] <= 64'b0;
    end
  end

  always_comb begin
    if (raddr1 == 5'd0) begin
      rdata1 = 64'b0;
    end else begin
      rdata1 = regs[raddr1];
    end

    if (raddr2 == 5'd0) begin
      rdata2 = 64'b0;
    end else begin
      rdata2 = regs[raddr2];
    end
  end

endmodule
