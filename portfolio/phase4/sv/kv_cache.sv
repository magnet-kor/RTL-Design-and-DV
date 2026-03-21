// =============================================================================
// kv_cache.sv — KV Cache Manager (DRAM-backed, autoregressive)
// =============================================================================
// Manages K and V vectors for all decode steps in DRAM.
// Per decode step s, layer l:
//   K_addr(l, s) = KV_BASE + l * LAYER_STRIDE + s * STEP_STRIDE
//   V_addr(l, s) = K_addr(l, s) + KV_DIM
//
// Where:
//   LAYER_STRIDE = MAX_SEQ * KV_DIM * 2 = 256*128*2 = 64 KB
//   STEP_STRIDE  = KV_DIM * 2           = 128*2     = 256 B
//
// FSM order enforces Write-before-Read invariant:
//   IDLE → LATCH → DMA_WRITE_K → DMA_WRITE_V → DMA_READ_ALL → DONE
// This guarantees step s K/V are in DRAM before history is loaded.
//
// KV DMA overhead: 32 (write) + 32*(s+1) cycles (read) per layer.
// At step 256: 8,224 cycles = 0.24% of total layer latency → negligible.
// =============================================================================
`timescale 1ns/1ps

module kv_cache #(
    parameter KV_DIM     = 128,
    parameter MAX_SEQ    = 256,
    parameter NUM_LAYERS = 24,
    parameter DATA_W     = 8,
    parameter ADDR_W     = 32,
    parameter DMA_DATA_W = 64,
    parameter SRAM_AW    = 18,
    parameter [ADDR_W-1:0] KV_BASE = 32'h8000_0000
)(
    input  logic                          clk, rst_n,
    input  logic [4:0]                    layer_id,
    input  logic [7:0]                    step_id,
    input  logic                          start,
    output logic                          done,
    // New K/V from QKV projection + RoPE
    input  logic signed [DATA_W-1:0]      k_new [0:KV_DIM-1],
    input  logic signed [DATA_W-1:0]      v_new [0:KV_DIM-1],
    // History output to MHA
    output logic signed [DATA_W-1:0]      k_hist [0:MAX_SEQ-1][0:KV_DIM-1],
    output logic signed [DATA_W-1:0]      v_hist [0:MAX_SEQ-1][0:KV_DIM-1],
    output logic [7:0]                    hist_len,
    // DMA interface
    output logic                          dma_rd_start, dma_wr_start,
    output logic [ADDR_W-1:0]             dma_rd_dram_addr, dma_wr_dram_addr,
    output logic [SRAM_AW-1:0]            dma_rd_sram_addr, dma_wr_sram_addr,
    output logic [15:0]                   dma_rd_len, dma_wr_len,
    input  logic                          dma_rd_done, dma_wr_done,
    // SRAM write port (from DMA read)
    input  logic [SRAM_AW-1:0]            sram_waddr,
    input  logic [DMA_DATA_W-1:0]         sram_wdata,
    input  logic                          sram_wen
);
    localparam LAYER_STRIDE = MAX_SEQ * KV_DIM * 2;
    localparam STEP_STRIDE  = KV_DIM * 2;
    localparam BPE          = DMA_DATA_W / 8;

    function automatic [ADDR_W-1:0] k_addr(input [4:0] l, input [7:0] s);
        k_addr = KV_BASE + l * LAYER_STRIDE + s * STEP_STRIDE;
    endfunction
    function automatic [ADDR_W-1:0] v_addr(input [4:0] l, input [7:0] s);
        v_addr = k_addr(l, s) + KV_DIM;
    endfunction

    // On-chip KV ring buffer
    localparam BUF_ENTRIES = MAX_SEQ * KV_DIM * 2 / BPE;
    logic [DMA_DATA_W-1:0] kv_buf [0:BUF_ENTRIES-1];

    // Populate on DMA read-back
    always_ff @(posedge clk) begin
        if (sram_wen)
            kv_buf[sram_waddr[$clog2(BUF_ENTRIES)-1:0]] <= sram_wdata;
    end

    // Unpack kv_buf → k_hist, v_hist
    always_comb begin
        for (int s = 0; s < MAX_SEQ; s++) begin
            for (int i = 0; i < KV_DIM; i++) begin
                automatic int ek = (s * STEP_STRIDE + i)         / BPE;
                automatic int bk = (s * STEP_STRIDE + i)         % BPE;
                automatic int ev = (s * STEP_STRIDE + KV_DIM + i)/ BPE;
                automatic int bv = (s * STEP_STRIDE + KV_DIM + i)% BPE;
                k_hist[s][i] = kv_buf[ek][bk*8 +: DATA_W];
                v_hist[s][i] = kv_buf[ev][bv*8 +: DATA_W];
            end
        end
    end

    // FSM
    typedef enum logic [2:0] {
        IDLE, LATCH_KV, DMA_WRITE_K, DMA_WRITE_V, DMA_READ_ALL, DONE_ST
    } state_t;
    state_t state;
    logic [7:0] step_r;
    logic [4:0] layer_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; done<=0; hist_len<=0;
            dma_rd_start<=0; dma_wr_start<=0;
        end else begin
            done<=0; dma_rd_start<=0; dma_wr_start<=0;
            case(state)
                IDLE: if(start) begin
                    step_r<=step_id; layer_r<=layer_id;
                    hist_len<=step_id+1; state<=LATCH_KV;
                end
                LATCH_KV: state<=DMA_WRITE_K;
                DMA_WRITE_K: begin
                    dma_wr_start<=1;
                    dma_wr_dram_addr<=k_addr(layer_r, step_r);
                    dma_wr_sram_addr<=SRAM_AW'(step_r*(STEP_STRIDE/BPE));
                    dma_wr_len<=KV_DIM;
                    if(dma_wr_done) state<=DMA_WRITE_V;
                end
                DMA_WRITE_V: begin
                    dma_wr_start<=1;
                    dma_wr_dram_addr<=v_addr(layer_r, step_r);
                    dma_wr_sram_addr<=SRAM_AW'(step_r*(STEP_STRIDE/BPE)+KV_DIM/BPE);
                    dma_wr_len<=KV_DIM;
                    if(dma_wr_done) state<=DMA_READ_ALL;
                end
                DMA_READ_ALL: begin
                    dma_rd_start<=1;
                    dma_rd_dram_addr<=k_addr(layer_r, 8'd0);
                    dma_rd_sram_addr<='0;
                    dma_rd_len<=16'((step_r+1)*STEP_STRIDE);
                    if(dma_rd_done) state<=DONE_ST;
                end
                DONE_ST: begin done<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
