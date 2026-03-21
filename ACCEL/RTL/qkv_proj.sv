// =============================================================================
// qkv_proj.sv — QKV Projection via Tiled Systolic Array
// =============================================================================
// Computes Q = Wq*x, K = Wk*x, V = Wv*x using a single 8x8 systolic array.
// Weight layout (contiguous, row-major):
//   [0             .. Wq_end]: Wq  [IN_DIM × Q_DIM]
//   [Wq_end+1      .. Wk_end]: Wk  [IN_DIM × KV_DIM]
//   [Wk_end+1      .. Wv_end]: Wv  [IN_DIM × KV_DIM]
//
// Tiling parameters (full-size):
//   TILES_K = IN_DIM / SIZE = 896/8 = 112  (K-reduction tiles)
//   TILES_N = Q_DIM / SIZE  = 896/8 = 112  (output tiles, per matrix)
//   Total cycles ~ 129,045 = 0.645 ms @ 200 MHz
//
// Tile_k == 0: reset accumulator. Tile_k == TILES_K-1: write output buffer.
// =============================================================================
`timescale 1ns/1ps

module qkv_proj #(
    parameter IN_DIM  = 896,
    parameter Q_DIM   = 896,
    parameter KV_DIM  = 128,
    parameter DATA_W  = 8,
    parameter ACC_W   = 32,
    parameter SIZE    = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          start,
    output logic                          done,

    // Activation SRAM (x_norm)
    output logic [$clog2(IN_DIM)-1:0]    act_addr,
    input  logic signed [DATA_W-1:0]     act_rdata,

    // Weight SRAM (Wq | Wk | Wv, contiguous)
    output logic [19:0]                   wgt_addr,
    input  logic signed [DATA_W-1:0]     wgt_rdata,

    // Outputs
    output logic signed [DATA_W-1:0]     q_out [0:Q_DIM-1],
    output logic signed [DATA_W-1:0]     k_out [0:KV_DIM-1],
    output logic signed [DATA_W-1:0]     v_out [0:KV_DIM-1],
    output logic                          q_valid,
    output logic                          k_valid,
    output logic                          v_valid
);
    localparam TILES_K_Q  = IN_DIM  / SIZE;
    localparam TILES_N_Q  = Q_DIM   / SIZE;
    localparam TILES_N_KV = KV_DIM  / SIZE;
    localparam WQ_BASE    = 20'd0;
    localparam WK_BASE    = 20'(IN_DIM * Q_DIM);
    localparam WV_BASE    = 20'(IN_DIM * Q_DIM + IN_DIM * KV_DIM);

    typedef enum logic [2:0] {
        IDLE, LOAD_TILE, COMPUTE, ACCUM, NEXT_TILE, DONE_ST
    } state_t;
    state_t state;

    logic [1:0]   mat_sel;      // 0=Q 1=K 2=V
    logic [9:0]   tile_n, tile_k;
    logic [5:0]   load_cnt;
    logic [2:0]   cyc_cnt;

    logic signed [DATA_W-1:0] wgt_tile [0:SIZE-1][0:SIZE-1];
    logic signed [ACC_W-1:0]  acc_q [0:Q_DIM-1];
    logic signed [ACC_W-1:0]  acc_kv[0:KV_DIM*2-1];

    // Systolic array
    logic signed [DATA_W-1:0] sa_top[0:SIZE-1], sa_left[0:SIZE-1];
    logic                      sa_vin;
    logic signed [ACC_W-1:0]  sa_bot[0:SIZE-1];
    logic                      sa_vout;

    systolic_array #(.SIZE(SIZE),.DATA_W(DATA_W),.ACC_W(ACC_W)) u_sa (
        .clk(clk),.rst_n(rst_n),
        .top_data(sa_top),.left_data(sa_left),.data_valid(sa_vin),
        .bottom_data(sa_bot),.out_valid(sa_vout)
    );

    function automatic [9:0] tiles_n(input [1:0] sel);
        return (sel == 0) ? 10'(TILES_N_Q-1) : 10'(TILES_N_KV-1);
    endfunction
    function automatic [19:0] wbase(input [1:0] sel);
        case(sel)
            2'd0: return WQ_BASE;
            2'd1: return WK_BASE;
            default: return WV_BASE;
        endcase
    endfunction
    function automatic [9:0] ndim(input [1:0] sel);
        return (sel == 0) ? 10'(Q_DIM) : 10'(KV_DIM);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; done<=0; sa_vin<=0;
            mat_sel<=0; tile_n<=0; tile_k<=0; load_cnt<=0; cyc_cnt<=0;
            q_valid<=0; k_valid<=0; v_valid<=0;
        end else begin
            done<=0; sa_vin<=0; q_valid<=0; k_valid<=0; v_valid<=0;
            case(state)
                IDLE: if(start) begin
                    mat_sel<=0; tile_n<=0; tile_k<=0; load_cnt<=0; state<=LOAD_TILE;
                end
                LOAD_TILE: begin
                    wgt_addr <= wbase(mat_sel)
                              + 20'(tile_k*SIZE + load_cnt[5:3]) * ndim(mat_sel)
                              + 20'(tile_n*SIZE + load_cnt[2:0]);
                    if(load_cnt>0) wgt_tile[(load_cnt-1)[5:3]][(load_cnt-1)[2:0]] <= wgt_rdata;
                    if(load_cnt==63) begin
                        wgt_tile[7][7]<=wgt_rdata; load_cnt<=0; cyc_cnt<=0; state<=COMPUTE;
                    end else load_cnt<=load_cnt+1;
                end
                COMPUTE: begin
                    sa_vin<=1;
                    act_addr <= $clog2(IN_DIM)'(tile_k*SIZE + cyc_cnt);
                    for(int i=0;i<SIZE;i++) sa_top[i] <= act_rdata;
                    for(int i=0;i<SIZE;i++) sa_left[i] <= wgt_tile[cyc_cnt][i];
                    if(cyc_cnt==SIZE-1) begin cyc_cnt<=0; state<=ACCUM; end
                    else cyc_cnt<=cyc_cnt+1;
                end
                ACCUM: if(sa_vout) begin
                    for(int i=0;i<SIZE;i++) begin
                        automatic int idx = tile_n*SIZE+i;
                        if(mat_sel==0) acc_q[idx]   <= (tile_k==0) ? sa_bot[i] : acc_q[idx]+sa_bot[i];
                        else           acc_kv[idx + (mat_sel==2 ? KV_DIM : 0)] <=
                                       (tile_k==0) ? sa_bot[i] : acc_kv[idx+(mat_sel==2?KV_DIM:0)]+sa_bot[i];
                    end
                    state<=NEXT_TILE;
                end
                NEXT_TILE: begin
                    if(tile_k==TILES_K_Q-1) begin
                        // Write output
                        for(int i=0;i<SIZE;i++) begin
                            automatic int idx=tile_n*SIZE+i;
                            automatic logic signed [ACC_W-1:0] v =
                                (mat_sel==0)?acc_q[idx]:acc_kv[idx+(mat_sel==2?KV_DIM:0)];
                            automatic logic signed [DATA_W-1:0] c =
                                (v>127)?8'sd127:(v<-128)?-8'sd128:v[DATA_W-1:0];
                            if(mat_sel==0) begin q_out[idx]<=c; end
                            else if(mat_sel==1) begin k_out[idx]<=c; end
                            else begin v_out[idx]<=c; end
                        end
                        tile_k<=0;
                        if(tile_n==tiles_n(mat_sel)) begin
                            tile_n<=0;
                            if(mat_sel==0) begin q_valid<=1; mat_sel<=1; state<=LOAD_TILE; end
                            else if(mat_sel==1) begin k_valid<=1; mat_sel<=2; state<=LOAD_TILE; end
                            else begin v_valid<=1; state<=DONE_ST; end
                        end else begin tile_n<=tile_n+1; state<=LOAD_TILE; end
                    end else begin tile_k<=tile_k+1; state<=LOAD_TILE; end
                end
                DONE_ST: begin done<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
