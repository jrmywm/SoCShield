`timescale 1ns/1ps
module tb_soc;
  parameter MODE=0;
  reg clk=0;always #5 clk=!clk;
  reg rst_n=0;reg stall=0;
  wire trap,cv,rv,busy;wire[7:0]ch;wire[31:0]result,seq;
  soc_top #(.SHADOW(MODE)) dut(.clk(clk),.rst_n(rst_n),.mem_stall(stall),.trap(trap),
    .console_valid(cv),.console_data(ch),.result_valid(rv),.result(result),.dma_busy(busy),.commit_seq(seq));
  integer cycle=0,seed=1,stall_cycles=0,stall_left=0;
  integer accepts=0,completions=0,forwards=0,denials=0,alias_denials=0;
  integer phase_start=0,phase_end=0,last_accept=-1,max_gap=0,latency_max=0;
  integer begin_cycle=-1,commit_cycle=-1,ack_cycle=-1,overlap=0;
  integer cpu_accepted=0,cpu_completed=0,contested=0;
  integer inhibited_cycles=0;
  reg cpu_outstanding=0;reg[31:0]cpu_expected;reg cpu_write_q;
  integer fd,events,j,trace_on=0,random_stalls=0,require_overlap=1;reg[31:0]rng;
  reg armed=0,stall_used=0;
  reg outstanding=0,expected_allow,expected_error,forwarded=0;
  reg[31:0]addr_q,data_q,expected_data;reg write_q;
  integer accepted_at;
  reg[31:0]active_base[0:3],active_limit[0:3],next_base[0:3],next_limit[0:3];
  reg[2:0]active_perm[0:3],next_perm[0:3];
  reg[31:0]reference_mem[0:16383];
  reg found; reg[32:0]word_end;
  initial begin
    if(!$value$plusargs("SEED=%d",seed))seed=1;
    if(!$value$plusargs("STALL=%d",stall_cycles))stall_cycles=0;
    if(!$value$plusargs("RANDOM=%d",random_stalls))random_stalls=0;
    if(!$value$plusargs("REQUIRE_OVERLAP=%d",require_overlap))require_overlap=1;
    rng=seed;
    events=$fopen("events.csv","w");$fdisplay(events,"cycle,event,address,data,error");
    if($test$plusargs("TRACE"))begin $dumpfile("soc.vcd");$dumpvars(1,tb_soc.dut);end
    for(j=0;j<16384;j=j+1)reference_mem[j]=0;
    for(j=0;j<4;j=j+1)begin active_perm[j]=0;next_perm[j]=0;active_base[j]=0;active_limit[j]=0;end
    repeat(5)@(negedge clk);rst_n=1;
  end
  // Test-only endpoint schedule. The CPU private/control paths stay live.
  always @(negedge clk)begin
    if(!rst_n)stall=0;
    else if(stall_left>0)begin stall=1;stall_left=stall_left-1;end
    else if(dut.stall_arm && !stall_used && dut.mv)begin stall_used=1;stall_left=stall_cycles>0?stall_cycles-1:0;stall=stall_cycles!=0;end
    else begin
      rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
      stall=random_stalls!=0 && rng[2:0]==0;
    end
  end
  always @(posedge clk)if(rst_n)begin
    cycle=cycle+1;
    if(cycle>4000000)$fatal(1,"watchdog cycle=%d pc=%h",cycle,dut.cpu.reg_pc);
    if(trap)$fatal(1,"CPU trap pc=%h",dut.cpu.reg_pc);
    if(dut.local_fire && dut.dma_sel && dut.dma_error)$fatal(1,"DMA register error addr=%h write=%b data=%h",dut.ca,dut.cw,dut.cwd);
    if(cv)$write("%c",ch);
    if(dut.memory.c_req_valid && dut.memory.d_req_valid)contested=contested+1;
    if(dut.c_rsp_valid)begin
      if(!cpu_outstanding || dut.c_rsp_error || dut.c_rsp_data!==cpu_expected)$fatal(1,"CPU shared response mismatch or duplicate");
      cpu_completed=cpu_completed+1;cpu_outstanding=0;
    end
    if(dut.control.cfg_fire)begin
      $fdisplay(events,"%0d,cfg,%h,%h,%0d",cycle,dut.control.payload_base,dut.control.payload_limit,dut.control.payload_perm);
      next_base[dut.control.payload_index]=dut.control.payload_base;
      next_limit[dut.control.payload_index]=dut.control.payload_limit;
      next_perm[dut.control.payload_index]=dut.control.payload_perm;
    end
    if(dut.measure_phase==1 && phase_start==0)phase_start=cycle;
    if(dut.measure_phase==2 && phase_end==0)phase_end=cycle;
    if(phase_start>0 && phase_end==0 && !dut.control.firewall.permit_accept)inhibited_cycles=inhibited_cycles+1;
    if(dut.control.begin_fire && phase_start>0 && phase_end==0)begin
      begin_cycle=cycle;if(outstanding)overlap=overlap+1;
    end
    if(dut.control.commit_fire && phase_start>0 && phase_end==0)commit_cycle=cycle;
    if(dut.control.commit_ack)begin
      $fdisplay(events,"%0d,ack,0,0,0",cycle);
      if(outstanding)$fatal(1,"commit acknowledgment with old operation outstanding");
      for(j=0;j<4;j=j+1)begin active_base[j]=next_base[j];active_limit[j]=next_limit[j];active_perm[j]=next_perm[j];end
      if(phase_start>0 && phase_end==0)ack_cycle=cycle;
    end
    if(dut.qv && dut.qr)begin
      if(outstanding)$fatal(1,"duplicate accepted DMA operation");
      outstanding=1;forwarded=0;addr_q=dut.qa;data_q=dut.qd;write_q=dut.qw;accepted_at=cycle;
      accepts=accepts+1;expected_allow=0;found=0;word_end={1'b0,dut.qa}+33'd3;
      $fdisplay(events,"%0d,request,%h,%h,%0d",cycle,addr_q,data_q,write_q);
      for(j=0;j<4;j=j+1)if(!found && active_perm[j][0] && dut.qa>=active_base[j] && dut.qa<=active_limit[j])begin
        found=1;expected_allow=(dut.qw?active_perm[j][2]:active_perm[j][1]) && word_end<={1'b0,active_limit[j]} && dut.qa[1:0]==0;
      end
      expected_error=!expected_allow || addr_q<32'h10000000 || addr_q>32'h1000fffc;
      expected_data=0;
      if(phase_start>0 && (phase_end==0 || last_accept<=ack_cycle))begin
        if(last_accept>=0 && cycle-last_accept>max_gap)max_gap=cycle-last_accept;
      end
      last_accept=cycle;
    end
    if(dut.mv && dut.mr)begin
      if(!outstanding || !expected_allow || forwarded)$fatal(1,"unexpected or denied forwarding");
      if(dut.ma!==addr_q || dut.md!==data_q || dut.mw!==write_q)$fatal(1,"forward payload mismatch");
      forwarded=1;forwards=forwards+1;
      $fdisplay(events,"%0d,memory,%h,%h,%0d",cycle,dut.ma,dut.md,dut.mw);
    end
    // Independent SRAM contents and response expectations from accepted ports.
    if(dut.memory.c_req_valid && dut.memory.c_req_ready && dut.ca>=32'h10000000 && dut.ca<=32'h1000fffc)begin
      if(cpu_outstanding)$fatal(1,"duplicate CPU shared request");
      cpu_outstanding=1;cpu_accepted=cpu_accepted+1;
      cpu_expected=dut.cw?0:reference_mem[dut.ca[15:2]];
      if(dut.cw)for(j=0;j<4;j=j+1)if(dut.cws[j])reference_mem[dut.ca[15:2]][j*8+:8]=dut.cwd[j*8+:8];
    end
    if(dut.mv && dut.mr && !expected_error)begin
      if(write_q)reference_mem[addr_q[15:2]]=data_q;
      else expected_data=reference_mem[addr_q[15:2]];
    end
    if(dut.sv && dut.sr)begin
      if(!outstanding)$fatal(1,"unsolicited response");
      if(dut.se!==expected_error || dut.sd!==expected_data)$fatal(1,"response mismatch addr=%h expected %b/%h got %b/%h",addr_q,expected_error,expected_data,dut.se,dut.sd);
      if(expected_allow && !forwarded)$fatal(1,"allowed transaction never forwarded");
      if(expected_error)begin denials=denials+1;if(expected_allow)alias_denials=alias_denials+1;end
      outstanding=0;completions=completions+1;
      $fdisplay(events,"%0d,response,%h,%h,%0d",cycle,addr_q,dut.sd,dut.se);
      if(cycle-accepted_at>latency_max)latency_max=cycle-accepted_at;
    end
    if(rv)begin
      if(result!==32'h600d600d && result!==32'h600d0001)$fatal(1,"firmware failure %h",result);
      if(dut.boot_signature!==32'hbeefaa44)$fatal(1,"missing independent boot signature");
      if(result==32'h600d600d)begin
        if(cpu_accepted!=cpu_completed || cpu_outstanding)$fatal(1,"CPU transaction accounting mismatch");
        if(accepts!=completions || outstanding || alias_denials!=3 || (require_overlap!=0 && overlap==0))$fatal(1,"missing scenario evidence a=%d c=%d alias=%d overlap=%d",accepts,completions,alias_denials,overlap);
        for(j=0;j<16384;j=j+1)if(dut.memory.mem[j]!==reference_mem[j])$fatal(1,"SRAM mismatch word %d",j);
      end
      fd=$fopen("metrics.csv","w");
      $fdisplay(fd,"mode,seed,cycles,accepted,completed,forwarded,errors,alias_errors,begin_cycle,commit_cycle,ack_cycle,program_cycles,max_acceptance_gap,max_latency,overlap,cpu_accepted,cpu_completed,contested_cycles,inhibited_cycles");
      $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",MODE,seed,cycle,accepts,completions,forwards,denials,alias_denials,begin_cycle,commit_cycle,ack_cycle,phase_end-phase_start,max_gap,latency_max,overlap,cpu_accepted,cpu_completed,contested,inhibited_cycles);
      $fclose(fd);$fclose(events);$display("PASS soc mode=%0d cycles=%0d accepted=%0d errors=%0d overlap=%0d",MODE,cycle,accepts,denials,overlap);$finish;
    end
  end
endmodule
