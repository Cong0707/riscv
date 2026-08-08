`timescale 1ns/1ps

// End-to-end RV64F/D and fcsr smoke test over the core's separate I/D ports.
module tb_rv64fd_core;
  localparam logic [63:0] RESET_PC = 64'h0000_0000_8000_0000;
  localparam int MEM_BYTES = 4096;
  localparam logic [63:0] MEM_LIMIT = RESET_PC + 64'(MEM_BYTES);
  localparam int DATA_OFFSET = 512;

  logic clk_i;
  logic rst_ni;
  logic i_valid_o, i_ready_i;
  logic [63:0] i_addr_o;
  logic [31:0] i_rdata_i;
  logic d_valid_o, d_write_o, d_ready_i;
  logic [63:0] d_addr_o, d_wdata_o, d_rdata_i;
  logic [7:0] d_wstrb_o;
  logic [63:0] debug_pc_o;
  logic halted_o, trap_valid_o;
  logic [63:0] trap_cause_o, trap_tval_o;
  logic [7:0] mem [0:MEM_BYTES-1];
  integer i;
  integer cycles;
  integer reads;
  integer writes;
  logic trap_seen;

  rv64_core #(.RESET_PC(RESET_PC)) dut (
    .clk_i, .rst_ni,
    .i_valid_o, .i_addr_o, .i_ready_i, .i_rdata_i,
    .d_valid_o, .d_write_o, .d_addr_o, .d_wdata_o, .d_wstrb_o,
    .d_ready_i, .d_rdata_i,
    .debug_pc_o, .halted_o, .trap_valid_o, .trap_cause_o, .trap_tval_o
  );

  always #5 clk_i = ~clk_i;

  function automatic logic [31:0] i_type(
    input logic signed [11:0] imm,
    input logic [4:0] rs1,
    input logic [2:0] funct3,
    input logic [4:0] rd,
    input logic [6:0] opcode
  );
    i_type = {imm[11:0], rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] s_type(
    input logic signed [11:0] imm,
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input logic [2:0] funct3,
    input logic [6:0] opcode
  );
    s_type = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
  endfunction

  function automatic logic [31:0] fp_r_type(
    input logic [6:0] funct7,
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input logic [2:0] funct3,
    input logic [4:0] rd
  );
    fp_r_type = {funct7, rs2, rs1, funct3, rd, 7'b1010011};
  endfunction

  function automatic logic [31:0] fp_fma_type(
    input logic [6:0] opcode,
    input logic [4:0] rs3,
    input logic [1:0] fmt,
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input logic [2:0] rm,
    input logic [4:0] rd
  );
    fp_fma_type = {rs3, fmt, rs2, rs1, rm, rd, opcode};
  endfunction

  function automatic logic [31:0] csr_type(
    input logic [11:0] csr,
    input logic [4:0] rs1_or_zimm,
    input logic [2:0] funct3,
    input logic [4:0] rd
  );
    csr_type = {csr, rs1_or_zimm, funct3, rd, 7'b1110011};
  endfunction

  task automatic put32(input int unsigned offset, input logic [31:0] value);
    begin
      mem[offset + 0] = value[7:0];
      mem[offset + 1] = value[15:8];
      mem[offset + 2] = value[23:16];
      mem[offset + 3] = value[31:24];
    end
  endtask

  task automatic put64(input int unsigned offset, input logic [63:0] value);
    begin
      for (int unsigned lane = 0; lane < 8; lane++)
        mem[offset + lane] = value[lane*8 +: 8];
    end
  endtask

  task automatic check64(
    input int unsigned offset,
    input logic [63:0] expected,
    input string name
  );
    logic [63:0] actual;
    begin
      actual = 64'b0;
      for (int unsigned lane = 0; lane < 8; lane++)
        actual[lane*8 +: 8] = mem[offset + lane];
      if (actual !== expected)
        $fatal(1, "%s at +0x%03x got %016h expected %016h", name, offset,
               actual, expected);
      $display("[PASS] %-22s +0x%03x = %016h", name, offset, actual);
    end
  endtask

  task automatic check32(
    input int unsigned offset,
    input logic [31:0] expected,
    input string name
  );
    logic [31:0] actual;
    begin
      actual = {mem[offset + 3], mem[offset + 2], mem[offset + 1], mem[offset]};
      if (actual !== expected)
        $fatal(1, "%s at +0x%03x got %08h expected %08h", name, offset,
               actual, expected);
      $display("[PASS] %-22s +0x%03x = %08h", name, offset, actual);
    end
  endtask

  always_comb begin
    int unsigned i_index;
    int unsigned d_index;
    i_ready_i = i_valid_o;
    i_rdata_i = 32'b0;
    i_index = 0;
    if (i_valid_o && (i_addr_o >= RESET_PC) && (i_addr_o < MEM_LIMIT)) begin
      i_index = int'(i_addr_o - RESET_PC);
      for (int unsigned lane = 0; lane < 4; lane++)
        if ((i_index + lane) < MEM_BYTES)
          i_rdata_i[lane*8 +: 8] = mem[i_index + lane];
    end

    d_ready_i = d_valid_o;
    d_rdata_i = 64'b0;
    d_index = 0;
    if (d_valid_o && !d_write_o && (d_addr_o >= RESET_PC) &&
        (d_addr_o < MEM_LIMIT)) begin
      d_index = int'(d_addr_o - RESET_PC);
      for (int unsigned lane = 0; lane < 8; lane++)
        if ((d_index + lane) < MEM_BYTES)
          d_rdata_i[lane*8 +: 8] = mem[d_index + lane];
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      trap_seen <= 1'b0;
      reads <= 0;
      writes <= 0;
    end else begin
      if (trap_valid_o)
        trap_seen <= 1'b1;
      if (d_valid_o && d_ready_i) begin
        if (d_write_o) begin
          writes <= writes + 1;
          if (d_wstrb_o == 8'b0)
            $fatal(1, "zero-strobe data write");
          for (int unsigned lane = 0; lane < 8; lane++) begin
            if (d_wstrb_o[lane])
              mem[int'(d_addr_o - RESET_PC) + lane] <= d_wdata_o[lane*8 +: 8];
          end
        end else begin
          reads <= reads + 1;
        end
      end
    end
  end

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    cycles = 0;
    for (i = 0; i < MEM_BYTES; i = i + 1)
      mem[i] = 8'b0;

    // Source operands at DATA_OFFSET.  Stores begin at DATA_OFFSET + 64.
    put32(DATA_OFFSET + 0, 32'h3fc0_0000); // 1.5f
    put32(DATA_OFFSET + 4, 32'h4010_0000); // 2.25f
    put64(DATA_OFFSET + 8, 64'h3ff8_0000_0000_0000); // 1.5
    put64(DATA_OFFSET + 16, 64'h4002_0000_0000_0000); // 2.25

    put32(0,   {20'd0, 5'd1, 7'b0010111}); // auipc x1, 0
    put32(4,   i_type(12'sd512, 5'd1, 3'b000, 5'd1, 7'b0010011));
    put32(8,   i_type(12'sd0, 5'd1, 3'b010, 5'd1, 7'b0000111)); // flw f1,0(x1)
    put32(12,  i_type(12'sd4, 5'd1, 3'b010, 5'd2, 7'b0000111)); // flw f2,4(x1)
    put32(16,  fp_r_type(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3));
    put32(20,  s_type(12'sd64, 5'd3, 5'd1, 3'b010, 7'b0100111));
    put32(24,  fp_r_type(7'b0001000, 5'd2, 5'd3, 3'b000, 5'd4));
    put32(28,  s_type(12'sd68, 5'd4, 5'd1, 3'b010, 7'b0100111));
    put32(32,  fp_fma_type(7'b1000011, 5'd3, 2'b00, 5'd2, 5'd1, 3'b000, 5'd5));
    put32(36,  s_type(12'sd72, 5'd5, 5'd1, 3'b010, 7'b0100111));
    put32(40,  fp_r_type(7'b0001100, 5'd1, 5'd3, 3'b000, 5'd6));
    put32(44,  s_type(12'sd76, 5'd6, 5'd1, 3'b010, 7'b0100111));
    put32(48,  fp_r_type(7'b1110000, 5'd0, 5'd3, 3'b001, 5'd2)); // fclass.s x2,f3
    put32(52,  fp_r_type(7'b1100000, 5'd0, 5'd3, 3'b000, 5'd4)); // fcvt.w.s x4,f3
    put32(56,  csr_type(12'h001, 5'd0, 3'b010, 5'd5)); // csrrs x5,fflags,x0
    put32(60,  csr_type(12'h002, 5'd3, 3'b101, 5'd0)); // csrrwi x0,frm,3
    put32(64,  fp_r_type(7'b1100000, 5'd0, 5'd3, 3'b111, 5'd7)); // dynamic rm
    put32(68,  csr_type(12'h003, 5'd0, 3'b010, 5'd6)); // csrrs x6,fcsr,x0
    put32(72,  csr_type(12'h001, 5'd0, 3'b001, 5'd9)); // csrrw x9,fflags,x0
    put32(76,  csr_type(12'h001, 5'd0, 3'b010, 5'd10)); // csrrs x10,fflags,x0
    put32(80,  i_type(12'sd8, 5'd1, 3'b011, 5'd10, 7'b0000111)); // fld f10,8(x1)
    put32(84,  i_type(12'sd16, 5'd1, 3'b011, 5'd11, 7'b0000111));
    put32(88,  fp_r_type(7'b0000001, 5'd11, 5'd10, 3'b000, 5'd12));
    put32(92,  s_type(12'sd80, 5'd12, 5'd1, 3'b011, 7'b0100111));
    put32(96,  fp_r_type(7'b0100001, 5'd0, 5'd3, 3'b000, 5'd13));
    put32(100, s_type(12'sd88, 5'd13, 5'd1, 3'b011, 7'b0100111));
    put32(104, fp_r_type(7'b0100000, 5'd1, 5'd12, 3'b000, 5'd14));
    put32(108, s_type(12'sd96, 5'd14, 5'd1, 3'b010, 7'b0100111));
    put32(112, fp_r_type(7'b0010001, 5'd10, 5'd12, 3'b000, 5'd15));
    put32(116, s_type(12'sd104, 5'd15, 5'd1, 3'b011, 7'b0100111));
    put32(120, s_type(12'sd112, 5'd2, 5'd1, 3'b011, 7'b0100011));
    put32(124, s_type(12'sd120, 5'd4, 5'd1, 3'b011, 7'b0100011));
    put32(128, s_type(12'sd128, 5'd5, 5'd1, 3'b011, 7'b0100011));
    put32(132, s_type(12'sd136, 5'd6, 5'd1, 3'b011, 7'b0100011));
    put32(136, s_type(12'sd144, 5'd7, 5'd1, 3'b011, 7'b0100011));
    put32(140, s_type(12'sd152, 5'd9, 5'd1, 3'b011, 7'b0100011));
    put32(144, s_type(12'sd160, 5'd10, 5'd1, 3'b011, 7'b0100011));
    put32(148, 32'h0000_0073); // ecall

    repeat (5) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    while (!halted_o && (cycles < 3000)) begin
      @(posedge clk_i);
      cycles = cycles + 1;
    end
    #1;
    if (!halted_o)
      $fatal(1, "timeout pc=%h", debug_pc_o);
    if (!trap_seen || (trap_cause_o != 64'd11))
      $fatal(1, "expected ECALL trap, valid=%b cause=%h tval=%h", trap_seen,
             trap_cause_o, trap_tval_o);

    check32(DATA_OFFSET + 64, 32'h4070_0000, "fadd.s store");
    check32(DATA_OFFSET + 68, 32'h4107_0000, "fmul.s store");
    check32(DATA_OFFSET + 72, 32'h40e4_0000, "fmadd.s store");
    check32(DATA_OFFSET + 76, 32'h4020_0000, "fdiv.s store");
    check64(DATA_OFFSET + 80, 64'h400e_0000_0000_0000, "fadd.d store");
    check64(DATA_OFFSET + 88, 64'h400e_0000_0000_0000, "fcvt.d.s store");
    check32(DATA_OFFSET + 96, 32'h4070_0000, "fcvt.s.d store");
    check64(DATA_OFFSET + 104, 64'h400e_0000_0000_0000, "fsgnj.d store");
    check64(DATA_OFFSET + 112, 64'h40, "fclass.s");
    check64(DATA_OFFSET + 120, 64'h4, "fcvt.w.s");
    check64(DATA_OFFSET + 128, 64'h1, "fflags read");
    check64(DATA_OFFSET + 136, 64'h61, "fcsr dynamic rm");
    check64(DATA_OFFSET + 144, 64'h4, "fcvt dynamic rm");
    check64(DATA_OFFSET + 152, 64'h1, "fflags clear old");
    check64(DATA_OFFSET + 160, 64'h0, "fflags clear new");
    if (reads < 4 || writes < 15)
      $fatal(1, "insufficient FP memory activity reads=%0d writes=%0d", reads, writes);
    $display("RV64FD core PASS: cycles=%0d reads=%0d writes=%0d", cycles, reads, writes);
    $finish;
  end
endmodule
