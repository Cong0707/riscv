`timescale 1ns/1ps

// FLEN=64 floating-point register file. Unlike x0, f0 is an ordinary register.
module rv64_fregfile (
  input  logic        clk,
  input  logic        rst,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [63:0] wdata,
  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  input  logic [4:0]  raddr3,
  output logic [63:0] rdata1,
  output logic [63:0] rdata2,
  output logic [63:0] rdata3
);

  logic [63:0] regs [0:31];
  integer i;

  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < 32; i = i + 1)
        regs[i] <= 64'b0;
    end else if (we) begin
      regs[waddr] <= wdata;
    end
  end

  always_comb begin
    rdata1 = regs[raddr1];
    rdata2 = regs[raddr2];
    rdata3 = regs[raddr3];
  end

endmodule
