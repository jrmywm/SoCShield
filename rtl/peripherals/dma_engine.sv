// Small single-outstanding DMA engine with a CPU-local MMIO control port.
module dma_engine (
  input wire clk, rst_n,
  input wire bus_valid, bus_write,
  input wire [11:0] bus_addr,
  input wire [31:0] bus_wdata,
  input wire [3:0] bus_wstrb,
  output reg [31:0] bus_rdata,
  output reg bus_error,

  output wire req_valid,
  input wire req_ready,
  output wire [31:0] req_addr,
  output wire req_write,
  output wire [31:0] req_wdata,
  input wire rsp_valid,
  output wire rsp_ready,
  input wire rsp_error,
  input wire [31:0] rsp_rdata
);
  localparam [2:0] IDLE=3'd0, REQUEST=3'd1, RESPONSE=3'd2, GAP=3'd3;

  reg [2:0] state;
  reg [31:0] stage_addr, stage_count, stage_pattern;
  reg stage_write;
  reg [31:0] active_addr, active_count, active_pattern, word_index;
  reg active_write;
  reg [31:0] success_count, denied_count, checksum;
  reg done, error_sticky;
  reg [7:0] stage_gap, active_gap, gap_left;

  // Keep the carry above bit 33: COUNT * 4 can nearly fill 34 bits, and
  // adding a high base address needs a 35th bit before range validation.
  wire [34:0] stage_span = {1'b0, stage_count, 2'b00};
  wire [34:0] stage_end = {3'b000, stage_addr} + stage_span;

  assign req_valid = rst_n && (state==REQUEST);
  assign req_addr = active_addr;
  assign req_write = active_write;
  assign req_wdata = active_write ? active_pattern + word_index : 32'b0;
  assign rsp_ready = rst_n && (state==RESPONSE);

  always @* begin
    bus_rdata = 32'b0;
    bus_error = 1'b0;
    if (rst_n && bus_valid) begin
      if (bus_addr[1:0] != 2'b00 || (bus_write && bus_wstrb != 4'hf)) begin
        bus_error = 1'b1;
      end else if (bus_write) begin
        case (bus_addr)
          12'h000,12'h004,12'h00c: ;
          12'h008: if (bus_wdata[31:1] != 0) bus_error=1'b1;
          12'h010: if (bus_wdata != 1 || state!=IDLE ||
                            stage_addr[1:0]!=0 || stage_end>35'd4294967296)
                       bus_error=1'b1;
          12'h024: ;
          12'h028: if (bus_wdata[31:8]!=0) bus_error=1'b1;
          default: bus_error=1'b1;
        endcase
      end else begin
        case (bus_addr)
          12'h000: bus_rdata=stage_addr;
          12'h004: bus_rdata=stage_count;
          12'h008: bus_rdata={31'b0,stage_write};
          12'h00c: bus_rdata=stage_pattern;
          12'h014: begin bus_rdata[0]=(state!=IDLE); bus_rdata[1]=done; end
          12'h018: bus_rdata=success_count;
          12'h01c: bus_rdata=denied_count;
          12'h020: bus_rdata=checksum;
          12'h024: bus_rdata={31'b0,error_sticky};
          12'h028: bus_rdata={24'b0,stage_gap};
          default: bus_error=1'b1;
        endcase
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      state<=IDLE; stage_addr<=0; stage_count<=0; stage_pattern<=0; stage_write<=0;
      active_addr<=0; active_count<=0; active_pattern<=0; active_write<=0; word_index<=0;
      success_count<=0; denied_count<=0; checksum<=0; done<=0; error_sticky<=0;
      stage_gap<=0; active_gap<=0; gap_left<=0;
    end else begin
      if (bus_valid && bus_error) error_sticky<=1'b1;
      if (bus_valid && bus_write && !bus_error) begin
        case (bus_addr)
          12'h000: stage_addr<=bus_wdata;
          12'h004: stage_count<=bus_wdata;
          12'h008: stage_write<=bus_wdata[0];
          12'h00c: stage_pattern<=bus_wdata;
          12'h010: begin
            done<=1'b0;
            // These are per-job results. ERR is also raised by denied memory
            // responses and can be cleared by software with the W1C register.
            success_count<=0;
            denied_count<=0;
            checksum<=0;
            error_sticky<=0;
            active_addr<=stage_addr;
            active_count<=stage_count;
            active_pattern<=stage_pattern;
            active_write<=stage_write;
            active_gap<=stage_gap;
            word_index<=0;
            if (stage_count==0) begin
              state<=IDLE;
              done<=1'b1;
            end else state<=REQUEST;
          end
          12'h024: if (bus_wdata[0]) error_sticky<=1'b0;
          12'h028: stage_gap<=bus_wdata[7:0];
        endcase
      end

      if (state==REQUEST && req_ready) state<=RESPONSE;

      if (state==RESPONSE && rsp_valid) begin
        if (rsp_error) begin
          denied_count<=denied_count+1'b1;
          error_sticky<=1'b1;
        end else begin
          success_count<=success_count+1'b1;
          if (!active_write) checksum<=checksum ^ rsp_rdata;
        end
        if (word_index+1'b1 >= active_count) begin
          state<=IDLE;
          done<=1'b1;
        end else begin
          active_addr<=active_addr+32'd4;
          word_index<=word_index+1'b1;
          if (active_gap==0) state<=REQUEST;
          else begin
            gap_left<=active_gap;
            state<=GAP;
          end
        end
      end

      if (state==GAP) begin
        if (gap_left<=1) begin
          gap_left<=0;
          state<=REQUEST;
        end else gap_left<=gap_left-1'b1;
      end
    end
  end
endmodule
