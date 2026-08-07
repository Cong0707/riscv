`timescale 1ns/1ps

module rv64c_decompressor (
  input  logic [15:0] instr_i,
  output logic [31:0] instr_o,
  output logic        legal_o
);

  localparam logic [6:0] OPCODE_LOAD      = 7'b0000011;
  localparam logic [6:0] OPCODE_OP_IMM    = 7'b0010011;
  localparam logic [6:0] OPCODE_OP_IMM_32 = 7'b0011011;
  localparam logic [6:0] OPCODE_STORE     = 7'b0100011;
  localparam logic [6:0] OPCODE_OP        = 7'b0110011;
  localparam logic [6:0] OPCODE_LUI       = 7'b0110111;
  localparam logic [6:0] OPCODE_OP_32     = 7'b0111011;
  localparam logic [6:0] OPCODE_BRANCH    = 7'b1100011;
  localparam logic [6:0] OPCODE_JALR      = 7'b1100111;
  localparam logic [6:0] OPCODE_JAL       = 7'b1101111;

  localparam logic [31:0] RV64I_NOP    = 32'h0000_0013;
  localparam logic [31:0] RV64I_EBREAK = 32'h0010_0073;

  logic [4:0]  rd_c;
  logic [4:0]  rs2_c;
  logic [4:0]  rs1_p;
  logic [4:0]  rd_p;
  logic [4:0]  rs2_p;
  logic [5:0]  shamt_c;
  logic [11:0] ci_imm;
  logic [11:0] addi4spn_imm;
  logic [11:0] addi16sp_imm;
  logic [11:0] lw_imm;
  logic [11:0] ld_imm;
  logic [11:0] lwsp_imm;
  logic [11:0] ldsp_imm;
  logic [11:0] swsp_imm;
  logic [11:0] sdsp_imm;
  logic [12:1] cb_imm;
  logic [20:1] cj_imm;
  logic [19:0] lui_imm;

  function automatic logic [31:0] encode_r (
    input logic [6:0] funct7,
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [6:0] opcode
  );
    begin
      encode_r = {funct7, rs2, rs1, funct3, rd, opcode};
    end
  endfunction

  function automatic logic [31:0] encode_i (
    input logic [11:0] imm,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    begin
      encode_i = {imm, rs1, funct3, rd, opcode};
    end
  endfunction

  function automatic logic [31:0] encode_s (
    input logic [11:0] imm,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [6:0]  opcode
  );
    begin
      encode_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    end
  endfunction

  function automatic logic [31:0] encode_b (
    input logic [12:1] imm,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [6:0]  opcode
  );
    begin
      encode_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                  imm[4:1], imm[11], opcode};
    end
  endfunction

  function automatic logic [31:0] encode_u (
    input logic [19:0] imm,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    begin
      encode_u = {imm, rd, opcode};
    end
  endfunction

  function automatic logic [31:0] encode_j (
    input logic [20:1] imm,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    begin
      encode_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    end
  endfunction

  always @* begin
    rd_c  = instr_i[11:7];
    rs2_c = instr_i[6:2];
    rs1_p = {2'b01, instr_i[9:7]};
    rd_p  = {2'b01, instr_i[4:2]};
    rs2_p = {2'b01, instr_i[4:2]};

    shamt_c      = {instr_i[12], instr_i[6:2]};
    ci_imm       = {{6{instr_i[12]}}, instr_i[12], instr_i[6:2]};
    addi4spn_imm = {2'b00, instr_i[10:7], instr_i[12:11],
                    instr_i[5], instr_i[6], 2'b00};
    addi16sp_imm = {{3{instr_i[12]}}, instr_i[4:3], instr_i[5],
                    instr_i[2], instr_i[6], 4'b0000};
    lw_imm       = {5'b00000, instr_i[5], instr_i[12:10],
                    instr_i[6], 2'b00};
    ld_imm       = {4'b0000, instr_i[6:5], instr_i[12:10], 3'b000};
    lwsp_imm     = {4'b0000, instr_i[3:2], instr_i[12],
                    instr_i[6:4], 2'b00};
    ldsp_imm     = {3'b000, instr_i[4:2], instr_i[12],
                    instr_i[6:5], 3'b000};
    swsp_imm     = {4'b0000, instr_i[8:7], instr_i[12:9], 2'b00};
    sdsp_imm     = {3'b000, instr_i[9:7], instr_i[12:10], 3'b000};
    cb_imm       = {{4{instr_i[12]}}, instr_i[12], instr_i[6:5],
                    instr_i[2], instr_i[11:10], instr_i[4:3]};
    cj_imm       = {{9{instr_i[12]}}, instr_i[12], instr_i[8],
                    instr_i[10:9], instr_i[6], instr_i[7], instr_i[2],
                    instr_i[11], instr_i[5:3]};
    lui_imm      = {{14{instr_i[12]}}, instr_i[12], instr_i[6:2]};

    instr_o = RV64I_NOP;
    legal_o = 1'b0;

    case (instr_i[1:0])
      2'b00: begin
        case (instr_i[15:13])
          3'b000: begin // C.ADDI4SPN
            if (addi4spn_imm != 12'b0) begin
              instr_o = encode_i(addi4spn_imm, 5'd2, 3'b000,
                                 rd_p, OPCODE_OP_IMM);
              legal_o = 1'b1;
            end
          end

          3'b001: begin // C.FLD requires D
          end

          3'b010: begin // C.LW
            instr_o = encode_i(lw_imm, rs1_p, 3'b010, rd_p, OPCODE_LOAD);
            legal_o = 1'b1;
          end

          3'b011: begin // C.LD (RV64)
            instr_o = encode_i(ld_imm, rs1_p, 3'b011, rd_p, OPCODE_LOAD);
            legal_o = 1'b1;
          end

          3'b100: begin // Reserved
          end

          3'b101: begin // C.FSD requires D
          end

          3'b110: begin // C.SW
            instr_o = encode_s(lw_imm, rs2_p, rs1_p, 3'b010, OPCODE_STORE);
            legal_o = 1'b1;
          end

          3'b111: begin // C.SD (RV64)
            instr_o = encode_s(ld_imm, rs2_p, rs1_p, 3'b011, OPCODE_STORE);
            legal_o = 1'b1;
          end

          default: begin
          end
        endcase
      end

      2'b01: begin
        case (instr_i[15:13])
          3'b000: begin // C.ADDI, C.NOP, and HINTs
            legal_o = 1'b1;
            if ((rd_c != 5'd0) && (ci_imm != 12'b0)) begin
              instr_o = encode_i(ci_imm, rd_c, 3'b000, rd_c,
                                 OPCODE_OP_IMM);
            end
          end

          3'b001: begin // C.ADDIW (C.JAL is RV32 only)
            if (rd_c != 5'd0) begin
              instr_o = encode_i(ci_imm, rd_c, 3'b000, rd_c,
                                 OPCODE_OP_IMM_32);
              legal_o = 1'b1;
            end
          end

          3'b010: begin // C.LI; rd=x0 encodes a HINT
            legal_o = 1'b1;
            if (rd_c != 5'd0) begin
              instr_o = encode_i(ci_imm, 5'd0, 3'b000, rd_c,
                                 OPCODE_OP_IMM);
            end
          end

          3'b011: begin
            if (rd_c == 5'd2) begin // C.ADDI16SP
              if (addi16sp_imm != 12'b0) begin
                instr_o = encode_i(addi16sp_imm, 5'd2, 3'b000, 5'd2,
                                   OPCODE_OP_IMM);
                legal_o = 1'b1;
              end
            end else if (ci_imm != 12'b0) begin // C.LUI or rd=x0 HINT
              legal_o = 1'b1;
              if (rd_c != 5'd0) begin
                instr_o = encode_u(lui_imm, rd_c, OPCODE_LUI);
              end
            end
          end

          3'b100: begin
            case (instr_i[11:10])
              2'b00: begin // C.SRLI; shamt=0 is a HINT on RV64
                legal_o = 1'b1;
                if (shamt_c != 6'b0) begin
                  instr_o = encode_i({6'b000000, shamt_c}, rs1_p,
                                     3'b101, rs1_p, OPCODE_OP_IMM);
                end
              end

              2'b01: begin // C.SRAI; shamt=0 is a HINT on RV64
                legal_o = 1'b1;
                if (shamt_c != 6'b0) begin
                  instr_o = encode_i({6'b010000, shamt_c}, rs1_p,
                                     3'b101, rs1_p, OPCODE_OP_IMM);
                end
              end

              2'b10: begin // C.ANDI
                instr_o = encode_i(ci_imm, rs1_p, 3'b111, rs1_p,
                                   OPCODE_OP_IMM);
                legal_o = 1'b1;
              end

              2'b11: begin
                if (instr_i[12] == 1'b0) begin
                  case (instr_i[6:5])
                    2'b00: instr_o = encode_r(7'b0100000, rs2_p, rs1_p,
                                               3'b000, rs1_p, OPCODE_OP); // C.SUB
                    2'b01: instr_o = encode_r(7'b0000000, rs2_p, rs1_p,
                                               3'b100, rs1_p, OPCODE_OP); // C.XOR
                    2'b10: instr_o = encode_r(7'b0000000, rs2_p, rs1_p,
                                               3'b110, rs1_p, OPCODE_OP); // C.OR
                    2'b11: instr_o = encode_r(7'b0000000, rs2_p, rs1_p,
                                               3'b111, rs1_p, OPCODE_OP); // C.AND
                    default: instr_o = RV64I_NOP;
                  endcase
                  legal_o = 1'b1;
                end else begin
                  case (instr_i[6:5])
                    2'b00: begin // C.SUBW (RV64)
                      instr_o = encode_r(7'b0100000, rs2_p, rs1_p,
                                         3'b000, rs1_p, OPCODE_OP_32);
                      legal_o = 1'b1;
                    end
                    2'b01: begin // C.ADDW (RV64)
                      instr_o = encode_r(7'b0000000, rs2_p, rs1_p,
                                         3'b000, rs1_p, OPCODE_OP_32);
                      legal_o = 1'b1;
                    end
                    default: begin // Reserved without Zcb/Zcmp extensions
                    end
                  endcase
                end
              end

              default: begin
              end
            endcase
          end

          3'b101: begin // C.J
            instr_o = encode_j(cj_imm, 5'd0, OPCODE_JAL);
            legal_o = 1'b1;
          end

          3'b110: begin // C.BEQZ
            instr_o = encode_b(cb_imm, 5'd0, rs1_p, 3'b000,
                               OPCODE_BRANCH);
            legal_o = 1'b1;
          end

          3'b111: begin // C.BNEZ
            instr_o = encode_b(cb_imm, 5'd0, rs1_p, 3'b001,
                               OPCODE_BRANCH);
            legal_o = 1'b1;
          end

          default: begin
          end
        endcase
      end

      2'b10: begin
        case (instr_i[15:13])
          3'b000: begin // C.SLLI and HINTs
            legal_o = 1'b1;
            if ((rd_c != 5'd0) && (shamt_c != 6'b0)) begin
              instr_o = encode_i({6'b000000, shamt_c}, rd_c,
                                 3'b001, rd_c, OPCODE_OP_IMM);
            end
          end

          3'b001: begin // C.FLDSP requires D
          end

          3'b010: begin // C.LWSP; rd=x0 is reserved
            if (rd_c != 5'd0) begin
              instr_o = encode_i(lwsp_imm, 5'd2, 3'b010, rd_c,
                                 OPCODE_LOAD);
              legal_o = 1'b1;
            end
          end

          3'b011: begin // C.LDSP (RV64); rd=x0 is reserved
            if (rd_c != 5'd0) begin
              instr_o = encode_i(ldsp_imm, 5'd2, 3'b011, rd_c,
                                 OPCODE_LOAD);
              legal_o = 1'b1;
            end
          end

          3'b100: begin
            if (instr_i[12] == 1'b0) begin
              if (rs2_c == 5'd0) begin // C.JR
                if (rd_c != 5'd0) begin
                  instr_o = encode_i(12'b0, rd_c, 3'b000, 5'd0,
                                     OPCODE_JALR);
                  legal_o = 1'b1;
                end
              end else begin // C.MV; rd=x0 encodes a HINT
                legal_o = 1'b1;
                if (rd_c != 5'd0) begin
                  instr_o = encode_r(7'b0000000, rs2_c, 5'd0,
                                     3'b000, rd_c, OPCODE_OP);
                end
              end
            end else begin
              if (rs2_c == 5'd0) begin
                if (rd_c == 5'd0) begin // C.EBREAK
                  instr_o = RV64I_EBREAK;
                end else begin // C.JALR
                  instr_o = encode_i(12'b0, rd_c, 3'b000, 5'd1,
                                     OPCODE_JALR);
                end
                legal_o = 1'b1;
              end else begin // C.ADD; rd=x0 encodes a HINT
                legal_o = 1'b1;
                if (rd_c != 5'd0) begin
                  instr_o = encode_r(7'b0000000, rs2_c, rd_c,
                                     3'b000, rd_c, OPCODE_OP);
                end
              end
            end
          end

          3'b101: begin // C.FSDSP requires D
          end

          3'b110: begin // C.SWSP
            instr_o = encode_s(swsp_imm, rs2_c, 5'd2, 3'b010,
                               OPCODE_STORE);
            legal_o = 1'b1;
          end

          3'b111: begin // C.SDSP (RV64)
            instr_o = encode_s(sdsp_imm, rs2_c, 5'd2, 3'b011,
                               OPCODE_STORE);
            legal_o = 1'b1;
          end

          default: begin
          end
        endcase
      end

      default: begin // 2'b11 starts an uncompressed instruction
      end
    endcase
  end

endmodule
