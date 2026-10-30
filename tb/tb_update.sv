`timescale 1ns/1ps
module tb_update;
  parameter MODE=0;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, traffic=0, hold_mem=0, hold_response=0;
  wire req_valid=traffic;
  reg req_write=0; reg [31:0] req_addr=32'h1000,req_wdata=0;
  wire req_ready,rsp_valid,rsp_error;
  wire [31:0] rsp_rdata;
  wire rsp_ready=rst_n && !hold_response;
  wire mem_req_valid,mem_req_write,mem_rsp_ready;
  wire [31:0] mem_req_addr,mem_req_wdata;
  reg mem_rsp_valid=0,mem_rsp_error=0;
  reg [31:0] mem_rsp_rdata=0,memory_word=32'h13579bdf;
  reg memory_pending=0;
  wire mem_req_ready=rst_n && !hold_mem && !memory_pending && !mem_rsp_valid;
  integer response_delay=0;
  reg update_begin_valid=0,commit_valid=0,cfg_valid=0;
  wire update_begin_ready,commit_ready,commit_ack,update_busy,cfg_ready;
  reg [1:0] cfg_index=0;
  reg cfg_enable=0,cfg_read=0,cfg_write=0;
  reg [31:0] cfg_base=32'h1000,cfg_limit=32'h1003;
  firewall_update #(.SHADOW(MODE)) dut(.*);
  integer cycle=0,accepted=0,completed=0,forwarded=0;
  integer gap=0,stall=0,age=0;
  integer begin_cycle,commit_cycle,ack_cycle,blocked_cycles=0,program_accepts=0;
  integer last_accept=-1,max_accept_gap=0,baseline_latency=-1,baseline_interval=-1;
  reg measuring=0,programming=0,policy_allow=0,next_allow=1;
  reg active=0,allowed_q=0,issued=0,received=0,saved_write=0;
  reg [31:0] saved_data=0,expected_result=0,golden_word=32'h13579bdf;
  integer accepted_at=0;
  reg old_mem_stall=0,old_rsp_stall=0;
  reg [64:0] old_payload;
  reg [32:0] old_response;
  always @(negedge clk) begin req_write=cycle[0]; req_wdata=32'h5a000000+cycle; end
  always @(posedge clk) begin
    cycle<=cycle+1;
    if(!rst_n) begin memory_pending<=0; mem_rsp_valid<=0; response_delay<=0; end
    else begin
      if(mem_req_valid && mem_req_ready) begin
        memory_pending<=1; response_delay<=2; mem_rsp_rdata<=memory_word;
        if(mem_req_write) memory_word<=mem_req_wdata;
      end
      if(memory_pending) begin
        if(response_delay==0) begin mem_rsp_valid<=1; memory_pending<=0; end
        else response_delay<=response_delay-1;
      end
      if(mem_rsp_valid && mem_rsp_ready) mem_rsp_valid<=0;
    end
  end
  always @(posedge clk) if(rst_n) begin
    if(old_mem_stall && (!mem_req_valid || {mem_req_addr,mem_req_write,mem_req_wdata} !== old_payload))
      $fatal(1,"update forwarding instability");
    if(old_rsp_stall && (!rsp_valid || {rsp_error,rsp_rdata} !== old_response))
      $fatal(1,"update response instability");
    old_mem_stall=mem_req_valid && !mem_req_ready;
    old_rsp_stall=rsp_valid && !rsp_ready;
    old_payload={mem_req_addr,mem_req_write,mem_req_wdata}; old_response={rsp_error,rsp_rdata};
    if(commit_ack) begin
      if(active || mem_req_valid || memory_pending || mem_rsp_valid) $fatal(1,"commit before old traffic drained");
      policy_allow=next_allow;
      if(measuring) begin ack_cycle=cycle; programming=0; end
    end
    if(measuring && !dut.permit_accept) blocked_cycles=blocked_cycles+1;
    if(req_ready && active) $fatal(1,"update reopened occupied slot");
    if(mem_req_valid) begin
      if(!active || !allowed_q || issued) $fatal(1,"bad update forwarding");
      if({mem_req_addr,mem_req_write,mem_req_wdata} !== {32'h1000,saved_write,saved_data})
        $fatal(1,"update payload mismatch");
    end
    if(mem_req_valid && mem_req_ready) begin
      issued=1; forwarded=forwarded+1;
      expected_result=saved_write ? 0 : golden_word;
      if(saved_write) golden_word=saved_data;
    end
    if(mem_rsp_valid && mem_rsp_ready) received=1;
    if(rsp_valid) begin
      if(!active) $fatal(1,"unsolicited update response");
      if(allowed_q) begin
        if(!received || rsp_error || rsp_rdata!==expected_result) $fatal(1,"old-policy response corrupted");
      end else if(!rsp_error || rsp_rdata!==0 || issued) $fatal(1,"post-revocation request escaped");
    end
    if(rsp_valid && rsp_ready) begin
      if(allowed_q && !measuring && baseline_latency<0) baseline_latency=cycle-accepted_at;
      active=0; completed=completed+1;
    end
    if(req_valid && req_ready) begin
      active=1; allowed_q=policy_allow; issued=0; received=0;
      saved_write=req_write; saved_data=req_wdata; accepted_at=cycle;
      accepted=accepted+1;
      if(programming) program_accepts=program_accepts+1;
      if(last_accept>=0) begin
        if(!measuring && baseline_interval<0) baseline_interval=cycle-last_accept;
        if(measuring && cycle-last_accept>max_accept_gap) max_accept_gap=cycle-last_accept;
      end
      last_accept=cycle;
    end
  end
  task begin_update;
    begin
      @(negedge clk); update_begin_valid=1;
      do @(posedge clk); while(!update_begin_ready);
      if(measuring) begin begin_cycle=cycle; programming=1; end
      @(negedge clk); update_begin_valid=0;
    end
  endtask
  task program_policy(input allow_access);
    integer k;
    begin
      for(k=0;k<4;k=k+1) begin
        @(negedge clk); cfg_valid=1; cfg_index=k;
        cfg_enable=(k==0); cfg_read=allow_access; cfg_write=allow_access;
        do @(posedge clk); while(!cfg_ready);
        @(negedge clk); cfg_valid=0;
        repeat(gap) @(negedge clk);
      end
    end
  endtask
  task commit_policy;
    begin
      // Conflicting configuration must lose to an accepted commit.
      @(negedge clk); commit_valid=1; cfg_valid=1; cfg_index=0;
      cfg_enable=1; cfg_read=!next_allow; cfg_write=!next_allow;
      do @(posedge clk); while(!commit_ready);
      if(cfg_ready) $fatal(1,"configuration accepted with commit");
      if(measuring) commit_cycle=cycle;
      @(negedge clk); commit_valid=0; cfg_valid=0;
      while(!commit_ack) @(negedge clk);
      @(negedge clk);
    end
  endtask
  integer fd;
  initial begin
    if(!$value$plusargs("GAP=%d",gap)) gap=0;
    if(!$value$plusargs("STALL=%d",stall)) stall=0;
    $dumpfile("update.vcd"); $dumpvars(0,tb_update);
    repeat(2) @(negedge clk); rst_n=1;
    begin_update();
    // Incomplete policies cannot be committed.
    commit_valid=1; repeat(2) begin @(negedge clk); if(commit_ready || commit_ack) $fatal(1,"partial policy committed"); end
    commit_valid=0; program_policy(1); commit_policy();
    traffic=1;
    while(completed<8) @(negedge clk);
    // Start with an outstanding operation to exercise the drain barrier.
    hold_mem=(stall!=0);
    while(!active) @(negedge clk);
    measuring=1; next_allow=0;
    fork
      begin begin_update(); program_policy(0); commit_policy(); end
      begin repeat(stall) @(negedge clk); hold_mem=0; end
    join
    // Continue long enough to show that requests after ack are denied.
    repeat(20) @(negedge clk);
    traffic=0; while(active) @(negedge clk);
    if(memory_word!==golden_word) $fatal(1,"write memory mismatch after revocation");
    fd=$fopen("metrics.csv","w");
    $fdisplay(fd,"shadow,gap,stall,begin_to_ack,commit_to_ack,blocked_cycles,program_accepts,max_accept_gap,allowed_latency,allowed_interval,accepted,completed,forwarded");
    $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",MODE,gap,stall,ack_cycle-begin_cycle,ack_cycle-commit_cycle,blocked_cycles,program_accepts,max_accept_gap,baseline_latency,baseline_interval,accepted,completed,forwarded);
    $fclose(fd);
    // Further contract checks do not contribute to the timing CSV.
    measuring=0; next_allow=1;
    begin_update(); program_policy(1); commit_policy(); // reuse the other bank
    hold_response=1; traffic=1;
    while(!rsp_valid) @(negedge clk);
    next_allow=0;
    fork
      begin begin_update(); program_policy(0); commit_policy(); end
      begin repeat(96) @(negedge clk); hold_response=0; end
    join
    repeat(8) @(negedge clk); traffic=0;
    while(active) @(negedge clk);
    cfg_valid=1; commit_valid=1;
    repeat(2) begin @(negedge clk); if(cfg_ready || commit_ready) $fatal(1,"trusted command outside update session"); end
    cfg_valid=0; commit_valid=0;
    $display("PASS update shadow=%0d gap=%0d stall=%0d begin_to_ack=%0d commit_to_ack=%0d blocked=%0d traffic_during_program=%0d",MODE,gap,stall,ack_cycle-begin_cycle,ack_cycle-commit_cycle,blocked_cycles,program_accepts);
    $finish;
  end
  initial begin #2000000; $fatal(1,"update timeout"); end
endmodule
