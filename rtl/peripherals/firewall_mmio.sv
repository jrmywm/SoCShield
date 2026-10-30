// Immediate, trusted CPU-local register interface around firewall_update.
module firewall_mmio #(parameter SHADOW=0) (
  input wire clk, rst_n,
  input wire req_valid, output wire req_ready,
  input wire [31:0] req_addr, input wire req_write, input wire [31:0] req_wdata,
  output wire rsp_valid, input wire rsp_ready, output wire rsp_error, output wire [31:0] rsp_rdata,
  output wire mem_req_valid, input wire mem_req_ready,
  output wire [31:0] mem_req_addr, output wire mem_req_write, output wire [31:0] mem_req_wdata,
  input wire mem_rsp_valid, output wire mem_rsp_ready, input wire mem_rsp_error, input wire [31:0] mem_rsp_rdata,
  input wire bus_valid, bus_write, input wire [11:0] bus_addr,
  input wire [31:0] bus_wdata, input wire [3:0] bus_wstrb,
  output reg [31:0] bus_rdata, output reg bus_error
);
  localparam NONE=2'd0, BEGIN_CMD=2'd1, ENTRY_CMD=2'd2, COMMIT_CMD=2'd3;
  reg [1:0] mailbox;
  reg session_open, commit_sent;
  reg [31:0] errors, commit_seq, cmd_seq;
  reg [3:0] written_mask;
  reg [1:0] stage_index, payload_index;
  reg [31:0] stage_base, stage_limit, payload_base, payload_limit;
  reg [2:0] stage_perm, payload_perm;
  wire begin_ready, cfg_ready, commit_ready, commit_ack, update_busy;
  wire begin_valid = mailbox==BEGIN_CMD;
  wire cfg_valid = mailbox==ENTRY_CMD;
  wire commit_valid = mailbox==COMMIT_CMD && !commit_sent;
  wire begin_fire = begin_valid && begin_ready;
  wire cfg_fire = cfg_valid && cfg_ready;
  wire commit_fire = commit_valid && commit_ready;
  reg [2:0] error_set;

  firewall_update #(.SHADOW(SHADOW)) firewall (
    .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_ready(req_ready),
    .req_addr(req_addr), .req_write(req_write), .req_wdata(req_wdata),
    .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_error(rsp_error), .rsp_rdata(rsp_rdata),
    .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready), .mem_req_addr(mem_req_addr),
    .mem_req_write(mem_req_write), .mem_req_wdata(mem_req_wdata), .mem_rsp_valid(mem_rsp_valid),
    .mem_rsp_ready(mem_rsp_ready), .mem_rsp_error(mem_rsp_error), .mem_rsp_rdata(mem_rsp_rdata),
    .update_begin_valid(begin_valid), .update_begin_ready(begin_ready),
    .commit_valid(commit_valid), .commit_ready(commit_ready), .commit_ack(commit_ack), .update_busy(update_busy),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_index(payload_index), .cfg_enable(payload_perm[0]),
    .cfg_base(payload_base), .cfg_limit(payload_limit), .cfg_read(payload_perm[1]), .cfg_write(payload_perm[2])
  );

  always @* begin
    bus_rdata=0; bus_error=0; error_set=0;
    if (rst_n && bus_valid) begin
      if (bus_addr[1:0]!=0 || (bus_write && bus_wstrb!=4'hf)) error_set[0]=1;
      else if (bus_write) begin
        case (bus_addr)
          12'h008: begin
            if (mailbox!=NONE) error_set[2]=1;
            else if ((bus_wdata==1 && session_open) ||
                     (bus_wdata==2 && !session_open) ||
                     (bus_wdata==3 && (!session_open || written_mask!=4'hf)) ||
                     (bus_wdata!=1 && bus_wdata!=2 && bus_wdata!=3)) error_set[1]=1;
          end
          12'h00c,12'h014,12'h018: ;
          12'h010: if (bus_wdata[31:2]!=0) error_set[0]=1;
          12'h01c: if (bus_wdata[31:3]!=0) error_set[0]=1;
          default: error_set[0]=1;
        endcase
      end else begin
        case (bus_addr)
          12'h000: bus_rdata=32'h534f4301;
          12'h004: begin bus_rdata[0]=(mailbox!=NONE); bus_rdata[1]=session_open || update_busy; bus_rdata[2]=(mailbox==COMMIT_CMD); bus_rdata[8]=(SHADOW!=0); end
          12'h00c: bus_rdata=errors;
          12'h010: bus_rdata={30'b0,stage_index};
          12'h014: bus_rdata=stage_base;
          12'h018: bus_rdata=stage_limit;
          12'h01c: bus_rdata={29'b0,stage_perm};
          12'h020: bus_rdata=commit_seq;
          12'h024: bus_rdata={28'b0,written_mask};
          12'h028: bus_rdata=cmd_seq;
          default: error_set[0]=1;
        endcase
      end
      bus_error=|error_set;
    end
  end
  always @(posedge clk) begin
    if (!rst_n) begin
      mailbox<=NONE; session_open<=0; commit_sent<=0; errors<=0;
      commit_seq<=0; cmd_seq<=0; written_mask<=0;
      stage_index<=0; stage_base<=0; stage_limit<=0; stage_perm<=0;
      payload_index<=0; payload_base<=0; payload_limit<=0; payload_perm<=0;
    end else begin
      if (bus_valid && bus_write && bus_addr==12'h00c && !bus_error)
        errors <= (errors & ~bus_wdata) | {29'b0,error_set};
      else errors <= errors | {29'b0,error_set};
      if (begin_fire) begin mailbox<=NONE; cmd_seq<=cmd_seq+1; end
      if (cfg_fire) begin mailbox<=NONE; written_mask[payload_index]<=1; cmd_seq<=cmd_seq+1; end
      if (commit_fire) begin commit_sent<=1; cmd_seq<=cmd_seq+1; end
      if (mailbox==COMMIT_CMD && commit_ack) begin
        mailbox<=NONE; commit_sent<=0; session_open<=0; commit_seq<=commit_seq+1;
      end
      if (bus_valid && bus_write && !bus_error) begin
        case (bus_addr)
          12'h008: case (bus_wdata)
            1: begin mailbox<=BEGIN_CMD; session_open<=1; written_mask<=0; end
            2: begin mailbox<=ENTRY_CMD; payload_index<=stage_index; payload_base<=stage_base; payload_limit<=stage_limit; payload_perm<=stage_perm; end
            3: begin mailbox<=COMMIT_CMD; commit_sent<=0; end
          endcase
          12'h010: stage_index<=bus_wdata[1:0];
          12'h014: stage_base<=bus_wdata;
          12'h018: stage_limit<=bus_wdata;
          12'h01c: stage_perm<=bus_wdata[2:0];
        endcase
      end
    end
  end
`ifdef FORMAL_MMIO
  `include "mmio_properties.svh"
`endif
endmodule
