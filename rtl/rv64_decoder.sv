`timescale 1ns/1ps

module rv64_decoder (
  input  logic [31:0]              instr,
  output logic [4:0]               rs1,
  output logic [4:0]               rs2,
  output logic [4:0]               rd,
  output rv64_pkg::decode_ctrl_t   ctrl
);

  always_comb begin
    rs1 = instr[19:15];
    rs2 = instr[24:20];
    rd  = instr[11:7];

    ctrl             = '0;
    ctrl.legal       = 1'b0;
    ctrl.illegal     = 1'b1;
    ctrl.alu_op      = rv64_pkg::ALU_NONE;
    ctrl.imm_type    = rv64_pkg::IMM_NONE;
    ctrl.branch      = rv64_pkg::BR_NONE;
    ctrl.mem_size    = rv64_pkg::MEM_NONE;

    case (instr[6:0])
      rv64_pkg::OPCODE_LUI: begin
        ctrl.legal       = 1'b1;
        ctrl.uses_rd     = 1'b1;
        ctrl.reg_write   = 1'b1;
        ctrl.alu_src_imm = 1'b1;
        ctrl.alu_op      = rv64_pkg::ALU_COPY_B;
        ctrl.imm_type    = rv64_pkg::IMM_U;
      end

      rv64_pkg::OPCODE_AUIPC: begin
        ctrl.legal       = 1'b1;
        ctrl.uses_rd     = 1'b1;
        ctrl.reg_write   = 1'b1;
        ctrl.alu_src_pc  = 1'b1;
        ctrl.alu_src_imm = 1'b1;
        ctrl.alu_op      = rv64_pkg::ALU_ADD;
        ctrl.imm_type    = rv64_pkg::IMM_U;
      end

      rv64_pkg::OPCODE_JAL: begin
        ctrl.legal       = 1'b1;
        ctrl.uses_rd     = 1'b1;
        ctrl.reg_write   = 1'b1;
        ctrl.alu_src_pc  = 1'b1;
        ctrl.alu_src_imm = 1'b1;
        ctrl.alu_op      = rv64_pkg::ALU_ADD;
        ctrl.imm_type    = rv64_pkg::IMM_J;
        ctrl.is_jal      = 1'b1;
      end

      rv64_pkg::OPCODE_JALR: begin
        if (instr[14:12] == 3'b000) begin
          ctrl.legal       = 1'b1;
          ctrl.uses_rs1    = 1'b1;
          ctrl.uses_rd     = 1'b1;
          ctrl.reg_write   = 1'b1;
          ctrl.alu_src_imm = 1'b1;
          ctrl.alu_op      = rv64_pkg::ALU_ADD;
          ctrl.imm_type    = rv64_pkg::IMM_I;
          ctrl.is_jalr      = 1'b1;
        end
      end

      rv64_pkg::OPCODE_BRANCH: begin
        ctrl.uses_rs1  = 1'b1;
        ctrl.uses_rs2  = 1'b1;
        ctrl.is_branch = 1'b1;
        ctrl.imm_type  = rv64_pkg::IMM_B;
        case (instr[14:12])
          3'b000: begin ctrl.legal = 1'b1; ctrl.branch = rv64_pkg::BR_EQ;  end
          3'b001: begin ctrl.legal = 1'b1; ctrl.branch = rv64_pkg::BR_NE;  end
          3'b100: begin ctrl.legal = 1'b1; ctrl.branch = rv64_pkg::BR_LT;  end
          3'b101: begin ctrl.legal = 1'b1; ctrl.branch = rv64_pkg::BR_GE;  end
          3'b110: begin ctrl.legal = 1'b1; ctrl.branch = rv64_pkg::BR_LTU; end
          3'b111: begin ctrl.legal = 1'b1; ctrl.branch = rv64_pkg::BR_GEU; end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_LOAD: begin
        ctrl.uses_rs1    = 1'b1;
        ctrl.uses_rd     = 1'b1;
        ctrl.reg_write   = 1'b1;
        ctrl.mem_read    = 1'b1;
        ctrl.alu_src_imm = 1'b1;
        ctrl.alu_op      = rv64_pkg::ALU_ADD;
        ctrl.imm_type    = rv64_pkg::IMM_I;
        case (instr[14:12])
          3'b000: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_B; end
          3'b001: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_H; end
          3'b010: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_W; end
          3'b011: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_D; end
          3'b100: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_B; ctrl.mem_unsigned = 1'b1; end
          3'b101: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_H; ctrl.mem_unsigned = 1'b1; end
          3'b110: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_W; ctrl.mem_unsigned = 1'b1; end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_STORE: begin
        ctrl.uses_rs1    = 1'b1;
        ctrl.uses_rs2    = 1'b1;
        ctrl.mem_write   = 1'b1;
        ctrl.alu_src_imm = 1'b1;
        ctrl.alu_op      = rv64_pkg::ALU_ADD;
        ctrl.imm_type    = rv64_pkg::IMM_S;
        case (instr[14:12])
          3'b000: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_B; end
          3'b001: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_H; end
          3'b010: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_W; end
          3'b011: begin ctrl.legal = 1'b1; ctrl.mem_size = rv64_pkg::MEM_D; end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_OP_IMM: begin
        ctrl.uses_rs1    = 1'b1;
        ctrl.uses_rd     = 1'b1;
        ctrl.reg_write   = 1'b1;
        ctrl.alu_src_imm = 1'b1;
        ctrl.imm_type    = rv64_pkg::IMM_I;
        case (instr[14:12])
          3'b000: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_ADD;  end // ADDI
          3'b010: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SLT;  end // SLTI
          3'b011: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SLTU; end // SLTIU
          3'b100: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_XOR;  end // XORI
          3'b110: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_OR;   end // ORI
          3'b111: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_AND;  end // ANDI
          3'b001: begin
            if (instr[31:26] == 6'b000000) begin
              ctrl.legal  = 1'b1;
              ctrl.alu_op = rv64_pkg::ALU_SLL;
            end
          end
          3'b101: begin
            if (instr[31:26] == 6'b000000) begin
              ctrl.legal  = 1'b1;
              ctrl.alu_op = rv64_pkg::ALU_SRL;
            end else if (instr[31:26] == 6'b010000) begin
              ctrl.legal  = 1'b1;
              ctrl.alu_op = rv64_pkg::ALU_SRA;
            end
          end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_OP_IMM_32: begin
        ctrl.uses_rs1    = 1'b1;
        ctrl.uses_rd     = 1'b1;
        ctrl.reg_write   = 1'b1;
        ctrl.alu_src_imm = 1'b1;
        ctrl.imm_type    = rv64_pkg::IMM_I;
        case (instr[14:12])
          3'b000: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_ADDW; end // ADDIW
          3'b001: begin
            if (instr[31:25] == 7'b0000000) begin
              ctrl.legal  = 1'b1;
              ctrl.alu_op = rv64_pkg::ALU_SLLW;
            end
          end
          3'b101: begin
            if (instr[31:25] == 7'b0000000) begin
              ctrl.legal  = 1'b1;
              ctrl.alu_op = rv64_pkg::ALU_SRLW;
            end else if (instr[31:25] == 7'b0100000) begin
              ctrl.legal  = 1'b1;
              ctrl.alu_op = rv64_pkg::ALU_SRAW;
            end
          end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_OP: begin
        ctrl.uses_rs1  = 1'b1;
        ctrl.uses_rs2  = 1'b1;
        ctrl.uses_rd   = 1'b1;
        ctrl.reg_write = 1'b1;
        case ({instr[31:25], instr[14:12]})
          10'b0000000_000: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_ADD;  end
          10'b0100000_000: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SUB;  end
          10'b0000000_001: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SLL;  end
          10'b0000000_010: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SLT;  end
          10'b0000000_011: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SLTU; end
          10'b0000000_100: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_XOR;  end
          10'b0000000_101: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SRL;  end
          10'b0100000_101: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SRA;  end
          10'b0000000_110: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_OR;   end
          10'b0000000_111: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_AND;  end
          10'b0000001_000: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_MUL;    end
          10'b0000001_001: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_MULH;   end
          10'b0000001_010: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_MULHSU; end
          10'b0000001_011: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_MULHU;  end
          10'b0000001_100: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_DIV;    end
          10'b0000001_101: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_DIVU;   end
          10'b0000001_110: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_REM;    end
          10'b0000001_111: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_REMU;   end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_OP_32: begin
        ctrl.uses_rs1  = 1'b1;
        ctrl.uses_rs2  = 1'b1;
        ctrl.uses_rd   = 1'b1;
        ctrl.reg_write = 1'b1;
        case ({instr[31:25], instr[14:12]})
          10'b0000000_000: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_ADDW; end
          10'b0100000_000: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SUBW; end
          10'b0000000_001: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SLLW; end
          10'b0000000_101: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SRLW; end
          10'b0100000_101: begin ctrl.legal = 1'b1; ctrl.alu_op = rv64_pkg::ALU_SRAW; end
          10'b0000001_000: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_MULW;  end
          10'b0000001_100: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_DIVW;  end
          10'b0000001_101: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_DIVUW; end
          10'b0000001_110: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_REMW;  end
          10'b0000001_111: begin ctrl.legal = 1'b1; ctrl.is_mdu = 1'b1; ctrl.mdu_op = rv64_pkg::MDU_REMUW; end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_MISC_MEM: begin
        // FENCE is architecturally ordered; this core's in-order memory
        // system can implement it as a no-op. FENCE.I is outside RV64I.
        if (instr[14:12] == 3'b000) begin
          ctrl.legal     = 1'b1;
          ctrl.is_fence  = 1'b1;
        end
      end

      rv64_pkg::OPCODE_SYSTEM: begin
        if (instr == 32'h0000_0073) begin
          ctrl.legal   = 1'b1;
          ctrl.is_ecall = 1'b1;
        end else if (instr == 32'h0010_0073) begin
          ctrl.legal    = 1'b1;
          ctrl.is_ebreak = 1'b1;
        end
      end

      default: begin
        // Reserved opcodes and extensions not yet implemented remain illegal.
      end
    endcase

    ctrl.illegal = !ctrl.legal;

    // Do not expose side effects for a malformed/reserved encoding. The
    // explicit illegal bit still lets a trap unit report the instruction.
    if (ctrl.illegal) begin
      ctrl.uses_rs1    = 1'b0;
      ctrl.uses_rs2    = 1'b0;
      ctrl.uses_rd     = 1'b0;
      ctrl.reg_write   = 1'b0;
      ctrl.mem_read    = 1'b0;
      ctrl.mem_write   = 1'b0;
      ctrl.mem_unsigned = 1'b0;
      ctrl.alu_src_imm = 1'b0;
      ctrl.alu_src_pc  = 1'b0;
      ctrl.is_branch   = 1'b0;
      ctrl.is_jal      = 1'b0;
      ctrl.is_jalr     = 1'b0;
      ctrl.is_fence    = 1'b0;
      ctrl.is_mdu      = 1'b0;
      ctrl.is_ecall    = 1'b0;
      ctrl.is_ebreak   = 1'b0;
      ctrl.alu_op      = rv64_pkg::ALU_NONE;
      ctrl.imm_type    = rv64_pkg::IMM_NONE;
      ctrl.branch      = rv64_pkg::BR_NONE;
      ctrl.mem_size    = rv64_pkg::MEM_NONE;
      ctrl.mdu_op      = rv64_pkg::MDU_MUL;
    end
  end

endmodule
