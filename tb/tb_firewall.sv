`timescale 1ns/1ps
module tb_firewall;
  reg clk=0, rst_n=0; always #5 clk=~clk;
  reg req_valid=0, req_write=0, rsp_ready=0, mem_req_ready=0, mem_rsp_valid=0, mem_rsp_error=0;
  reg [31:0] req_addr=0, req_wdata=0, mem_rsp_rdata=0;
  reg cfg_valid=0, cfg_enable=0, cfg_read=0, cfg_write=0;
  reg [1:0] cfg_index=0; reg [31:0] cfg_base=0, cfg_limit=0;
  wire req_ready, rsp_valid, rsp_error, mem_req_valid, mem_req_write, mem_rsp_ready, cfg_ready;
  wire [31:0] rsp_rdata, mem_req_addr, mem_req_wdata;
  firewall dut(.*);
  integer forwards=0;
  always @(posedge clk) if (rst_n && mem_req_valid && mem_req_ready) forwards <= forwards+1;
  task configure(input [1:0] idx, input [31:0] lo, hi, input rd, wr);
    begin @(negedge clk); cfg_valid=1; cfg_index=idx; cfg_enable=1; cfg_base=lo; cfg_limit=hi; cfg_read=rd; cfg_write=wr;
      if (!cfg_ready) $fatal(1,"configuration not ready");
      @(negedge clk); cfg_valid=0; end
  endtask
  task request(input [31:0] addr, input wr, input [31:0] data);
    begin @(negedge clk); req_valid=1; req_addr=addr; req_write=wr; req_wdata=data;
      if (!req_ready) $fatal(1,"request not ready");
      @(negedge clk); req_valid=0; req_addr=32'hdeadbeef; req_write=~wr; req_wdata=0; end
  endtask
  task denied(input [31:0] addr, input wr);
    integer before_count;
    begin before_count=forwards; request(addr,wr,0);
      if (!rsp_valid || !rsp_error || rsp_rdata !== 0 || mem_req_valid) $fatal(1,"denial failed at %h",addr);
      repeat(2) begin @(negedge clk); if (!rsp_valid || !rsp_error || rsp_rdata !== 0 || mem_req_valid) $fatal(1,"denied response unstable"); end
      rsp_ready=1; @(negedge clk); rsp_ready=0;
      if (forwards != before_count) $fatal(1,"denial forwarded"); end
  endtask
  task allowed(input [31:0] addr, input wr, input [31:0] data);
    integer before_count;
    begin before_count=forwards; request(addr,wr,data);
      repeat(3) begin
        if (!mem_req_valid || mem_req_addr !== addr || mem_req_write !== wr || mem_req_wdata !== data) $fatal(1,"forward payload changed");
        @(negedge clk);
      end
      mem_req_ready=1; @(negedge clk); mem_req_ready=0;
      if (mem_req_valid || !mem_rsp_ready || forwards != before_count+1) $fatal(1,"forward count");
      mem_rsp_valid=1; mem_rsp_rdata=32'h12345678; @(negedge clk); mem_rsp_valid=0;
      if (!rsp_valid || rsp_error || rsp_rdata !== (wr ? 32'b0 : 32'h12345678)) $fatal(1,"response mismatch");
      repeat(2) begin @(negedge clk); if (!rsp_valid) $fatal(1,"response dropped"); end
      rsp_ready=1; @(negedge clk); rsp_ready=0;
      if (forwards != before_count+1) $fatal(1,"duplicate forward"); end
  endtask
  initial begin
    $dumpfile("firewall.vcd"); $dumpvars(0,tb_firewall);
    repeat(2) @(negedge clk); rst_n=1;
    configure(0,32'h1000,32'h10ff,1,0);
    configure(1,32'h1080,32'h11ff,1,1);
    allowed(32'h1000,0,32'hcafebabe); allowed(32'h10fc,0,0);
    denied(32'h1080,1); allowed(32'h1100,1,32'habcdef01);
    denied(32'h0ffc,0); denied(32'h1200,0); denied(32'h1001,0); denied(32'h1000,1);
    request(32'h1000,0,0); if (!mem_req_valid) $fatal(1,"expected pending request");
    rst_n=0; @(negedge clk); if (mem_req_valid || rsp_valid) $fatal(1,"reset valid");
    rst_n=1; denied(32'h1000,0);
    $display("PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"timeout"); end
endmodule
