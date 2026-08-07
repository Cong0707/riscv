`timescale 1ns/1ps

module tb_rv64c_core;
  localparam logic [63:0] RESET_PC = 64'h0000_0000_8000_0000;
  localparam int MEM_BYTES = 8192;
  localparam int SIGNATURE_OFFSET = 4096;
  localparam logic [63:0] MEM_LIMIT = RESET_PC + 64'd8192;
  localparam string HEX_FILE = "sim/generated/rv64c_smoke.hex";

  logic clk_i;
  logic rst_ni;
  logic i_valid_o;
  logic [63:0] i_addr_o;
  logic i_ready_i;
  logic [31:0] i_rdata_i;
  logic d_valid_o;
  logic d_write_o;
  logic [63:0] d_addr_o;
  logic [63:0] d_wdata_o;
  logic [7:0] d_wstrb_o;
  logic d_ready_i;
  logic [63:0] d_rdata_i;
  logic [63:0] debug_pc_o;
  logic halted_o;
  logic trap_valid_o;
  logic [63:0] trap_cause_o;
  logic [63:0] trap_tval_o;

  logic [7:0] mem [0:MEM_BYTES-1];
  integer cycle_count;
  integer fetch_cycles;
  integer cross_fetch_cycles;
  integer halfword_pc_cycles;
  integer read_cycles;
  integer write_cycles;
  integer word_write_cycles;
  integer dword_write_cycles;
  integer i;
  logic trap_seen;
  logic [63:0] seen_trap_cause;
  logic [63:0] seen_trap_tval;

  rv64_core #(.RESET_PC(RESET_PC)) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .i_valid_o(i_valid_o),
    .i_addr_o(i_addr_o),
    .i_ready_i(i_ready_i),
    .i_rdata_i(i_rdata_i),
    .d_valid_o(d_valid_o),
    .d_write_o(d_write_o),
    .d_addr_o(d_addr_o),
    .d_wdata_o(d_wdata_o),
    .d_wstrb_o(d_wstrb_o),
    .d_ready_i(d_ready_i),
    .d_rdata_i(d_rdata_i),
    .debug_pc_o(debug_pc_o),
    .halted_o(halted_o),
    .trap_valid_o(trap_valid_o),
    .trap_cause_o(trap_cause_o),
    .trap_tval_o(trap_tval_o)
  );

  always #5 clk_i = ~clk_i;

  always_comb begin
    int unsigned i_index;
    int unsigned d_index;

    i_ready_i = i_valid_o;
    i_rdata_i = 32'b0;
    i_index = 0;
    if (i_valid_o && (i_addr_o >= RESET_PC) && (i_addr_o < MEM_LIMIT)) begin
      i_index = int'(i_addr_o - RESET_PC);
      for (int unsigned lane = 0; lane < 4; lane++) begin
        if ((i_index + lane) < MEM_BYTES)
          i_rdata_i[lane*8 +: 8] = mem[i_index + lane];
      end
    end

    d_ready_i = d_valid_o;
    d_rdata_i = 64'b0;
    d_index = 0;
    if (d_valid_o && !d_write_o &&
        (d_addr_o >= RESET_PC) && (d_addr_o < MEM_LIMIT)) begin
      d_index = int'(d_addr_o - RESET_PC);
      for (int unsigned lane = 0; lane < 8; lane++) begin
        if ((d_index + lane) < MEM_BYTES)
          d_rdata_i[lane*8 +: 8] = mem[d_index + lane];
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      trap_seen <= 1'b0;
      seen_trap_cause <= 64'b0;
      seen_trap_tval <= 64'b0;
    end else if (trap_valid_o) begin
      trap_seen <= 1'b1;
      seen_trap_cause <= trap_cause_o;
      seen_trap_tval <= trap_tval_o;
    end

    if (rst_ni && i_valid_o && i_ready_i) begin
      fetch_cycles <= fetch_cycles + 1;
      if ((i_addr_o < RESET_PC) || (i_addr_o >= MEM_LIMIT))
        $fatal(1, "instruction address outside test memory: %h", i_addr_o);
      if (i_addr_o[1:0] != 2'b00)
        $fatal(1, "external instruction request is not word aligned: %h", i_addr_o);
      if (dut.fetch_cross_q)
        cross_fetch_cycles <= cross_fetch_cycles + 1;
      if (dut.pc_q[1])
        halfword_pc_cycles <= halfword_pc_cycles + 1;
    end

    if (rst_ni && d_valid_o && d_ready_i) begin
      if ((d_addr_o < RESET_PC) || (d_addr_o >= MEM_LIMIT))
        $fatal(1, "data address outside test memory: %h", d_addr_o);
      if (d_write_o) begin
        write_cycles <= write_cycles + 1;
        case (d_wstrb_o)
          8'h0f: word_write_cycles <= word_write_cycles + 1;
          8'hff: dword_write_cycles <= dword_write_cycles + 1;
          default: $fatal(1, "unexpected write strobe %02h at %h",
                          d_wstrb_o, d_addr_o);
        endcase
        for (int unsigned lane = 0; lane < 8; lane++) begin
          if (d_wstrb_o[lane] &&
              ((int'(d_addr_o - RESET_PC) + lane) < MEM_BYTES))
            mem[int'(d_addr_o - RESET_PC) + lane] <= d_wdata_o[lane*8 +: 8];
          else if (d_wstrb_o[lane])
            $fatal(1, "write crosses test memory boundary at %h", d_addr_o);
        end
      end else begin
        read_cycles <= read_cycles + 1;
        if (d_wstrb_o != 8'h00)
          $fatal(1, "read transaction has write strobe %02h at %h",
                 d_wstrb_o, d_addr_o);
      end
    end
  end

  task automatic check64(
    input logic [15:0] offset,
    input logic [63:0] expected,
    input string name
  );
    logic [63:0] actual;
    begin
      actual = 64'b0;
      for (int unsigned lane = 0; lane < 8; lane++)
        actual[lane*8 +: 8] = mem[SIGNATURE_OFFSET + int'(offset) + lane];
      if (actual !== expected)
        $fatal(1, "value %s at +%0d: expected %016h, got %016h",
               name, offset, expected, actual);
      $display("[PASS] %-20s +0x%03x = %016h", name, offset, actual);
    end
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    cycle_count = 0;
    fetch_cycles = 0;
    cross_fetch_cycles = 0;
    halfword_pc_cycles = 0;
    read_cycles = 0;
    write_cycles = 0;
    word_write_cycles = 0;
    dword_write_cycles = 0;
    for (i = 0; i < MEM_BYTES; i = i + 1)
      mem[i] = 8'b0;
    $readmemh(HEX_FILE, mem);

    repeat (5) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    while ((halted_o !== 1'b1) && cycle_count < 4000) begin
      @(posedge clk_i);
      cycle_count = cycle_count + 1;
    end
    if (halted_o !== 1'b1)
      $fatal(1, "timeout after %0d cycles; pc=%016h", cycle_count, debug_pc_o);
    #1;

    if (!trap_seen || (seen_trap_cause !== 64'd3) ||
        (seen_trap_tval !== (RESET_PC + 64'h126)))
      $fatal(1, "expected C.EBREAK trap at +0x126, seen=%b cause=%016h tval=%016h",
             trap_seen, seen_trap_cause, seen_trap_tval);

    check64(16'h000, 64'h0000_0000_0000_0005, "cross-word addi");
    check64(16'h008, 64'h0000_0000_0000_0008, "c.addi");
    check64(16'h010, 64'h0000_0000_0000_0007, "c.addiw");
    check64(16'h018, 64'hffff_ffff_ffff_fffb, "c.li");
    check64(16'h020, 64'h0000_0000_0000_1000, "c.lui");
    check64(16'h028, 64'h0000_0000_8000_1310, "c.addi16sp");
    check64(16'h030, 64'h0000_0000_8000_1320, "c.addi4spn");
    check64(16'h038, 64'h0000_0000_0000_0015, "c.sd/c.ld");
    check64(16'h040, 64'hffff_ffff_ffff_ffff, "c.sw/c.lw");
    check64(16'h048, 64'h0000_0000_0000_0021, "c.sdsp/c.ldsp");
    check64(16'h050, 64'hffff_ffff_ffff_fffe, "c.swsp/c.lwsp");
    check64(16'h058, 64'h0000_0000_0000_0020, "c.slli");
    check64(16'h060, 64'h0000_0000_0000_0008, "c.srli");
    check64(16'h068, 64'hffff_ffff_ffff_fffc, "c.srai");
    check64(16'h070, 64'h0000_0000_0000_0004, "c.andi");
    check64(16'h078, 64'h0000_0000_0000_0011, "c.sub");
    check64(16'h080, 64'h0000_0000_0000_0017, "c.xor");
    check64(16'h088, 64'h0000_0000_0000_0017, "c.or");
    check64(16'h090, 64'h0000_0000_0000_0000, "c.and");
    check64(16'h098, 64'h0000_0000_7fff_ffff, "c.subw");
    check64(16'h0a0, 64'hffff_ffff_8000_0001, "c.addw");
    check64(16'h0a8, 64'h0000_0000_0000_0001, "c.mv");
    check64(16'h0b0, 64'h0000_0000_0000_0002, "c.add");
    check64(16'h0b8, 64'h0000_0000_0000_0001, "c.beqz taken");
    check64(16'h0c0, 64'h0000_0000_0000_0002, "c.bnez taken");
    check64(16'h0c8, 64'h0000_0000_0000_0003, "c.beqz not taken");
    check64(16'h0d0, 64'h0000_0000_0000_0004, "c.bnez not taken");
    check64(16'h0d8, 64'h0000_0000_0000_0005, "c.j");
    check64(16'h0e0, 64'h0000_0000_0000_002a, "c.jalr/c.jr");
    check64(16'h0e8, 64'h0000_0000_8000_0116, "c.jalr link");

    check64(16'h320, 64'h0000_0000_0000_0015, "c.sd data");
    check64(16'h328, 64'h0000_0000_ffff_ffff, "c.sw data");
    check64(16'h340, 64'h0000_0000_0000_0021, "c.sdsp data");
    check64(16'h348, 64'h0000_0000_ffff_fffe, "c.swsp data");

    if (read_cycles != 4 || write_cycles != 34)
      $fatal(1, "unexpected data traffic: read=%0d write=%0d",
             read_cycles, write_cycles);
    if (word_write_cycles != 2 || dword_write_cycles != 32)
      $fatal(1, "unexpected write widths: wstrb0f=%0d wstrbff=%0d",
             word_write_cycles, dword_write_cycles);
    if (cross_fetch_cycles == 0 || halfword_pc_cycles == 0)
      $fatal(1, "mixed-width fetch path was not observed: cross=%0d halfword_pc=%0d",
             cross_fetch_cycles, halfword_pc_cycles);

    $display("RV64C smoke test PASS: cycles=%0d fetches=%0d cross=%0d halfword_pc=%0d reads=%0d writes=%0d",
             cycle_count, fetch_cycles, cross_fetch_cycles,
             halfword_pc_cycles, read_cycles, write_cycles);
    $finish;
  end

endmodule
