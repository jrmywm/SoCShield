`timescale 1ns/1ps
module tb_shared;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0, stall=0;
 reg cv=0,cw=0,cr=1,dv=0,dw=0,dr=1;
 reg [31:0] ca=0,cd=0,da=0,dd=0;
 reg [3:0] cs=0,ds=0;
 wire cready,dready,crv,drv,ce,de;
 wire [31:0] co,do_;
 reg tracked=0,tracked_owner=0;
 initial begin #100000; $fatal(1,"watchdog shared");end
 always @(posedge clk)begin
  if(!rst_n)tracked<=0;
  else begin
   if(crv || drv)begin
    if(!tracked || drv!==tracked_owner || crv===drv)$fatal(1,"response ownership or accounting");
   end
   if(cready || dready)begin
    if(tracked)$fatal(1,"multiple accepted requests");
    tracked<=1;tracked_owner<=dready;
   end
   if(crv && cr || drv && dr)tracked<=0;
  end
 end
 shared_sram #(.WORDS(4),.LATENCY(2)) dut(clk,rst_n,stall,cv,cready,ca,cw,cd,cs,crv,cr,ce,co,dv,dready,da,dw,dd,ds,drv,dr,de,do_);
 task tick; begin @(posedge clk); #1; end endtask
 task request(input who, input [31:0] addr, input wr, input [31:0] data, input [3:0] mask, input err, input [31:0] expected);
 begin
  @(negedge clk); if(who) begin dv=1; da=addr; dw=wr; dd=data; ds=mask; end
  else begin cv=1; ca=addr; cw=wr; cd=data; cs=mask; end
  #1; if (!(who ? dready : cready)) $fatal(1,"request not ready");
  tick(); @(negedge clk); cv=0; dv=0;
  while (!(who ? drv : crv)) tick();
  if ((who ? de : ce) !== err || (who ? do_ : co) !== expected || (who ? crv : drv)) $fatal(1,"bad response at %h",addr);
  tick();
 end endtask
 initial begin
  tick(); @(negedge clk); rst_n=1;
  request(0,32'h10000000,1,32'h11223344,4'hf,0,0);
  request(0,32'h10000000,1,32'haabbccdd,4'b0101,0,0);
  request(1,32'h10000000,0,0,0,0,32'h11bb33dd);
  request(1,32'h10000010,1,32'hffffffff,4'hf,1,0);
  request(1,32'h20000000,1,32'hffffffff,4'hf,1,0);
  request(1,32'h0ffffffc,1,32'hffffffff,4'hf,1,0);
  request(1,32'h10000001,1,32'hffffffff,4'hf,1,0);
  request(0,32'h10000000,0,0,0,0,32'h11bb33dd);
  // Both requesters contend continuously: alternate grants.
  @(negedge clk); cv=1; dv=1; ca=32'h10000000; da=ca; cw=0; dw=0; cr=0; dr=0; #1;
  if (!dready || cready) $fatal(1,"round robin first grant"); tick();
  @(negedge clk); stall=1; repeat(3) tick(); if(crv||drv) $fatal(1,"stall failed");
  @(negedge clk); stall=0; while(!drv) tick();
  @(negedge clk); stall=1; repeat(3) begin tick(); if(!drv || crv || do_!==32'h11bb33dd) $fatal(1,"response not held"); end
  @(negedge clk); dr=1; tick(); @(negedge clk); stall=0; #1; if(!cready || dready) $fatal(1,"round robin second grant"); tick();
  @(negedge clk); cv=0; dv=0; rst_n=0; tick(); if(crv||drv||cready||dready) $fatal(1,"reset outputs");
  @(negedge clk); rst_n=1; cr=1; request(0,32'h10000000,0,0,0,0,32'h11bb33dd);
  $display("PASS shared SRAM directed tests"); $finish;
 end
endmodule
