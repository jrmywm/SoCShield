`timescale 1ns/1ps
module tb_dma;
  reg clk=0, rst_n=0;
  always #5 clk=~clk;

  reg bus_valid=0, bus_write=0;
  reg [11:0] bus_addr=0;
  reg [31:0] bus_wdata=0;
  reg [3:0] bus_wstrb=4'hf;
  wire [31:0] bus_rdata;
  wire bus_error;
  wire req_valid;
  reg req_ready=0;
  wire [31:0] req_addr, req_wdata;
  wire req_write;
  reg rsp_valid=0, rsp_error=0;
  wire rsp_ready;
  reg [31:0] rsp_rdata=0;

  dma_engine dut(.*);

  task mmio_write(input [11:0] addr, input [31:0] data, input expect_error);
    begin
      @(negedge clk); bus_valid=1; bus_write=1; bus_addr=addr; bus_wdata=data; bus_wstrb=4'hf;
      #1; if (bus_error !== expect_error) $fatal(1,"write error mismatch addr=%h data=%h",addr,data);
      @(posedge clk); @(negedge clk); bus_valid=0; bus_write=0;
    end
  endtask

  task mmio_read(input [11:0] addr, input [31:0] expected);
    begin
      @(negedge clk); bus_valid=1; bus_write=0; bus_addr=addr;
      #1; if (bus_error || bus_rdata !== expected)
        $fatal(1,"read mismatch addr=%h got=%h expected=%h err=%b",addr,bus_rdata,expected,bus_error);
      @(posedge clk); @(negedge clk); bus_valid=0;
    end
  endtask

  task await_request(input [31:0] addr, input wr, input [31:0] data);
    integer timeout;
    begin
      timeout=0;
      while (!req_valid && timeout<30) begin @(negedge clk); timeout=timeout+1; end
      if (!req_valid) $fatal(1,"request timeout");
      if (req_addr !== addr || req_write !== wr || req_wdata !== data)
        $fatal(1,"request mismatch got %h %b %h expected %h %b %h",req_addr,req_write,req_wdata,addr,wr,data);
    end
  endtask

  task accept_request;
    begin @(negedge clk); req_ready=1; @(posedge clk); @(negedge clk); req_ready=0; end
  endtask

  task send_response(input err, input [31:0] data);
    begin
      repeat (2) @(negedge clk);
      rsp_valid=1; rsp_error=err; rsp_rdata=data;
      @(posedge clk); @(negedge clk); rsp_valid=0; rsp_error=0;
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    if (req_valid || rsp_ready) $fatal(1,"DMA handshake outputs active in reset");
    rst_n=1;

    // Three writes exercise request back-pressure, a denied response, and
    // immutable active configuration while software edits the staging bank.
    mmio_write(12'h000,32'h00001000,0);
    mmio_write(12'h004,3,0);
    mmio_write(12'h008,1,0);
    mmio_write(12'h00c,32'h10,0);
    mmio_write(12'h010,1,0);
    await_request(32'h1000,1,32'h10);
    repeat (3) begin
      @(negedge clk);
      if (!req_valid || req_addr!==32'h1000 || !req_write || req_wdata!==32'h10)
        $fatal(1,"request changed while stalled");
    end
    mmio_write(12'h000,32'h3000,0);
    mmio_write(12'h004,1,0);
    mmio_write(12'h00c,32'hdeadbeef,0);
    mmio_write(12'h010,1,1);
    mmio_read(12'h014,1);
    accept_request(); send_response(0,0);
    await_request(32'h1004,1,32'h11); accept_request(); send_response(1,0);
    await_request(32'h1008,1,32'h12); accept_request(); send_response(0,0);
    mmio_read(12'h014,2);
    mmio_read(12'h018,2);
    mmio_read(12'h01c,1);
    mmio_read(12'h020,0);
    mmio_read(12'h024,1);

    // Successful reads XOR into the checksum; denied words remain counted.
    mmio_write(12'h000,32'h2000,0);
    mmio_write(12'h004,2,0);
    mmio_write(12'h008,0,0);
    mmio_write(12'h00c,0,0);
    mmio_write(12'h010,1,0);
    await_request(32'h2000,0,0); accept_request(); send_response(0,32'h12345678);
    await_request(32'h2004,0,0); accept_request(); send_response(0,32'h00ff00ff);
    mmio_read(12'h018,2);
    mmio_read(12'h01c,0);
    mmio_read(12'h020,32'h12cb5687);
    mmio_read(12'h024,0);
    mmio_write(12'h024,1,0);
    mmio_read(12'h024,0);

    // Zero count finishes without issuing a memory request.
    mmio_write(12'h004,0,0);
    mmio_write(12'h010,1,0);
    mmio_read(12'h014,2);
    mmio_read(12'h018,0);
    mmio_read(12'h01c,0);
    mmio_read(12'h020,0);
    mmio_read(12'h024,0);
    if (req_valid) $fatal(1,"zero count issued request");

    // Unaligned and wrapping ranges are rejected before any bus request.
    mmio_write(12'h000,32'h00000001,0);
    mmio_write(12'h004,1,0);
    mmio_write(12'h010,1,1);
    if (req_valid) $fatal(1,"unaligned start issued request");
    mmio_write(12'h000,32'hfffffffc,0);
    mmio_write(12'h004,2,0);
    mmio_write(12'h010,1,1);
    if (req_valid) $fatal(1,"wrapping range issued request");
    // This addition would wrap even a 34-bit temporary without the carry bit.
    mmio_write(12'h004,32'hffffffff,0);
    mmio_write(12'h010,1,1);
    if (req_valid) $fatal(1,"large wrapping range issued request");
    mmio_read(12'h024,1);
    mmio_write(12'h024,1,0);
    mmio_read(12'h024,0);

    // Mis-sized MMIO write is rejected and made visible in ERR.
    @(negedge clk); bus_valid=1; bus_write=1; bus_addr=12'h000; bus_wdata=0; bus_wstrb=4'h3;
    #1; if (!bus_error) $fatal(1,"partial write accepted");
    @(posedge clk); @(negedge clk); bus_valid=0; bus_write=0; bus_wstrb=4'hf;
    mmio_read(12'h024,1);

    // Reset must gate a pending request and a pending response handshake.
    mmio_write(12'h000,32'h00004000,0);
    mmio_write(12'h004,1,0);
    mmio_write(12'h010,1,0);
    await_request(32'h4000,0,0);
    @(negedge clk); rst_n=0; #1;
    if (req_valid || rsp_ready) $fatal(1,"request handshake active in reset");
    @(posedge clk); @(negedge clk); rst_n=1;
    mmio_write(12'h000,32'h00005000,0);
    mmio_write(12'h004,1,0);
    mmio_write(12'h010,1,0);
    await_request(32'h5000,0,0); accept_request();
    if (!rsp_ready) $fatal(1,"response state not ready");
    @(negedge clk); rst_n=0; #1;
    if (req_valid || rsp_ready) $fatal(1,"response handshake active in reset");
    @(posedge clk); @(negedge clk); rst_n=1;

    $display("PASS tb_dma");
    $finish;
  end
  initial begin #30000; $fatal(1,"tb_dma timeout"); end
endmodule
