  reg past_valid=0;
  // Independent policy model. No restriction on trusted config values or
  // on unaccepted requester inputs; no fairness/progress assumptions.
  reg [3:0] en, rd, wr;
  reg [31:0] lo [0:3], hi [0:3];
  reg reference_allow;
  integer j;
  always @* begin
    reference_allow=0;
    for(integer k=3;k>=0;k=k-1)
      if(en[k] && req_addr>=lo[k] && req_addr<=hi[k])
        reference_allow=(req_write ? wr[k] : rd[k]) &&
                        ({1'b0,req_addr}+33'd3 <= {1'b0,hi[k]});
    if(req_addr[1:0]!=0) reference_allow=0;
  end

  reg busy, permitted, issued, returned;
  reg [31:0] saved_addr, saved_wdata, result;
  reg saved_write, result_error;
  reg seen_deny, seen_read, seen_write, seen_mem_stall, seen_rsp_stall;
  always @(posedge clk) begin
    past_valid<=1;
    if(!past_valid) assume(!rst_n);
    if(!rst_n) begin
      en<=0; rd<=0; wr<=0;
      for(j=0;j<4;j=j+1) begin lo[j]<=0; hi[j]<=0; end
      busy<=0; permitted<=0; issued<=0; returned<=0;
      saved_addr<=0; saved_wdata<=0; saved_write<=0;
      result<=0; result_error<=0;
      seen_deny<=0; seen_read<=0; seen_write<=0;
      seen_mem_stall<=0; seen_rsp_stall<=0;
    end else begin
      if(cfg_valid && cfg_ready) begin
        en[cfg_index]<=cfg_enable; rd[cfg_index]<=cfg_read; wr[cfg_index]<=cfg_write;
        lo[cfg_index]<=cfg_base; hi[cfg_index]<=cfg_limit;
      end
      if(req_valid && req_ready) begin
        busy<=1; permitted<=reference_allow; issued<=0; returned<=0;
        saved_addr<=req_addr; saved_wdata<=req_wdata; saved_write<=req_write;
        if(!reference_allow) seen_deny<=1;
      end
      if(mem_req_valid && mem_req_ready) issued<=1;
      if(mem_rsp_valid && mem_rsp_ready) begin
        returned<=1; result_error<=mem_rsp_error;
        result<=(mem_rsp_error || saved_write) ? 0 : mem_rsp_rdata;
      end
      if(rsp_valid && rsp_ready) begin
        busy<=0;
        if(permitted && !saved_write) seen_read<=1;
        if(permitted && saved_write) seen_write<=1;
      end
      if(mem_req_valid && !mem_req_ready) seen_mem_stall<=1;
      if(rsp_valid && !rsp_ready) seen_rsp_stall<=1;
    end

    if(past_valid) begin
      if(!rst_n) begin
        assert(!req_ready && !rsp_valid && !mem_req_valid && !mem_rsp_ready && !cfg_ready);
      end else begin
        // Inductive strengthening: prove model and implementation storage
        // agree even across arbitrarily long stalls and idle intervals.
        assert(enabled==en && read_ok==rd && write_ok==wr);
        for(integer m=0;m<4;m=m+1) begin
          assert(base[m]==lo[m]); assert(limit[m]==hi[m]);
        end
        assert((state==IDLE)==!busy);
        assert((state==SEND)==(busy && permitted && !issued));
        assert((state==WAIT_RSP)==(busy && permitted && issued && !returned));
        assert((state==RESP)==(busy && (!permitted || returned)));
        if(busy) begin
          assert(addr_q==saved_addr && wdata_q==saved_wdata && write_q==saved_write);
          if(permitted && returned) begin assert(error_q==result_error); assert(rdata_q==result); end
        end
        assert(req_ready == !busy);
        assert(cfg_ready == (!busy && !req_valid));
        assert(mem_req_valid == (busy && permitted && !issued));
        assert(mem_rsp_ready == (busy && permitted && issued && !returned));
        assert(rsp_valid == (busy && (!permitted || returned)));
        if(mem_req_valid) begin
          assert(busy && permitted && !issued);
          assert(mem_req_addr==saved_addr);
          assert(mem_req_write==saved_write);
          assert(mem_req_wdata==saved_wdata);
        end
        if(busy && !permitted) assert(!mem_req_valid);
        if(rsp_valid) begin
          if(!permitted) begin assert(rsp_error); assert(rsp_rdata==0); end
          else begin assert(rsp_error==result_error); assert(rsp_rdata==result); end
        end
        if($past(rst_n && mem_req_valid && !mem_req_ready)) begin
          assert(mem_req_valid);
          assert({mem_req_addr,mem_req_write,mem_req_wdata}==$past({mem_req_addr,mem_req_write,mem_req_wdata}));
        end
        if($past(rst_n && rsp_valid && !rsp_ready)) begin
          assert(rsp_valid);
          assert({rsp_error,rsp_rdata}==$past({rsp_error,rsp_rdata}));
        end
        cover(rsp_valid && !permitted && rsp_ready);
        cover(seen_read && seen_write && seen_deny);
        cover(seen_mem_stall && seen_rsp_stall && rsp_valid && rsp_ready);
        cover($past(!rst_n) && req_ready);
      end
      cover(!rst_n && $past(rst_n && busy && issued));
    end
  end
