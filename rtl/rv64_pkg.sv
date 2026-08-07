`timescale 1ns/1ps

package rv64_pkg;

  // Base integer opcode map. Extensions sharing these opcodes are selected
  // by funct fields in rv64_decoder.
  // These are logic typedefs rather than enum typedefs because Icarus 12 can
  // assert while elaborating package enums used in module ports. The named
  // constants retain the same width and encoding while remaining portable.
  typedef logic [6:0] opcode_t;
  localparam opcode_t OPCODE_LOAD      = 7'b0000011;
  localparam opcode_t OPCODE_MISC_MEM  = 7'b0001111;
  localparam opcode_t OPCODE_OP_IMM    = 7'b0010011;
  localparam opcode_t OPCODE_AUIPC     = 7'b0010111;
  localparam opcode_t OPCODE_OP_IMM_32 = 7'b0011011;
  localparam opcode_t OPCODE_STORE     = 7'b0100011;
  localparam opcode_t OPCODE_AMO       = 7'b0101111;
  localparam opcode_t OPCODE_OP        = 7'b0110011;
  localparam opcode_t OPCODE_LUI       = 7'b0110111;
  localparam opcode_t OPCODE_OP_32     = 7'b0111011;
  localparam opcode_t OPCODE_BRANCH    = 7'b1100011;
  localparam opcode_t OPCODE_JALR      = 7'b1100111;
  localparam opcode_t OPCODE_JAL       = 7'b1101111;
  localparam opcode_t OPCODE_SYSTEM    = 7'b1110011;

  typedef logic [4:0] alu_op_t;
  localparam alu_op_t ALU_ADD    = 5'd0;
  localparam alu_op_t ALU_SUB    = 5'd1;
  localparam alu_op_t ALU_SLL    = 5'd2;
  localparam alu_op_t ALU_SLT    = 5'd3;
  localparam alu_op_t ALU_SLTU   = 5'd4;
  localparam alu_op_t ALU_XOR    = 5'd5;
  localparam alu_op_t ALU_SRL    = 5'd6;
  localparam alu_op_t ALU_SRA    = 5'd7;
  localparam alu_op_t ALU_OR     = 5'd8;
  localparam alu_op_t ALU_AND    = 5'd9;
  localparam alu_op_t ALU_ADDW   = 5'd10;
  localparam alu_op_t ALU_SUBW   = 5'd11;
  localparam alu_op_t ALU_SLLW   = 5'd12;
  localparam alu_op_t ALU_SRLW   = 5'd13;
  localparam alu_op_t ALU_SRAW   = 5'd14;
  localparam alu_op_t ALU_COPY_B = 5'd15;
  localparam alu_op_t ALU_COPY_A = 5'd16;
  localparam alu_op_t ALU_NONE   = 5'd31;

  typedef logic [2:0] imm_type_t;
  localparam imm_type_t IMM_NONE = 3'd0;
  localparam imm_type_t IMM_I    = 3'd1;
  localparam imm_type_t IMM_S    = 3'd2;
  localparam imm_type_t IMM_B    = 3'd3;
  localparam imm_type_t IMM_U    = 3'd4;
  localparam imm_type_t IMM_J    = 3'd5;
  localparam imm_type_t IMM_Z    = 3'd6;

  typedef logic [3:0] branch_t;
  localparam branch_t BR_NONE = 4'd0;
  localparam branch_t BR_EQ   = 4'd1;
  localparam branch_t BR_NE   = 4'd2;
  localparam branch_t BR_LT   = 4'd3;
  localparam branch_t BR_GE   = 4'd4;
  localparam branch_t BR_LTU  = 4'd5;
  localparam branch_t BR_GEU  = 4'd6;

  typedef logic [2:0] mem_size_t;
  localparam mem_size_t MEM_NONE = 3'd0;
  localparam mem_size_t MEM_B    = 3'd1;
  localparam mem_size_t MEM_H    = 3'd2;
  localparam mem_size_t MEM_W    = 3'd3;
  localparam mem_size_t MEM_D    = 3'd4;

  typedef logic [3:0] mdu_op_t;
  localparam mdu_op_t MDU_MUL    = 4'd0;
  localparam mdu_op_t MDU_MULH   = 4'd1;
  localparam mdu_op_t MDU_MULHSU = 4'd2;
  localparam mdu_op_t MDU_MULHU  = 4'd3;
  localparam mdu_op_t MDU_DIV    = 4'd4;
  localparam mdu_op_t MDU_DIVU   = 4'd5;
  localparam mdu_op_t MDU_REM    = 4'd6;
  localparam mdu_op_t MDU_REMU   = 4'd7;
  localparam mdu_op_t MDU_MULW   = 4'd8;
  localparam mdu_op_t MDU_DIVW   = 4'd9;
  localparam mdu_op_t MDU_DIVUW  = 4'd10;
  localparam mdu_op_t MDU_REMW   = 4'd11;
  localparam mdu_op_t MDU_REMUW  = 4'd12;

  typedef logic [3:0] amo_op_t;
  localparam amo_op_t AMO_LR   = 4'd0;
  localparam amo_op_t AMO_SC   = 4'd1;
  localparam amo_op_t AMO_SWAP = 4'd2;
  localparam amo_op_t AMO_ADD  = 4'd3;
  localparam amo_op_t AMO_XOR  = 4'd4;
  localparam amo_op_t AMO_AND  = 4'd5;
  localparam amo_op_t AMO_OR   = 4'd6;
  localparam amo_op_t AMO_MIN  = 4'd7;
  localparam amo_op_t AMO_MAX  = 4'd8;
  localparam amo_op_t AMO_MINU = 4'd9;
  localparam amo_op_t AMO_MAXU = 4'd10;

  // Control information emitted by the instruction decoder.
  // alu_src_pc selects the current PC as the ALU A input (AUIPC and PC based
  // target calculations). alu_src_imm selects the decoded immediate as B.
  typedef struct packed {
    logic       legal;
    logic       illegal;
    logic       uses_rs1;
    logic       uses_rs2;
    logic       uses_rd;
    logic       reg_write;
    logic       mem_read;
    logic       mem_write;
    logic       mem_unsigned;
    logic       alu_src_imm;
    logic       alu_src_pc;
    logic       is_branch;
    logic       is_jal;
    logic       is_jalr;
    logic       is_fence;
    logic       is_mdu;
    logic       is_amo;
    logic       is_ecall;
    logic       is_ebreak;
    alu_op_t    alu_op;
    imm_type_t  imm_type;
    branch_t    branch;
    mem_size_t  mem_size;
    mdu_op_t    mdu_op;
    amo_op_t    amo_op;
  } decode_ctrl_t;

endpackage
