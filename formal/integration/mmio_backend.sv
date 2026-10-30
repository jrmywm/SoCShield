// Nondeterministic interface abstraction: no progress or response guarantees.
// This is not a model or proof of firewall_update's policy enforcement.
module firewall_update #(parameter SHADOW=0) (
 input wire clk,rst_n,
 input wire req_valid, output wire req_ready, input wire [31:0] req_addr,
 input wire req_write, input wire [31:0] req_wdata,
 output wire rsp_valid,input wire rsp_ready,output wire rsp_error,output wire [31:0] rsp_rdata,
 output wire mem_req_valid,input wire mem_req_ready,output wire [31:0] mem_req_addr,
 output wire mem_req_write,output wire [31:0] mem_req_wdata,
 input wire mem_rsp_valid,output wire mem_rsp_ready,input wire mem_rsp_error,input wire [31:0] mem_rsp_rdata,
 input wire update_begin_valid,output wire update_begin_ready,
 input wire commit_valid,output wire commit_ready,output wire commit_ack,output wire update_busy,
 input wire cfg_valid,output wire cfg_ready,input wire [1:0] cfg_index,input wire cfg_enable,
 input wire [31:0] cfg_base,cfg_limit,input wire cfg_read,cfg_write
);
 (* anyseq *) reg a,b,c,d,e;
 assign update_begin_ready=a; assign cfg_ready=b; assign commit_ready=c; assign commit_ack=d; assign update_busy=e;
 assign req_ready=0; assign rsp_valid=0; assign rsp_error=0; assign rsp_rdata=0;
 assign mem_req_valid=0; assign mem_req_addr=0; assign mem_req_write=0; assign mem_req_wdata=0; assign mem_rsp_ready=0;
endmodule
