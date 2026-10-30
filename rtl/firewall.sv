module firewall (
  input wire clk, rst_n,
  input wire req_valid, output wire req_ready,
  input wire [31:0] req_addr, input wire req_write, input wire [31:0] req_wdata,
  output wire rsp_valid, input wire rsp_ready, output wire rsp_error, output wire [31:0] rsp_rdata,
  output wire mem_req_valid, input wire mem_req_ready,
  output wire [31:0] mem_req_addr, output wire mem_req_write, output wire [31:0] mem_req_wdata,
  input wire mem_rsp_valid, output wire mem_rsp_ready, input wire mem_rsp_error, input wire [31:0] mem_rsp_rdata,
  input wire cfg_valid, output wire cfg_ready, input wire [1:0] cfg_index,
  input wire cfg_enable, input wire [31:0] cfg_base, cfg_limit, input wire cfg_read, cfg_write
);
  localparam IDLE=2'd0, SEND=2'd1, WAIT_RSP=2'd2, RESP=2'd3;
  reg [1:0] state;
  reg [3:0] enabled, read_ok, write_ok;
  reg [31:0] base [0:3], limit [0:3];
  reg [31:0] addr_q, wdata_q, rdata_q;
  reg write_q, error_q;
  reg found, allowed;
  integer i;
  always @* begin
    found = 1'b0; allowed = 1'b0;
    for (integer j=0; j<4; j=j+1) begin
      if (!found && enabled[j] && req_addr >= base[j] && req_addr <= limit[j]) begin
        found = 1'b1;
        allowed = (req_write ? write_ok[j] : read_ok[j]) &&
                  ({1'b0, req_addr} + 33'd3 <= {1'b0, limit[j]});
      end
    end
    // 33-bit end arithmetic prevents a word from escaping its selected region.
    if (req_addr[1:0] != 2'b00) allowed = 1'b0;
  end
  assign req_ready = rst_n && state == IDLE;
  assign cfg_ready = rst_n && state == IDLE && !req_valid;
  assign rsp_valid = rst_n && state == RESP;
  assign rsp_error = error_q;
  assign rsp_rdata = rdata_q;
  assign mem_req_valid = rst_n && state == SEND;
  assign mem_req_addr = addr_q;
  assign mem_req_write = write_q;
  assign mem_req_wdata = wdata_q;
  assign mem_rsp_ready = rst_n && state == WAIT_RSP;
  always @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE; enabled <= 0; read_ok <= 0; write_ok <= 0;
      addr_q <= 0; wdata_q <= 0; write_q <= 0; error_q <= 0; rdata_q <= 0;
      for (i=0; i<4; i=i+1) begin base[i] <= 0; limit[i] <= 0; end
    end else begin
      if (cfg_valid && cfg_ready) begin
        enabled[cfg_index] <= cfg_enable; base[cfg_index] <= cfg_base; limit[cfg_index] <= cfg_limit;
        read_ok[cfg_index] <= cfg_read; write_ok[cfg_index] <= cfg_write;
      end
      case (state)
        IDLE: if (req_valid && req_ready) begin
          addr_q <= req_addr; write_q <= req_write; wdata_q <= req_wdata;
          if (allowed) state <= SEND;
          else begin error_q <= 1; rdata_q <= 0; state <= RESP; end
        end
        SEND: if (mem_req_ready) state <= WAIT_RSP;
        WAIT_RSP: if (mem_rsp_valid) begin
          error_q <= mem_rsp_error;
          rdata_q <= (mem_rsp_error || write_q) ? 0 : mem_rsp_rdata;
          state <= RESP;
        end
        RESP: if (rsp_ready) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end
`ifdef FORMAL
  `include "firewall_properties.svh"
`endif
endmodule
