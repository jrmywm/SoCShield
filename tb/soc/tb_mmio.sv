`timescale 1ns/1ps
module mmio_case #(parameter SHADOW=0)(output reg done);
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, req_valid=0, req_write=0, rsp_ready=1;
  reg [31:0] req_addr=0, req_wdata=0;
  wire req_ready,rsp_valid,rsp_error; wire [31:0] rsp_rdata;
  wire mem_req_valid,mem_req_write,mem_rsp_ready; wire [31:0] mem_req_addr,mem_req_wdata;
  reg mem_req_ready=0,mem_rsp_valid=0,mem_rsp_error=0; reg [31:0] mem_rsp_rdata=0;
  reg bus_valid=0,bus_write=0; reg [11:0] bus_addr=0; reg [31:0] bus_wdata=0; reg [3:0] bus_wstrb=15;
  wire [31:0] bus_rdata; wire bus_error;
  firewall_mmio #(.SHADOW(SHADOW)) dut(.*);
  task wr(input [11:0] a,input [31:0] d,input expected_error);
    begin @(negedge clk); bus_valid=1; bus_write=1; bus_addr=a; bus_wdata=d; bus_wstrb=15; #1;
      if(bus_error!==expected_error) $fatal(1,"mode %0d write %h error %b expected %b",SHADOW,a,bus_error,expected_error);
      @(negedge clk); bus_valid=0; end
  endtask
  task rd(input [11:0] a,input [31:0] expected);
    begin @(negedge clk); bus_valid=1; bus_write=0; bus_addr=a; #1;
      if(bus_error || bus_rdata!==expected) $fatal(1,"mode %0d read %h got %h expected %h",SHADOW,a,bus_rdata,expected);
      @(negedge clk); bus_valid=0; end
  endtask
  task wait_idle;
    integer n; begin n=0; while(dut.mailbox!=0 && n<100) begin @(negedge clk); n=n+1; end
      if(n==100) $fatal(1,"mode %0d mailbox timeout",SHADOW); end
  endtask
  task entry(input integer idx,input [31:0] base,input [31:0] limit,input [31:0] perm);
    begin wr('h10,idx,0); wr('h14,base,0); wr('h18,limit,0); wr('h1c,perm,0); wr('h08,2,0); wait_idle(); end
  endtask
  integer i;
  initial begin
    done=0; repeat(2) @(negedge clk); rst_n=1;
    rd('h00,32'h534f4301); rd('h04,SHADOW ? 256 : 0);
    wr('h11,0,1); wr('h10,4,1); wr('h1c,8,1);
    @(negedge clk); bus_valid=1; bus_write=1; bus_addr='h14; bus_wdata=99; bus_wstrb=1; #1;
    if(!bus_error) $fatal(1,"partial write accepted");
    @(negedge clk); bus_valid=0; bus_wstrb=15; rd('h14,0); rd('h0c,1); wr('h0c,1,0);
    wr('h08,2,1); wr('h08,1,0); wr('h08,1,1); wait_idle();
    wr('h08,3,1); rd('h0c,2); wr('h0c,7,0); rd('h0c,0);
    entry(0,32'h100,32'h1ff,7);
    for(i=1;i<4;i=i+1) entry(i,0,0,0);
    rd('h24,15); rd('h28,5); wr('h08,3,0); wait_idle(); rd('h20,1); rd('h28,6);
    // Hold an allowed operation at the memory interface indefinitely.
    @(negedge clk); req_valid=1; req_addr='h100;
    do @(negedge clk); while(!mem_req_valid);
    req_valid=0;
    wr('h08,1,0); wait_idle();
    if (!SHADOW) begin
      // Stop mode waits for the outstanding operation before entry acceptance.
      wr('h10,0,0); wr('h14,'h200,0); wr('h18,'h2ff,0); wr('h1c,7,0); wr('h08,2,0);
      wr('h14,'h300,0); wr('h08,2,1); rd('h0c,4);
      repeat(8) begin
        rd('h04,3); rd('h24,0); rd('h14,'h300);
        if(dut.payload_base!==32'h200 || !dut.cfg_valid) $fatal(1,"payload changed under backpressure");
      end
      @(negedge clk); mem_req_ready=1; @(negedge clk); mem_req_ready=0;
      mem_rsp_valid=1; @(negedge clk); mem_rsp_valid=0;
      wait_idle(); rd('h24,1);
    end else begin
      entry(0,'h200,'h2ff,7);
    end
    for(i=1;i<4;i=i+1) entry(i,0,0,0);
    wr('h08,3,0);
    if (SHADOW) begin
      repeat(8) begin rd('h04,32'h107); rd('h20,1); wr('h08,1,1); end
      rd('h0c,4);
      @(negedge clk); mem_req_ready=1; @(negedge clk); mem_req_ready=0;
      mem_rsp_valid=1; @(negedge clk); mem_rsp_valid=0;
    end
    wait_idle(); rd('h20,2); rd('h28,12);
    // The installed payload, rather than the subsequently modified staging register, controls access.
    @(negedge clk); req_valid=1; req_addr='h200;
    do @(negedge clk); while(!mem_req_valid);
    if(mem_req_addr!==32'h200) $fatal(1,"wrong memory address");
    req_valid=0;
    // Reset abandons a pending operation and clears all observable bookkeeping.
    rst_n=0; repeat(2) @(negedge clk); rst_n=1;
    rd('h20,0); rd('h24,0); rd('h28,0); rd('h0c,0); rd('h04,SHADOW ? 256 : 0);
    done=1;
  end
  initial begin #100000; $fatal(1,"mode %0d test timeout",SHADOW); end
endmodule
module tb_mmio;
  wire done0,done1;
  mmio_case #(.SHADOW(0)) a(done0);
  mmio_case #(.SHADOW(1)) b(done1);
  initial begin wait(done0 && done1); $display("PASS mmio both modes"); $finish; end
endmodule
