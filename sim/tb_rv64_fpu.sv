`timescale 1ns/1ps

module tb_rv64_fpu;
  import rv64_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic start_i;
  fp_op_t op_i;
  fp_fmt_t fmt_i;
  fp_fmt_t src_fmt_i;
  fp_int_fmt_t int_fmt_i;
  logic [1:0] fma_op_i;
  logic [2:0] rm_i;
  logic [63:0] a_i, b_i, c_i, x_i;
  logic ready_o, busy_o, done_o;
  logic [63:0] result_o, int_result_o;
  logic [4:0] flags_o;
  integer completed;

  rv64_fpu dut (
    .clk_i,
    .rst_ni,
    .start_i,
    .op_i,
    .fmt_i,
    .src_fmt_i,
    .int_fmt_i,
    .fma_op_i,
    .rm_i,
    .a_i,
    .b_i,
    .c_i,
    .x_i,
    .ready_o,
    .busy_o,
    .done_o,
    .result_o,
    .int_result_o,
    .flags_o
  );

  always #5 clk_i = ~clk_i;

  task automatic execute(
    input fp_op_t op,
    input fp_fmt_t fmt,
    input fp_fmt_t src_fmt,
    input fp_int_fmt_t int_fmt,
    input logic [1:0] fma_op,
    input logic [2:0] rm,
    input logic [63:0] a,
    input logic [63:0] b,
    input logic [63:0] c,
    input logic [63:0] x,
    input logic [63:0] expected_result,
    input logic [63:0] expected_int,
    input logic [4:0] expected_flags,
    input logic expect_long,
    input [8*36-1:0] name
  );
    integer cycles;
    begin
      while (!ready_o || done_o) begin
        @(posedge clk_i);
        #1;
      end

      op_i = op;
      fmt_i = fmt;
      src_fmt_i = src_fmt;
      int_fmt_i = int_fmt;
      fma_op_i = fma_op;
      rm_i = rm;
      a_i = a;
      b_i = b;
      c_i = c;
      x_i = x;
      start_i = 1'b1;
      @(posedge clk_i);
      #1;
      start_i = 1'b0;
      // A multi-cycle request owns its inputs after the launch handshake.
      if ((op == FP_DIV) || (op == FP_SQRT)) begin
        a_i = 64'b0;
        b_i = 64'b0;
      end
      if (!busy_o)
        $fatal(1, "%0s did not enter busy state", name);
      if (done_o)
        $fatal(1, "%0s completed in its launch cycle", name);

      cycles = 0;
      while (!done_o) begin
        @(posedge clk_i);
        #1;
        cycles = cycles + 1;
        if (cycles > 200)
          $fatal(1, "%0s timed out", name);
      end
      if (expect_long && cycles < 2)
        $fatal(1, "%0s was not multi-cycle", name);
      if (result_o !== expected_result)
        $fatal(1, "%0s result got %h expected %h", name, result_o,
               expected_result);
      if (int_result_o !== expected_int)
        $fatal(1, "%0s integer result got %h expected %h", name,
               int_result_o, expected_int);
      if (flags_o !== expected_flags)
        $fatal(1, "%0s flags got %b expected %b", name, flags_o,
               expected_flags);
      completed = completed + 1;

      @(posedge clk_i);
      #1;
      if (done_o)
        $fatal(1, "%0s done pulse lasted more than one cycle", name);
    end
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    start_i = 1'b0;
    op_i = FP_NONE;
    fmt_i = FP_FMT_S;
    src_fmt_i = FP_FMT_S;
    int_fmt_i = FP_INT_W;
    fma_op_i = 2'b00;
    rm_i = 3'b000;
    a_i = 64'b0;
    b_i = 64'b0;
    c_i = 64'b0;
    x_i = 64'b0;
    completed = 0;

    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);
    #1;

    // Basic arithmetic and single-precision NaN boxing.
    execute(FP_ADD, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b00, 3'b000,
            64'hffff_ffff_3fc0_0000, 64'hffff_ffff_4010_0000, 0, 0,
            64'hffff_ffff_4070_0000, 0, 0, 0, "fadd.s");
    execute(FP_SUB, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b00, 3'b000,
            64'hffff_ffff_4070_0000, 64'hffff_ffff_3fa0_0000, 0, 0,
            64'hffff_ffff_4020_0000, 0, 0, 0, "fsub.s");
    execute(FP_ADD, FP_FMT_D, FP_FMT_D, FP_INT_W, 2'b00, 3'b000,
            64'h3ff8_0000_0000_0000, 64'h4002_0000_0000_0000, 0, 0,
            64'h400e_0000_0000_0000, 0, 0, 0, "fadd.d");
    execute(FP_MUL, FP_FMT_D, FP_FMT_D, FP_INT_W, 2'b00, 3'b000,
            64'h3ff8_0000_0000_0000, 64'h4002_0000_0000_0000, 0, 0,
            64'h400b_0000_0000_0000, 0, 0, 0, "fmul.d");

    // The four HardFloat op encodings directly represent the RISC-V FMA set.
    execute(FP_FMA, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b00, 3'b000,
            64'hffff_ffff_4000_0000, 64'hffff_ffff_4040_0000,
            64'hffff_ffff_4080_0000, 0, 64'hffff_ffff_4120_0000, 0, 0, 0,
            "fmadd.s");
    execute(FP_FMA, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b01, 3'b000,
            64'hffff_ffff_4000_0000, 64'hffff_ffff_4040_0000,
            64'hffff_ffff_4080_0000, 0, 64'hffff_ffff_4000_0000, 0, 0, 0,
            "fmsub.s");
    execute(FP_FMA, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b10, 3'b000,
            64'hffff_ffff_4000_0000, 64'hffff_ffff_4040_0000,
            64'hffff_ffff_4080_0000, 0, 64'hffff_ffff_c000_0000, 0, 0, 0,
            "fnmsub.s");
    execute(FP_FMA, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b11, 3'b000,
            64'hffff_ffff_4000_0000, 64'hffff_ffff_4040_0000,
            64'hffff_ffff_4080_0000, 0, 64'hffff_ffff_c120_0000, 0, 0, 0,
            "fnmadd.s");
    execute(FP_FMA, FP_FMT_D, FP_FMT_D, FP_INT_W, 2'b00, 3'b000,
            64'h4000_0000_0000_0000, 64'h4008_0000_0000_0000,
            64'h4010_0000_0000_0000, 0, 64'h4024_0000_0000_0000, 0, 0, 0,
            "fmadd.d");

    // divSqrtRecFN_small must hold busy until the selected format completes.
    execute(FP_DIV, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b00, 3'b000,
            64'hffff_ffff_40e0_0000, 64'hffff_ffff_4000_0000, 0, 0,
            64'hffff_ffff_4060_0000, 0, 0, 1, "fdiv.s");
    execute(FP_SQRT, FP_FMT_D, FP_FMT_D, FP_INT_W, 2'b00, 3'b000,
            64'h4022_0000_0000_0000, 0, 0, 0,
            64'h4008_0000_0000_0000, 0, 0, 1, "fsqrt.d");
    execute(FP_DIV, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b00, 3'b000,
            64'hffff_ffff_3f80_0000, 64'hffff_ffff_0000_0000, 0, 0,
            64'hffff_ffff_7f80_0000, 0, 5'b01000, 0, "fdiv.s_dz");
    execute(FP_SQRT, FP_FMT_S, FP_FMT_S, FP_INT_W, 2'b00, 3'b000,
            64'hffff_ffff_bf80_0000, 0, 0, 0,
            64'hffff_ffff_7fc0_0000, 0, 5'b10000, 0, "fsqrt.s_nv");

    // Sign injection and min/max retain bit patterns while honoring signed zero.
    execute(FP_SGNJ, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            64'hffff_ffff_3fc0_0000, 64'hffff_ffff_c000_0000, 0, 0,
            64'hffff_ffff_bfc0_0000, 0, 0, 0, "fsgnj.s");
    execute(FP_SGNJN, FP_FMT_D, FP_FMT_D, FP_INT_W, 0, 0,
            64'h3ff8_0000_0000_0000, 64'hc000_0000_0000_0000, 0, 0,
            64'h3ff8_0000_0000_0000, 0, 0, 0, "fsgnjn.d");
    execute(FP_SGNJX, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            64'hffff_ffff_bfc0_0000, 64'hffff_ffff_c000_0000, 0, 0,
            64'hffff_ffff_3fc0_0000, 0, 0, 0, "fsgnjx.s");
    execute(FP_MIN, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            64'hffff_ffff_0000_0000, 64'hffff_ffff_8000_0000, 0, 0,
            64'hffff_ffff_8000_0000, 0, 0, 0, "fmin.s_zero");
    execute(FP_MAX, FP_FMT_D, FP_FMT_D, FP_INT_W, 0, 0,
            64'h0000_0000_0000_0000, 64'h8000_0000_0000_0000, 0, 0,
            64'h0000_0000_0000_0000, 0, 0, 0, "fmax.d_zero");
    execute(FP_MIN, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            64'hffff_ffff_7f80_0001, 64'hffff_ffff_4040_0000, 0, 0,
            64'hffff_ffff_4040_0000, 0, 5'b10000, 0, "fmin.s_snan");

    // Comparisons and FCLASS follow the RISC-V-specific NaN behavior.
    execute(FP_CMP_EQ, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            64'hffff_ffff_7fc0_0000, 64'hffff_ffff_3f80_0000, 0, 0,
            0, 0, 0, 0, "feq.s_qnan");
    execute(FP_CMP_LT, FP_FMT_D, FP_FMT_D, FP_INT_W, 0, 0,
            64'h7ff8_0000_0000_0000, 64'h3ff0_0000_0000_0000, 0, 0,
            0, 0, 5'b10000, 0, "flt.d_qnan");
    execute(FP_CLASS, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            64'hffff_ffff_8000_0001, 0, 0, 0, 0, 64'h4, 0, 0,
            "fclass.s_negative_subnormal");
    execute(FP_CLASS, FP_FMT_D, FP_FMT_D, FP_INT_W, 0, 0,
            64'hbff0_0000_0000_0000, 0, 0, 0, 0, 64'h2, 0, 0,
            "fclass.d_negative_normal");

    // Raw moves deliberately bypass NaN-box checking, unlike FP arithmetic.
    execute(FP_MOVE_F2X, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            64'h0000_0000_8123_4567, 0, 0, 0, 0,
            64'hffff_ffff_8123_4567, 0, 0, "fmv.x.w_raw");
    execute(FP_MOVE_X2F, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            0, 0, 0, 64'h1234_5678_89ab_cdef,
            64'hffff_ffff_89ab_cdef, 0, 0, 0, "fmv.w.x_box");
    execute(FP_MOVE_F2X, FP_FMT_D, FP_FMT_D, FP_INT_W, 0, 0,
            64'h8123_4567_89ab_cdef, 0, 0, 0, 0,
            64'h8123_4567_89ab_cdef, 0, 0, "fmv.x.d_raw");

    // Conversions cover W/WU/L/LU selection, result extension, and rounding.
    execute(FP_CVT_F2I, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 3'b000,
            64'hffff_ffff_4070_0000, 0, 0, 0, 0, 64'h4, 5'b00001, 0,
            "fcvt.w.s_rne");
    execute(FP_CVT_F2I, FP_FMT_D, FP_FMT_D, FP_INT_WU, 0, 3'b000,
            64'hbff4_0000_0000_0000, 0, 0, 0, 0, 0, 5'b10000, 0,
            "fcvt.wu.d_negative");
    execute(FP_CVT_I2F, FP_FMT_S, FP_FMT_S, FP_INT_L, 0, 3'b000,
            0, 0, 0, 64'd16777217, 64'hffff_ffff_4b80_0000, 0, 5'b00001, 0,
            "fcvt.s.l_rne");
    execute(FP_CVT_I2F, FP_FMT_S, FP_FMT_S, FP_INT_L, 0, 3'b100,
            0, 0, 0, 64'd16777217, 64'hffff_ffff_4b80_0001, 0, 5'b00001, 0,
            "fcvt.s.l_rmm");
    execute(FP_CVT_I2F, FP_FMT_D, FP_FMT_D, FP_INT_LU, 0, 3'b000,
            0, 0, 0, 64'hffff_ffff_ffff_ffff,
            64'h43f0_0000_0000_0000, 0, 5'b00001, 0, "fcvt.d.lu");
    execute(FP_CVT_F2F, FP_FMT_S, FP_FMT_D, FP_INT_W, 0, 3'b000,
            64'h3ff8_0000_0000_0000, 0, 0, 0,
            64'hffff_ffff_3fc0_0000, 0, 0, 0, "fcvt.s.d");
    execute(FP_CVT_F2F, FP_FMT_D, FP_FMT_S, FP_INT_W, 0, 3'b000,
            64'hffff_ffff_3fc0_0000, 0, 0, 0,
            64'h3ff8_0000_0000_0000, 0, 0, 0, "fcvt.d.s");

    // Invalid NaN-boxed S input becomes canonical qNaN without an NV flag.
    execute(FP_ADD, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 0,
            64'h0000_0000_3fc0_0000, 64'hffff_ffff_4010_0000, 0, 0,
            64'hffff_ffff_7fc0_0000, 0, 0, 0, "fadd.s_bad_box");
    execute(FP_DIV, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 3'b000,
            64'hffff_ffff_0080_0000, 64'hffff_ffff_4040_0000, 0, 0,
            64'hffff_ffff_002a_aaab, 0, 5'b00011, 1, "fdiv.s_underflow");
    execute(FP_MUL, FP_FMT_S, FP_FMT_S, FP_INT_W, 0, 3'b000,
            64'hffff_ffff_7f7f_ffff, 64'hffff_ffff_4000_0000, 0, 0,
            64'hffff_ffff_7f80_0000, 0, 5'b00101, 0, "fmul.s_overflow");

    $display("RV64F/D wrapper PASS: completed=%0d", completed);
    $finish;
  end
endmodule
