`timescale 1ns/1ps

module async_fifo_tb;

    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 4;
    parameter DEPTH      = 1 << ADDR_WIDTH;

    reg                    wr_clk, rd_clk;
    reg                    wr_rst_n, rd_rst_n;
    reg                    wr_en, rd_en;
    reg  [DATA_WIDTH-1:0]  wdata;
    wire [DATA_WIDTH-1:0]  rdata;
    wire                   full, empty;

    integer errors;

    reg [DATA_WIDTH-1:0] ref_q [0:2047];
    integer ref_head, ref_tail;

    async_fifo #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) dut (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n), .wr_en(wr_en), .wdata(wdata), .full(full),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n), .rd_en(rd_en), .rdata(rdata), .empty(empty)
    );

    initial wr_clk = 0;
    always #7 wr_clk = ~wr_clk;

    initial rd_clk = 0;
    always #13 rd_clk = ~rd_clk;

    task w_write(input [DATA_WIDTH-1:0] data);
        begin
            @(negedge wr_clk);
            wdata = data;
            if (!full) begin
                wr_en = 1;
                ref_q[ref_tail] = data;
                ref_tail = ref_tail + 1;
            end else begin
                wr_en = 0;
                $display("[%0t] wr: skipped, FIFO full (expected)", $time);
            end
            @(negedge wr_clk);
            wr_en = 0;
        end
    endtask

    task r_read;
        begin
            @(negedge rd_clk);
            if (!empty) begin
                rd_en = 1;
                if (rdata !== ref_q[ref_head]) begin
                    $display("[%0t] ERROR: read mismatch. got=%0h expected=%0h (idx=%0d)",
                              $time, rdata, ref_q[ref_head], ref_head);
                    errors = errors + 1;
                end
                ref_head = ref_head + 1;
            end else begin
                rd_en = 0;
                $display("[%0t] rd: skipped, FIFO empty (expected)", $time);
            end
            @(negedge rd_clk);
            rd_en = 0;
        end
    endtask

    integer i;
    integer seed;

    initial begin
        errors   = 0;
        ref_head = 0;
        ref_tail = 0;
        seed     = 99;

        wr_rst_n = 0; rd_rst_n = 0;
        wr_en = 0; rd_en = 0; wdata = 0;

        repeat (3) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (3) @(posedge rd_clk);
        rd_rst_n = 1;

        $display("Test 1: fill to full");
        for (i = 0; i < DEPTH; i = i + 1)
            w_write(i);

        w_write(8'hAA);

        if (!full) begin
            $display("[%0t] ERROR: expected full after %0d writes", $time, DEPTH);
            errors = errors + 1;
        end

        $display("Test 2: drain to empty");
        for (i = 0; i < DEPTH; i = i + 1)
            r_read();

        r_read();

        if (!empty) begin
            $display("[%0t] ERROR: expected empty after draining", $time);
            errors = errors + 1;
        end

        $display("Test 3: concurrent randomized read/write traffic");
        fork
            begin : wr_proc
                for (i = 0; i < 300; i = i + 1) begin
                    if (($random(seed) % 4) != 0)
                        w_write($random(seed) & 8'hFF);
                    else
                        @(negedge wr_clk);
                end
            end
            begin : rd_proc
                for (i = 0; i < 300; i = i + 1) begin
                    if (($random(seed) % 4) != 0)
                        r_read();
                    else
                        @(negedge rd_clk);
                end
            end
        join

        while (!empty)
            r_read();

        $display("Test 4: reset mid-operation");
        w_write(8'h11);
        w_write(8'h22);

        wr_rst_n = 0;
        rd_rst_n = 0;
        repeat (3) @(posedge wr_clk);
        repeat (3) @(posedge rd_clk);
        wr_rst_n = 1;
        rd_rst_n = 1;
        repeat (3) @(posedge wr_clk);
        repeat (3) @(posedge rd_clk);

        ref_head = ref_tail;

        if (!empty) begin
            $display("[%0t] ERROR: expected empty immediately after reset", $time);
            errors = errors + 1;
        end
        if (full) begin
            $display("[%0t] ERROR: expected NOT full immediately after reset", $time);
            errors = errors + 1;
        end

        for (i = 0; i < 8; i = i + 1)
            w_write(8'h50 + i);
        for (i = 0; i < 8; i = i + 1)
            r_read();

        if (errors == 0)
            $display("Pass: all checks passed");
        else
            $display("Fail: %0d error(s) found", errors);

        $finish;
    end

endmodule