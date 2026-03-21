// =============================================================================
// rope.sv — Rotary Position Embedding
// =============================================================================
// Applies RoPE rotation to Q and K vectors at decode position pos_m.
// Rotation formula (per head, per pair k):
//   Q'[2k]   =  cos(m*θ_k)*Q[2k]   - sin(m*θ_k)*Q[2k+1]
//   Q'[2k+1] =  sin(m*θ_k)*Q[2k]   + cos(m*θ_k)*Q[2k+1]
//   θ_k = 10000^(-2k/64), k = 0..31
//
// LUT (INT8 Q7): cos_rom and sin_rom, 256×32 = 8 KB each = 16 KB total.
//   16× faster than CORDIC (7,168 vs 448 cycles for 14 Q-heads).
//   Q7 accuracy: ±0.78% = same as INT8 weight quantization.
//
// Scaling: INT8 × INT8 = INT16; ×cos/sin (Q7, ×128) → >>7 removes scale.
// Processing: Q heads (14), then K heads (2), each 32 pairs × 2 cycles.
// Total latency: (14+2) × 32 × 2 = 1,024 cycles.
// =============================================================================
`timescale 1ns/1ps

module rope #(
    parameter Q_HEADS  = 14,
    parameter KV_HEADS = 2,
    parameter HEAD_DIM = 64,
    parameter HALF_D   = 32,
    parameter MAX_SEQ  = 256,
    parameter DATA_W   = 8
)(
    input  logic                          clk, rst_n,
    input  logic                          start,
    output logic                          done,
    input  logic [7:0]                    pos_m,
    input  logic signed [DATA_W-1:0]      q_in  [0:Q_HEADS*HEAD_DIM-1],
    input  logic signed [DATA_W-1:0]      k_in  [0:KV_HEADS*HEAD_DIM-1],
    output logic signed [DATA_W-1:0]      q_out [0:Q_HEADS*HEAD_DIM-1],
    output logic signed [DATA_W-1:0]      k_out [0:KV_HEADS*HEAD_DIM-1],
    // External LUT ports (unused when ROM is internal)
    output logic [12:0]                   cos_addr, sin_addr,
    input  logic signed [DATA_W-1:0]      cos_rdata, sin_rdata
);
    localparam LUT_SZ = MAX_SEQ * HALF_D;

    logic signed [DATA_W-1:0] cos_rom [0:LUT_SZ-1];
    logic signed [DATA_W-1:0] sin_rom [0:LUT_SZ-1];

    initial begin
        $readmemh("rope_cos.hex", cos_rom);
        $readmemh("rope_sin.hex", sin_rom);
    end

    logic signed [DATA_W-1:0] q_buf [0:Q_HEADS*HEAD_DIM-1];
    logic signed [DATA_W-1:0] k_buf [0:KV_HEADS*HEAD_DIM-1];

    typedef enum logic [1:0] { IDLE, ROT_Q, ROT_K, DONE_ST } state_t;
    state_t state;

    logic [3:0] head_idx;
    logic [4:0] pair_k;
    logic        rot_phase;
    logic signed [DATA_W-1:0] cos_r, sin_r, q0r, q1r, k0r, k1r;

    logic [12:0] lut_addr;
    assign lut_addr = pos_m * HALF_D + pair_k;
    assign cos_addr = lut_addr;
    assign sin_addr = lut_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; done<=0; head_idx<=0; pair_k<=0; rot_phase<=0;
        end else begin
            done<=0;
            case(state)
                IDLE: if(start) begin
                    for(int i=0;i<Q_HEADS*HEAD_DIM;i++)  q_buf[i]<=q_in[i];
                    for(int i=0;i<KV_HEADS*HEAD_DIM;i++) k_buf[i]<=k_in[i];
                    head_idx<=0; pair_k<=0; rot_phase<=0; state<=ROT_Q;
                end
                ROT_Q: begin
                    if(!rot_phase) begin
                        q0r<=q_buf[head_idx*HEAD_DIM+pair_k*2];
                        q1r<=q_buf[head_idx*HEAD_DIM+pair_k*2+1];
                        cos_r<=cos_rom[lut_addr]; sin_r<=sin_rom[lut_addr];
                        rot_phase<=1;
                    end else begin
                        automatic logic signed [23:0] nq0=
                            $signed(cos_r)*$signed(q0r)-$signed(sin_r)*$signed(q1r);
                        automatic logic signed [23:0] nq1=
                            $signed(sin_r)*$signed(q0r)+$signed(cos_r)*$signed(q1r);
                        automatic logic signed [15:0] rq0=nq0>>>7, rq1=nq1>>>7;
                        q_buf[head_idx*HEAD_DIM+pair_k*2]   <=(rq0>127)?8'sd127:(rq0<-128)?-8'sd128:rq0[7:0];
                        q_buf[head_idx*HEAD_DIM+pair_k*2+1] <=(rq1>127)?8'sd127:(rq1<-128)?-8'sd128:rq1[7:0];
                        rot_phase<=0;
                        if(pair_k==HALF_D-1) begin
                            pair_k<=0;
                            if(head_idx==Q_HEADS-1) begin head_idx<=0; state<=ROT_K; end
                            else head_idx<=head_idx+1;
                        end else pair_k<=pair_k+1;
                    end
                end
                ROT_K: begin
                    if(!rot_phase) begin
                        k0r<=k_buf[head_idx*HEAD_DIM+pair_k*2];
                        k1r<=k_buf[head_idx*HEAD_DIM+pair_k*2+1];
                        cos_r<=cos_rom[lut_addr]; sin_r<=sin_rom[lut_addr];
                        rot_phase<=1;
                    end else begin
                        automatic logic signed [23:0] nk0=
                            $signed(cos_r)*$signed(k0r)-$signed(sin_r)*$signed(k1r);
                        automatic logic signed [23:0] nk1=
                            $signed(sin_r)*$signed(k0r)+$signed(cos_r)*$signed(k1r);
                        automatic logic signed [15:0] rk0=nk0>>>7, rk1=nk1>>>7;
                        k_buf[head_idx*HEAD_DIM+pair_k*2]   <=(rk0>127)?8'sd127:(rk0<-128)?-8'sd128:rk0[7:0];
                        k_buf[head_idx*HEAD_DIM+pair_k*2+1] <=(rk1>127)?8'sd127:(rk1<-128)?-8'sd128:rk1[7:0];
                        rot_phase<=0;
                        if(pair_k==HALF_D-1) begin
                            pair_k<=0;
                            if(head_idx==KV_HEADS-1) state<=DONE_ST;
                            else head_idx<=head_idx+1;
                        end else pair_k<=pair_k+1;
                    end
                end
                DONE_ST: begin
                    for(int i=0;i<Q_HEADS*HEAD_DIM;i++)  q_out[i]<=q_buf[i];
                    for(int i=0;i<KV_HEADS*HEAD_DIM;i++) k_out[i]<=k_buf[i];
                    done<=1; state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
