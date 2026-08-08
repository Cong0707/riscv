`timescale 1ns/1ps

// Blocking RV64F/RV64D execution wrapper around Berkeley HardFloat.
// Architectural values use IEEE bit encodings; recFN stays inside this unit.
module rv64_fpu (
  input  logic                      clk_i,
  input  logic                      rst_ni,
  input  logic                      start_i,
  input  rv64_pkg::fp_op_t          op_i,
  input  rv64_pkg::fp_fmt_t         fmt_i,
  input  rv64_pkg::fp_fmt_t         src_fmt_i,
  input  rv64_pkg::fp_int_fmt_t     int_fmt_i,
  input  logic [1:0]                fma_op_i,
  input  logic [2:0]                rm_i,
  input  logic [63:0]               a_i,
  input  logic [63:0]               b_i,
  input  logic [63:0]               c_i,
  input  logic [63:0]               x_i,
  output logic                      ready_o,
  output logic                      busy_o,
  output logic                      done_o,
  output logic [63:0]               result_o,
  output logic [63:0]               int_result_o,
  output logic [4:0]                flags_o
);

  localparam logic [31:0] S_CANONICAL_NAN = 32'h7fc0_0000;
  localparam logic [63:0] D_CANONICAL_NAN = 64'h7ff8_0000_0000_0000;

  logic [31:0] a_s_bits, b_s_bits, c_s_bits;
  logic [63:0] a_d_bits, b_d_bits, c_d_bits;
  logic [32:0] a_s_rec, b_s_rec, c_s_rec;
  logic [64:0] a_d_rec, b_d_rec, c_d_rec;

  logic [32:0] s_add_rec, s_mul_rec, s_fma_rec;
  logic [64:0] d_add_rec, d_mul_rec, d_fma_rec;
  logic [4:0] s_add_flags, s_mul_flags, s_fma_flags;
  logic [4:0] d_add_flags, d_mul_flags, d_fma_flags;
  logic [31:0] s_add_bits, s_mul_bits, s_fma_bits;
  logic [63:0] d_add_bits, d_mul_bits, d_fma_bits;

  logic [32:0] s_div_rec;
  logic [64:0] d_div_rec;
  logic [32:0] s_div_a_q, s_div_b_q;
  logic [64:0] d_div_a_q, d_div_b_q;
  logic [31:0] s_div_a_bits_q, s_div_b_bits_q;
  logic [63:0] d_div_a_bits_q, d_div_b_bits_q;
  logic [32:0] s_div_a, s_div_b;
  logic [64:0] d_div_a, d_div_b;
  logic [4:0] s_div_flags, d_div_flags;
  logic [31:0] s_div_bits;
  logic [63:0] d_div_bits;
  logic s_div_ready, d_div_ready;
  logic s_div_valid, d_div_valid;
  logic s_div_done, d_div_done;

  logic s_cmp_lt, s_cmp_eq, s_cmp_gt;
  logic d_cmp_lt, d_cmp_eq, d_cmp_gt;
  logic [4:0] s_cmp_flags, d_cmp_flags;

  logic [32:0] s_i32s_rec, s_i32u_rec, s_i64s_rec, s_i64u_rec;
  logic [64:0] d_i32s_rec, d_i32u_rec, d_i64s_rec, d_i64u_rec;
  logic [4:0] s_i32s_flags, s_i32u_flags, s_i64s_flags, s_i64u_flags;
  logic [4:0] d_i32s_flags, d_i32u_flags, d_i64s_flags, d_i64u_flags;
  logic [31:0] s_i32s_bits, s_i32u_bits, s_i64s_bits, s_i64u_bits;
  logic [63:0] d_i32s_bits, d_i32u_bits, d_i64s_bits, d_i64u_bits;

  logic [31:0] s_f2i32;
  logic [63:0] s_f2i64;
  logic [31:0] d_f2i32;
  logic [63:0] d_f2i64;
  logic [2:0] s_f2i32_flags, s_f2i64_flags;
  logic [2:0] d_f2i32_flags, d_f2i64_flags;
  logic f2i_signed;

  logic [64:0] s_to_d_rec;
  logic [32:0] d_to_s_rec;
  logic [4:0] s_to_d_flags, d_to_s_flags;
  logic [63:0] s_to_d_bits;
  logic [31:0] d_to_s_bits;

  logic active_q, div_active_q, div_issued_q, div_sqrt_q, done_q;
  rv64_pkg::fp_fmt_t div_fmt_q;
  logic [2:0] div_rm_q;
  logic [63:0] result_q, int_result_q;
  logic [4:0] flags_q;
  logic div_selected_done;
  logic div_selected_ready;
  logic div_request_ready;
  logic operation_is_divsqrt;
  logic div_sqrt;
  logic [2:0] div_rm;
  logic accept;
  logic [63:0] comb_result;
  logic [63:0] comb_int_result;
  logic [4:0] comb_flags;

  function automatic logic is_snan_s(input logic [30:0] value);
    is_snan_s = (&value[30:23]) && (|value[22:0]) && !value[22];
  endfunction

  function automatic logic is_nan_s(input logic [30:0] value);
    is_nan_s = (&value[30:23]) && (|value[22:0]);
  endfunction

  function automatic logic is_snan_d(input logic [62:0] value);
    is_snan_d = (&value[62:52]) && (|value[51:0]) && !value[51];
  endfunction

  function automatic logic is_nan_d(input logic [62:0] value);
    is_nan_d = (&value[62:52]) && (|value[51:0]);
  endfunction

  function automatic logic [9:0] classify_s(input logic [31:0] value);
    logic sign;
    logic exp_zero;
    logic exp_one;
    logic frac_zero;
    begin
      sign = value[31];
      exp_zero = (value[30:23] == 8'b0);
      exp_one = (&value[30:23]);
      frac_zero = (value[22:0] == 0);
      classify_s = 10'b0;
      if (exp_one && frac_zero)
        classify_s[sign ? 0 : 7] = 1'b1;
      else if (exp_one)
        classify_s[is_snan_s(value[30:0]) ? 8 : 9] = 1'b1;
      else if (exp_zero && !frac_zero)
        classify_s[sign ? 2 : 5] = 1'b1;
      else if (exp_zero)
        classify_s[sign ? 3 : 4] = 1'b1;
      else
        classify_s[sign ? 1 : 6] = 1'b1;
    end
  endfunction

  function automatic logic [9:0] classify_d(input logic [63:0] value);
    logic sign;
    logic exp_zero;
    logic exp_one;
    logic frac_zero;
    begin
      sign = value[63];
      exp_zero = (value[62:52] == 11'b0);
      exp_one = (&value[62:52]);
      frac_zero = (value[51:0] == 0);
      classify_d = 10'b0;
      if (exp_one && frac_zero)
        classify_d[sign ? 0 : 7] = 1'b1;
      else if (exp_one)
        classify_d[is_snan_d(value[62:0]) ? 8 : 9] = 1'b1;
      else if (exp_zero && !frac_zero)
        classify_d[sign ? 2 : 5] = 1'b1;
      else if (exp_zero)
        classify_d[sign ? 3 : 4] = 1'b1;
      else
        classify_d[sign ? 1 : 6] = 1'b1;
    end
  endfunction

  function automatic logic [4:0] map_int_flags(input logic [2:0] value);
    logic invalid;
    begin
      // HardFloat reports {invalid, overflow, inexact}.  RISC-V FCVT maps
      // NaN and out-of-range results to NV and never reports OF/UF/DZ.
      invalid = value[2] || value[1];
      map_int_flags = {invalid, 3'b000, value[0] && !invalid};
    end
  endfunction

  function automatic logic [31:0] select_divsqrt_s_result(
    input logic        sqrt_op,
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [31:0] hardfloat_result
  );
    logic a_nan, b_nan, a_inf, b_inf, a_zero, b_zero, result_sign;
    begin
      a_nan = is_nan_s(a[30:0]);
      b_nan = is_nan_s(b[30:0]);
      a_inf = (&a[30:23]) && (a[22:0] == 0);
      b_inf = (&b[30:23]) && (b[22:0] == 0);
      a_zero = (a[30:0] == 0);
      b_zero = (b[30:0] == 0);
      result_sign = a[31] ^ b[31];
      select_divsqrt_s_result = hardfloat_result;
      if (sqrt_op) begin
        if (a_nan || (a[31] && !a_zero))
          select_divsqrt_s_result = S_CANONICAL_NAN;
        else if (a_inf || a_zero)
          select_divsqrt_s_result = a;
      end else if (a_nan || b_nan || (a_inf && b_inf) ||
                   (a_zero && b_zero)) begin
        select_divsqrt_s_result = S_CANONICAL_NAN;
      end else if (a_inf || b_zero) begin
        select_divsqrt_s_result = {result_sign, 8'hff, 23'b0};
      end else if (a_zero || b_inf) begin
        select_divsqrt_s_result = {result_sign, 31'b0};
      end
    end
  endfunction

  function automatic logic [63:0] select_divsqrt_d_result(
    input logic        sqrt_op,
    input logic [63:0] a,
    input logic [63:0] b,
    input logic [63:0] hardfloat_result
  );
    logic a_nan, b_nan, a_inf, b_inf, a_zero, b_zero, result_sign;
    begin
      a_nan = is_nan_d(a[62:0]);
      b_nan = is_nan_d(b[62:0]);
      a_inf = (&a[62:52]) && (a[51:0] == 0);
      b_inf = (&b[62:52]) && (b[51:0] == 0);
      a_zero = (a[62:0] == 0);
      b_zero = (b[62:0] == 0);
      result_sign = a[63] ^ b[63];
      select_divsqrt_d_result = hardfloat_result;
      if (sqrt_op) begin
        if (a_nan || (a[63] && !a_zero))
          select_divsqrt_d_result = D_CANONICAL_NAN;
        else if (a_inf || a_zero)
          select_divsqrt_d_result = a;
      end else if (a_nan || b_nan || (a_inf && b_inf) ||
                   (a_zero && b_zero)) begin
        select_divsqrt_d_result = D_CANONICAL_NAN;
      end else if (a_inf || b_zero) begin
        select_divsqrt_d_result = {result_sign, 11'h7ff, 52'b0};
      end else if (a_zero || b_inf) begin
        select_divsqrt_d_result = {result_sign, 63'b0};
      end
    end
  endfunction

  assign a_s_bits = (a_i[63:32] == 32'hffff_ffff)
                  ? a_i[31:0] : S_CANONICAL_NAN;
  assign b_s_bits = (b_i[63:32] == 32'hffff_ffff)
                  ? b_i[31:0] : S_CANONICAL_NAN;
  assign c_s_bits = (c_i[63:32] == 32'hffff_ffff)
                  ? c_i[31:0] : S_CANONICAL_NAN;
  assign a_d_bits = a_i;
  assign b_d_bits = b_i;
  assign c_d_bits = c_i;
  assign f2i_signed = !int_fmt_i[0];
  assign s_div_a = (div_active_q || done_q) ? s_div_a_q : a_s_rec;
  assign s_div_b = (div_active_q || done_q) ? s_div_b_q : b_s_rec;
  assign d_div_a = (div_active_q || done_q) ? d_div_a_q : a_d_rec;
  assign d_div_b = (div_active_q || done_q) ? d_div_b_q : b_d_rec;
  assign div_sqrt = (div_active_q || done_q) ? div_sqrt_q :
                    (op_i == rv64_pkg::FP_SQRT);
  assign div_rm = (div_active_q || done_q) ? div_rm_q : rm_i;

  fNToRecFN #(8, 24) rec_s_a(.in(a_s_bits), .out(a_s_rec));
  fNToRecFN #(8, 24) rec_s_b(.in(b_s_bits), .out(b_s_rec));
  fNToRecFN #(8, 24) rec_s_c(.in(c_s_bits), .out(c_s_rec));
  fNToRecFN #(11, 53) rec_d_a(.in(a_d_bits), .out(a_d_rec));
  fNToRecFN #(11, 53) rec_d_b(.in(b_d_bits), .out(b_d_rec));
  fNToRecFN #(11, 53) rec_d_c(.in(c_d_bits), .out(c_d_rec));

  addRecFN #(8, 24) add_s(
    .control(1'b1), .subOp(op_i == rv64_pkg::FP_SUB), .a(a_s_rec), .b(b_s_rec),
    .roundingMode(rm_i), .out(s_add_rec), .exceptionFlags(s_add_flags));
  addRecFN #(11, 53) add_d(
    .control(1'b1), .subOp(op_i == rv64_pkg::FP_SUB), .a(a_d_rec), .b(b_d_rec),
    .roundingMode(rm_i), .out(d_add_rec), .exceptionFlags(d_add_flags));
  mulRecFN #(8, 24) mul_s(
    .control(1'b1), .a(a_s_rec), .b(b_s_rec), .roundingMode(rm_i),
    .out(s_mul_rec), .exceptionFlags(s_mul_flags));
  mulRecFN #(11, 53) mul_d(
    .control(1'b1), .a(a_d_rec), .b(b_d_rec), .roundingMode(rm_i),
    .out(d_mul_rec), .exceptionFlags(d_mul_flags));
  mulAddRecFN #(8, 24) fma_s(
    .control(1'b1), .op(fma_op_i), .a(a_s_rec), .b(b_s_rec), .c(c_s_rec),
    .roundingMode(rm_i), .out(s_fma_rec), .exceptionFlags(s_fma_flags));
  mulAddRecFN #(11, 53) fma_d(
    .control(1'b1), .op(fma_op_i), .a(a_d_rec), .b(b_d_rec), .c(c_d_rec),
    .roundingMode(rm_i), .out(d_fma_rec), .exceptionFlags(d_fma_flags));

  recFNToFN #(8, 24) out_s_add(.in(s_add_rec), .out(s_add_bits));
  recFNToFN #(8, 24) out_s_mul(.in(s_mul_rec), .out(s_mul_bits));
  recFNToFN #(8, 24) out_s_fma(.in(s_fma_rec), .out(s_fma_bits));
  recFNToFN #(11, 53) out_d_add(.in(d_add_rec), .out(d_add_bits));
  recFNToFN #(11, 53) out_d_mul(.in(d_mul_rec), .out(d_mul_bits));
  recFNToFN #(11, 53) out_d_fma(.in(d_fma_rec), .out(d_fma_bits));

  /* verilator lint_off PINCONNECTEMPTY */
  divSqrtRecFN_small #(8, 24, 0) div_s(
    .nReset(rst_ni), .clock(clk_i), .control(1'b1), .inReady(s_div_ready),
    .inValid(s_div_valid), .sqrtOp(div_sqrt), .a(s_div_a),
    .b(s_div_b), .roundingMode(div_rm), .outValid(s_div_done),
    .sqrtOpOut(), .out(s_div_rec), .exceptionFlags(s_div_flags));
  divSqrtRecFN_small #(11, 53, 0) div_d(
    .nReset(rst_ni), .clock(clk_i), .control(1'b1), .inReady(d_div_ready),
    .inValid(d_div_valid), .sqrtOp(div_sqrt), .a(d_div_a),
    .b(d_div_b), .roundingMode(div_rm), .outValid(d_div_done),
    .sqrtOpOut(), .out(d_div_rec), .exceptionFlags(d_div_flags));
  recFNToFN #(8, 24) out_s_div(.in(s_div_rec), .out(s_div_bits));
  recFNToFN #(11, 53) out_d_div(.in(d_div_rec), .out(d_div_bits));

  compareRecFN #(8, 24) cmp_s(
    .a(a_s_rec), .b(b_s_rec),
    .signaling((op_i == rv64_pkg::FP_CMP_LT) || (op_i == rv64_pkg::FP_CMP_LE)),
    .lt(s_cmp_lt), .eq(s_cmp_eq), .gt(s_cmp_gt), .unordered(),
    .exceptionFlags(s_cmp_flags));
  compareRecFN #(11, 53) cmp_d(
    .a(a_d_rec), .b(b_d_rec),
    .signaling((op_i == rv64_pkg::FP_CMP_LT) || (op_i == rv64_pkg::FP_CMP_LE)),
    .lt(d_cmp_lt), .eq(d_cmp_eq), .gt(d_cmp_gt), .unordered(),
    .exceptionFlags(d_cmp_flags));
  /* verilator lint_on PINCONNECTEMPTY */

  iNToRecFN #(32, 8, 24) i32s_s(.control(1'b1), .signedIn(1'b1), .in(x_i[31:0]),
    .roundingMode(rm_i), .out(s_i32s_rec), .exceptionFlags(s_i32s_flags));
  iNToRecFN #(32, 8, 24) i32u_s(.control(1'b1), .signedIn(1'b0), .in(x_i[31:0]),
    .roundingMode(rm_i), .out(s_i32u_rec), .exceptionFlags(s_i32u_flags));
  iNToRecFN #(64, 8, 24) i64s_s(.control(1'b1), .signedIn(1'b1), .in(x_i),
    .roundingMode(rm_i), .out(s_i64s_rec), .exceptionFlags(s_i64s_flags));
  iNToRecFN #(64, 8, 24) i64u_s(.control(1'b1), .signedIn(1'b0), .in(x_i),
    .roundingMode(rm_i), .out(s_i64u_rec), .exceptionFlags(s_i64u_flags));
  iNToRecFN #(32, 11, 53) i32s_d(.control(1'b1), .signedIn(1'b1), .in(x_i[31:0]),
    .roundingMode(rm_i), .out(d_i32s_rec), .exceptionFlags(d_i32s_flags));
  iNToRecFN #(32, 11, 53) i32u_d(.control(1'b1), .signedIn(1'b0), .in(x_i[31:0]),
    .roundingMode(rm_i), .out(d_i32u_rec), .exceptionFlags(d_i32u_flags));
  iNToRecFN #(64, 11, 53) i64s_d(.control(1'b1), .signedIn(1'b1), .in(x_i),
    .roundingMode(rm_i), .out(d_i64s_rec), .exceptionFlags(d_i64s_flags));
  iNToRecFN #(64, 11, 53) i64u_d(.control(1'b1), .signedIn(1'b0), .in(x_i),
    .roundingMode(rm_i), .out(d_i64u_rec), .exceptionFlags(d_i64u_flags));

  recFNToFN #(8, 24) out_s_i32s(.in(s_i32s_rec), .out(s_i32s_bits));
  recFNToFN #(8, 24) out_s_i32u(.in(s_i32u_rec), .out(s_i32u_bits));
  recFNToFN #(8, 24) out_s_i64s(.in(s_i64s_rec), .out(s_i64s_bits));
  recFNToFN #(8, 24) out_s_i64u(.in(s_i64u_rec), .out(s_i64u_bits));
  recFNToFN #(11, 53) out_d_i32s(.in(d_i32s_rec), .out(d_i32s_bits));
  recFNToFN #(11, 53) out_d_i32u(.in(d_i32u_rec), .out(d_i32u_bits));
  recFNToFN #(11, 53) out_d_i64s(.in(d_i64s_rec), .out(d_i64s_bits));
  recFNToFN #(11, 53) out_d_i64u(.in(d_i64u_rec), .out(d_i64u_bits));

  recFNToIN #(8, 24, 32) f2i32_s(.control(1'b1), .in(a_s_rec),
    .roundingMode(rm_i), .signedOut(f2i_signed), .out(s_f2i32),
    .intExceptionFlags(s_f2i32_flags));
  recFNToIN #(8, 24, 64) f2i64_s(.control(1'b1), .in(a_s_rec),
    .roundingMode(rm_i), .signedOut(f2i_signed), .out(s_f2i64),
    .intExceptionFlags(s_f2i64_flags));
  recFNToIN #(11, 53, 32) f2i32_d(.control(1'b1), .in(a_d_rec),
    .roundingMode(rm_i), .signedOut(f2i_signed), .out(d_f2i32),
    .intExceptionFlags(d_f2i32_flags));
  recFNToIN #(11, 53, 64) f2i64_d(.control(1'b1), .in(a_d_rec),
    .roundingMode(rm_i), .signedOut(f2i_signed), .out(d_f2i64),
    .intExceptionFlags(d_f2i64_flags));

  recFNToRecFN #(8, 24, 11, 53) s_to_d(.control(1'b1), .in(a_s_rec),
    .roundingMode(rm_i), .out(s_to_d_rec), .exceptionFlags(s_to_d_flags));
  recFNToRecFN #(11, 53, 8, 24) d_to_s(.control(1'b1), .in(a_d_rec),
    .roundingMode(rm_i), .out(d_to_s_rec), .exceptionFlags(d_to_s_flags));
  recFNToFN #(11, 53) out_s_to_d(.in(s_to_d_rec), .out(s_to_d_bits));
  recFNToFN #(8, 24) out_d_to_s(.in(d_to_s_rec), .out(d_to_s_bits));

  assign operation_is_divsqrt = (op_i == rv64_pkg::FP_DIV) ||
                                (op_i == rv64_pkg::FP_SQRT);
  assign div_request_ready = (fmt_i == rv64_pkg::FP_FMT_S)
                           ? s_div_ready : d_div_ready;
  assign div_selected_ready = (div_fmt_q == rv64_pkg::FP_FMT_S)
                            ? s_div_ready : d_div_ready;
  assign div_selected_done = (div_fmt_q == rv64_pkg::FP_FMT_S)
                           ? s_div_done : d_div_done;
  assign ready_o = !active_q && (!operation_is_divsqrt || div_request_ready);
  assign accept = start_i && ready_o;
  assign s_div_valid = active_q && div_active_q && !div_issued_q &&
                       (div_fmt_q == rv64_pkg::FP_FMT_S);
  assign d_div_valid = active_q && div_active_q && !div_issued_q &&
                       (div_fmt_q == rv64_pkg::FP_FMT_D);
  assign busy_o = active_q;
  assign done_o = done_q;
  assign result_o = result_q;
  assign int_result_o = int_result_q;
  assign flags_o = flags_q;

  always_comb begin
    comb_result = 64'b0;
    comb_int_result = 64'b0;
    comb_flags = 5'b0;

    if (fmt_i == rv64_pkg::FP_FMT_S) begin
      case (op_i)
        rv64_pkg::FP_ADD, rv64_pkg::FP_SUB: begin
          comb_result = {32'hffff_ffff, s_add_bits};
          comb_flags = s_add_flags;
        end
        rv64_pkg::FP_MUL: begin
          comb_result = {32'hffff_ffff, s_mul_bits};
          comb_flags = s_mul_flags;
        end
        rv64_pkg::FP_FMA: begin
          comb_result = {32'hffff_ffff, s_fma_bits};
          comb_flags = s_fma_flags;
        end
        rv64_pkg::FP_SGNJ:
          comb_result = {32'hffff_ffff, b_s_bits[31], a_s_bits[30:0]};
        rv64_pkg::FP_SGNJN:
          comb_result = {32'hffff_ffff, ~b_s_bits[31], a_s_bits[30:0]};
        rv64_pkg::FP_SGNJX:
          comb_result = {32'hffff_ffff, a_s_bits[31] ^ b_s_bits[31],
                         a_s_bits[30:0]};
        rv64_pkg::FP_MIN, rv64_pkg::FP_MAX: begin
          if (is_nan_s(a_s_bits[30:0]) && is_nan_s(b_s_bits[30:0]))
            comb_result = {32'hffff_ffff, S_CANONICAL_NAN};
          else if (is_nan_s(a_s_bits[30:0]))
            comb_result = {32'hffff_ffff, b_s_bits};
          else if (is_nan_s(b_s_bits[30:0]))
            comb_result = {32'hffff_ffff, a_s_bits};
          else if ((a_s_bits[30:0] == 0) && (b_s_bits[30:0] == 0))
            comb_result = {32'hffff_ffff,
                           (op_i == rv64_pkg::FP_MIN)
                             ? (a_s_bits[31] | b_s_bits[31])
                             : (a_s_bits[31] & b_s_bits[31]),
                           31'b0};
          else if (op_i == rv64_pkg::FP_MIN)
            comb_result = {32'hffff_ffff, s_cmp_lt ? a_s_bits : b_s_bits};
          else
            comb_result = {32'hffff_ffff, s_cmp_gt ? a_s_bits : b_s_bits};
          comb_flags = {is_snan_s(a_s_bits[30:0]) ||
                        is_snan_s(b_s_bits[30:0]), 4'b0};
        end
        rv64_pkg::FP_CMP_EQ: begin
          comb_int_result = {63'b0, s_cmp_eq};
          comb_flags = s_cmp_flags;
        end
        rv64_pkg::FP_CMP_LT: begin
          comb_int_result = {63'b0, s_cmp_lt};
          comb_flags = s_cmp_flags;
        end
        rv64_pkg::FP_CMP_LE: begin
          comb_int_result = {63'b0, s_cmp_lt || s_cmp_eq};
          comb_flags = s_cmp_flags;
        end
        rv64_pkg::FP_CLASS:
          comb_int_result = {54'b0, classify_s(a_s_bits)};
        rv64_pkg::FP_CVT_F2I: begin
          if (int_fmt_i[1]) begin
            comb_int_result = s_f2i64;
            comb_flags = map_int_flags(s_f2i64_flags);
          end else begin
            comb_int_result = {{32{s_f2i32[31]}}, s_f2i32};
            comb_flags = map_int_flags(s_f2i32_flags);
          end
        end
        rv64_pkg::FP_CVT_I2F: begin
          case (int_fmt_i)
            rv64_pkg::FP_INT_W: begin
              comb_result = {32'hffff_ffff, s_i32s_bits};
              comb_flags = s_i32s_flags;
            end
            rv64_pkg::FP_INT_WU: begin
              comb_result = {32'hffff_ffff, s_i32u_bits};
              comb_flags = s_i32u_flags;
            end
            rv64_pkg::FP_INT_L: begin
              comb_result = {32'hffff_ffff, s_i64s_bits};
              comb_flags = s_i64s_flags;
            end
            rv64_pkg::FP_INT_LU: begin
              comb_result = {32'hffff_ffff, s_i64u_bits};
              comb_flags = s_i64u_flags;
            end
            default: begin end
          endcase
        end
        rv64_pkg::FP_CVT_F2F: begin
          if (src_fmt_i == rv64_pkg::FP_FMT_D) begin
            comb_result = {32'hffff_ffff, d_to_s_bits};
            comb_flags = d_to_s_flags;
          end
        end
        rv64_pkg::FP_MOVE_F2X:
          comb_int_result = {{32{a_i[31]}}, a_i[31:0]};
        rv64_pkg::FP_MOVE_X2F:
          comb_result = {32'hffff_ffff, x_i[31:0]};
        default: begin end
      endcase
    end else begin
      case (op_i)
        rv64_pkg::FP_ADD, rv64_pkg::FP_SUB: begin
          comb_result = d_add_bits;
          comb_flags = d_add_flags;
        end
        rv64_pkg::FP_MUL: begin
          comb_result = d_mul_bits;
          comb_flags = d_mul_flags;
        end
        rv64_pkg::FP_FMA: begin
          comb_result = d_fma_bits;
          comb_flags = d_fma_flags;
        end
        rv64_pkg::FP_SGNJ:
          comb_result = {b_d_bits[63], a_d_bits[62:0]};
        rv64_pkg::FP_SGNJN:
          comb_result = {~b_d_bits[63], a_d_bits[62:0]};
        rv64_pkg::FP_SGNJX:
          comb_result = {a_d_bits[63] ^ b_d_bits[63], a_d_bits[62:0]};
        rv64_pkg::FP_MIN, rv64_pkg::FP_MAX: begin
          if (is_nan_d(a_d_bits[62:0]) && is_nan_d(b_d_bits[62:0]))
            comb_result = D_CANONICAL_NAN;
          else if (is_nan_d(a_d_bits[62:0]))
            comb_result = b_d_bits;
          else if (is_nan_d(b_d_bits[62:0]))
            comb_result = a_d_bits;
          else if ((a_d_bits[62:0] == 0) && (b_d_bits[62:0] == 0))
            comb_result = {(op_i == rv64_pkg::FP_MIN)
                              ? (a_d_bits[63] | b_d_bits[63])
                              : (a_d_bits[63] & b_d_bits[63]),
                           63'b0};
          else if (op_i == rv64_pkg::FP_MIN)
            comb_result = d_cmp_lt ? a_d_bits : b_d_bits;
          else
            comb_result = d_cmp_gt ? a_d_bits : b_d_bits;
          comb_flags = {is_snan_d(a_d_bits[62:0]) ||
                        is_snan_d(b_d_bits[62:0]), 4'b0};
        end
        rv64_pkg::FP_CMP_EQ: begin
          comb_int_result = {63'b0, d_cmp_eq};
          comb_flags = d_cmp_flags;
        end
        rv64_pkg::FP_CMP_LT: begin
          comb_int_result = {63'b0, d_cmp_lt};
          comb_flags = d_cmp_flags;
        end
        rv64_pkg::FP_CMP_LE: begin
          comb_int_result = {63'b0, d_cmp_lt || d_cmp_eq};
          comb_flags = d_cmp_flags;
        end
        rv64_pkg::FP_CLASS:
          comb_int_result = {54'b0, classify_d(a_d_bits)};
        rv64_pkg::FP_CVT_F2I: begin
          if (int_fmt_i[1]) begin
            comb_int_result = d_f2i64;
            comb_flags = map_int_flags(d_f2i64_flags);
          end else begin
            comb_int_result = {{32{d_f2i32[31]}}, d_f2i32};
            comb_flags = map_int_flags(d_f2i32_flags);
          end
        end
        rv64_pkg::FP_CVT_I2F: begin
          case (int_fmt_i)
            rv64_pkg::FP_INT_W: begin
              comb_result = d_i32s_bits;
              comb_flags = d_i32s_flags;
            end
            rv64_pkg::FP_INT_WU: begin
              comb_result = d_i32u_bits;
              comb_flags = d_i32u_flags;
            end
            rv64_pkg::FP_INT_L: begin
              comb_result = d_i64s_bits;
              comb_flags = d_i64s_flags;
            end
            rv64_pkg::FP_INT_LU: begin
              comb_result = d_i64u_bits;
              comb_flags = d_i64u_flags;
            end
            default: begin end
          endcase
        end
        rv64_pkg::FP_CVT_F2F: begin
          if (src_fmt_i == rv64_pkg::FP_FMT_S) begin
            comb_result = s_to_d_bits;
            comb_flags = s_to_d_flags;
          end
        end
        rv64_pkg::FP_MOVE_F2X:
          comb_int_result = a_i;
        rv64_pkg::FP_MOVE_X2F:
          comb_result = x_i;
        default: begin end
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      active_q <= 1'b0;
      div_active_q <= 1'b0;
      div_issued_q <= 1'b0;
      div_sqrt_q <= 1'b0;
      div_fmt_q <= rv64_pkg::FP_FMT_S;
      div_rm_q <= 3'b0;
      s_div_a_q <= 33'b0;
      s_div_b_q <= 33'b0;
      d_div_a_q <= 65'b0;
      d_div_b_q <= 65'b0;
      s_div_a_bits_q <= 32'b0;
      s_div_b_bits_q <= 32'b0;
      d_div_a_bits_q <= 64'b0;
      d_div_b_bits_q <= 64'b0;
      done_q <= 1'b0;
      result_q <= 64'b0;
      int_result_q <= 64'b0;
      flags_q <= 5'b0;
    end else begin
      done_q <= 1'b0;
      if (active_q) begin
        if (div_active_q) begin
          if (!div_issued_q) begin
            if (div_selected_ready)
              div_issued_q <= 1'b1;
          end else if (div_selected_done) begin
            result_q <= (div_fmt_q == rv64_pkg::FP_FMT_S)
                      ? {32'hffff_ffff,
                         select_divsqrt_s_result(
                           div_sqrt_q, s_div_a_bits_q, s_div_b_bits_q,
                           s_div_bits)}
                      : select_divsqrt_d_result(
                          div_sqrt_q, d_div_a_bits_q, d_div_b_bits_q,
                          d_div_bits);
            int_result_q <= 64'b0;
            flags_q <= (div_fmt_q == rv64_pkg::FP_FMT_S)
                     ? s_div_flags : d_div_flags;
            active_q <= 1'b0;
            div_active_q <= 1'b0;
            div_issued_q <= 1'b0;
            done_q <= 1'b1;
          end
        end else begin
          active_q <= 1'b0;
          done_q <= 1'b1;
        end
      end else if (accept) begin
        active_q <= 1'b1;
        div_active_q <= operation_is_divsqrt;
        div_issued_q <= 1'b0;
        div_fmt_q <= fmt_i;
        div_sqrt_q <= (op_i == rv64_pkg::FP_SQRT);
        div_rm_q <= rm_i;
        s_div_a_q <= a_s_rec;
        s_div_b_q <= b_s_rec;
        d_div_a_q <= a_d_rec;
        d_div_b_q <= b_d_rec;
        s_div_a_bits_q <= a_s_bits;
        s_div_b_bits_q <= b_s_bits;
        d_div_a_bits_q <= a_d_bits;
        d_div_b_bits_q <= b_d_bits;
        if (!operation_is_divsqrt) begin
          result_q <= comb_result;
          int_result_q <= comb_int_result;
          flags_q <= comb_flags;
        end
      end
    end
  end

endmodule
