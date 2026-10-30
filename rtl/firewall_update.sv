// Safe policy updates. SHADOW=0: drain, program, resume.
// SHADOW=1: program inactive bank, drain, atomically switch.
module firewall_update #(parameter SHADOW=0) (
  input wire clk, rst_n,
  input wire req_valid, output wire req_ready,
  input wire [31:0] req_addr, input wire req_write, input wire [31:0] req_wdata,
  output wire rsp_valid, input wire rsp_ready, output wire rsp_error, output wire [31:0] rsp_rdata,
  output wire mem_req_valid, input wire mem_req_ready,
  output wire [31:0] mem_req_addr, output wire mem_req_write, output wire [31:0] mem_req_wdata,
  input wire mem_rsp_valid, output wire mem_rsp_ready, input wire mem_rsp_error, input wire [31:0] mem_rsp_rdata,
  input wire update_begin_valid, output wire update_begin_ready,
  input wire commit_valid, output wire commit_ready, output reg commit_ack,
  output wire update_busy,
  input wire cfg_valid, output wire cfg_ready, input wire [1:0] cfg_index,
  input wire cfg_enable, input wire [31:0] cfg_base, cfg_limit, input wire cfg_read, cfg_write
);
  localparam IDLE=2'd0, SEND=2'd1, WAIT_RSP=2'd2, RESP=2'd3;
  localparam RUN=2'd0, DRAIN=2'd1, PROGRAM=2'd2;
  localparam BANKS=SHADOW ? 2 : 1;
  reg [1:0] state, phase;
  reg active_bank;
  reg [3:0] written;
  reg [3:0] enabled[0:BANKS-1], read_ok[0:BANKS-1], write_ok[0:BANKS-1];
  reg [31:0] base[0:BANKS*4-1], limit[0:BANKS*4-1];
  wire selected_bank=SHADOW ? active_bank : 1'b0;
  wire program_bank=SHADOW ? !active_bank : 1'b0;
  wire begin_fire=update_begin_valid && update_begin_ready;
  wire commit_fire=commit_valid && commit_ready;
  wire permit_accept=(phase==RUN && (SHADOW || !update_begin_valid)) ||
                     (SHADOW && phase==PROGRAM && !commit_fire);
  reg found, allowed;
  reg [31:0] addr_q,wdata_q,rdata_q;
  reg write_q,error_q;
  integer i,b;
  always @* begin
    found=0; allowed=0;
    for(integer j=0;j<4;j=j+1) begin
      if(!found && enabled[selected_bank][j] &&
         req_addr>=base[selected_bank*4+j] && req_addr<=limit[selected_bank*4+j]) begin
        found=1;
        allowed=(req_write ? write_ok[selected_bank][j] : read_ok[selected_bank][j]) &&
                ({1'b0,req_addr}+33'd3 <= {1'b0,limit[selected_bank*4+j]});
      end
    end
    if(req_addr[1:0]!=0) allowed=0;
  end
  assign req_ready=rst_n && state==IDLE && permit_accept;
  assign rsp_valid=rst_n && state==RESP;
  assign rsp_error=error_q;
  assign rsp_rdata=rdata_q;
  assign mem_req_valid=rst_n && state==SEND;
  assign mem_req_addr=addr_q;
  assign mem_req_write=write_q;
  assign mem_req_wdata=wdata_q;
  assign mem_rsp_ready=rst_n && state==WAIT_RSP;
  assign update_begin_ready=rst_n && phase==RUN;
  assign commit_ready=rst_n && phase==PROGRAM && (&written);
  assign cfg_ready=rst_n && phase==PROGRAM && !commit_fire;
  assign update_busy=rst_n && phase!=RUN;
  always @(posedge clk) begin
    if(!rst_n) begin
      state<=IDLE; phase<=RUN; active_bank<=0; written<=0; commit_ack<=0;
      addr_q<=0; wdata_q<=0; rdata_q<=0; write_q<=0; error_q<=0;
      for(b=0;b<BANKS;b=b+1) begin enabled[b]<=0; read_ok[b]<=0; write_ok[b]<=0; end
      for(i=0;i<BANKS*4;i=i+1) begin base[i]<=0; limit[i]<=0; end
    end else begin
      commit_ack<=0;
      case(phase)
        RUN: if(begin_fire) begin written<=0; phase<=SHADOW ? PROGRAM : DRAIN; end
        DRAIN: if(state==IDLE) begin
          if(SHADOW) begin active_bank<=!active_bank; phase<=RUN; commit_ack<=1; end
          else phase<=PROGRAM;
        end
        PROGRAM: if(commit_fire) begin
          if(SHADOW) phase<=DRAIN;
          else begin phase<=RUN; commit_ack<=1; end
        end
        default: phase<=RUN;
      endcase
      if(cfg_valid && cfg_ready) begin
        written[cfg_index]<=1;
        enabled[program_bank][cfg_index]<=cfg_enable;
        read_ok[program_bank][cfg_index]<=cfg_read;
        write_ok[program_bank][cfg_index]<=cfg_write;
        base[program_bank*4+cfg_index]<=cfg_base;
        limit[program_bank*4+cfg_index]<=cfg_limit;
      end
      case(state)
        IDLE: if(req_valid && req_ready) begin
          addr_q<=req_addr; write_q<=req_write; wdata_q<=req_wdata;
          if(allowed) state<=SEND;
          else begin state<=RESP; error_q<=1; rdata_q<=0; end
        end
        SEND: if(mem_req_ready) state<=WAIT_RSP;
        WAIT_RSP: if(mem_rsp_valid) begin
          error_q<=mem_rsp_error;
          rdata_q<=(mem_rsp_error || write_q) ? 0 : mem_rsp_rdata;
          state<=RESP;
        end
        RESP: if(rsp_ready) state<=IDLE;
        default: state<=IDLE;
      endcase
    end
  end
`ifdef FORMAL
  `include "update_properties.svh"
`endif
endmodule
