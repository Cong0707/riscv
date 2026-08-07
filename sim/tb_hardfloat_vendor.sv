`timescale 1ns/1ps

module tb_hardfloat_vendor;
  logic clk;
  logic rst_n;
  logic div_valid;

  logic [32:0] f32_a_rec;
  logic [32:0] f32_b_rec;
  logic [32:0] f32_add_rec;
  logic [4:0]  f32_add_flags;
  logic [31:0] f32_add_bits;

  logic [64:0] f64_a_rec;
  logic [64:0] f64_b_rec;
  logic        f64_div_ready;
  logic        f64_div_out_valid;
  logic        f64_div_sqrt_out;
  logic [64:0] f64_div_rec;
  logic [4:0]  f64_div_flags;
  logic [63:0] f64_div_bits;

  always #5 clk = ~clk;

  fNToRecFN #(8, 24) recode_f32_a(
    .in(32'h3fc0_0000),
    .out(f32_a_rec)
  );
  fNToRecFN #(8, 24) recode_f32_b(
    .in(32'h4010_0000),
    .out(f32_b_rec)
  );
  addRecFN #(8, 24) add_f32(
    .control(1'b1),
    .subOp(1'b0),
    .a(f32_a_rec),
    .b(f32_b_rec),
    .roundingMode(3'b000),
    .out(f32_add_rec),
    .exceptionFlags(f32_add_flags)
  );
  recFNToFN #(8, 24) decode_f32_add(
    .in(f32_add_rec),
    .out(f32_add_bits)
  );

  fNToRecFN #(11, 53) recode_f64_a(
    .in(64'h4002_0000_0000_0000),
    .out(f64_a_rec)
  );
  fNToRecFN #(11, 53) recode_f64_b(
    .in(64'h4010_0000_0000_0000),
    .out(f64_b_rec)
  );
  divSqrtRecFN_small #(11, 53, 0) div_f64(
    .nReset(rst_n),
    .clock(clk),
    .control(1'b1),
    .inReady(f64_div_ready),
    .inValid(div_valid),
    .sqrtOp(1'b0),
    .a(f64_a_rec),
    .b(f64_b_rec),
    .roundingMode(3'b000),
    .outValid(f64_div_out_valid),
    .sqrtOpOut(f64_div_sqrt_out),
    .out(f64_div_rec),
    .exceptionFlags(f64_div_flags)
  );
  recFNToFN #(11, 53) decode_f64_div(
    .in(f64_div_rec),
    .out(f64_div_bits)
  );

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    div_valid = 1'b0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    if (f32_add_bits !== 32'h4070_0000 || f32_add_flags !== 5'b0)
      $fatal(1, "HardFloat F32 add mismatch: result=%h flags=%b",
             f32_add_bits, f32_add_flags);
    if (!f64_div_ready)
      $fatal(1, "HardFloat F64 divide unit did not become ready");

    @(negedge clk);
    div_valid = 1'b1;
    @(negedge clk);
    div_valid = 1'b0;
    while (!f64_div_out_valid) @(posedge clk);
    #1;

    if (f64_div_sqrt_out !== 1'b0)
      $fatal(1, "HardFloat F64 divide returned sqrt tag");
    if (f64_div_bits !== 64'h3fe2_0000_0000_0000 ||
        f64_div_flags !== 5'b0)
      $fatal(1, "HardFloat F64 divide mismatch: result=%h flags=%b",
             f64_div_bits, f64_div_flags);

    $display("HardFloat vendor PASS: f32_add=%h f64_div=%h",
             f32_add_bits, f64_div_bits);
    $finish;
  end
endmodule
