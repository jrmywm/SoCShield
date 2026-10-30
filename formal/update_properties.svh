  reg f_past=0;
  reg f_bank;
  wire f_effective_bank=SHADOW ? (f_bank ^ commit_ack) : 1'b0;
  reg [3:0] f_en[0:BANKS-1],f_rd[0:BANKS-1],f_wr[0:BANKS-1];
  reg [31:0] f_lo[0:BANKS*4-1],f_hi[0:BANKS*4-1];
  reg f_allow;
  always @* begin
    f_allow=0;
    for(integer k=3;k>=0;k=k-1)
      if(f_en[selected_bank][k] && req_addr>=f_lo[selected_bank*4+k] && req_addr<=f_hi[selected_bank*4+k])
        f_allow=(req_write ? f_wr[selected_bank][k] : f_rd[selected_bank][k]) &&
                ({1'b0,req_addr}+33'd3 <= {1'b0,f_hi[selected_bank*4+k]});
    if(req_addr[1:0]!=0) f_allow=0;
  end
  reg f_busy,f_permitted,f_issued,f_returned;
  reg [31:0] f_addr,f_wdata,f_result;
  reg f_write,f_error;
  reg f_open,f_commit_pending,f_barrier;
  reg [3:0] f_written,f_wait;
  reg f_seen_write,f_seen_commit;
  integer q;
  always @(posedge clk) begin
    f_past<=1;
    if(!f_past) assume(!rst_n);
    if(!rst_n) begin
      f_bank<=0; f_busy<=0; f_permitted<=0; f_issued<=0; f_returned<=0;
      f_addr<=0; f_wdata<=0; f_write<=0; f_result<=0; f_error<=0;
      f_open<=0; f_commit_pending<=0; f_barrier<=0; f_written<=0; f_wait<=0;
      f_seen_write<=0; f_seen_commit<=0;
      for(q=0;q<BANKS;q=q+1) begin f_en[q]<=0; f_rd[q]<=0; f_wr[q]<=0; end
      for(q=0;q<BANKS*4;q=q+1) begin f_lo[q]<=0; f_hi[q]<=0; end
    end else begin
      if(commit_ack) begin
        if(SHADOW) f_bank<=!f_bank;
        f_open<=0; f_commit_pending<=0; f_barrier<=0; f_seen_commit<=1;
      end
      if(update_begin_valid && update_begin_ready) begin
        f_open<=1; f_written<=0; f_wait<=0;
        if(!SHADOW) f_barrier<=1;
      end
      if(cfg_valid && cfg_ready) begin
        f_written[cfg_index]<=1;
        f_en[program_bank][cfg_index]<=cfg_enable;
        f_rd[program_bank][cfg_index]<=cfg_read;
        f_wr[program_bank][cfg_index]<=cfg_write;
        f_lo[(program_bank)*4+cfg_index]<=cfg_base;
        f_hi[(program_bank)*4+cfg_index]<=cfg_limit;
      end
      if(commit_valid && commit_ready) begin f_commit_pending<=1; if(SHADOW) f_barrier<=1; end
      if(f_barrier && f_busy && f_wait!=15) f_wait<=f_wait+1'b1;
      if(req_valid && req_ready) begin
        f_busy<=1; f_permitted<=f_allow; f_issued<=0; f_returned<=0;
        f_addr<=req_addr; f_wdata<=req_wdata; f_write<=req_write;
      end
      if(mem_req_valid && mem_req_ready) begin
        f_issued<=1; if(mem_req_write) f_seen_write<=1;
      end
      if(mem_rsp_valid && mem_rsp_ready) begin
        f_returned<=1; f_error<=mem_rsp_error;
        f_result<=(mem_rsp_error || f_write) ? 0 : mem_rsp_rdata;
      end
      if(rsp_valid && rsp_ready) f_busy<=0;
    end
    if(f_past) begin
      if(!rst_n) assert(!req_ready && !rsp_valid && !mem_req_valid && !cfg_ready && !commit_ready && !update_begin_ready);
      else begin
        for(integer m=0;m<BANKS;m=m+1) begin
          assert(enabled[m]==f_en[m] && read_ok[m]==f_rd[m] && write_ok[m]==f_wr[m]);
        end
        for(integer m=0;m<BANKS*4;m=m+1) begin assert(base[m]==f_lo[m]); assert(limit[m]==f_hi[m]); end
        assert(active_bank==f_effective_bank);
        // Prove steering separately, then share storage update expressions
        // so optimization can merge duplicate policy registers.
        assert(selected_bank==f_effective_bank);
        assert(program_bank==(SHADOW ? !f_effective_bank : 0));
        assert(written==f_written);
        assert((state==IDLE)==!f_busy);
        assert((state==SEND)==(f_busy && f_permitted && !f_issued));
        assert((state==WAIT_RSP)==(f_busy && f_permitted && f_issued && !f_returned));
        assert((state==RESP)==(f_busy && (!f_permitted || f_returned)));
        if(f_busy) begin
          assert(addr_q==f_addr && write_q==f_write && wdata_q==f_wdata);
          if(f_permitted && f_returned) begin assert(error_q==f_error); assert(rdata_q==f_result); end
        end
        assert((update_busy || commit_ack)==f_open);
        assert(f_barrier==(SHADOW ? (phase==DRAIN || commit_ack) : f_open));
        assert(f_commit_pending==(SHADOW ? (phase==DRAIN || commit_ack) : commit_ack));
        if(!SHADOW && phase==PROGRAM) assert(!f_busy);
        if(f_barrier && !commit_ack) assert(!req_ready);
        if(commit_ready) assert(f_open && (&f_written) && !f_commit_pending);
        if(cfg_ready) begin assert(f_open && !f_commit_pending); if(!SHADOW) assert(!f_busy); end
        if(commit_ack) begin assert(f_commit_pending && !f_busy); assert(!mem_req_valid && !cfg_ready); end
        if(commit_valid && commit_ready) begin assert(!cfg_ready); assert(!req_ready); end
        if(!SHADOW && update_begin_valid && update_begin_ready) assert(!req_ready);
        if(f_busy) assert(!req_ready);
        assert(mem_req_valid==(f_busy && f_permitted && !f_issued));
        assert(mem_rsp_ready==(f_busy && f_permitted && f_issued && !f_returned));
        assert(rsp_valid==(f_busy && (!f_permitted || f_returned)));
        if(mem_req_valid) assert({mem_req_addr,mem_req_write,mem_req_wdata}=={f_addr,f_write,f_wdata});
        if(rsp_valid) begin
          if(!f_permitted) begin assert(rsp_error); assert(rsp_rdata==0); end
          else begin assert(rsp_error==f_error); assert(rsp_rdata==f_result); end
        end
        if($past(rst_n) && active_bank!=$past(active_bank)) assert(SHADOW && commit_ack);
        if($past(rst_n && mem_req_valid && !mem_req_ready)) begin
          assert(mem_req_valid); assert({mem_req_addr,mem_req_write,mem_req_wdata}==$past({mem_req_addr,mem_req_write,mem_req_wdata}));
        end
        if($past(rst_n && rsp_valid && !rsp_ready)) begin
          assert(rsp_valid); assert({rsp_error,rsp_rdata}==$past({rsp_error,rsp_rdata}));
        end
        cover(commit_ack && f_wait>=4);
        cover(f_seen_write && f_seen_commit && rsp_valid && !f_permitted);
        if(SHADOW) cover(cfg_valid && cfg_ready && req_valid && req_ready);
      end
      cover(!rst_n && $past(rst_n && f_commit_pending));
    end
  end
