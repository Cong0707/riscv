`timescale 1ns/1ps

/* verilator lint_off UNUSEDSIGNAL */

module rv64_imm_gen (
  input  logic [31:0]          instr,
  input  rv64_pkg::imm_type_t  imm_type,
  output logic [63:0]          imm
);

  always_comb begin
    case (imm_type)
      rv64_pkg::IMM_I: begin
        imm = {{52{instr[31]}}, instr[31:20]};
      end
      rv64_pkg::IMM_S: begin
        imm = {{52{instr[31]}}, instr[31:25], instr[11:7]};
      end
      rv64_pkg::IMM_B: begin
        imm = {{51{instr[31]}}, instr[31], instr[7], instr[30:25],
               instr[11:8], 1'b0};
      end
      rv64_pkg::IMM_U: begin
        imm = {{32{instr[31]}}, instr[31:12], 12'b0};
      end
      rv64_pkg::IMM_J: begin
        imm = {{43{instr[31]}}, instr[31], instr[19:12], instr[20],
               instr[30:21], 1'b0};
      end
      rv64_pkg::IMM_Z: begin
        imm = {{59{1'b0}}, instr[19:15]};
      end
      default: begin
        imm = 64'b0;
      end
    endcase
  end

endmodule

/* verilator lint_on UNUSEDSIGNAL */
