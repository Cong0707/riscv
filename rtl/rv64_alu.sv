`timescale 1ns/1ps

module rv64_alu (
  input  rv64_pkg::alu_op_t op,
  input  logic [63:0]       a,
  input  logic [63:0]       b,
  output logic [63:0]       result,
  output logic             cmp_eq,
  output logic             cmp_lt_signed,
  output logic             cmp_lt_unsigned
);

  logic [31:0] result_w;

  always_comb begin
    result   = 64'b0;
    result_w = 32'b0;

    case (op)
      rv64_pkg::ALU_ADD: begin
        result = a + b;
      end
      rv64_pkg::ALU_SUB: begin
        result = a - b;
      end
      rv64_pkg::ALU_SLL: begin
        result = a << b[5:0];
      end
      rv64_pkg::ALU_SLT: begin
        result = {63'b0, ($signed(a) < $signed(b))};
      end
      rv64_pkg::ALU_SLTU: begin
        result = {63'b0, (a < b)};
      end
      rv64_pkg::ALU_XOR: begin
        result = a ^ b;
      end
      rv64_pkg::ALU_SRL: begin
        result = a >> b[5:0];
      end
      rv64_pkg::ALU_SRA: begin
        result = $signed(a) >>> b[5:0];
      end
      rv64_pkg::ALU_OR: begin
        result = a | b;
      end
      rv64_pkg::ALU_AND: begin
        result = a & b;
      end
      rv64_pkg::ALU_ADDW: begin
        result_w = a[31:0] + b[31:0];
        result   = {{32{result_w[31]}}, result_w};
      end
      rv64_pkg::ALU_SUBW: begin
        result_w = a[31:0] - b[31:0];
        result   = {{32{result_w[31]}}, result_w};
      end
      rv64_pkg::ALU_SLLW: begin
        result_w = a[31:0] << b[4:0];
        result   = {{32{result_w[31]}}, result_w};
      end
      rv64_pkg::ALU_SRLW: begin
        result_w = a[31:0] >> b[4:0];
        result   = {{32{result_w[31]}}, result_w};
      end
      rv64_pkg::ALU_SRAW: begin
        result_w = $signed(a[31:0]) >>> b[4:0];
        result   = {{32{result_w[31]}}, result_w};
      end
      rv64_pkg::ALU_COPY_B: begin
        result = b;
      end
      rv64_pkg::ALU_COPY_A: begin
        result = a;
      end
      default: begin
        result = 64'b0;
      end
    endcase

    cmp_eq           = (a == b);
    cmp_lt_signed    = ($signed(a) < $signed(b));
    cmp_lt_unsigned  = (a < b);
  end

endmodule
