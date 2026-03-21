// =============================================================================
// ffn.sv — Feed-Forward Network (SwiGLU variant)
// =============================================================================
// SwiGLU structure:
//   gate   = SiLU(FC1(x))     = SiLU(W1 * x_norm)
//   up     = FC2(x)           = W2 * x_norm
//   hidden = gate ⊙ up        (element-wise, INT8*INT8>>7)
//   out    = FC3(hidden)      = W3 * hidden
//
// Systolic array time-multiplexed: FC1 → FC2 → FC3 (sequential, 1 instance).
// Sequential processing justified: decode batch=1, no data parallelism.
// GEMM tile counts (full size):
//   FC1/FC2: tiles_K=112, tiles_N=608 → 68,096 tiles → 544,775 cycles each
//   FC3:     tiles_K=608, tiles_N=112 → 68,096 tiles → 544,775 cycles
//   SiLU+gate: 9,728 cycles (4864 elements × 2 cycles)
//   Total: ~1,639,189 cycles = 8.2 ms @ 200 MHz (FFN = 87.7% of layer MACs)
//
// hidden[4864] stored in on-chip FF registers (4.75 KB) to avoid SRAM
// read-back overhead of 9,728 cycles.
// =============================================================================
`timescale 1ns/1ps

module ffn #(
    parameter IN_DIM  = 896,
    parameter FFN_DIM = 4864,
    parameter DATA_W  = 8,
    parameter ACC_W   = 32,
    parameter SIZE    = 8,
    parameter TILES_K_FC1 = IN_DIM  / SIZE,
    parameter TILES_N_FC1 = FFN_DIM / SIZE,
    parameter TILES_K_FC3 = FFN_DIM / SIZE,
    parameter TILES_N_FC3 = IN_DIM  / SIZE
)(
    input  logic                          clk, rst_n,
    input  logic                          start,
    output logic                          done,
    output logic [$clog2(IN_DIM)-1:0]    act_addr,
    input  logic signed [DATA_W-1:0]     act_rdata,
    output logic [22:0]                   wgt_addr,
    input  logic signed [DATA_W-1:0]     wgt_rdata,
    output logic signed [DATA_W-1:0]     ffn_out [0:IN_DIM-1],
    output logic                          out_valid
);
    localparam W1_BASE = 23'd0;
    localparam W2_BASE = 23'(IN_DIM * FFN_DIM);
    localparam W3_BASE = 23'(IN_DIM * FFN_DIM * 2);

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

    // SiLU LUT
    logic [7:0]                  silu_addr;
    logic signed [DATA_W-1:0]   silu_data;
    logic silu_vin, silu_vout;

    silu_lut u_silu (.clk(clk),.rst_n(rst_n),
        .addr(silu_addr),.valid_in(silu_vin),
        .data(silu_data),.valid_out(silu_vout));

    // Intermediate buffers
    logic signed [DATA_W-1:0] gate_buf [0:FFN_DIM-1];
    logic signed [DATA_W-1:0] up_buf   [0:FFN_DIM-1];
    logic signed [DATA_W-1:0] hidden   [0:FFN_DIM-1];
    logic signed [ACC_W-1:0]  acc_fc3  [0:IN_DIM-1];

    typedef enum logic [2:0] {
        IDLE, FC1_COMP, FC2_COMP, SILU_GATE, FC3_COMP, OUTPUT_ST, DONE_ST
    } state_t;
    state_t state;

    typedef enum logic [1:0] { SUB_LOAD, SUB_COMPUTE, SUB_ACCUM } sub_t;
    sub_t sub_state;

    logic [9:0]  tile_n, tile_k;
    logic [5:0]  load_cnt;
    logic [2:0]  cyc_cnt;
    logic [12:0] silu_idx;
    logic signed [DATA_W-1:0] wgt_tile [0:SIZE-1][0:SIZE-1];

    function automatic [22:0] wbase(input state_t s);
        case(s)
            FC1_COMP: return W1_BASE;
            FC2_COMP: return W2_BASE;
            default:  return W3_BASE;
        endcase
    endfunction
    function automatic [9:0] tiles_k_max(input state_t s);
        return (s==FC3_COMP) ? 10'(TILES_K_FC3-1) : 10'(TILES_K_FC1-1);
    endfunction
    function automatic [9:0] tiles_n_max(input state_t s);
        return (s==FC3_COMP) ? 10'(TILES_N_FC3-1) : 10'(TILES_N_FC1-1);
    endfunction
    function automatic [9:0] ndim(input state_t s);
        return (s==FC3_COMP) ? 10'(IN_DIM) : 10'(FFN_DIM);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; sub_state<=SUB_LOAD; done<=0; out_valid<=0;
            sa_vin<=0; silu_vin<=0;
            tile_n<=0; tile_k<=0; load_cnt<=0; cyc_cnt<=0; silu_idx<=0;
        end else begin
            done<=0; out_valid<=0; sa_vin<=0; silu_vin<=0;
            case(state)
                IDLE: if(start) begin
                    tile_n<=0; tile_k<=0; load_cnt<=0; cyc_cnt<=0;
                    sub_state<=SUB_LOAD; state<=FC1_COMP;
                    for(int i=0;i<IN_DIM;i++) acc_fc3[i]<='0;
                end
                FC1_COMP, FC2_COMP, FC3_COMP: begin
                    case(sub_state)
                        SUB_LOAD: begin
                            wgt_addr <= wbase(state)
                                      + 23'(tile_k*SIZE+load_cnt[5:3]) * ndim(state)
                                      + 23'(tile_n*SIZE+load_cnt[2:0]);
                            if(load_cnt>0) wgt_tile[(load_cnt-1)[5:3]][(load_cnt-1)[2:0]]<=wgt_rdata;
                            if(load_cnt==63) begin
                                wgt_tile[7][7]<=wgt_rdata; load_cnt<=0; cyc_cnt<=0;
                                sub_state<=SUB_COMPUTE;
                            end else load_cnt<=load_cnt+1;
                        end
                        SUB_COMPUTE: begin
                            sa_vin<=1;
                            if(state==FC3_COMP)
                                for(int i=0;i<SIZE;i++) sa_top[i]<=hidden[tile_k*SIZE+cyc_cnt];
                            else begin
                                act_addr<=$clog2(IN_DIM)'(tile_k*SIZE+cyc_cnt);
                                for(int i=0;i<SIZE;i++) sa_top[i]<=act_rdata;
                            end
                            for(int i=0;i<SIZE;i++) sa_left[i]<=wgt_tile[cyc_cnt][i];
                            if(cyc_cnt==SIZE-1) begin cyc_cnt<=0; sub_state<=SUB_ACCUM; end
                            else cyc_cnt<=cyc_cnt+1;
                        end
                        SUB_ACCUM: if(sa_vout) begin
                            for(int i=0;i<SIZE;i++) begin
                                automatic int idx=tile_n*SIZE+i;
                                automatic logic signed [ACC_W-1:0] v=(tile_k==0)?sa_bot[i]:
                                    ((state==FC3_COMP)?acc_fc3[idx]:sa_bot[i])+sa_bot[i];
                                automatic logic signed [DATA_W-1:0] c=
                                    (v>127)?8'sd127:(v<-128)?-8'sd128:v[DATA_W-1:0];
                                if(tile_k==tiles_k_max(state)) begin
                                    if(state==FC1_COMP) gate_buf[idx]<=c;
                                    else if(state==FC2_COMP) up_buf[idx]<=c;
                                    else acc_fc3[idx]<=(tile_k==0)?sa_bot[i]:acc_fc3[idx]+sa_bot[i];
                                end else begin
                                    if(state==FC3_COMP) acc_fc3[idx]<=(tile_k==0)?sa_bot[i]:acc_fc3[idx]+sa_bot[i];
                                end
                            end
                            if(tile_k==tiles_k_max(state)) begin
                                tile_k<=0;
                                if(tile_n==tiles_n_max(state)) begin
                                    tile_n<=0; load_cnt<=0; sub_state<=SUB_LOAD;
                                    case(state)
                                        FC1_COMP: state<=FC2_COMP;
                                        FC2_COMP: begin silu_idx<=0; state<=SILU_GATE; end
                                        FC3_COMP: state<=OUTPUT_ST;
                                        default: state<=IDLE;
                                    endcase
                                end else begin tile_n<=tile_n+1; load_cnt<=0; sub_state<=SUB_LOAD; end
                            end else begin tile_k<=tile_k+1; load_cnt<=0; sub_state<=SUB_LOAD; end
                        end
                    endcase
                end
                SILU_GATE: begin
                    silu_vin<=1;
                    silu_addr<=8'(gate_buf[silu_idx]+128);
                    if(silu_vout && silu_idx>0) begin
                        automatic int idx=silu_idx-1;
                        automatic logic signed [15:0] prod=
                            $signed(silu_data)*$signed(up_buf[idx]);
                        hidden[idx]<=(prod[15:7]>127)?8'sd127:
                                     (prod[15:7]<-128)?-8'sd128:prod[14:7];
                    end
                    if(silu_idx==FFN_DIM) begin
                        if(silu_vout) begin
                            automatic logic signed [15:0] lp=
                                $signed(silu_data)*$signed(up_buf[FFN_DIM-1]);
                            hidden[FFN_DIM-1]<=lp>>>7;
                        end
                        tile_n<=0; tile_k<=0; load_cnt<=0; sub_state<=SUB_LOAD;
                        state<=FC3_COMP;
                    end else silu_idx<=silu_idx+1;
                end
                OUTPUT_ST: begin
                    for(int i=0;i<IN_DIM;i++)
                        ffn_out[i]<=(acc_fc3[i]>127)?8'sd127:
                                    (acc_fc3[i]<-128)?-8'sd128:acc_fc3[i][DATA_W-1:0];
                    out_valid<=1; state<=DONE_ST;
                end
                DONE_ST: begin done<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end

    // act_addr driven by COMPUTE states; tie-off otherwise
    always_comb begin
        if(state==FC1_COMP || state==FC2_COMP)
            act_addr = $clog2(IN_DIM)'(tile_k*SIZE+cyc_cnt);
        else
            act_addr = '0;
    end
endmodule
