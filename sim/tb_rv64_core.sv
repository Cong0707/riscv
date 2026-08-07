`timescale 1ns/1ps

// Self-checking RV64I smoke test.  The memory is deliberately byte addressed.
// Instruction and data requests use the improved Harvard interface: fetches
// return four consecutive little-endian bytes, while data reads return eight
// bytes and data writes honor each byte in d_wstrb_o.
module tb_rv64_core;
  localparam logic [63:0] RESET_PC = 64'h0000_0000_8000_0000;
  localparam int MEM_BYTES = 8192;
  localparam int SIGNATURE_OFFSET = 4096;
  localparam logic [63:0] MEM_LIMIT = RESET_PC + 64'd8192;
  localparam string HEX_FILE = "sim/generated/rv64i_smoke.hex";

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
  integer bus_cycles;
  integer fetch_cycles;
  integer read_cycles;
  integer write_cycles;
  integer cycle_count;
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

  // The core has no wait-state protocol requirement in this smoke test.
  // Keeping ready combinational makes the memory model deterministic and
  // permits an implementation to issue independent fetch/data requests.
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
    if (rst_ni && (i_valid_o && i_ready_i || d_valid_o && d_ready_i)) begin
      bus_cycles <= bus_cycles + int'(i_valid_o && i_ready_i) +
                    int'(d_valid_o && d_ready_i);
    end
    if (rst_ni && i_valid_o && i_ready_i) begin
      fetch_cycles <= fetch_cycles + 1;
      if ((i_addr_o < RESET_PC) || (i_addr_o >= MEM_LIMIT))
        $fatal(1, "instruction address outside test memory: %h", i_addr_o);
    end
    if (rst_ni && d_valid_o && d_ready_i) begin
      if (d_write_o) begin
        write_cycles <= write_cycles + 1;
        if (d_wstrb_o == 8'b0)
          $fatal(1, "write transaction has no asserted byte strobe at %h", d_addr_o);
        if ((d_addr_o < RESET_PC) || (d_addr_o >= MEM_LIMIT))
          $fatal(1, "write address outside test memory: %h", d_addr_o);
        for (int unsigned lane = 0; lane < 8; lane++) begin
          if (d_wstrb_o[lane] &&
              ((int'(d_addr_o - RESET_PC) + lane) < MEM_BYTES))
            mem[int'(d_addr_o - RESET_PC) + lane] <= d_wdata_o[lane*8 +: 8];
          else if (d_wstrb_o[lane])
            $fatal(1, "write crosses test memory boundary at %h", d_addr_o);
        end
      end else begin
        read_cycles <= read_cycles + 1;
        if ((d_addr_o < RESET_PC) || (d_addr_o >= MEM_LIMIT))
          $fatal(1, "data read address outside test memory: %h", d_addr_o);
      end
    end
  end

  task automatic check64(input logic [15:0] offset, input logic [63:0] expected, input string name);
    logic [63:0] actual;
    begin
      actual = 64'b0;
      for (int unsigned lane = 0; lane < 8; lane++)
        actual[lane*8 +: 8] = mem[SIGNATURE_OFFSET + int'(offset) + lane];
      if (actual !== expected)
        $fatal(1, "signature %s at +%0d: expected %016h, got %016h", name, offset, expected, actual);
      $display("[PASS] %-16s +0x%03x = %016h", name, offset, actual);
    end
  endtask

  task automatic check8(input logic [15:0] offset, input logic [7:0] expected, input string name);
    begin
      if (mem[SIGNATURE_OFFSET + int'(offset)] !== expected)
        $fatal(1, "memory byte %s at +%0d: expected %02h, got %02h", name, offset, expected, mem[SIGNATURE_OFFSET + int'(offset)]);
      $display("[PASS] %-16s +0x%03x = %02h", name, offset, mem[SIGNATURE_OFFSET + int'(offset)]);
    end
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    bus_cycles = 0;
    fetch_cycles = 0;
    read_cycles = 0;
    write_cycles = 0;
    cycle_count = 0;
    for (i = 0; i < MEM_BYTES; i = i + 1)
      mem[i] = 8'b0;
    $readmemh(HEX_FILE, mem);

    repeat (5) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // Keep the timeout finite so a broken fetch/handshake cannot hang CI.
    while ((halted_o !== 1'b1) && cycle_count < 2000) begin
      @(posedge clk_i);
      cycle_count = cycle_count + 1;
    end
    if (halted_o !== 1'b1)
      $fatal(1, "timeout after %0d cycles; pc=%016h trap=%b cause=%016h", cycle_count, debug_pc_o, trap_valid_o, trap_cause_o);
    #1;

    if (!trap_seen)
      $fatal(1, "core halted without asserting trap_valid_o");
    if (seen_trap_cause !== 64'd11)
      $fatal(1, "expected ECALL cause 11, got %016h (tval=%016h)", seen_trap_cause, seen_trap_tval);

    check64(16'h000, 64'd17, "add/forward");
    check64(16'h008, 64'd18, "load-use");
    check64(16'h010, 64'd7, "branch flush");
    check64(16'h018, 64'd9, "jal target");
    check64(16'h020, RESET_PC + 64'd64, "jal link");
    check64(16'h028, 64'd12, "jalr target");
    check64(16'h030, RESET_PC + 64'd92, "jalr link");
    check64(16'h038, 64'hffff_ffff_ffff_fffe, "srai");
    check64(16'h040, 64'h3fff_ffff_ffff_fffe, "srli");
    check64(16'h048, 64'h0000_000a_0000_0000, "slli");
    check64(16'h050, 64'd13, "sub");
    check64(16'h058, 64'd16, "and");
    check64(16'h060, 64'd19, "or");
    check64(16'h068, 64'd3, "xor");
    check64(16'h070, 64'd1, "slt");
    check64(16'h078, 64'd0, "sltu");
    check64(16'h080, 64'h0000_0000_7fff_ffff, "addiw");
    check64(16'h088, 64'hffff_ffff_8000_0000, "slliw");
    check64(16'h090, 64'd1, "srliw");
    check64(16'h098, 64'hffff_ffff_ffff_ffff, "sraiw");
    check64(16'h0a0, 64'hffff_ffff_8000_0000, "addw");
    check64(16'h0a8, 64'h0000_0000_7fff_fffe, "subw");
    check64(16'h0b0, 64'd10, "sllw");
    check64(16'h0b8, 64'h0000_0000_4000_0000, "srlw");
    check64(16'h0c0, 64'hffff_ffff_ffff_ffff, "lb");
    check64(16'h0c8, 64'd255, "lbu");
    check64(16'h0d0, 64'hffff_ffff_ffff_fffe, "lh");
    check64(16'h0d8, 64'd65534, "lhu");
    check64(16'h0e0, 64'h0000_0000_1234_5678, "lw");
    check64(16'h0e8, 64'h0000_0000_1234_5678, "lwu");
    check64(16'h0f0, 64'hffff_ffff_8000_0000, "lw signed");
    check64(16'h0f8, 64'h0000_0000_8000_0000, "lwu unsigned");
    check8(16'h100, 8'hff, "sb byte 0");
    check8(16'h101, 8'h7f, "sb byte 1");
    check8(16'h102, 8'hfe, "sh byte 0");
    check8(16'h103, 8'hff, "sh byte 1");
    check8(16'h104, 8'h78, "sw byte 0");
    check8(16'h105, 8'h56, "sw byte 1");
    check8(16'h106, 8'h34, "sw byte 2");
    check8(16'h107, 8'h12, "sw byte 3");
    check8(16'h10c, 8'h00, "sw signed byte 0");
    check8(16'h10d, 8'h00, "sw signed byte 1");
    check8(16'h10e, 8'h00, "sw signed byte 2");
    check8(16'h10f, 8'h80, "sw signed byte 3");
    check64(16'h3f0, 64'b0, "jalr flush mark");
    check64(16'h3f8, 64'b0, "branch flush mark");
    if (fetch_cycles < 80 || write_cycles < 30 || read_cycles < 9)
      $fatal(1, "insufficient bus activity: fetches=%0d reads=%0d writes=%0d", fetch_cycles, read_cycles, write_cycles);
    $display("RV64I smoke test PASS: cycles=%0d bus=%0d fetches=%0d reads=%0d writes=%0d", cycle_count, bus_cycles, fetch_cycles, read_cycles, write_cycles);
    $finish;
  end
endmodule
