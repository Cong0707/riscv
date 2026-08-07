`timescale 1ns/1ps

module tb_rv64a_core;
  localparam logic [63:0] RESET_PC = 64'h0000_0000_8000_0000;
  localparam int MEM_BYTES = 8192;
  localparam int SIGNATURE_OFFSET = 4096;
  localparam logic [63:0] MEM_LIMIT = RESET_PC + 64'd8192;
  localparam logic [63:0] FAILED_SC_ADDR =
      RESET_PC + 64'h0000_0000_0000_1310;
  localparam string HEX_FILE = "sim/generated/rv64a_smoke.hex";

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
  integer read_cycles;
  integer write_cycles;
  integer word_write_cycles;
  integer dword_write_cycles;
  integer failed_sc_addr_writes;
  integer i;
  logic trap_seen;
  logic [63:0] seen_trap_cause;

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
    end else if (trap_valid_o) begin
      trap_seen <= 1'b1;
      seen_trap_cause <= trap_cause_o;
    end

    if (rst_ni && i_valid_o && i_ready_i) begin
      fetch_cycles <= fetch_cycles + 1;
      if ((i_addr_o < RESET_PC) || (i_addr_o >= MEM_LIMIT))
        $fatal(1, "instruction address outside test memory: %h", i_addr_o);
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

        if (d_addr_o == FAILED_SC_ADDR)
          failed_sc_addr_writes <= failed_sc_addr_writes + 1;

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
    read_cycles = 0;
    write_cycles = 0;
    word_write_cycles = 0;
    dword_write_cycles = 0;
    failed_sc_addr_writes = 0;
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

    if (!trap_seen || (seen_trap_cause !== 64'd11))
      $fatal(1, "expected ECALL trap cause 11, seen=%b cause=%016h tval=%016h",
             trap_seen, seen_trap_cause, trap_tval_o);

    check64(16'h000, 64'h0000_0000_0000_0011, "lr.w old");
    check64(16'h008, 64'h0000_0000_0000_0000, "sc.w success");
    check64(16'h010, 64'h0000_0000_0000_0011, "lr.d old");
    check64(16'h018, 64'h0000_0000_0000_0000, "sc.d success");
    check64(16'h020, 64'h0000_0000_0000_0001, "sc.d failure");
    check64(16'h028, 64'h0000_0000_0000_0005, "amoswap.w old");
    check64(16'h030, 64'h0000_0000_0000_0005, "amoswap.d old");
    check64(16'h038, 64'h0000_0000_0000_0005, "amoadd.w old");
    check64(16'h040, 64'h0000_0000_0000_0005, "amoadd.d old");
    check64(16'h048, 64'h0000_0000_0000_000f, "amoxor.w old");
    check64(16'h050, 64'h0000_0000_0000_000f, "amoxor.d old");
    check64(16'h058, 64'h0000_0000_0000_003f, "amoand.w old");
    check64(16'h060, 64'h0000_0000_0000_003f, "amoand.d old");
    check64(16'h068, 64'h0000_0000_0000_0030, "amoor.w old");
    check64(16'h070, 64'h0000_0000_0000_0030, "amoor.d old");
    check64(16'h078, 64'hffff_ffff_ffff_fffb, "amomin.w old");
    check64(16'h080, 64'hffff_ffff_ffff_fffb, "amomin.d old");
    check64(16'h088, 64'hffff_ffff_ffff_fffb, "amomax.w old");
    check64(16'h090, 64'hffff_ffff_ffff_fffb, "amomax.d old");
    check64(16'h098, 64'hffff_ffff_ffff_ffff, "amominu.w old");
    check64(16'h0a0, 64'hffff_ffff_ffff_ffff, "amominu.d old");
    check64(16'h0a8, 64'hffff_ffff_ffff_ffff, "amomaxu.w old");
    check64(16'h0b0, 64'hffff_ffff_ffff_ffff, "amomaxu.d old");

    check64(16'h300, 64'h0000_0000_0000_0017, "lr/sc.w final");
    check64(16'h308, 64'h0000_0000_0000_0017, "lr/sc.d final");
    check64(16'h310, 64'h0000_0000_0000_0025, "failed sc final");
    check64(16'h318, 64'h0000_0000_0000_0009, "amoswap.w final");
    check64(16'h320, 64'h0000_0000_0000_0009, "amoswap.d final");
    check64(16'h328, 64'h0000_0000_0000_0008, "amoadd.w final");
    check64(16'h330, 64'h0000_0000_0000_0008, "amoadd.d final");
    check64(16'h338, 64'h0000_0000_0000_003c, "amoxor.w final");
    check64(16'h340, 64'h0000_0000_0000_003c, "amoxor.d final");
    check64(16'h348, 64'h0000_0000_0000_0015, "amoand.w final");
    check64(16'h350, 64'h0000_0000_0000_0015, "amoand.d final");
    check64(16'h358, 64'h0000_0000_0000_003f, "amoor.w final");
    check64(16'h360, 64'h0000_0000_0000_003f, "amoor.d final");
    check64(16'h368, 64'h0000_0000_ffff_fffb, "amomin.w final");
    check64(16'h370, 64'hffff_ffff_ffff_fffb, "amomin.d final");
    check64(16'h378, 64'h0000_0000_0000_0003, "amomax.w final");
    check64(16'h380, 64'h0000_0000_0000_0003, "amomax.d final");
    check64(16'h388, 64'h0000_0000_0000_0001, "amominu.w final");
    check64(16'h390, 64'h0000_0000_0000_0001, "amominu.d final");
    check64(16'h398, 64'h0000_0000_ffff_ffff, "amomaxu.w final");
    check64(16'h3a0, 64'hffff_ffff_ffff_ffff, "amomaxu.d final");

    if (read_cycles != 21 || write_cycles != 65)
      $fatal(1, "unexpected data traffic: read=%0d write=%0d",
             read_cycles, write_cycles);
    if (word_write_cycles != 20 || dword_write_cycles != 45)
      $fatal(1, "unexpected write widths: wstrb0f=%0d wstrbff=%0d",
             word_write_cycles, dword_write_cycles);
    if (failed_sc_addr_writes != 2)
      $fatal(1, "failed SC issued a write: target write count=%0d, expected 2",
             failed_sc_addr_writes);
    if (fetch_cycles < 135)
      $fatal(1, "too few instruction fetches: %0d", fetch_cycles);

    $display("RV64A smoke test PASS: cycles=%0d fetches=%0d reads=%0d writes=%0d w=%0d d=%0d",
             cycle_count, fetch_cycles, read_cycles, write_cycles,
             word_write_cycles, dword_write_cycles);
    $finish;
  end

endmodule
