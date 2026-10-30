// Small trusted-CPU / untrusted-DMA integration. Native bus, not AXI.
`include "soc_map.vh"
module soc_top #(parameter SHADOW=0, parameter MEMFILE="build/soc/firmware.hex")(
  input wire clk,rst_n,input wire mem_stall,
  output wire trap, output reg console_valid,output reg [7:0] console_data,
  output reg result_valid,output reg [31:0] result,
  output wire dma_busy,output wire [31:0] commit_seq
);
  wire cv,ci,cr; wire [31:0] ca,cwd,crd; wire [3:0] cws;
  picorv32 #(.PROGADDR_RESET(0),.STACKADDR(32'h10000),.ENABLE_COUNTERS(0),
    .ENABLE_COUNTERS64(0),.ENABLE_MUL(0),.ENABLE_DIV(0),.ENABLE_IRQ(0)) cpu (
    .clk(clk),.resetn(rst_n),.trap(trap),.mem_valid(cv),.mem_instr(ci),
    .mem_ready(cr),.mem_addr(ca),.mem_wdata(cwd),.mem_wstrb(cws),.mem_rdata(crd),
    .irq(32'b0),.pcpi_wr(1'b0),.pcpi_rd(32'b0),.pcpi_wait(1'b0),.pcpi_ready(1'b0));
  reg [31:0] private_ram[0:16383];
  integer k;
  initial begin
    for(k=0;k<16384;k=k+1) private_ram[k]=0;
    $readmemh(MEMFILE,private_ram);
  end
  wire private_sel=ca<`SOC_PRIVATE_BYTES;
  wire shared_sel=ca>=`SOC_SHARED_BASE && ca<`SOC_SHARED_END;
  wire fw_sel=ca>=`SOC_FW_BASE && ca<`SOC_FW_BASE+4096;
  wire dma_sel=ca>=`SOC_DMA_BASE && ca<`SOC_DMA_BASE+4096;
  wire log_sel=ca>=`SOC_LOG_BASE && ca<`SOC_LOG_BASE+4096;
  wire cw=|cws;
  wire [31:0] fw_data,dma_data;
  wire fw_error,dma_error;
  // Shared transfers have a separate accepted-request latch: CPU mem_valid
  // remains high until the response, but the SRAM must see only one request.
  reg shared_pending;
  reg cpu_fault;
  wire c_req_ready,c_rsp_valid,c_rsp_error; wire [31:0] c_rsp_data;
  assign cr=rst_n && cv && (shared_sel ? c_rsp_valid : 1'b1);
  assign crd=private_sel ? private_ram[ca[15:2]] : shared_sel ? c_rsp_data :
             fw_sel ? fw_data : dma_sel ? dma_data :
             log_sel && ca[11:0]==12'h008 ? {31'b0,cpu_fault} : 32'b0;
  wire local_fire=cv && cr && !shared_sel;
  reg [31:0] boot_signature, measure_phase;
  reg stall_arm;
  always @(posedge clk) begin
    console_valid<=0; result_valid<=0;
    if(!rst_n) begin shared_pending<=0;cpu_fault<=0;result<=0;console_data<=0;boot_signature<=0;measure_phase<=0;stall_arm<=0;end
    else begin
      if(cv && shared_sel && !shared_pending && c_req_ready) shared_pending<=1;
      if(c_rsp_valid) begin shared_pending<=0;if(c_rsp_error) cpu_fault<=1;end
      if(local_fire) begin
        if(private_sel && cw) begin
          for(integer b=0;b<4;b=b+1) if(cws[b]) private_ram[ca[15:2]][8*b+:8]<=cwd[8*b+:8];
        end
        if(fw_sel && fw_error || dma_sel && dma_error) cpu_fault<=1;
        if(!private_sel && !fw_sel && !dma_sel && !log_sel) cpu_fault<=1;
        if(log_sel) begin
          if(ca[1:0]!=0 || (cw && cws!=4'hf)) cpu_fault<=1;
          else if(cw && ca[11:0]==0) begin console_valid<=1;console_data<=cwd[7:0];end
          else if(cw && ca[11:0]==4) begin result_valid<=1;result<=cwd;end
          else if(cw && ca[11:0]==12'h00c) boot_signature<=cwd;
          else if(cw && ca[11:0]==12'h010) stall_arm<=cwd[0];
          else if(cw && ca[11:0]==12'h014) measure_phase<=cwd;
          else if(ca[11:0]!=8) cpu_fault<=1;
        end
      end
    end
  end
  wire qv,qr,qw,sv,sr,se; wire[31:0]qa,qd,sd;
  wire mv,mr,mw,rv,rr,re;wire[31:0]ma,md,rd;
  firewall_mmio #(.SHADOW(SHADOW)) control(
    .clk(clk),.rst_n(rst_n),.bus_valid(local_fire && fw_sel),.bus_write(cw),
    .bus_addr(ca[11:0]),.bus_wdata(cwd),.bus_wstrb(cws),.bus_rdata(fw_data),.bus_error(fw_error),
    .req_valid(qv),.req_ready(qr),.req_addr(qa),.req_write(qw),.req_wdata(qd),
    .rsp_valid(sv),.rsp_ready(sr),.rsp_error(se),.rsp_rdata(sd),
    .mem_req_valid(mv),.mem_req_ready(mr),.mem_req_addr(ma),.mem_req_write(mw),.mem_req_wdata(md),
    .mem_rsp_valid(rv),.mem_rsp_ready(rr),.mem_rsp_error(re),.mem_rsp_rdata(rd));
  dma_engine dma(
    .clk(clk),.rst_n(rst_n),.bus_valid(local_fire && dma_sel),.bus_write(cw),
    .bus_addr(ca[11:0]),.bus_wdata(cwd),.bus_wstrb(cws),.bus_rdata(dma_data),.bus_error(dma_error),
    .req_valid(qv),.req_ready(qr),.req_addr(qa),.req_write(qw),.req_wdata(qd),
    .rsp_valid(sv),.rsp_ready(sr),.rsp_error(se),.rsp_rdata(sd));
  assign dma_busy=dma.state!=0;
  // These observation outputs are for the enclosing demo/testbench only.
  assign commit_seq=control.commit_seq;
  shared_sram memory(
    .clk(clk),.rst_n(rst_n),.stall(mem_stall),
    .c_req_valid(cv && shared_sel && !shared_pending),.c_req_ready(c_req_ready),
    .c_req_addr(ca),.c_req_write(cw),.c_req_wdata(cwd),.c_req_wstrb(cws),
    .c_rsp_valid(c_rsp_valid),.c_rsp_ready(1'b1),.c_rsp_error(c_rsp_error),.c_rsp_rdata(c_rsp_data),
    .d_req_valid(mv),.d_req_ready(mr),.d_req_addr(ma),.d_req_write(mw),.d_req_wdata(md),.d_req_wstrb(4'hf),
    .d_rsp_valid(rv),.d_rsp_ready(rr),.d_rsp_error(re),.d_rsp_rdata(rd));
endmodule
