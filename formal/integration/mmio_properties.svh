// Wrapper-local safety properties. The backend may stall or respond arbitrarily.
reg f_past=0;
always @(posedge clk) begin
  f_past<=1;
  if (!f_past) assume(!rst_n);
  if (f_past && rst_n && $past(rst_n)) begin
    assert(commit_seq == ($past(commit_seq) + (($past(mailbox==COMMIT_CMD && commit_ack)) ? 1 : 0)));
    assert(cmd_seq == ($past(cmd_seq) + (($past(begin_fire || cfg_fire || commit_fire)) ? 1 : 0)));
    if ($past(bus_valid && bus_write && bus_addr==12'h00c && !bus_error))
      assert(errors == (($past(errors) & ~$past(bus_wdata)) | {29'b0,$past(error_set)}));
    else assert(errors == ($past(errors) | {29'b0,$past(error_set)}));
    if ($past(cfg_valid && !cfg_ready)) begin
      assert(cfg_valid);
      assert({payload_index,payload_base,payload_limit,payload_perm} ==
             $past({payload_index,payload_base,payload_limit,payload_perm}));
    end
    if ($past(mailbox==COMMIT_CMD && !commit_ack)) begin
      assert(mailbox==COMMIT_CMD);
      assert(session_open);
    end
    if ($past(bus_valid && bus_write && bus_error && bus_addr==12'h008 && mailbox==NONE))
      assert(mailbox==NONE);
    if ($past(bus_valid && bus_write && !bus_error && bus_addr==12'h008 && bus_wdata==1)) begin
      assert(session_open); assert(mailbox==BEGIN_CMD); assert(written_mask==0);
    end
    if ($past(bus_valid && bus_write && !bus_error && bus_addr==12'h008 && bus_wdata==2)) begin
      assert(mailbox==ENTRY_CMD);
      assert({payload_index,payload_base,payload_limit,payload_perm} ==
             $past({stage_index,stage_base,stage_limit,stage_perm}));
    end
  end
  if (rst_n && f_past) begin
    if (commit_valid) assert(session_open && written_mask==4'hf);
    if (mailbox!=NONE && bus_valid && bus_write && bus_addr==12'h008) assert(bus_error);
    if (bus_valid && bus_error) assert(|error_set);
    if (cfg_valid) assert(session_open);
    if (mailbox==COMMIT_CMD) assert(session_open);
    if (bus_valid && bus_write && bus_addr==12'h008 && !bus_error) begin
      assert(mailbox==NONE);
      if (bus_wdata==1) assert(!session_open);
      if (bus_wdata==2) assert(session_open);
      if (bus_wdata==3) assert(session_open && written_mask==4'hf);
    end
  end
end
