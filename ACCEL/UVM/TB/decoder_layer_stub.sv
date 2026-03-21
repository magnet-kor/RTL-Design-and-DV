// =============================================================================
// decoder_layer_stub.sv — Parameterized DUT Stub for UVM Verification
// =============================================================================
// Behavioral stub used when running the UVM environment without the full
// decoder_layer.sv datapath. Models:
//   - Control FSM: start → LATENCY cycles → done
//   - Output:      x_out = x_in + 1 (clipped INT8)
//   - AXI4:        correct AR/AW/W/B handshake sequences
//   - Weight SRAM: returns address-based pattern data
//
// Replace this stub with the real decoder_layer.sv for full regression.
// LATENCY=20 enables fast UVM infrastructure verification.
// =============================================================================
`timescale 1ns/1ps

module decoder_layer_stub #(
    parameter HIDDEN   = 16,
    parameter DATA_W   = 8,
    parameter ADDR_W   = 32,
    parameter DMA_DW   = 64,
    parameter LATENCY  = 20
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          start,
    output logic                          done,
    input  logic [7:0]                    step_id,
    input  logic [4:0]                    layer_id,
    input  logic signed [DATA_W-1:0]      x_in  [0:HIDDEN-1],
    output logic signed [DATA_W-1:0]      x_out [0:HIDDEN-1],
    // Weight SRAM
    input  logic [19:0]                   qkv_wgt_addr,
    output logic signed [DATA_W-1:0]      qkv_wgt_rdata,
    input  logic [22:0]                   mha_ffn_wgt_addr,
    output logic signed [DATA_W-1:0]      mha_ffn_wgt_rdata,
    // AXI4
    output logic [ADDR_W-1:0]             ARADDR,
    output logic [7:0]                    ARLEN,
    output logic [2:0]                    ARSIZE,
    output logic [1:0]                    ARBURST,
    output logic                          ARVALID,
    input  logic                          ARREADY,
    input  logic [DMA_DW-1:0]            RDATA,
    input  logic                          RVALID,
    input  logic                          RLAST,
    output logic                          RREADY,
    output logic [ADDR_W-1:0]             AWADDR,
    output logic [7:0]                    AWLEN,
    output logic [2:0]                    AWSIZE,
    output logic [1:0]                    AWBURST,
    output logic                          AWVALID,
    input  logic                          AWREADY,
    output logic [DMA_DW-1:0]            WDATA,
    output logic                          WVALID,
    output logic                          WLAST,
    input  logic                          WREADY,
    input  logic                          BVALID,
    output logic                          BREADY
);
    // Weight SRAM: address-based pattern
    assign qkv_wgt_rdata     = DATA_W'(qkv_wgt_addr[DATA_W-1:0]);
    assign mha_ffn_wgt_rdata = DATA_W'(mha_ffn_wgt_addr[DATA_W-1:0]);

    typedef enum logic [2:0] {
        IDLE, RUNNING, AXI_WR_ADDR, AXI_WR_DATA,
        AXI_WR_RESP, AXI_RD_ADDR, AXI_RD_DATA, DONE_ST
    } state_t;
    state_t state;

    logic signed [DATA_W-1:0] x_latch [0:HIDDEN-1];
    logic [$clog2(LATENCY+2)-1:0] cnt;
    logic [7:0] beat_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            done    <= 0;
            cnt     <= 0;
            beat_cnt<= 0;
            ARVALID <= 0; ARADDR  <= '0; ARLEN <= '0; ARSIZE <= '0; ARBURST <= '0;
            RREADY  <= 0;
            AWVALID <= 0; AWADDR  <= '0; AWLEN <= '0; AWSIZE <= '0; AWBURST <= '0;
            WVALID  <= 0; WDATA   <= '0; WLAST <= 0; BREADY <= 0;
            for (int i = 0; i < HIDDEN; i++) x_out[i] <= 0;
        end else begin
            done    <= 0;
            ARVALID <= 0; ARADDR  <= '0; ARLEN <= '0; ARSIZE <= '0; ARBURST <= '0;
            AWVALID <= 0; AWADDR  <= '0; AWLEN <= '0; AWSIZE <= '0; AWBURST <= '0;
            WVALID  <= 0; WDATA   <= '0;
            WLAST   <= 0;

            case (state)
                IDLE: begin
                    if (start) begin
                        for (int i = 0; i < HIDDEN; i++) x_latch[i] <= x_in[i];
                        cnt   <= 0;
                        state <= RUNNING;
                    end
                end

                RUNNING: begin
                    // At mid-point: start AXI write (KV cache write-back)
                    if (cnt == LATENCY/2) state <= AXI_WR_ADDR;
                    else                  cnt   <= cnt + 1;
                end

                // AXI Write: Address
                AXI_WR_ADDR: begin
                    AWVALID <= 1;
                    AWADDR  <= 32'h8000_0000 + {24'b0, step_id} * 256;
                    AWLEN   <= 8'd15;
                    AWSIZE  <= 3'd3;
                    AWBURST <= 2'b01;
                    if (AWREADY) begin
                        AWVALID  <= 0;
                        beat_cnt <= 0;
                        state    <= AXI_WR_DATA;
                    end
                end

                // AXI Write: Data
                AXI_WR_DATA: begin
                    WVALID <= 1;
                    WDATA  <= {8{x_latch[0]}};
                    WLAST  <= (beat_cnt == 15);
                    if (WREADY) begin
                        if (beat_cnt == 15) begin
                            WVALID <= 0;
                            WLAST  <= 0;
                            BREADY <= 1;
                            state  <= AXI_WR_RESP;
                        end else
                            beat_cnt <= beat_cnt + 1;
                    end
                end

                // AXI Write: Response
                AXI_WR_RESP: begin
                    if (BVALID) begin
                        BREADY <= 0;
                        state  <= AXI_RD_ADDR;
                    end
                end

                // AXI Read: Address (KV history read)
                AXI_RD_ADDR: begin
                    ARVALID <= 1;
                    ARADDR  <= 32'h8000_0000;
                    ARLEN   <= 8'd15;
                    ARSIZE  <= 3'd3;
                    ARBURST <= 2'b01;
                    if (ARREADY) begin
                        ARVALID  <= 0;
                        RREADY   <= 1;
                        beat_cnt <= 0;
                        state    <= AXI_RD_DATA;
                    end
                end

                // AXI Read: Data
                AXI_RD_DATA: begin
                    if (RVALID) begin
                        beat_cnt <= beat_cnt + 1;
                        if (RLAST) begin
                            RREADY <= 0;
                            state  <= DONE_ST;
                        end
                    end
                end

                DONE_ST: begin
                    for (int i = 0; i < HIDDEN; i++) begin
                        automatic logic signed [DATA_W:0] v =
                            $signed(x_latch[i]) + 1;
                        x_out[i] <= (v > 127) ? 8'sd127 : v[DATA_W-1:0];
                    end
                    done  <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end



endmodule
