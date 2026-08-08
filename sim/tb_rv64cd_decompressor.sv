`timescale 1ns/1ps

module tb_rv64cd_decompressor;
  logic [15:0] instr_i;
  logic [31:0] instr_o;
  logic legal_o;
  integer completed;

  rv64c_decompressor dut (.*);

  function automatic logic [31:0] encode_i(
    input logic [11:0] imm,
    input logic [4:0] rs1,
    input logic [4:0] rd
  );
    encode_i = {imm, rs1, 3'b011, rd, 7'b0000111};
  endfunction

  function automatic logic [31:0] encode_s(
    input logic [11:0] imm,
    input logic [4:0] rs2,
    input logic [4:0] rs1
  );
    encode_s = {imm[11:5], rs2, rs1, 3'b011, imm[4:0], 7'b0100111};
  endfunction

  task automatic check(
    input logic [15:0] compressed,
    input logic [31:0] expected,
    input string name
  );
    begin
      instr_i = compressed;
      #1;
      if (!legal_o || (instr_o !== expected))
        $fatal(1, "%s got legal=%b instr=%08h expected=%08h", name,
               legal_o, instr_o, expected);
      completed = completed + 1;
    end
  endtask

  initial begin
    completed = 0;
    instr_i = 16'b0;

    // Prime-register forms, including the maximum 248-byte scaled offset.
    check(16'b001_000_001_00_000_00, encode_i(12'd0, 5'd9, 5'd8),
          "c.fld");
    check(16'b001_111_001_11_000_00, encode_i(12'd248, 5'd9, 5'd8),
          "c.fld max offset");
    check(16'b101_000_001_00_010_00, encode_s(12'd0, 5'd10, 5'd9),
          "c.fsd");

    // Stack forms permit f0 because floating register zero is not hardwired.
    check(16'b001_0_00000_00000_10, encode_i(12'd0, 5'd2, 5'd0),
          "c.fldsp f0");
    check(16'b001_1_00011_11111_10, encode_i(12'd504, 5'd2, 5'd3),
          "c.fldsp max offset");
    check(16'b101_000000_00101_10, encode_s(12'd0, 5'd5, 5'd2),
          "c.fsdsp");
    check(16'b101_111111_00101_10, encode_s(12'd504, 5'd5, 5'd2),
          "c.fsdsp max offset");

    $display("RV64C+D decompressor PASS: completed=%0d", completed);
    $finish;
  end
endmodule
