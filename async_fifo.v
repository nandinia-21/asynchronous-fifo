module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wdata,
    output reg                   full,

    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rdata,
    output reg                   empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;
    localparam PW    = ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg  [ADDR_WIDTH:0] wbin, wgray;
    wire [ADDR_WIDTH:0] wbinnext, wgraynext;
    wire                wfull_next;

    reg  [ADDR_WIDTH:0] rbin, rgray;
    wire [ADDR_WIDTH:0] rbinnext, rgraynext;
    wire                rempty_next;

    reg [ADDR_WIDTH:0] rq1_rdptr, rq2_rdptr;
    reg [ADDR_WIDTH:0] wq1_wrptr, wq2_wrptr;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)
            {rq2_rdptr, rq1_rdptr} <= 0;
        else
            {rq2_rdptr, rq1_rdptr} <= {rq1_rdptr, rgray};
    end

    assign wbinnext  = wbin + (wr_en & ~full);
    assign wgraynext = (wbinnext >> 1) ^ wbinnext;

    assign wfull_next = (wgraynext == {~rq2_rdptr[ADDR_WIDTH:ADDR_WIDTH-1],
                                         rq2_rdptr[ADDR_WIDTH-2:0]});

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wbin  <= 0;
            wgray <= 0;
        end else begin
            wbin  <= wbinnext;
            wgray <= wgraynext;
        end
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)
            full <= 1'b0;
        else
            full <= wfull_next;
    end

    always @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wbin[ADDR_WIDTH-1:0]] <= wdata;
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            {wq2_wrptr, wq1_wrptr} <= 0;
        else
            {wq2_wrptr, wq1_wrptr} <= {wq1_wrptr, wgray};
    end

    assign rbinnext  = rbin + (rd_en & ~empty);
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;

    assign rempty_next = (rgraynext == wq2_wrptr);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rbin  <= 0;
            rgray <= 0;
        end else begin
            rbin  <= rbinnext;
            rgray <= rgraynext;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            empty <= 1'b1;
        else
            empty <= rempty_next;
    end

    assign rdata = mem[rbin[ADDR_WIDTH-1:0]];

endmodule