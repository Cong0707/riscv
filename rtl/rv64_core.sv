`timescale 1ns/1ps

module rv64_core #(
  parameter logic [63:0] RESET_PC = 64'h0000_0000_8000_0000
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  output logic        i_valid_o,
  output logic [63:0] i_addr_o,
  input  logic        i_ready_i,
  input  logic [31:0] i_rdata_i,

  output logic        d_valid_o,
  output logic        d_write_o,
  output logic [63:0] d_addr_o,
  output logic [63:0] d_wdata_o,
  output logic [7:0]  d_wstrb_o,
  input  logic        d_ready_i,
  input  logic [63:0] d_rdata_i,

  output logic [63:0] debug_pc_o,
  output logic        halted_o,
  output logic        trap_valid_o,
  output logic [63:0] trap_cause_o,
  output logic [63:0] trap_tval_o
);

  import rv64_pkg::*;

  localparam logic [63:0] CAUSE_INSTR_ADDR_MISALIGNED = 64'd0;
  localparam logic [63:0] CAUSE_ILLEGAL_INSTRUCTION   = 64'd2;
  localparam logic [63:0] CAUSE_BREAKPOINT            = 64'd3;
  localparam logic [63:0] CAUSE_LOAD_ADDR_MISALIGNED  = 64'd4;
  localparam logic [63:0] CAUSE_STORE_ADDR_MISALIGNED = 64'd6;
  localparam logic [63:0] CAUSE_ECALL_MMODE            = 64'd11;

  typedef struct packed {
    logic        valid;
    logic [63:0] pc;
    logic [31:0] instr;
    logic [31:0] original_instr;
    logic [2:0]  instr_len;
  } if_id_t;

  typedef struct packed {
    logic         valid;
    logic [63:0]  pc;
    logic [31:0]  original_instr;
    logic [2:0]   instr_len;
    logic [63:0]  imm;
    logic [63:0]  rs1_value;
    logic [63:0]  rs2_value;
    logic [63:0]  frs1_value;
    logic [63:0]  frs2_value;
    logic [63:0]  frs3_value;
    logic [4:0]   rs1;
    logic [4:0]   rs2;
    logic [4:0]   frs1;
    logic [4:0]   frs2;
    logic [4:0]   frs3;
    logic [4:0]   rd;
    decode_ctrl_t ctrl;
  } id_ex_t;

  typedef struct packed {
    logic         valid;
    logic [63:0]  wb_value;
    logic [63:0]  fp_wb_value;
    logic [63:0]  address;
    logic [63:0]  store_data;
    logic [7:0]   write_strobe;
    logic [4:0]   fp_flags;
    logic         csr_write;
    logic [63:0]  csr_value;
    logic [4:0]   rd;
    decode_ctrl_t ctrl;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [63:0] wb_value;
    logic [4:0]  rd;
    logic        reg_write;
    logic [63:0] fp_wb_value;
    logic        fp_reg_write;
    logic [4:0]  fp_flags;
    logic        is_fp;
    logic        csr_write;
    logic [11:0] csr_addr;
    logic [63:0] csr_value;
  } mem_wb_t;

  logic [63:0] pc_q;
  logic        fetch_cross_q;
  logic [15:0] fetch_low_half_q;
  if_id_t      if_id_q;
  id_ex_t      id_ex_q;
  ex_mem_t     ex_mem_q;
  mem_wb_t     mem_wb_q;

  logic        halted_q;
  logic        trap_pending_q;
  logic [63:0] trap_pending_cause_q;
  logic [63:0] trap_pending_tval_q;
  logic        trap_valid_q;
  logic [63:0] trap_cause_q;
  logic [63:0] trap_tval_q;
  logic [4:0]  fflags_q;
  logic [2:0]  frm_q;

  logic [4:0]   id_rs1;
  logic [4:0]   id_rs2;
  logic [4:0]   id_rs3;
  logic [4:0]   id_rd;
  decode_ctrl_t id_ctrl;
  logic [63:0]  id_imm;
  logic [63:0]  rf_rs1_value;
  logic [63:0]  rf_rs2_value;
  logic [63:0]  id_rs1_value;
  logic [63:0]  id_rs2_value;
  logic [63:0]  rf_frs1_value;
  logic [63:0]  rf_frs2_value;
  logic [63:0]  rf_frs3_value;
  logic [63:0]  id_frs1_value;
  logic [63:0]  id_frs2_value;
  logic [63:0]  id_frs3_value;

  logic [15:0] fetch_halfword;
  logic [31:0] decompressed_instr;
  logic        compressed_legal;
  logic        fetch_compressed;
  logic        fetch_complete;
  logic [31:0] fetch_instr;
  logic [31:0] fetch_original_instr;
  logic [2:0]  fetch_instr_len;

  logic [63:0] ex_rs1_value;
  logic [63:0] ex_rs2_value;
  logic [63:0] ex_frs1_value;
  logic [63:0] ex_frs2_value;
  logic [63:0] ex_frs3_value;
  logic [63:0] ex_alu_a;
  logic [63:0] ex_alu_b;
  alu_op_t     ex_alu_op;
  mdu_op_t     ex_mdu_op;
  amo_op_t     ex_amo_op;
  logic [63:0] ex_alu_result;
  logic        ex_cmp_eq;
  logic        ex_cmp_lt_signed;
  logic        ex_cmp_lt_unsigned;
  logic        ex_branch_taken;
  logic        ex_redirect;
  logic [63:0] ex_redirect_target;
  logic [63:0] ex_wb_value;
  logic [63:0] ex_fp_wb_value;
  logic        ex_exception;
  logic [63:0] ex_exception_cause;
  logic [63:0] ex_exception_tval;
  logic        ex_address_misaligned;

  logic        load_use_stall;
  logic        csr_hazard_stall;
  logic        data_wait;
  logic        mdu_start;
  logic        mdu_busy;
  logic        mdu_done;
  logic        mdu_wait;
  logic [63:0] mdu_result;
  logic        amo_start;
  logic        amo_busy;
  logic        amo_done;
  logic [63:0] amo_result;
  logic        amo_mem_valid;
  logic        amo_mem_write;
  logic [63:0] amo_mem_addr;
  logic [63:0] amo_mem_wdata;
  logic [7:0]  amo_mem_wstrb;
  logic        reservation_clear;
  logic [63:0] load_value;
  logic [63:0] fp_load_value;

  logic        fpu_start;
  logic        fpu_ready;
  logic        fpu_busy;
  logic        fpu_done;
  logic        fpu_wait;
  logic        fp_rm_invalid;
  logic [2:0]  fpu_rm;
  logic [63:0] fpu_result;
  logic [63:0] fpu_int_result;
  logic [4:0]  fpu_flags;
  fp_op_t      ex_fp_op;
  fp_fmt_t     ex_fp_fmt;
  fp_fmt_t     ex_fp_src_fmt;
  fp_int_fmt_t ex_fp_int_fmt;
  logic [1:0]  ex_fp_fma_op;

  logic [63:0] ex_csr_read_value;
  logic [63:0] ex_csr_source;
  logic [63:0] ex_csr_write_value;
  logic        ex_csr_write;

  function automatic logic [7:0] write_strobe_for_size(
    input logic [2:0] size
  );
    begin
      case (size)
        rv64_pkg::MEM_B: write_strobe_for_size = 8'b0000_0001;
        rv64_pkg::MEM_H: write_strobe_for_size = 8'b0000_0011;
        rv64_pkg::MEM_W: write_strobe_for_size = 8'b0000_1111;
        rv64_pkg::MEM_D: write_strobe_for_size = 8'b1111_1111;
        default: write_strobe_for_size = 8'b0000_0000;
      endcase
    end
  endfunction

  rv64_decoder decoder (
    .instr(if_id_q.instr),
    .rs1(id_rs1),
    .rs2(id_rs2),
    .rs3(id_rs3),
    .rd(id_rd),
    .ctrl(id_ctrl)
  );

  rv64_imm_gen imm_gen (
    .instr(if_id_q.instr),
    .imm_type(id_ctrl.imm_type),
    .imm(id_imm)
  );

  rv64_regfile regfile (
    .clk(clk_i),
    .rst(!rst_ni),
    .we(mem_wb_q.valid && mem_wb_q.reg_write),
    .waddr(mem_wb_q.rd),
    .wdata(mem_wb_q.wb_value),
    .raddr1(id_rs1),
    .raddr2(id_rs2),
    .rdata1(rf_rs1_value),
    .rdata2(rf_rs2_value)
  );

  rv64_fregfile fregfile (
    .clk(clk_i),
    .rst(!rst_ni),
    .we(mem_wb_q.valid && mem_wb_q.fp_reg_write),
    .waddr(mem_wb_q.rd),
    .wdata(mem_wb_q.fp_wb_value),
    .raddr1(id_rs1),
    .raddr2(id_rs2),
    .raddr3(id_rs3),
    .rdata1(rf_frs1_value),
    .rdata2(rf_frs2_value),
    .rdata3(rf_frs3_value)
  );

  rv64_alu alu (
    .op(ex_alu_op),
    .a(ex_alu_a),
    .b(ex_alu_b),
    .result(ex_alu_result),
    .cmp_eq(ex_cmp_eq),
    .cmp_lt_signed(ex_cmp_lt_signed),
    .cmp_lt_unsigned(ex_cmp_lt_unsigned)
  );

  rv64c_decompressor decompressor (
    .instr_i(fetch_halfword),
    .instr_o(decompressed_instr),
    .legal_o(compressed_legal)
  );

  rv64_mdu mdu (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(mdu_start),
    .op_i(ex_mdu_op),
    .a_i(ex_rs1_value),
    .b_i(ex_rs2_value),
    .busy_o(mdu_busy),
    .done_o(mdu_done),
    .result_o(mdu_result)
  );

  rv64_fpu fpu (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(fpu_start),
    .op_i(ex_fp_op),
    .fmt_i(ex_fp_fmt),
    .src_fmt_i(ex_fp_src_fmt),
    .int_fmt_i(ex_fp_int_fmt),
    .fma_op_i(ex_fp_fma_op),
    .rm_i(fpu_rm),
    .a_i(ex_frs1_value),
    .b_i(ex_frs2_value),
    .c_i(ex_frs3_value),
    .x_i(ex_rs1_value),
    .ready_o(fpu_ready),
    .busy_o(fpu_busy),
    .done_o(fpu_done),
    .result_o(fpu_result),
    .int_result_o(fpu_int_result),
    .flags_o(fpu_flags)
  );

  rv64_amo amo (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(amo_start),
    .op_i(ex_amo_op),
    .word_i(ex_mem_q.ctrl.mem_size == rv64_pkg::MEM_W),
    .addr_i(ex_mem_q.address),
    .operand_i(ex_mem_q.store_data),
    .reservation_clear_i(reservation_clear),
    .busy_o(amo_busy),
    .done_o(amo_done),
    .result_o(amo_result),
    .mem_valid_o(amo_mem_valid),
    .mem_write_o(amo_mem_write),
    .mem_addr_o(amo_mem_addr),
    .mem_wdata_o(amo_mem_wdata),
    .mem_wstrb_o(amo_mem_wstrb),
    .mem_ready_i(d_ready_i),
    .mem_rdata_i(d_rdata_i)
  );

  always_comb begin
    fpu_rm = id_ex_q.ctrl.fp_rm;
    if (id_ex_q.ctrl.fp_rm == 3'b111)
      fpu_rm = frm_q;
    fp_rm_invalid = id_ex_q.valid && id_ex_q.ctrl.is_fp && (fpu_rm > 3'b100);

    ex_csr_read_value = 64'b0;
    case (id_ex_q.ctrl.csr_addr)
      12'h001: ex_csr_read_value = {59'b0, fflags_q};
      12'h002: ex_csr_read_value = {61'b0, frm_q};
      12'h003: ex_csr_read_value = {56'b0, frm_q, fflags_q};
      default: begin end
    endcase

    ex_csr_source = id_ex_q.ctrl.csr_use_imm
                  ? {59'b0, id_ex_q.rs1} : ex_rs1_value;
    ex_csr_write_value = ex_csr_read_value;
    case (id_ex_q.ctrl.csr_op)
      CSR_RW: ex_csr_write_value = ex_csr_source;
      CSR_RS: ex_csr_write_value = ex_csr_read_value | ex_csr_source;
      CSR_RC: ex_csr_write_value = ex_csr_read_value & ~ex_csr_source;
      default: begin end
    endcase
    ex_csr_write = id_ex_q.valid && id_ex_q.ctrl.is_csr &&
                   ((id_ex_q.ctrl.csr_op == CSR_RW) || (ex_csr_source != 64'b0));
  end

  assign fpu_start = rst_ni && !halted_q && id_ex_q.valid &&
                     id_ex_q.ctrl.is_fp && !fp_rm_invalid &&
                     fpu_ready && !fpu_busy && !fpu_done && !data_wait;
  assign fpu_wait = id_ex_q.valid && id_ex_q.ctrl.is_fp &&
                    !fp_rm_invalid && !fpu_done;
  assign ex_fp_op = id_ex_q.ctrl.fp_op;
  assign ex_fp_fmt = id_ex_q.ctrl.fp_fmt;
  assign ex_fp_src_fmt = id_ex_q.ctrl.fp_src_fmt;
  assign ex_fp_int_fmt = id_ex_q.ctrl.fp_int_fmt;
  assign ex_fp_fma_op = id_ex_q.ctrl.fp_fma_op;

  assign reservation_clear = rst_ni && !ex_mem_q.ctrl.is_amo &&
                             d_valid_o && d_write_o && d_ready_i;
  assign fetch_halfword = pc_q[1] ? i_rdata_i[31:16] : i_rdata_i[15:0];

  always_comb begin
    fetch_compressed = (fetch_halfword[1:0] != 2'b11);
    fetch_complete = 1'b0;
    fetch_instr = 32'b0;
    fetch_original_instr = 32'b0;
    fetch_instr_len = 3'd4;

    if (fetch_cross_q) begin
      fetch_complete = 1'b1;
      fetch_instr = {i_rdata_i[15:0], fetch_low_half_q};
      fetch_original_instr = fetch_instr;
    end else if (fetch_compressed) begin
      fetch_complete = 1'b1;
      fetch_instr = compressed_legal ? decompressed_instr : 32'b0;
      fetch_original_instr = {16'b0, fetch_halfword};
      fetch_instr_len = 3'd2;
    end else if (!pc_q[1]) begin
      fetch_complete = 1'b1;
      fetch_instr = i_rdata_i;
      fetch_original_instr = i_rdata_i;
    end
  end

  always_comb begin
    id_rs1_value = rf_rs1_value;
    id_rs2_value = rf_rs2_value;
    id_frs1_value = rf_frs1_value;
    id_frs2_value = rf_frs2_value;
    id_frs3_value = rf_frs3_value;

    if (mem_wb_q.valid && mem_wb_q.reg_write && (mem_wb_q.rd != 5'd0)) begin
      if (id_ctrl.uses_rs1 && (id_rs1 == mem_wb_q.rd)) begin
        id_rs1_value = mem_wb_q.wb_value;
      end
      if (id_ctrl.uses_rs2 && (id_rs2 == mem_wb_q.rd)) begin
        id_rs2_value = mem_wb_q.wb_value;
      end
    end

    if (mem_wb_q.valid && mem_wb_q.fp_reg_write) begin
      if (id_ctrl.uses_frs1 && (id_rs1 == mem_wb_q.rd)) begin
        id_frs1_value = mem_wb_q.fp_wb_value;
      end
      if (id_ctrl.uses_frs2 && (id_rs2 == mem_wb_q.rd)) begin
        id_frs2_value = mem_wb_q.fp_wb_value;
      end
      if (id_ctrl.uses_frs3 && (id_rs3 == mem_wb_q.rd)) begin
        id_frs3_value = mem_wb_q.fp_wb_value;
      end
    end
  end

  always_comb begin
    ex_rs1_value = id_ex_q.rs1_value;
    ex_rs2_value = id_ex_q.rs2_value;
    ex_frs1_value = id_ex_q.frs1_value;
    ex_frs2_value = id_ex_q.frs2_value;
    ex_frs3_value = id_ex_q.frs3_value;

    if (mem_wb_q.valid && mem_wb_q.reg_write && (mem_wb_q.rd != 5'd0)) begin
      if (id_ex_q.ctrl.uses_rs1 && (id_ex_q.rs1 == mem_wb_q.rd)) begin
        ex_rs1_value = mem_wb_q.wb_value;
      end
      if (id_ex_q.ctrl.uses_rs2 && (id_ex_q.rs2 == mem_wb_q.rd)) begin
        ex_rs2_value = mem_wb_q.wb_value;
      end
    end

    if (ex_mem_q.valid && ex_mem_q.ctrl.reg_write && !ex_mem_q.ctrl.mem_read &&
        !ex_mem_q.ctrl.is_amo &&
        (ex_mem_q.rd != 5'd0)) begin
      if (id_ex_q.ctrl.uses_rs1 && (id_ex_q.rs1 == ex_mem_q.rd)) begin
        ex_rs1_value = ex_mem_q.wb_value;
      end
      if (id_ex_q.ctrl.uses_rs2 && (id_ex_q.rs2 == ex_mem_q.rd)) begin
        ex_rs2_value = ex_mem_q.wb_value;
      end
    end

    if (ex_mem_q.valid && ex_mem_q.ctrl.is_amo && amo_done &&
        (ex_mem_q.rd != 5'd0)) begin
      if (id_ex_q.ctrl.uses_rs1 && (id_ex_q.rs1 == ex_mem_q.rd)) begin
        ex_rs1_value = amo_result;
      end
      if (id_ex_q.ctrl.uses_rs2 && (id_ex_q.rs2 == ex_mem_q.rd)) begin
        ex_rs2_value = amo_result;
      end
    end

    if (mem_wb_q.valid && mem_wb_q.fp_reg_write) begin
      if (id_ex_q.ctrl.uses_frs1 && (id_ex_q.frs1 == mem_wb_q.rd)) begin
        ex_frs1_value = mem_wb_q.fp_wb_value;
      end
      if (id_ex_q.ctrl.uses_frs2 && (id_ex_q.frs2 == mem_wb_q.rd)) begin
        ex_frs2_value = mem_wb_q.fp_wb_value;
      end
      if (id_ex_q.ctrl.uses_frs3 && (id_ex_q.frs3 == mem_wb_q.rd)) begin
        ex_frs3_value = mem_wb_q.fp_wb_value;
      end
    end

    if (ex_mem_q.valid && ex_mem_q.ctrl.fp_reg_write &&
        !ex_mem_q.ctrl.fp_mem_read) begin
      if (id_ex_q.ctrl.uses_frs1 && (id_ex_q.frs1 == ex_mem_q.rd)) begin
        ex_frs1_value = ex_mem_q.fp_wb_value;
      end
      if (id_ex_q.ctrl.uses_frs2 && (id_ex_q.frs2 == ex_mem_q.rd)) begin
        ex_frs2_value = ex_mem_q.fp_wb_value;
      end
      if (id_ex_q.ctrl.uses_frs3 && (id_ex_q.frs3 == ex_mem_q.rd)) begin
        ex_frs3_value = ex_mem_q.fp_wb_value;
      end
    end
  end

  always_comb begin
    ex_alu_op = id_ex_q.ctrl.alu_op;
    ex_mdu_op = id_ex_q.ctrl.mdu_op;
    ex_amo_op = ex_mem_q.ctrl.amo_op;
    ex_alu_a = id_ex_q.ctrl.alu_src_pc ? id_ex_q.pc : ex_rs1_value;
    ex_alu_b = id_ex_q.ctrl.alu_src_imm ? id_ex_q.imm : ex_rs2_value;

    ex_branch_taken = 1'b0;
    case (id_ex_q.ctrl.branch)
      BR_EQ:  ex_branch_taken = ex_cmp_eq;
      BR_NE:  ex_branch_taken = !ex_cmp_eq;
      BR_LT:  ex_branch_taken = ex_cmp_lt_signed;
      BR_GE:  ex_branch_taken = !ex_cmp_lt_signed;
      BR_LTU: ex_branch_taken = ex_cmp_lt_unsigned;
      BR_GEU: ex_branch_taken = !ex_cmp_lt_unsigned;
      default: begin end
    endcase

    ex_redirect = id_ex_q.valid &&
                  (id_ex_q.ctrl.is_jal || id_ex_q.ctrl.is_jalr ||
                   (id_ex_q.ctrl.is_branch && ex_branch_taken));

    if (id_ex_q.ctrl.is_jalr) begin
      ex_redirect_target = (ex_rs1_value + id_ex_q.imm) & ~64'd1;
    end else begin
      ex_redirect_target = id_ex_q.pc + id_ex_q.imm;
    end

    ex_fp_wb_value = fpu_result;
    if (id_ex_q.ctrl.is_fp && id_ex_q.ctrl.reg_write) begin
      ex_wb_value = fpu_int_result;
    end else if (id_ex_q.ctrl.is_csr) begin
      ex_wb_value = ex_csr_read_value;
    end else if (id_ex_q.ctrl.is_mdu) begin
      ex_wb_value = mdu_result;
    end else if (id_ex_q.ctrl.is_jal || id_ex_q.ctrl.is_jalr) begin
      ex_wb_value = id_ex_q.pc + {61'b0, id_ex_q.instr_len};
    end else begin
      ex_wb_value = ex_alu_result;
    end
  end

  always_comb begin
    ex_address_misaligned = 1'b0;
    case (id_ex_q.ctrl.mem_size)
      rv64_pkg::MEM_H: ex_address_misaligned = ex_alu_result[0];
      rv64_pkg::MEM_W: ex_address_misaligned = |ex_alu_result[1:0];
      rv64_pkg::MEM_D: ex_address_misaligned = |ex_alu_result[2:0];
      default: begin end
    endcase

    ex_exception       = 1'b0;
    ex_exception_cause = 64'b0;
    ex_exception_tval  = 64'b0;

    if (id_ex_q.valid) begin
      if (id_ex_q.ctrl.illegal) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
        ex_exception_tval  = {32'b0, id_ex_q.original_instr};
      end else if (fp_rm_invalid) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
        ex_exception_tval  = {32'b0, id_ex_q.original_instr};
      end else if (id_ex_q.ctrl.is_ebreak) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_BREAKPOINT;
        ex_exception_tval  = id_ex_q.pc;
      end else if (id_ex_q.ctrl.is_ecall) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_ECALL_MMODE;
        ex_exception_tval  = 64'b0;
      end else if (ex_redirect && ex_redirect_target[0]) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_INSTR_ADDR_MISALIGNED;
        ex_exception_tval  = ex_redirect_target;
      end else if (id_ex_q.ctrl.mem_read && ex_address_misaligned) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_LOAD_ADDR_MISALIGNED;
        ex_exception_tval  = ex_alu_result;
      end else if (id_ex_q.ctrl.mem_write && ex_address_misaligned) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_STORE_ADDR_MISALIGNED;
        ex_exception_tval  = ex_alu_result;
      end else if (id_ex_q.ctrl.is_amo && ex_address_misaligned) begin
        ex_exception       = 1'b1;
        ex_exception_cause = (id_ex_q.ctrl.amo_op == AMO_LR)
                           ? CAUSE_LOAD_ADDR_MISALIGNED
                           : CAUSE_STORE_ADDR_MISALIGNED;
        ex_exception_tval  = ex_alu_result;
      end
    end
  end

  always_comb begin
    load_value = d_rdata_i;
    fp_load_value = d_rdata_i;
    case (ex_mem_q.ctrl.mem_size)
      rv64_pkg::MEM_B: begin
        load_value = ex_mem_q.ctrl.mem_unsigned
                   ? {56'b0, d_rdata_i[7:0]}
                   : {{56{d_rdata_i[7]}}, d_rdata_i[7:0]};
      end
      rv64_pkg::MEM_H: begin
        load_value = ex_mem_q.ctrl.mem_unsigned
                   ? {48'b0, d_rdata_i[15:0]}
                   : {{48{d_rdata_i[15]}}, d_rdata_i[15:0]};
      end
      rv64_pkg::MEM_W: begin
        load_value = ex_mem_q.ctrl.mem_unsigned
                   ? {32'b0, d_rdata_i[31:0]}
                   : {{32{d_rdata_i[31]}}, d_rdata_i[31:0]};
      end
      default: begin end
    endcase

    if (ex_mem_q.ctrl.fp_mem_read &&
        (ex_mem_q.ctrl.mem_size == rv64_pkg::MEM_W)) begin
      fp_load_value = {32'hffff_ffff, d_rdata_i[31:0]};
    end
  end

  always_comb begin
    load_use_stall = 1'b0;
    if (id_ex_q.valid && id_ex_q.ctrl.mem_read && if_id_q.valid) begin
      if (id_ex_q.ctrl.reg_write && (id_ex_q.rd != 5'd0)) begin
        load_use_stall = (id_ctrl.uses_rs1 && (id_rs1 == id_ex_q.rd)) ||
                         (id_ctrl.uses_rs2 && (id_rs2 == id_ex_q.rd));
      end
      if (id_ex_q.ctrl.fp_reg_write) begin
        load_use_stall = load_use_stall ||
                         (id_ctrl.uses_frs1 && (id_rs1 == id_ex_q.rd)) ||
                         (id_ctrl.uses_frs2 && (id_rs2 == id_ex_q.rd)) ||
                         (id_ctrl.uses_frs3 && (id_rs3 == id_ex_q.rd));
      end
    end

    csr_hazard_stall = 1'b0;
    if (if_id_q.valid && id_ctrl.is_csr) begin
      csr_hazard_stall =
        (id_ex_q.valid && (id_ex_q.ctrl.is_csr || id_ex_q.ctrl.is_fp)) ||
        (ex_mem_q.valid && (ex_mem_q.ctrl.is_csr || ex_mem_q.ctrl.is_fp)) ||
        (mem_wb_q.valid && (mem_wb_q.csr_write || mem_wb_q.is_fp));
    end else if (if_id_q.valid && id_ctrl.is_fp && (id_ctrl.fp_rm == 3'b111)) begin
      csr_hazard_stall =
        (id_ex_q.valid && id_ex_q.ctrl.is_csr) ||
        (ex_mem_q.valid && ex_mem_q.ctrl.is_csr) ||
        (mem_wb_q.valid && mem_wb_q.csr_write);
    end

    data_wait = ex_mem_q.valid &&
                (ex_mem_q.ctrl.mem_read || ex_mem_q.ctrl.mem_write) &&
                !d_ready_i;
    if (ex_mem_q.valid && ex_mem_q.ctrl.is_amo)
      data_wait = !amo_done;

    mdu_wait = id_ex_q.valid && id_ex_q.ctrl.is_mdu && !mdu_done;
    mdu_start = rst_ni && id_ex_q.valid && id_ex_q.ctrl.is_mdu &&
                !mdu_busy && !mdu_done && !data_wait;
    amo_start = rst_ni && !halted_q && ex_mem_q.valid &&
                ex_mem_q.ctrl.is_amo && !amo_busy && !amo_done;
  end

  always_comb begin
    i_valid_o = rst_ni && !halted_q && !trap_pending_q &&
                 !data_wait && !mdu_wait && !fpu_wait && !load_use_stall &&
                 !csr_hazard_stall &&
                !ex_redirect && !ex_exception;
    i_addr_o  = fetch_cross_q
              ? ((pc_q & ~64'd3) + 64'd4)
              : (pc_q & ~64'd3);

    d_valid_o = rst_ni && !halted_q && ex_mem_q.valid &&
                (ex_mem_q.ctrl.mem_read || ex_mem_q.ctrl.mem_write);
    d_write_o = ex_mem_q.ctrl.mem_write;
    d_addr_o  = ex_mem_q.address;
    d_wdata_o = ex_mem_q.store_data;
    d_wstrb_o = ex_mem_q.ctrl.mem_write ? ex_mem_q.write_strobe : 8'b0;
    if (ex_mem_q.ctrl.is_amo) begin
      d_valid_o = rst_ni && !halted_q && amo_mem_valid;
      d_write_o = amo_mem_write;
      d_addr_o  = amo_mem_addr;
      d_wdata_o = amo_mem_wdata;
      d_wstrb_o = amo_mem_wstrb;
    end

    debug_pc_o   = pc_q;
    halted_o     = halted_q;
    trap_valid_o = trap_valid_q;
    trap_cause_o = trap_cause_q;
    trap_tval_o  = trap_tval_q;
  end

  // FP flags and the three fcsr aliases become architecturally visible only
  // when their instruction reaches WB.  This preserves precise trap behavior.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fflags_q <= 5'b0;
      frm_q <= 3'b0;
    end else if (mem_wb_q.valid && mem_wb_q.csr_write) begin
      case (mem_wb_q.csr_addr)
        12'h001: fflags_q <= mem_wb_q.csr_value[4:0];
        12'h002: frm_q <= mem_wb_q.csr_value[2:0];
        12'h003: begin
          fflags_q <= mem_wb_q.csr_value[4:0];
          frm_q <= mem_wb_q.csr_value[7:5];
        end
        default: begin end
      endcase
    end else if (mem_wb_q.valid && mem_wb_q.is_fp) begin
      fflags_q <= fflags_q | mem_wb_q.fp_flags;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pc_q         <= RESET_PC;
      fetch_cross_q <= 1'b0;
      fetch_low_half_q <= 16'b0;
      if_id_q      <= '0;
      id_ex_q      <= '0;
      ex_mem_q     <= '0;
      mem_wb_q     <= '0;
      halted_q       <= 1'b0;
      trap_pending_q <= 1'b0;
      trap_pending_cause_q <= 64'b0;
      trap_pending_tval_q  <= 64'b0;
      trap_valid_q  <= 1'b0;
      trap_cause_q  <= 64'b0;
      trap_tval_q   <= 64'b0;
    end else if (halted_q) begin
      fetch_cross_q <= 1'b0;
      if_id_q.valid  <= 1'b0;
      id_ex_q.valid  <= 1'b0;
      ex_mem_q.valid <= 1'b0;
      mem_wb_q.valid <= 1'b0;
    end else if (trap_pending_q) begin
      // The previous cycle moved the last older EX/MEM result into MEM/WB.
      // Publish the trap on the same edge that result retires in the regfile.
      halted_q          <= 1'b1;
      trap_pending_q    <= 1'b0;
      trap_valid_q      <= 1'b1;
      trap_cause_q      <= trap_pending_cause_q;
      trap_tval_q       <= trap_pending_tval_q;
      fetch_cross_q     <= 1'b0;
      if_id_q.valid     <= 1'b0;
      id_ex_q.valid     <= 1'b0;
      ex_mem_q.valid    <= 1'b0;
      mem_wb_q.valid    <= 1'b0;
    end else if (data_wait) begin
      // The MEM operation is the oldest uncompleted instruction. Younger
      // stages and the fetch PC remain stable until the data port completes.
      mem_wb_q.valid <= 1'b0;
    end else begin
      mem_wb_q.valid     <= ex_mem_q.valid;
      mem_wb_q.rd        <= ex_mem_q.rd;
      mem_wb_q.reg_write <= ex_mem_q.ctrl.reg_write;
      mem_wb_q.fp_reg_write <= ex_mem_q.ctrl.fp_reg_write;
      mem_wb_q.fp_flags <= ex_mem_q.fp_flags;
      mem_wb_q.is_fp <= ex_mem_q.ctrl.is_fp;
      mem_wb_q.csr_write <= ex_mem_q.csr_write;
      mem_wb_q.csr_addr <= ex_mem_q.ctrl.csr_addr;
      mem_wb_q.csr_value <= ex_mem_q.csr_value;
      if (ex_mem_q.ctrl.is_amo)
        mem_wb_q.wb_value <= amo_result;
      else if (ex_mem_q.ctrl.mem_read)
        mem_wb_q.wb_value <= load_value;
      else
        mem_wb_q.wb_value <= ex_mem_q.wb_value;
      if (ex_mem_q.ctrl.fp_mem_read)
        mem_wb_q.fp_wb_value <= fp_load_value;
      else
        mem_wb_q.fp_wb_value <= ex_mem_q.fp_wb_value;

      ex_mem_q.valid      <= id_ex_q.valid && !ex_exception;
      ex_mem_q.wb_value   <= ex_wb_value;
      ex_mem_q.fp_wb_value <= ex_fp_wb_value;
      ex_mem_q.address    <= ex_alu_result;
      ex_mem_q.store_data <= id_ex_q.ctrl.fp_mem_write
                           ? ex_frs2_value : ex_rs2_value;
      ex_mem_q.write_strobe <= write_strobe_for_size(id_ex_q.ctrl.mem_size);
      ex_mem_q.fp_flags <= id_ex_q.ctrl.is_fp ? fpu_flags : 5'b0;
      ex_mem_q.csr_write <= ex_csr_write;
      ex_mem_q.csr_value <= ex_csr_write_value;
      ex_mem_q.rd         <= id_ex_q.rd;
      ex_mem_q.ctrl       <= id_ex_q.ctrl;

      if (mdu_wait || fpu_wait) begin
        // Keep the M instruction and all younger work stable while allowing
        // older MEM/WB work to retire exactly once.
        ex_mem_q.valid <= 1'b0;
      end else if (ex_exception) begin
        trap_pending_q       <= 1'b1;
        trap_pending_cause_q <= ex_exception_cause;
        trap_pending_tval_q  <= ex_exception_tval;
        fetch_cross_q        <= 1'b0;
        if_id_q.valid        <= 1'b0;
        id_ex_q.valid        <= 1'b0;
        ex_mem_q.valid       <= 1'b0;
      end else if (ex_redirect) begin
        pc_q           <= ex_redirect_target;
        fetch_cross_q  <= 1'b0;
        if_id_q.valid  <= 1'b0;
        id_ex_q.valid  <= 1'b0;
      end else if (load_use_stall || csr_hazard_stall) begin
        id_ex_q.valid <= 1'b0;
      end else begin
        id_ex_q.valid     <= if_id_q.valid;
        id_ex_q.pc        <= if_id_q.pc;
        id_ex_q.original_instr <= if_id_q.original_instr;
        id_ex_q.instr_len <= if_id_q.instr_len;
        id_ex_q.imm       <= id_imm;
        id_ex_q.rs1_value <= id_rs1_value;
        id_ex_q.rs2_value <= id_rs2_value;
        id_ex_q.frs1_value <= id_frs1_value;
        id_ex_q.frs2_value <= id_frs2_value;
        id_ex_q.frs3_value <= id_frs3_value;
        id_ex_q.rs1       <= id_rs1;
        id_ex_q.rs2       <= id_rs2;
        id_ex_q.frs1      <= id_rs1;
        id_ex_q.frs2      <= id_rs2;
        id_ex_q.frs3      <= id_rs3;
        id_ex_q.rd        <= id_rd;
        id_ex_q.ctrl      <= id_ctrl;

        if (i_valid_o && i_ready_i) begin
          if (fetch_complete) begin
            if_id_q.valid          <= 1'b1;
            if_id_q.pc             <= pc_q;
            if_id_q.instr          <= fetch_instr;
            if_id_q.original_instr <= fetch_original_instr;
            if_id_q.instr_len      <= fetch_instr_len;
            pc_q                   <= pc_q + {61'b0, fetch_instr_len};
            fetch_cross_q          <= 1'b0;
          end else begin
            if_id_q.valid    <= 1'b0;
            fetch_cross_q    <= 1'b1;
            fetch_low_half_q <= fetch_halfword;
          end
        end else begin
          if_id_q.valid <= 1'b0;
        end
      end
    end
  end

endmodule
