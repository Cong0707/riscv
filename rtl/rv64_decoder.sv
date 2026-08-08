`timescale 1ns/1ps

module rv64_decoder (
  input  logic [31:0]              instr,
  output logic [4:0]               rs1,
  output logic [4:0]               rs2,
  output logic [4:0]               rs3,
  output logic [4:0]               rd,
  output rv64_pkg::decode_ctrl_t   ctrl
);

  function automatic logic valid_rounding_mode(input logic [2:0] rm);
    valid_rounding_mode = (rm <= 3'b100) || (rm == 3'b111);
  endfunction

  always_comb begin
    rs1 = instr[19:15];
    rs2 = instr[24:20];
    rs3 = instr[31:27];
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

      rv64_pkg::OPCODE_LOAD_FP: begin
        ctrl.uses_rs1    = 1'b1;
        ctrl.mem_read    = 1'b1;
        ctrl.fp_mem_read = 1'b1;
        ctrl.fp_reg_write = 1'b1;
        ctrl.alu_src_imm = 1'b1;
        ctrl.alu_op      = rv64_pkg::ALU_ADD;
        ctrl.imm_type    = rv64_pkg::IMM_I;
        case (instr[14:12])
          3'b010: begin
            ctrl.legal = 1'b1;
            ctrl.mem_size = rv64_pkg::MEM_W;
            ctrl.fp_fmt = rv64_pkg::FP_FMT_S;
          end
          3'b011: begin
            ctrl.legal = 1'b1;
            ctrl.mem_size = rv64_pkg::MEM_D;
            ctrl.fp_fmt = rv64_pkg::FP_FMT_D;
          end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_STORE_FP: begin
        ctrl.uses_rs1     = 1'b1;
        ctrl.uses_frs2    = 1'b1;
        ctrl.mem_write    = 1'b1;
        ctrl.fp_mem_write = 1'b1;
        ctrl.alu_src_imm  = 1'b1;
        ctrl.alu_op       = rv64_pkg::ALU_ADD;
        ctrl.imm_type     = rv64_pkg::IMM_S;
        case (instr[14:12])
          3'b010: begin
            ctrl.legal = 1'b1;
            ctrl.mem_size = rv64_pkg::MEM_W;
            ctrl.fp_fmt = rv64_pkg::FP_FMT_S;
          end
          3'b011: begin
            ctrl.legal = 1'b1;
            ctrl.mem_size = rv64_pkg::MEM_D;
            ctrl.fp_fmt = rv64_pkg::FP_FMT_D;
          end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_MADD,
      rv64_pkg::OPCODE_MSUB,
      rv64_pkg::OPCODE_NMSUB,
      rv64_pkg::OPCODE_NMADD: begin
        if ((instr[26:25] <= rv64_pkg::FP_FMT_D) &&
            valid_rounding_mode(instr[14:12])) begin
          ctrl.legal        = 1'b1;
          ctrl.is_fp        = 1'b1;
          ctrl.uses_frs1    = 1'b1;
          ctrl.uses_frs2    = 1'b1;
          ctrl.uses_frs3    = 1'b1;
          ctrl.fp_reg_write = 1'b1;
          ctrl.fp_op        = rv64_pkg::FP_FMA;
          ctrl.fp_fmt       = instr[26:25];
          ctrl.fp_rm        = instr[14:12];
          case (instr[6:0])
            rv64_pkg::OPCODE_MADD:  ctrl.fp_fma_op = 2'b00;
            rv64_pkg::OPCODE_MSUB:  ctrl.fp_fma_op = 2'b01;
            rv64_pkg::OPCODE_NMSUB: ctrl.fp_fma_op = 2'b10;
            default:                 ctrl.fp_fma_op = 2'b11;
          endcase
        end
      end

      rv64_pkg::OPCODE_OP_FP: begin
        case (instr[31:25])
          7'b0000000, 7'b0000001: begin // FADD.S/D
            if (valid_rounding_mode(instr[14:12])) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1;
              ctrl.uses_frs1 = 1'b1; ctrl.uses_frs2 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_op = rv64_pkg::FP_ADD;
              ctrl.fp_fmt = {1'b0, instr[25]}; ctrl.fp_rm = instr[14:12];
            end
          end
          7'b0000100, 7'b0000101: begin // FSUB.S/D
            if (valid_rounding_mode(instr[14:12])) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1;
              ctrl.uses_frs1 = 1'b1; ctrl.uses_frs2 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_op = rv64_pkg::FP_SUB;
              ctrl.fp_fmt = {1'b0, instr[25]}; ctrl.fp_rm = instr[14:12];
            end
          end
          7'b0001000, 7'b0001001: begin // FMUL.S/D
            if (valid_rounding_mode(instr[14:12])) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1;
              ctrl.uses_frs1 = 1'b1; ctrl.uses_frs2 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_op = rv64_pkg::FP_MUL;
              ctrl.fp_fmt = {1'b0, instr[25]}; ctrl.fp_rm = instr[14:12];
            end
          end
          7'b0001100, 7'b0001101: begin // FDIV.S/D
            if (valid_rounding_mode(instr[14:12])) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1;
              ctrl.uses_frs1 = 1'b1; ctrl.uses_frs2 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_op = rv64_pkg::FP_DIV;
              ctrl.fp_fmt = {1'b0, instr[25]}; ctrl.fp_rm = instr[14:12];
            end
          end
          7'b0101100, 7'b0101101: begin // FSQRT.S/D
            if ((instr[24:20] == 5'd0) && valid_rounding_mode(instr[14:12])) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1;
              ctrl.uses_frs1 = 1'b1; ctrl.fp_reg_write = 1'b1;
              ctrl.fp_op = rv64_pkg::FP_SQRT; ctrl.fp_fmt = {1'b0, instr[25]};
              ctrl.fp_rm = instr[14:12];
            end
          end
          7'b0010000, 7'b0010001: begin // FSGNJ.S/D family
            case (instr[14:12])
              3'b000: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_SGNJ; end
              3'b001: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_SGNJN; end
              3'b010: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_SGNJX; end
              default: begin end
            endcase
            if (ctrl.legal) begin
              ctrl.is_fp = 1'b1; ctrl.uses_frs1 = 1'b1; ctrl.uses_frs2 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_fmt = {1'b0, instr[25]};
            end
          end
          7'b0010100, 7'b0010101: begin // FMIN/FMAX.S/D
            case (instr[14:12])
              3'b000: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_MIN; end
              3'b001: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_MAX; end
              default: begin end
            endcase
            if (ctrl.legal) begin
              ctrl.is_fp = 1'b1; ctrl.uses_frs1 = 1'b1; ctrl.uses_frs2 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_fmt = {1'b0, instr[25]};
            end
          end
          7'b0100000: begin // FCVT.S.D
            if ((instr[24:20] == 5'd1) && valid_rounding_mode(instr[14:12])) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1; ctrl.uses_frs1 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_op = rv64_pkg::FP_CVT_F2F;
              ctrl.fp_fmt = rv64_pkg::FP_FMT_S;
              ctrl.fp_src_fmt = rv64_pkg::FP_FMT_D;
              ctrl.fp_rm = instr[14:12];
            end
          end
          7'b0100001: begin // FCVT.D.S
            if ((instr[24:20] == 5'd0) && valid_rounding_mode(instr[14:12])) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1; ctrl.uses_frs1 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_op = rv64_pkg::FP_CVT_F2F;
              ctrl.fp_fmt = rv64_pkg::FP_FMT_D;
              ctrl.fp_src_fmt = rv64_pkg::FP_FMT_S;
              ctrl.fp_rm = instr[14:12];
            end
          end
          7'b1010000, 7'b1010001: begin // FEQ/FLT/FLE.S/D
            case (instr[14:12])
              3'b010: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_CMP_EQ; end
              3'b001: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_CMP_LT; end
              3'b000: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_CMP_LE; end
              default: begin end
            endcase
            if (ctrl.legal) begin
              ctrl.is_fp = 1'b1; ctrl.uses_frs1 = 1'b1; ctrl.uses_frs2 = 1'b1;
              ctrl.uses_rd = 1'b1; ctrl.reg_write = 1'b1;
              ctrl.fp_fmt = {1'b0, instr[25]};
            end
          end
          7'b1100000, 7'b1100001: begin // FCVT.W[U]/L[U].S/D
            if (valid_rounding_mode(instr[14:12]) && (instr[24:20] <= 5'd3)) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1; ctrl.uses_frs1 = 1'b1;
              ctrl.uses_rd = 1'b1; ctrl.reg_write = 1'b1;
              ctrl.fp_op = rv64_pkg::FP_CVT_F2I;
              ctrl.fp_fmt = {1'b0, instr[25]};
              ctrl.fp_int_fmt = instr[21:20]; ctrl.fp_rm = instr[14:12];
            end
          end
          7'b1101000, 7'b1101001: begin // FCVT.S/D.W[U]/L[U]
            if (valid_rounding_mode(instr[14:12]) && (instr[24:20] <= 5'd3)) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1; ctrl.uses_rs1 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_op = rv64_pkg::FP_CVT_I2F;
              ctrl.fp_fmt = {1'b0, instr[25]};
              ctrl.fp_int_fmt = instr[21:20];
              ctrl.fp_rm = instr[14:12];
            end
          end
          7'b1110000, 7'b1110001: begin // FMV.X.* and FCLASS.*
            if (instr[24:20] == 5'd0) begin
              case (instr[14:12])
                3'b000: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_MOVE_F2X; end
                3'b001: begin ctrl.legal = 1'b1; ctrl.fp_op = rv64_pkg::FP_CLASS; end
                default: begin end
              endcase
              if (ctrl.legal) begin
                ctrl.is_fp = 1'b1; ctrl.uses_frs1 = 1'b1;
                ctrl.uses_rd = 1'b1; ctrl.reg_write = 1'b1;
                ctrl.fp_fmt = {1'b0, instr[25]};
              end
            end
          end
          7'b1111000, 7'b1111001: begin // FMV.*.X
            if ((instr[24:20] == 5'd0) && (instr[14:12] == 3'b000)) begin
              ctrl.legal = 1'b1; ctrl.is_fp = 1'b1; ctrl.uses_rs1 = 1'b1;
              ctrl.fp_reg_write = 1'b1; ctrl.fp_op = rv64_pkg::FP_MOVE_X2F;
              ctrl.fp_fmt = {1'b0, instr[25]};
            end
          end
          default: begin end
        endcase
      end

      rv64_pkg::OPCODE_AMO: begin
        ctrl.uses_rs1  = 1'b1;
        ctrl.uses_rd   = 1'b1;
        ctrl.reg_write = 1'b1;
        ctrl.alu_op    = rv64_pkg::ALU_COPY_A;
        case (instr[14:12])
          3'b010: ctrl.mem_size = rv64_pkg::MEM_W;
          3'b011: ctrl.mem_size = rv64_pkg::MEM_D;
          default: ctrl.mem_size = rv64_pkg::MEM_NONE;
        endcase

        if (ctrl.mem_size != rv64_pkg::MEM_NONE) begin
          case (instr[31:27])
            5'b00010: begin
              if (instr[24:20] == 5'd0) begin
                ctrl.legal  = 1'b1;
                ctrl.is_amo = 1'b1;
                ctrl.amo_op = rv64_pkg::AMO_LR;
              end
            end
            5'b00011: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_SC;   end
            5'b00001: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_SWAP; end
            5'b00000: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_ADD;  end
            5'b00100: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_XOR;  end
            5'b01100: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_AND;  end
            5'b01000: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_OR;   end
            5'b10000: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_MIN;  end
            5'b10100: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_MAX;  end
            5'b11000: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_MINU; end
            5'b11100: begin ctrl.legal = 1'b1; ctrl.is_amo = 1'b1; ctrl.uses_rs2 = 1'b1; ctrl.amo_op = rv64_pkg::AMO_MAXU; end
            default: begin end
          endcase
        end
      end

      rv64_pkg::OPCODE_MISC_MEM: begin
        // FENCE is architecturally ordered; this core's in-order memory
        // system can implement it as a no-op. FENCE.I is outside RV64I.
        if (instr[14:12] == 3'b000) begin
          ctrl.legal     = 1'b1;
          ctrl.is_fence  = 1'b1;
        end else if ((instr[14:12] == 3'b001) && (instr[31:20] == 12'b0)) begin
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
        end else if ((instr[31:20] == 12'h001) || (instr[31:20] == 12'h002) ||
                     (instr[31:20] == 12'h003)) begin
          case (instr[14:12])
            3'b001: begin ctrl.legal = 1'b1; ctrl.csr_op = rv64_pkg::CSR_RW; end
            3'b010: begin ctrl.legal = 1'b1; ctrl.csr_op = rv64_pkg::CSR_RS; end
            3'b011: begin ctrl.legal = 1'b1; ctrl.csr_op = rv64_pkg::CSR_RC; end
            3'b101: begin ctrl.legal = 1'b1; ctrl.csr_op = rv64_pkg::CSR_RW; ctrl.csr_use_imm = 1'b1; end
            3'b110: begin ctrl.legal = 1'b1; ctrl.csr_op = rv64_pkg::CSR_RS; ctrl.csr_use_imm = 1'b1; end
            3'b111: begin ctrl.legal = 1'b1; ctrl.csr_op = rv64_pkg::CSR_RC; ctrl.csr_use_imm = 1'b1; end
            default: begin end
          endcase
          if (ctrl.legal) begin
            ctrl.is_csr = 1'b1;
            ctrl.uses_rd = 1'b1;
            ctrl.reg_write = 1'b1;
            ctrl.csr_addr = instr[31:20];
            if (!ctrl.csr_use_imm)
              ctrl.uses_rs1 = 1'b1;
          end
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
      ctrl.is_amo      = 1'b0;
      ctrl.is_csr      = 1'b0;
      ctrl.csr_use_imm = 1'b0;
      ctrl.uses_frs1   = 1'b0;
      ctrl.uses_frs2   = 1'b0;
      ctrl.uses_frs3   = 1'b0;
      ctrl.fp_reg_write = 1'b0;
      ctrl.fp_mem_read = 1'b0;
      ctrl.fp_mem_write = 1'b0;
      ctrl.is_fp       = 1'b0;
      ctrl.is_ecall    = 1'b0;
      ctrl.is_ebreak   = 1'b0;
      ctrl.alu_op      = rv64_pkg::ALU_NONE;
      ctrl.imm_type    = rv64_pkg::IMM_NONE;
      ctrl.branch      = rv64_pkg::BR_NONE;
      ctrl.mem_size    = rv64_pkg::MEM_NONE;
      ctrl.mdu_op      = rv64_pkg::MDU_MUL;
      ctrl.amo_op      = rv64_pkg::AMO_LR;
      ctrl.csr_op      = rv64_pkg::CSR_NONE;
      ctrl.csr_addr    = 12'b0;
      ctrl.fp_op       = rv64_pkg::FP_NONE;
    end
  end

endmodule
