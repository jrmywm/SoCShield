module shared_formal(input wire clk);
 reg rst_n = 0;
 always @(posedge clk) rst_n <= 1;
 (* anyseq *) reg stall, cv, cw, cr, dv, dw, dr;
 (* anyseq *) reg [31:0] ca, cd, da, dd;
 (* anyseq *) reg [3:0] cs, ds;
 wire cready,dready,crv,drv,ce,de;
 wire [31:0] co,do_;
 shared_sram #(.WORDS(4),.LATENCY(2)) dut(clk,rst_n,stall,cv,cready,ca,cw,cd,cs,crv,cr,ce,co,dv,dready,da,dw,dd,ds,drv,dr,de,do_);
 reg outstanding=0, expected_owner=0, expected_error=0;
 reg last_grant_d=1, past_valid=0;
 always @(posedge clk) begin
  past_valid <= 1;
  if (!rst_n) begin outstanding<=0; last_grant_d<=1; end
  else begin
   assert(!(cready && dready));
   assert(!(crv && drv));
   assert(!(cready || dready) || !outstanding);
   if (crv || drv) begin
    assert(outstanding);
    assert(drv == expected_owner);
    assert((drv ? de : ce) == expected_error);
    if (expected_error) assert((drv ? do_ : co) == 0);
   end
   if (cready || dready) begin
    outstanding <= 1;
    expected_owner <= dready;
    expected_error <= dready ? !(da >= 32'h10000000 && da < 32'h10000010 && da[1:0]==0) : !(ca >= 32'h10000000 && ca < 32'h10000010 && ca[1:0]==0);
    if (cv && dv) assert(dready != last_grant_d);
    last_grant_d <= dready;
   end
   if ((crv && cr) || (drv && dr)) outstanding <= 0;
   if (past_valid && $past(rst_n) && $past(crv && !cr)) begin
    assert(crv); assert($stable(co)); assert($stable(ce));
   end
   if (past_valid && $past(rst_n) && $past(drv && !dr)) begin
    assert(drv); assert($stable(do_)); assert($stable(de));
   end
   cover(crv && ce);
   cover(drv && !de);
   cover(cready && cv && dv && last_grant_d);
   cover(dready && cv && dv && !last_grant_d);
  end
 end
endmodule
