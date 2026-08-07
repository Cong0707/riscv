`timescale 1ns/1ps

module rv64_amo (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        start_i,
  input  logic [3:0]  op_i,
  input  logic        word_i,
  input  logic [63:0] addr_i,
  input  logic [63:0] operand_i,
  input  logic        reservation_clear_i,
  output logic        busy_o,
  output logic        done_o,
  output logic [63:0] result_o,
  output logic        mem_valid_o,
  output logic        mem_write_o,
  output logic [63:0] mem_addr_o,
  output logic [63:0] mem_wdata_o,
  output logic [7:0]  mem_wstrb_o,
  input  logic        mem_ready_i,
  input  logic [63:0] mem_rdata_i
);

  // Keep these encodings synchronized with rv64_pkg::amo_op_t.
  localparam logic [3:0] AMO_OP_LR   = 4'd0;
  localparam logic [3:0] AMO_OP_SC   = 4'd1;
  localparam logic [3:0] AMO_OP_SWAP = 4'd2;
  localparam logic [3:0] AMO_OP_ADD  = 4'd3;
  localparam logic [3:0] AMO_OP_XOR  = 4'd4;
  localparam logic [3:0] AMO_OP_AND  = 4'd5;
  localparam logic [3:0] AMO_OP_OR   = 4'd6;
  localparam logic [3:0] AMO_OP_MIN  = 4'd7;
  localparam logic [3:0] AMO_OP_MAX  = 4'd8;
  localparam logic [3:0] AMO_OP_MINU = 4'd9;
  localparam logic [3:0] AMO_OP_MAXU = 4'd10;

  localparam logic [1:0] STATE_IDLE  = 2'd0;
  localparam logic [1:0] STATE_READ  = 2'd1;
  localparam logic [1:0] STATE_WRITE = 2'd2;

  logic [1:0]  state_q;
  logic [3:0]  op_q;
  logic        word_q;
  logic [63:0] addr_q;
  logic [63:0] operand_q;
  logic [63:0] old_value_q;
  logic [63:0] new_value_q;
  logic        reservation_valid_q;
  logic        reservation_word_q;
  logic [63:0] reservation_addr_q;

  function automatic logic [63:0] loaded_value(
    input logic        word,
    input logic [63:0] data
  );
    begin
      loaded_value = word ? {{32{data[31]}}, data[31:0]} : data;
    end
  endfunction

  function automatic logic [63:0] calculate_new_value(
    input logic [3:0]  op,
    input logic        word,
    input logic [63:0] old_value,
    input logic [63:0] operand
  );
    logic [31:0] new_word;
    begin
      calculate_new_value = 64'b0;
      new_word = 32'b0;
      if (word) begin
        case (op)
          AMO_OP_SWAP: new_word = operand[31:0];
          AMO_OP_ADD:  new_word = old_value[31:0] + operand[31:0];
          AMO_OP_XOR:  new_word = old_value[31:0] ^ operand[31:0];
          AMO_OP_AND:  new_word = old_value[31:0] & operand[31:0];
          AMO_OP_OR:   new_word = old_value[31:0] | operand[31:0];
          AMO_OP_MIN:  new_word = ($signed(old_value[31:0]) < $signed(operand[31:0]))
                                     ? old_value[31:0] : operand[31:0];
          AMO_OP_MAX:  new_word = ($signed(old_value[31:0]) > $signed(operand[31:0]))
                                     ? old_value[31:0] : operand[31:0];
          AMO_OP_MINU: new_word = (old_value[31:0] < operand[31:0])
                                     ? old_value[31:0] : operand[31:0];
          AMO_OP_MAXU: new_word = (old_value[31:0] > operand[31:0])
                                     ? old_value[31:0] : operand[31:0];
          default: new_word = 32'b0;
        endcase
        calculate_new_value = {32'b0, new_word};
      end else begin
        case (op)
          AMO_OP_SWAP: calculate_new_value = operand;
          AMO_OP_ADD:  calculate_new_value = old_value + operand;
          AMO_OP_XOR:  calculate_new_value = old_value ^ operand;
          AMO_OP_AND:  calculate_new_value = old_value & operand;
          AMO_OP_OR:   calculate_new_value = old_value | operand;
          AMO_OP_MIN:  calculate_new_value = ($signed(old_value) < $signed(operand))
                                             ? old_value : operand;
          AMO_OP_MAX:  calculate_new_value = ($signed(old_value) > $signed(operand))
                                             ? old_value : operand;
          AMO_OP_MINU: calculate_new_value = (old_value < operand)
                                             ? old_value : operand;
          AMO_OP_MAXU: calculate_new_value = (old_value > operand)
                                             ? old_value : operand;
          default: calculate_new_value = 64'b0;
        endcase
      end
    end
  endfunction

  always_comb begin
    busy_o      = (state_q != STATE_IDLE);
    mem_valid_o = (state_q == STATE_READ) || (state_q == STATE_WRITE);
    mem_write_o = (state_q == STATE_WRITE);
    mem_addr_o  = addr_q;
    mem_wdata_o = word_q ? {32'b0, new_value_q[31:0]} : new_value_q;
    mem_wstrb_o = (state_q == STATE_WRITE)
                ? (word_q ? 8'h0f : 8'hff)
                : 8'h00;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q             <= STATE_IDLE;
      op_q                <= AMO_OP_LR;
      word_q              <= 1'b0;
      addr_q              <= 64'b0;
      operand_q           <= 64'b0;
      old_value_q         <= 64'b0;
      new_value_q         <= 64'b0;
      reservation_valid_q <= 1'b0;
      reservation_word_q  <= 1'b0;
      reservation_addr_q  <= 64'b0;
      done_o              <= 1'b0;
      result_o            <= 64'b0;
    end else begin
      done_o <= 1'b0;

      if (reservation_clear_i)
        reservation_valid_q <= 1'b0;

      case (state_q)
        STATE_IDLE: begin
          if (start_i) begin
            op_q      <= op_i;
            word_q    <= word_i;
            addr_q    <= addr_i;
            operand_q <= operand_i;

            if (op_i == AMO_OP_SC) begin
              reservation_valid_q <= 1'b0;
              if (reservation_valid_q &&
                  (reservation_addr_q == addr_i) &&
                  (reservation_word_q == word_i)) begin
                new_value_q <= word_i ? {32'b0, operand_i[31:0]} : operand_i;
                state_q <= STATE_WRITE;
              end else begin
                result_o <= 64'd1;
                done_o   <= 1'b1;
              end
            end else begin
              state_q <= STATE_READ;
            end
          end
        end

        STATE_READ: begin
          if (mem_ready_i) begin
            old_value_q <= loaded_value(word_q, mem_rdata_i);
            if (op_q == AMO_OP_LR) begin
              result_o            <= loaded_value(word_q, mem_rdata_i);
              reservation_valid_q <= 1'b1;
              reservation_word_q  <= word_q;
              reservation_addr_q  <= addr_q;
              state_q             <= STATE_IDLE;
              done_o              <= 1'b1;
            end else begin
              new_value_q <= calculate_new_value(
                op_q, word_q, mem_rdata_i, operand_q
              );
              state_q <= STATE_WRITE;
            end
          end
        end

        STATE_WRITE: begin
          if (mem_ready_i) begin
            result_o <= (op_q == AMO_OP_SC) ? 64'b0 : old_value_q;
            reservation_valid_q <= 1'b0;
            state_q <= STATE_IDLE;
            done_o  <= 1'b1;
          end
        end

        default: state_q <= STATE_IDLE;
      endcase
    end
  end

endmodule
