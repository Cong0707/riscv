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
  } if_id_t;

  typedef struct packed {
    logic         valid;
    logic [63:0]  pc;
    logic [31:0]  instr;
    logic [63:0]  imm;
    logic [63:0]  rs1_value;
    logic [63:0]  rs2_value;
    logic [4:0]   rs1;
    logic [4:0]   rs2;
    logic [4:0]   rd;
    decode_ctrl_t ctrl;
  } id_ex_t;

  typedef struct packed {
    logic         valid;
    logic [63:0]  wb_value;
    logic [63:0]  address;
    logic [63:0]  store_data;
    logic [4:0]   rd;
    decode_ctrl_t ctrl;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [63:0] wb_value;
    logic [4:0]  rd;
    logic        reg_write;
  } mem_wb_t;

  logic [63:0] pc_q;
  if_id_t      if_id_q;
  id_ex_t      id_ex_q;
  ex_mem_t     ex_mem_q;
  mem_wb_t     mem_wb_q;

  logic        halted_q;
  logic        trap_valid_q;
  logic [63:0] trap_cause_q;
  logic [63:0] trap_tval_q;

  logic [4:0]   id_rs1;
  logic [4:0]   id_rs2;
  logic [4:0]   id_rd;
  decode_ctrl_t id_ctrl;
  logic [63:0]  id_imm;
  logic [63:0]  rf_rs1_value;
  logic [63:0]  rf_rs2_value;
  logic [63:0]  id_rs1_value;
  logic [63:0]  id_rs2_value;

  logic [63:0] ex_rs1_value;
  logic [63:0] ex_rs2_value;
  logic [63:0] ex_alu_a;
  logic [63:0] ex_alu_b;
  alu_op_t     ex_alu_op;
  logic [63:0] ex_alu_result;
  logic        ex_cmp_eq;
  logic        ex_cmp_lt_signed;
  logic        ex_cmp_lt_unsigned;
  logic        ex_branch_taken;
  logic        ex_redirect;
  logic [63:0] ex_redirect_target;
  logic [63:0] ex_wb_value;
  logic        ex_exception;
  logic [63:0] ex_exception_cause;
  logic [63:0] ex_exception_tval;
  logic        ex_address_misaligned;

  logic        load_use_stall;
  logic        data_wait;
  logic [63:0] load_value;
  logic [7:0]  store_strobe;

  rv64_decoder decoder (
    .instr(if_id_q.instr),
    .rs1(id_rs1),
    .rs2(id_rs2),
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

  rv64_alu alu (
    .op(ex_alu_op),
    .a(ex_alu_a),
    .b(ex_alu_b),
    .result(ex_alu_result),
    .cmp_eq(ex_cmp_eq),
    .cmp_lt_signed(ex_cmp_lt_signed),
    .cmp_lt_unsigned(ex_cmp_lt_unsigned)
  );

  always_comb begin
    id_rs1_value = rf_rs1_value;
    id_rs2_value = rf_rs2_value;

    if (mem_wb_q.valid && mem_wb_q.reg_write && (mem_wb_q.rd != 5'd0)) begin
      if (id_ctrl.uses_rs1 && (id_rs1 == mem_wb_q.rd)) begin
        id_rs1_value = mem_wb_q.wb_value;
      end
      if (id_ctrl.uses_rs2 && (id_rs2 == mem_wb_q.rd)) begin
        id_rs2_value = mem_wb_q.wb_value;
      end
    end
  end

  always_comb begin
    ex_rs1_value = id_ex_q.rs1_value;
    ex_rs2_value = id_ex_q.rs2_value;

    if (mem_wb_q.valid && mem_wb_q.reg_write && (mem_wb_q.rd != 5'd0)) begin
      if (id_ex_q.ctrl.uses_rs1 && (id_ex_q.rs1 == mem_wb_q.rd)) begin
        ex_rs1_value = mem_wb_q.wb_value;
      end
      if (id_ex_q.ctrl.uses_rs2 && (id_ex_q.rs2 == mem_wb_q.rd)) begin
        ex_rs2_value = mem_wb_q.wb_value;
      end
    end

    if (ex_mem_q.valid && ex_mem_q.ctrl.reg_write && !ex_mem_q.ctrl.mem_read &&
        (ex_mem_q.rd != 5'd0)) begin
      if (id_ex_q.ctrl.uses_rs1 && (id_ex_q.rs1 == ex_mem_q.rd)) begin
        ex_rs1_value = ex_mem_q.wb_value;
      end
      if (id_ex_q.ctrl.uses_rs2 && (id_ex_q.rs2 == ex_mem_q.rd)) begin
        ex_rs2_value = ex_mem_q.wb_value;
      end
    end
  end

  always_comb begin
    ex_alu_op = id_ex_q.ctrl.alu_op;
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

    if (id_ex_q.ctrl.is_jal || id_ex_q.ctrl.is_jalr) begin
      ex_wb_value = id_ex_q.pc + 64'd4;
    end else begin
      ex_wb_value = ex_alu_result;
    end
  end

  always_comb begin
    ex_address_misaligned = 1'b0;
    case (id_ex_q.ctrl.mem_size)
      MEM_H: ex_address_misaligned = ex_alu_result[0];
      MEM_W: ex_address_misaligned = |ex_alu_result[1:0];
      MEM_D: ex_address_misaligned = |ex_alu_result[2:0];
      default: begin end
    endcase

    ex_exception       = 1'b0;
    ex_exception_cause = 64'b0;
    ex_exception_tval  = 64'b0;

    if (id_ex_q.valid) begin
      if (id_ex_q.ctrl.illegal) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_ILLEGAL_INSTRUCTION;
        ex_exception_tval  = {32'b0, id_ex_q.instr};
      end else if (id_ex_q.ctrl.is_ebreak) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_BREAKPOINT;
        ex_exception_tval  = id_ex_q.pc;
      end else if (id_ex_q.ctrl.is_ecall) begin
        ex_exception       = 1'b1;
        ex_exception_cause = CAUSE_ECALL_MMODE;
        ex_exception_tval  = 64'b0;
      end else if (ex_redirect && (ex_redirect_target[1:0] != 2'b00)) begin
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
      end
    end
  end

  always_comb begin
    load_value = d_rdata_i;
    case (ex_mem_q.ctrl.mem_size)
      MEM_B: begin
        load_value = ex_mem_q.ctrl.mem_unsigned
                   ? {56'b0, d_rdata_i[7:0]}
                   : {{56{d_rdata_i[7]}}, d_rdata_i[7:0]};
      end
      MEM_H: begin
        load_value = ex_mem_q.ctrl.mem_unsigned
                   ? {48'b0, d_rdata_i[15:0]}
                   : {{48{d_rdata_i[15]}}, d_rdata_i[15:0]};
      end
      MEM_W: begin
        load_value = ex_mem_q.ctrl.mem_unsigned
                   ? {32'b0, d_rdata_i[31:0]}
                   : {{32{d_rdata_i[31]}}, d_rdata_i[31:0]};
      end
      default: begin end
    endcase
  end

  always_comb begin
    case (ex_mem_q.ctrl.mem_size)
      MEM_B: store_strobe = 8'b0000_0001;
      MEM_H: store_strobe = 8'b0000_0011;
      MEM_W: store_strobe = 8'b0000_1111;
      MEM_D: store_strobe = 8'b1111_1111;
      default: store_strobe = 8'b0000_0000;
    endcase
  end

  always_comb begin
    load_use_stall = id_ex_q.valid && id_ex_q.ctrl.mem_read &&
                     (id_ex_q.rd != 5'd0) && if_id_q.valid &&
                     ((id_ctrl.uses_rs1 && (id_rs1 == id_ex_q.rd)) ||
                      (id_ctrl.uses_rs2 && (id_rs2 == id_ex_q.rd)));

    data_wait = ex_mem_q.valid &&
                (ex_mem_q.ctrl.mem_read || ex_mem_q.ctrl.mem_write) &&
                !d_ready_i;
  end

  always_comb begin
    i_valid_o = rst_ni && !halted_q && !data_wait && !load_use_stall &&
                !ex_redirect && !ex_exception;
    i_addr_o  = pc_q;

    d_valid_o = rst_ni && !halted_q && ex_mem_q.valid &&
                (ex_mem_q.ctrl.mem_read || ex_mem_q.ctrl.mem_write);
    d_write_o = ex_mem_q.ctrl.mem_write;
    d_addr_o  = ex_mem_q.address;
    d_wdata_o = ex_mem_q.store_data;
    d_wstrb_o = ex_mem_q.ctrl.mem_write ? store_strobe : 8'b0;

    debug_pc_o   = pc_q;
    halted_o     = halted_q;
    trap_valid_o = trap_valid_q;
    trap_cause_o = trap_cause_q;
    trap_tval_o  = trap_tval_q;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pc_q         <= RESET_PC;
      if_id_q      <= '0;
      id_ex_q      <= '0;
      ex_mem_q     <= '0;
      mem_wb_q     <= '0;
      halted_q     <= 1'b0;
      trap_valid_q <= 1'b0;
      trap_cause_q <= 64'b0;
      trap_tval_q  <= 64'b0;
    end else if (halted_q) begin
      if_id_q.valid  <= 1'b0;
      id_ex_q.valid  <= 1'b0;
      ex_mem_q.valid <= 1'b0;
      mem_wb_q.valid <= 1'b0;
    end else if (data_wait) begin
      // The MEM operation is the oldest uncompleted instruction. Younger
      // stages and the fetch PC remain stable until the data port completes.
      mem_wb_q.valid <= 1'b0;
    end else begin
      mem_wb_q.valid     <= ex_mem_q.valid;
      mem_wb_q.rd        <= ex_mem_q.rd;
      mem_wb_q.reg_write <= ex_mem_q.ctrl.reg_write;
      mem_wb_q.wb_value  <= ex_mem_q.ctrl.mem_read
                          ? load_value
                          : ex_mem_q.wb_value;

      ex_mem_q.valid      <= id_ex_q.valid && !ex_exception;
      ex_mem_q.wb_value   <= ex_wb_value;
      ex_mem_q.address    <= ex_alu_result;
      ex_mem_q.store_data <= ex_rs2_value;
      ex_mem_q.rd         <= id_ex_q.rd;
      ex_mem_q.ctrl       <= id_ex_q.ctrl;

      if (ex_exception) begin
        halted_q      <= 1'b1;
        trap_valid_q  <= 1'b1;
        trap_cause_q  <= ex_exception_cause;
        trap_tval_q   <= ex_exception_tval;
        if_id_q.valid <= 1'b0;
        id_ex_q.valid <= 1'b0;
        ex_mem_q.valid <= 1'b0;
      end else if (ex_redirect) begin
        pc_q           <= ex_redirect_target;
        if_id_q.valid  <= 1'b0;
        id_ex_q.valid  <= 1'b0;
      end else if (load_use_stall) begin
        id_ex_q.valid <= 1'b0;
      end else begin
        id_ex_q.valid     <= if_id_q.valid;
        id_ex_q.pc        <= if_id_q.pc;
        id_ex_q.instr     <= if_id_q.instr;
        id_ex_q.imm       <= id_imm;
        id_ex_q.rs1_value <= id_rs1_value;
        id_ex_q.rs2_value <= id_rs2_value;
        id_ex_q.rs1       <= id_rs1;
        id_ex_q.rs2       <= id_rs2;
        id_ex_q.rd        <= id_rd;
        id_ex_q.ctrl      <= id_ctrl;

        if (i_valid_o && i_ready_i) begin
          if_id_q.valid <= 1'b1;
          if_id_q.pc    <= pc_q;
          if_id_q.instr <= i_rdata_i;
          pc_q          <= pc_q + 64'd4;
        end else begin
          if_id_q.valid <= 1'b0;
        end
      end
    end
  end

endmodule
