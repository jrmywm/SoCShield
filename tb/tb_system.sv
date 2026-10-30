`timescale 1ns/1ps
// Executable requester + persistent memory model + independent scoreboard.
module tb_system;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, req_valid=0, req_write=0, rsp_ready=0;
  reg [31:0] req_addr=0, req_wdata=0;
  wire req_ready, rsp_valid, rsp_error;
  wire [31:0] rsp_rdata;
  wire mem_req_valid, mem_req_write, mem_rsp_ready;
  wire [31:0] mem_req_addr, mem_req_wdata;
  wire mem_req_ready;
  reg mem_rsp_valid=0, mem_rsp_error=0;
  reg [31:0] mem_rsp_rdata=0;
  reg cfg_valid=0, cfg_enable=0, cfg_read=0, cfg_write=0;
  reg [1:0] cfg_index=0;
  reg [31:0] cfg_base=0, cfg_limit=0;
  wire cfg_ready;
  firewall dut(.*);

  reg [31:0] prng=32'h51c0ffee;
  reg force_mem_stall=0, force_rsp_stall=0;
  reg mem_pending=0;
  integer delay_left=0;
  reg [31:0] memory [0:16383];
  reg [31:0] golden [0:16383];
  reg [31:0] top_word=32'hfacecafe, golden_top=32'hfacecafe;
  // Ordinary model storage is 64 KiB; the final word of the 32-bit address
  // space is modeled separately. The configured error address is 0x2000.
  assign mem_req_ready = rst_n && !mem_pending && !mem_rsp_valid &&
                         !force_mem_stall && prng[0];
  always @(posedge clk) begin
    prng <= {prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};
    if (!rst_n) begin
      mem_pending<=0; mem_rsp_valid<=0; mem_rsp_error<=0;
      mem_rsp_rdata<=0; delay_left<=0;
    end else begin
      if (mem_req_valid && mem_req_ready) begin
        mem_pending<=1; delay_left<=1+prng[3:1];
        mem_rsp_error <= (mem_req_addr==32'h2000);
        if (mem_req_addr==32'h2000) mem_rsp_rdata<=32'hbadbad00;
        else if (mem_req_addr==32'hfffffffc) begin
          mem_rsp_rdata<=top_word;
          if (mem_req_write) top_word<=mem_req_wdata;
        end else begin
          if (mem_req_addr[31:16] != 0) $fatal(1,"model address outside storage");
          mem_rsp_rdata<=memory[mem_req_addr[15:2]];
          if (mem_req_write) memory[mem_req_addr[15:2]]<=mem_req_wdata;
        end
      end
      if (mem_pending && !force_rsp_stall) begin
        if (delay_left==0) begin mem_rsp_valid<=1; mem_pending<=0; end
        else delay_left<=delay_left-1;
      end
      if (mem_rsp_valid && mem_rsp_ready) mem_rsp_valid<=0;
    end
  end

  reg [3:0] policy_en=0, policy_rd=0, policy_wr=0;
  reg [31:0] policy_lo [0:3], policy_hi [0:3];
  // Reverse traversal intentionally differs from DUT first-match traversal.
  function automatic permit(input [31:0] address, input wr);
    integer n; reg p;
    begin
      p=0;
      for(n=3;n>=0;n=n-1)
        if(policy_en[n] && address>=policy_lo[n] && address<=policy_hi[n])
          p=(wr ? policy_wr[n] : policy_rd[n]) &&
            ({1'b0,address}+33'd3 <= {1'b0,policy_hi[n]});
      permit=p && address[1:0]==0;
    end
  endfunction
  reg active=0, permitted=0, issued=0, received=0;
  reg [31:0] saved_addr=0, saved_data=0, expected_data=0;
  reg saved_write=0, expected_error=0;
  integer accepted=0, completed=0, forwarded=0, denied_count=0, aborted=0;
  integer i;
  reg prev_live=0, prev_mem_stall=0, prev_rsp_stall=0;
  reg [64:0] prev_payload=0;
  reg [32:0] prev_response=0;
  always @(posedge clk) begin
    if (!rst_n) begin
      if(active) aborted=aborted+1;
      active=0; issued=0; received=0; policy_en=0; policy_rd=0; policy_wr=0;
      prev_live=0; prev_mem_stall=0; prev_rsp_stall=0;
      for(i=0;i<4;i=i+1) begin policy_lo[i]=0; policy_hi[i]=0; end
    end else begin
      if(prev_live && prev_mem_stall &&
         (!mem_req_valid || {mem_req_addr,mem_req_write,mem_req_wdata} !== prev_payload))
        $fatal(1,"downstream request changed under backpressure");
      if(prev_live && prev_rsp_stall &&
         (!rsp_valid || {rsp_error,rsp_rdata} !== prev_response))
        $fatal(1,"upstream response changed under backpressure");
      prev_live=1; prev_mem_stall=mem_req_valid && !mem_req_ready;
      prev_rsp_stall=rsp_valid && !rsp_ready;
      prev_payload={mem_req_addr,mem_req_write,mem_req_wdata};
      prev_response={rsp_error,rsp_rdata};
      if(req_ready && active) $fatal(1,"accepted slot reopened too early");
      if(cfg_ready && (active || req_valid)) $fatal(1,"configuration priority violated");
      if(mem_req_valid) begin
        if(!active || !permitted || issued) $fatal(1,"unsolicited/denied/duplicate forwarding");
        if({mem_req_addr,mem_req_write,mem_req_wdata} !== {saved_addr,saved_write,saved_data})
          $fatal(1,"forwarded payload mismatch");
      end
      if(mem_req_valid && mem_req_ready) begin
        issued=1; forwarded=forwarded+1;
        expected_error=(saved_addr==32'h2000);
        expected_data=(expected_error || saved_write) ? 0 :
                      (saved_addr==32'hfffffffc ? golden_top : golden[saved_addr[15:2]]);
        if(saved_write && !expected_error) begin
          if(saved_addr==32'hfffffffc) golden_top=saved_data;
          else golden[saved_addr[15:2]]=saved_data;
        end
      end
      if(mem_rsp_valid && mem_rsp_ready) begin
        if(!active || !issued || received) $fatal(1,"unexpected memory response");
        received=1;
      end
      if(rsp_valid) begin
        if(!active) $fatal(1,"duplicate/unsolicited response");
        if(permitted) begin
          if(!received || rsp_error !== expected_error || rsp_rdata !== expected_data)
            $fatal(1,"allowed response mismatch at %h",saved_addr);
        end else if(!rsp_error || rsp_rdata !== 0 || issued)
          $fatal(1,"denial response mismatch");
      end
      if(rsp_valid && rsp_ready) begin active=0; completed=completed+1; end
      if(req_valid && req_ready) begin
        if(active) $fatal(1,"two outstanding requests");
        active=1; permitted=permit(req_addr,req_write); issued=0; received=0;
        saved_addr=req_addr; saved_write=req_write; saved_data=req_wdata;
        if(!permitted) denied_count=denied_count+1;
        accepted=accepted+1;
      end
      if(cfg_valid && cfg_ready) begin
        policy_en[cfg_index]=cfg_enable; policy_rd[cfg_index]=cfg_read; policy_wr[cfg_index]=cfg_write;
        policy_lo[cfg_index]=cfg_base; policy_hi[cfg_index]=cfg_limit;
      end
    end
  end

  task configure(input [1:0] idx,input en,input [31:0] lo,hi,input rd,wr);
    begin
      @(negedge clk); cfg_valid=1; cfg_index=idx; cfg_enable=en;
      cfg_base=lo; cfg_limit=hi; cfg_read=rd; cfg_write=wr;
      do @(posedge clk); while(!cfg_ready);
      @(negedge clk); cfg_valid=0;
    end
  endtask
  task start_request(input [31:0] addr,input wr,input [31:0] data);
    begin
      @(negedge clk); req_valid=1; req_addr=addr; req_write=wr; req_wdata=data;
      do @(posedge clk); while(!req_ready);
      @(negedge clk); req_valid=0;
    end
  endtask
  task finish_request;
    integer stall_cycles;
    begin
      // While busy, unaccepted input changes must not affect the transaction.
      while(!rsp_valid) begin
        req_valid=1; req_addr=prng; req_wdata=~prng; req_write=prng[5];
        @(negedge clk);
      end
      for(stall_cycles=0;stall_cycles<3;stall_cycles=stall_cycles+1) begin
        req_valid=1; req_addr=~prng; req_wdata=prng; req_write=prng[6];
        @(negedge clk);
      end
      req_valid=0; rsp_ready=1;
      @(negedge clk); rsp_ready=0;
    end
  endtask
  task transaction(input [31:0] addr,input wr,input [31:0] data);
    begin start_request(addr,wr,data); finish_request(); end
  endtask
  task reset_interface;
    begin
      @(negedge clk); rst_n=0; req_valid=0; rsp_ready=0; cfg_valid=0;
      repeat(2) @(negedge clk);
      if(req_ready || rsp_valid || mem_req_valid || mem_rsp_ready || cfg_ready)
        $fatal(1,"handshake enabled during reset");
      rst_n=1;
    end
  endtask
  task normal_policy;
    begin
      configure(0,1,32'h1000,32'h10ff,1,0);
      configure(1,1,32'h1080,32'h11ff,1,1);
      configure(2,1,32'h2000,32'h2003,1,1);
      configure(3,1,32'hfffffffc,32'hffffffff,1,1);
    end
  endtask
  integer n; reg [31:0] random_addr;
  initial begin
    for(n=0;n<16384;n=n+1) begin memory[n]=32'ha5a50000^n; golden[n]=memory[n]; end
    $dumpfile("system.vcd"); $dumpvars(0,tb_system);
    reset_interface();
    transaction(32'h1000,0,0); // default deny
    normal_policy();
    transaction(32'h1000,0,0); transaction(32'h10fc,0,0);
    transaction(32'h1080,1,32'hdeadbeef); // overlap: lower rule denies
    transaction(32'h1100,1,32'h12345678); transaction(32'h1100,0,0);
    transaction(32'h0ffc,0,0); transaction(32'h1200,1,0);
    transaction(32'h1001,0,0); transaction(32'h1002,1,0); transaction(32'h1003,0,0);
    transaction(32'h2000,0,0); transaction(32'h2000,1,32'hdeadbeef);
    transaction(32'hfffffffc,1,32'h76543210); transaction(32'hfffffffc,0,0);
    // Region ends inside a word. First matching rule must deny, without
    // falling through to the broader, later rule.
    configure(0,1,32'h1100,32'h1101,1,1);
    transaction(32'h1100,0,0); transaction(32'h1100,1,0);
    configure(0,0,0,0,0,0); transaction(32'h1100,0,0);
    configure(0,1,32'h1104,32'h1103,1,1); transaction(32'h1100,0,0);
    normal_policy();
    for(n=0;n<512;n=n+1) begin
      random_addr=32'h0ff0+{22'b0,prng[9:2],2'b0};
      if(n%7==0) random_addr=random_addr|{30'b0,prng[1:0]};
      transaction(random_addr,prng[4],prng^n);
    end
    // Simultaneous request/config: request wins and uses the old policy.
    @(negedge clk); req_valid=1; req_addr=32'h1000; req_write=1; req_wdata=0;
    cfg_valid=1; cfg_index=0; cfg_enable=1; cfg_read=1; cfg_write=1;
    cfg_base=32'h1000; cfg_limit=32'h10ff;
    @(posedge clk); if(cfg_ready || !req_ready) $fatal(1,"event priority");
    @(negedge clk); cfg_valid=0; req_valid=0; finish_request();
    transaction(32'h1000,1,0); // rejected config did not change permission
    // Reset in each occupied phase; storage persists, interfaces flush.
    force_mem_stall=1; start_request(32'h1100,0,0); reset_interface(); force_mem_stall=0;
    transaction(32'h1100,0,0); normal_policy();
    force_rsp_stall=1; start_request(32'h1100,1,32'hc001cafe);
    while(!mem_pending) @(negedge clk);
    reset_interface(); force_rsp_stall=0; normal_policy();
    transaction(32'h1100,0,0); // already-issued write survives reset
    start_request(32'h1100,0,0); while(!rsp_valid) @(negedge clk);
    reset_interface(); transaction(32'h1100,0,0);
    if(active || accepted != completed+aborted) $fatal(1,"accounting after reset");
    $display("PASS system accepted=%0d completed=%0d aborted=%0d forwarded=%0d denied=%0d seed=51c0ffee",accepted,completed,aborted,forwarded,denied_count);
    $finish;
  end
  initial begin #2000000; $fatal(1,"system timeout"); end
endmodule
