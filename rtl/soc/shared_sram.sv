module shared_sram #(
    parameter integer WORDS = 16384,
    parameter integer LATENCY = 1
) (
    input wire clk, rst_n, stall,
    input wire c_req_valid, output wire c_req_ready,
    input wire [31:0] c_req_addr, input wire c_req_write,
    input wire [31:0] c_req_wdata, input wire [3:0] c_req_wstrb,
    output wire c_rsp_valid, input wire c_rsp_ready,
    output wire c_rsp_error, output wire [31:0] c_rsp_rdata,
    input wire d_req_valid, output wire d_req_ready,
    input wire [31:0] d_req_addr, input wire d_req_write,
    input wire [31:0] d_req_wdata, input wire [3:0] d_req_wstrb,
    output wire d_rsp_valid, input wire d_rsp_ready,
    output wire d_rsp_error, output wire [31:0] d_rsp_rdata
);
    localparam [32:0] BASE = 33'h010000000;
    localparam [32:0] LIMIT = BASE + (33'd4 * WORDS);
    reg [31:0] mem [0:WORDS-1];
    reg busy, owner, prefer_d, response_valid;
    reg response_error;
    reg [31:0] response_data;
    integer remaining;
    integer i, b;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 0;
    end

    wire grant_d = d_req_valid && (!c_req_valid || prefer_d);
    wire grant_c = c_req_valid && (!d_req_valid || !prefer_d);
    assign c_req_ready = rst_n && !stall && !busy && grant_c;
    assign d_req_ready = rst_n && !stall && !busy && grant_d;
    assign c_rsp_valid = rst_n && response_valid && !owner;
    assign d_rsp_valid = rst_n && response_valid && owner;
    assign c_rsp_error = response_error;
    assign d_rsp_error = response_error;
    assign c_rsp_rdata = response_data;
    assign d_rsp_rdata = response_data;
    wire accept = c_req_ready || d_req_ready;
    wire [31:0] address = grant_d ? d_req_addr : c_req_addr;
    wire write_req = grant_d ? d_req_write : c_req_write;
    wire [31:0] wdata = grant_d ? d_req_wdata : c_req_wdata;
    wire [3:0] wstrb = grant_d ? d_req_wstrb : c_req_wstrb;
    wire in_range = ({1'b0,address} >= BASE) && ({1'b0,address} < LIMIT)
                    && (address[1:0] == 2'b00);
    localparam integer INDEX_WIDTH = WORDS > 1 ? $clog2(WORDS) : 1;
    wire [INDEX_WIDTH-1:0] index = (address - BASE[31:0]) >> 2;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 0;
            owner <= 0;
            prefer_d <= 0;
            response_valid <= 0;
            response_error <= 0;
            response_data <= 0;
            remaining <= 0;
        end else begin
            if (accept) begin
                busy <= 1;
                owner <= grant_d;
                prefer_d <= !grant_d;
                response_valid <= 0;
                response_error <= !in_range;
                response_data <= in_range && !write_req ? mem[index] : 32'b0;
                remaining <= LATENCY > 0 ? LATENCY : 1;
                if (in_range && write_req)
                    for (b = 0; b < 4; b = b + 1)
                        if (wstrb[b]) mem[index][8*b +: 8] <= wdata[8*b +: 8];
            end else if (response_valid) begin
                if ((owner && d_rsp_ready) || (!owner && c_rsp_ready)) begin
                    response_valid <= 0;
                    busy <= 0;
                end
            end else if (busy && !stall) begin
                if (remaining <= 1) response_valid <= 1;
                else remaining <= remaining - 1;
            end
        end
    end
endmodule

