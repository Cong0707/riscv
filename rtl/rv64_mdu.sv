`timescale 1ns/1ps

module rv64_mdu (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        start_i,
  input  logic [3:0]  op_i,
  input  logic [63:0] a_i,
  input  logic [63:0] b_i,
  output logic        busy_o,
  output logic        done_o,
  output logic [63:0] result_o
);

  // Keep these encodings synchronized with rv64_pkg::mdu_op_t.
  localparam logic [3:0] MDU_OP_MUL    = 4'd0;
  localparam logic [3:0] MDU_OP_MULH   = 4'd1;
  localparam logic [3:0] MDU_OP_MULHSU = 4'd2;
  localparam logic [3:0] MDU_OP_MULHU  = 4'd3;
  localparam logic [3:0] MDU_OP_DIV    = 4'd4;
  localparam logic [3:0] MDU_OP_DIVU   = 4'd5;
  localparam logic [3:0] MDU_OP_REM    = 4'd6;
  localparam logic [3:0] MDU_OP_REMU   = 4'd7;
  localparam logic [3:0] MDU_OP_MULW   = 4'd8;
  localparam logic [3:0] MDU_OP_DIVW   = 4'd9;
  localparam logic [3:0] MDU_OP_DIVUW  = 4'd10;
  localparam logic [3:0] MDU_OP_REMW   = 4'd11;
  localparam logic [3:0] MDU_OP_REMUW  = 4'd12;

  localparam logic [63:0] INT64_MIN = 64'h8000_0000_0000_0000;
  localparam logic [31:0] INT32_MIN = 32'h8000_0000;

  logic        pending_q;
  logic [63:0] pending_result_q;

  function automatic logic [63:0] calculate_result(
    input logic [3:0]  op,
    input logic [63:0] a,
    input logic [63:0] b
  );
    logic signed [63:0]  signed_a;
    logic signed [63:0]  signed_b;
    logic signed [31:0]  signed_a_word;
    logic signed [31:0]  signed_b_word;
    logic signed [127:0] multiply_a;
    logic signed [127:0] multiply_b;
    logic signed [127:0] multiply_product;
    logic [31:0]         word_result;
    begin
      signed_a = $signed(a);
      signed_b = $signed(b);
      signed_a_word = $signed(a[31:0]);
      signed_b_word = $signed(b[31:0]);
      multiply_a = 128'sd0;
      multiply_b = 128'sd0;
      multiply_product = 128'sd0;
      word_result = 32'b0;
      calculate_result = 64'b0;

      case (op)
        MDU_OP_MUL: begin
          multiply_a = $signed({{64{a[63]}}, a});
          multiply_b = $signed({{64{b[63]}}, b});
          multiply_product = multiply_a * multiply_b;
          calculate_result = multiply_product[63:0];
        end

        MDU_OP_MULH: begin
          multiply_a = $signed({{64{a[63]}}, a});
          multiply_b = $signed({{64{b[63]}}, b});
          multiply_product = multiply_a * multiply_b;
          calculate_result = multiply_product[127:64];
        end

        MDU_OP_MULHSU: begin
          multiply_a = $signed({{64{a[63]}}, a});
          multiply_b = $signed({64'b0, b});
          multiply_product = multiply_a * multiply_b;
          calculate_result = multiply_product[127:64];
        end

        MDU_OP_MULHU: begin
          multiply_a = $signed({64'b0, a});
          multiply_b = $signed({64'b0, b});
          multiply_product = multiply_a * multiply_b;
          calculate_result = multiply_product[127:64];
        end

        MDU_OP_DIV: begin
          if (b == 64'b0) begin
            calculate_result = 64'hffff_ffff_ffff_ffff;
          end else if ((a == INT64_MIN) && (b == 64'hffff_ffff_ffff_ffff)) begin
            calculate_result = INT64_MIN;
          end else begin
            calculate_result = signed_a / signed_b;
          end
        end

        MDU_OP_DIVU: begin
          if (b == 64'b0) begin
            calculate_result = 64'hffff_ffff_ffff_ffff;
          end else begin
            calculate_result = a / b;
          end
        end

        MDU_OP_REM: begin
          if (b == 64'b0) begin
            calculate_result = a;
          end else if ((a == INT64_MIN) && (b == 64'hffff_ffff_ffff_ffff)) begin
            calculate_result = 64'b0;
          end else begin
            calculate_result = signed_a % signed_b;
          end
        end

        MDU_OP_REMU: begin
          if (b == 64'b0) begin
            calculate_result = a;
          end else begin
            calculate_result = a % b;
          end
        end

        MDU_OP_MULW: begin
          word_result = a[31:0] * b[31:0];
          calculate_result = {{32{word_result[31]}}, word_result};
        end

        MDU_OP_DIVW: begin
          if (b[31:0] == 32'b0) begin
            word_result = 32'hffff_ffff;
          end else if ((a[31:0] == INT32_MIN) && (b[31:0] == 32'hffff_ffff)) begin
            word_result = INT32_MIN;
          end else begin
            word_result = signed_a_word / signed_b_word;
          end
          calculate_result = {{32{word_result[31]}}, word_result};
        end

        MDU_OP_DIVUW: begin
          if (b[31:0] == 32'b0) begin
            word_result = 32'hffff_ffff;
          end else begin
            word_result = a[31:0] / b[31:0];
          end
          calculate_result = {{32{word_result[31]}}, word_result};
        end

        MDU_OP_REMW: begin
          if (b[31:0] == 32'b0) begin
            word_result = a[31:0];
          end else if ((a[31:0] == INT32_MIN) && (b[31:0] == 32'hffff_ffff)) begin
            word_result = 32'b0;
          end else begin
            word_result = signed_a_word % signed_b_word;
          end
          calculate_result = {{32{word_result[31]}}, word_result};
        end

        MDU_OP_REMUW: begin
          if (b[31:0] == 32'b0) begin
            word_result = a[31:0];
          end else begin
            word_result = a[31:0] % b[31:0];
          end
          calculate_result = {{32{word_result[31]}}, word_result};
        end

        default: calculate_result = 64'b0;
      endcase
    end
  endfunction

  assign busy_o = pending_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pending_q        <= 1'b0;
      pending_result_q <= 64'b0;
      done_o           <= 1'b0;
      result_o         <= 64'b0;
    end else begin
      done_o <= 1'b0;

      if (pending_q) begin
        pending_q <= 1'b0;
        result_o  <= pending_result_q;
        done_o    <= 1'b1;
      end else if (start_i) begin
        pending_q        <= 1'b1;
        pending_result_q <= calculate_result(op_i, a_i, b_i);
      end
    end
  end

endmodule
