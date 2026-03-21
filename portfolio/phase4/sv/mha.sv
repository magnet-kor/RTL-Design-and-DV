// =============================================================================
// mha.sv — Multi-Head Attention with Grouped Query Attention (GQA)
// =============================================================================
// Decode mode (seq=1): Q[1×896] × K_hist[s×128] → scores → softmax → AV → OutProj
//
// GQA mapping: Q_HEADS=14, KV_HEADS=2, ratio=7.
//   KV head index = q_head / 7
//   KV Cache = 7× smaller than full MHA (128 vs 896 per step)
//
// Systolic array reuse within MHA:
//   QKᵀ (14 heads × 8 tiles = 112 calls)
//   AV  (14 heads × ceil(s/8) calls)
//   OutProj (112×112 = 12,544 tiles)
//   Combined with QKV and FFN: 9 calls/layer total.
//
// >>3 = ÷8 = ÷√64: head_dim=64, √64=8=2³. Zero-latency arithmetic shift.
// =============================================================================
`timescale 1ns/1ps

module mha #(
    parameter HIDDEN   = 896,
    parameter Q_HEADS  = 14,
    parameter KV_HEADS = 2,
    parameter HEAD_DIM = 64,
    parameter KV_DIM   = 128,
    parameter MAX_SEQ  = 256,
    parameter DATA_W   = 8,
    parameter ACC_W    = 32,
    parameter SIZE     = 8
)(
    input  logic                          clk, rst_n,
    input  logic                          start,
    output logic                          done,
    input  logic [7:0]                    hist_len,
    input  logic signed [DATA_W-1:0]      q_rot  [0:HIDDEN-1],
    input  logic signed [DATA_W-1:0]      k_hist [0:MAX_SEQ-1][0:KV_DIM-1],
    input  logic signed [DATA_W-1:0]      v_hist [0:MAX_SEQ-1][0:KV_DIM-1],
    output logic [19:0]                   wo_addr,
    input  logic signed [DATA_W-1:0]      wo_rdata,
    output logic signed [DATA_W-1:0]      attn_out [0:HIDDEN-1],
    output logic                          out_valid
);
    // One systolic array instance — time-multiplexed across QKt, AV, OutProj
    logic signed [DATA_W-1:0] sa_top[0:SIZE-1], sa_left[0:SIZE-1];
    logic                      sa_vin;
    logic signed [ACC_W-1:0]  sa_bot[0:SIZE-1];
    logic                      sa_vout;

    systolic_array #(.SIZE(SIZE),.DATA_W(DATA_W),.ACC_W(ACC_W)) u_sa (
        .clk(clk),.rst_n(rst_n),
        .top_data(sa_top),.left_data(sa_left),.data_valid(sa_vin),
        .bottom_data(sa_bot),.out_valid(sa_vout)
    );

    softmax #(.N(SIZE),.DATA_W(DATA_W)) u_sfx (
        .clk(clk),.rst_n(rst_n),
        .scores(sfx_scores),.valid_in(sfx_vin),
        .probs(sfx_probs),.valid_out(sfx_vout)
    );

    logic signed [DATA_W-1:0] sfx_scores[0:SIZE-1];
    logic [DATA_W-1:0]         sfx_probs [0:SIZE-1];
    logic sfx_vin, sfx_vout;

    // Internal buffers
    logic signed [ACC_W-1:0]  qkt_scores[0:Q_HEADS-1][0:MAX_SEQ-1];
    logic [DATA_W-1:0]         probs     [0:Q_HEADS-1][0:MAX_SEQ-1];
    logic signed [ACC_W-1:0]  context   [0:HIDDEN-1];
    logic signed [ACC_W-1:0]  out_acc   [0:HIDDEN-1];

    function automatic [0:0] kv_head_of(input [3:0] qh);
        kv_head_of = qh / (Q_HEADS / KV_HEADS);
    endfunction

    typedef enum logic [3:0] {
        IDLE, QKT_COMPUTE, SCALE_SHIFT, SOFTMAX_IN, SOFTMAX_WAIT,
        AV_COMPUTE, OUTPROJ, RESIDUAL, DONE_ST
    } state_t;
    state_t state;

    logic [3:0] head_idx;
    logic [7:0] seq_idx;
    logic [2:0] cyc_cnt;
    logic [6:0] tile_n, tile_k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; done<=0; out_valid<=0;
            sa_vin<=0; sfx_vin<=0;
            head_idx<=0; seq_idx<=0; cyc_cnt<=0; tile_n<=0; tile_k<=0;
        end else begin
            done<=0; out_valid<=0; sa_vin<=0; sfx_vin<=0;
            case(state)
                IDLE: if(start) begin
                    head_idx<=0; seq_idx<=0; cyc_cnt<=0;
                    for(int i=0;i<HIDDEN;i++) out_acc[i]<='0;
                    state<=QKT_COMPUTE;
                end
                QKT_COMPUTE: begin
                    sa_vin<=1;
                    for(int i=0;i<SIZE;i++)
                        sa_top[i] <= q_rot[head_idx*HEAD_DIM + cyc_cnt*SIZE + i];
                    for(int i=0;i<SIZE;i++)
                        sa_left[i] <= k_hist[seq_idx]
                                             [kv_head_of(head_idx)*HEAD_DIM + cyc_cnt*SIZE + i];
                    if(sa_vout) begin
                        qkt_scores[head_idx][seq_idx] <=
                            (cyc_cnt==0) ? sa_bot[0] :
                            qkt_scores[head_idx][seq_idx] + sa_bot[0];
                    end
                    if(cyc_cnt==SIZE-1) begin
                        cyc_cnt<=0;
                        if(seq_idx==hist_len-1) begin
                            if(head_idx==Q_HEADS-1) begin
                                head_idx<=0; state<=SCALE_SHIFT;
                            end else begin head_idx<=head_idx+1; seq_idx<=0; end
                        end else seq_idx<=seq_idx+1;
                    end else cyc_cnt<=cyc_cnt+1;
                end
                SCALE_SHIFT: begin
                    for(int h=0;h<Q_HEADS;h++)
                        for(int s=0;s<MAX_SEQ;s++)
                            qkt_scores[h][s] <= $signed(qkt_scores[h][s]) >>> 3;
                    head_idx<=0; seq_idx<=0; state<=SOFTMAX_IN;
                end
                SOFTMAX_IN: begin
                    sfx_vin<=1;
                    for(int i=0;i<SIZE;i++) begin
                        automatic int s=seq_idx*SIZE+i;
                        sfx_scores[i]<=(s<hist_len)?
                            qkt_scores[head_idx][s][DATA_W-1:0]:8'sh80;
                    end
                    state<=SOFTMAX_WAIT;
                end
                SOFTMAX_WAIT: if(sfx_vout) begin
                    for(int i=0;i<SIZE;i++) begin
                        automatic int s=seq_idx*SIZE+i;
                        if(s<hist_len) probs[head_idx][s]<=sfx_probs[i];
                    end
                    if(seq_idx*SIZE+SIZE>=hist_len) begin
                        if(head_idx==Q_HEADS-1) begin
                            head_idx<=0; seq_idx<=0; state<=AV_COMPUTE;
                        end else begin head_idx<=head_idx+1; seq_idx<=0; state<=SOFTMAX_IN; end
                    end else begin seq_idx<=seq_idx+1; state<=SOFTMAX_IN; end
                end
                AV_COMPUTE: begin
                    sa_vin<=1;
                    for(int i=0;i<SIZE;i++) begin
                        automatic int s=seq_idx+i;
                        sa_top[i]<=(s<hist_len)?$signed({1'b0,probs[head_idx][s]}):8'sh0;
                        sa_left[i]<=v_hist[seq_idx+i/SIZE]
                                           [kv_head_of(head_idx)*HEAD_DIM+cyc_cnt];
                    end
                    if(cyc_cnt==SIZE-1) begin
                        cyc_cnt<=0;
                        if(seq_idx+SIZE>=hist_len) begin
                            if(head_idx==Q_HEADS-1) begin
                                head_idx<=0; tile_n<=0; tile_k<=0; cyc_cnt<=0;
                                state<=OUTPROJ;
                            end else begin head_idx<=head_idx+1; seq_idx<=0; end
                        end else seq_idx<=seq_idx+SIZE;
                    end else cyc_cnt<=cyc_cnt+1;
                    if(sa_vout)
                        for(int i=0;i<SIZE;i++)
                            context[head_idx*HEAD_DIM+cyc_cnt*SIZE+i] <=
                                (cyc_cnt==0)?sa_bot[i]:context[head_idx*HEAD_DIM+cyc_cnt*SIZE+i]+sa_bot[i];
                end
                OUTPROJ: begin
                    sa_vin<=1;
                    for(int i=0;i<SIZE;i++)
                        sa_top[i]<=context[tile_k*SIZE+cyc_cnt][DATA_W-1:0];
                    wo_addr<=(tile_k*SIZE+cyc_cnt)*HIDDEN+tile_n*SIZE;
                    sa_left[0]<=wo_rdata;
                    if(cyc_cnt==SIZE-1) begin
                        cyc_cnt<=0;
                        if(tile_k==HIDDEN/SIZE-1) begin
                            tile_k<=0;
                            if(tile_n==HIDDEN/SIZE-1) state<=RESIDUAL;
                            else tile_n<=tile_n+1;
                        end else tile_k<=tile_k+1;
                    end else cyc_cnt<=cyc_cnt+1;
                    if(sa_vout)
                        for(int i=0;i<SIZE;i++)
                            out_acc[tile_n*SIZE+i]<=out_acc[tile_n*SIZE+i]+sa_bot[i];
                end
                RESIDUAL: begin
                    for(int i=0;i<HIDDEN;i++)
                        attn_out[i]<=(out_acc[i]>127)?8'sd127:
                                     (out_acc[i]<-128)?-8'sd128:out_acc[i][DATA_W-1:0];
                    out_valid<=1; state<=DONE_ST;
                end
                DONE_ST: begin done<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
