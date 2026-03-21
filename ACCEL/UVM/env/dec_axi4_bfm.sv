// =============================================================================
// dec_axi4_bfm.sv — AXI4 Slave Bus Functional Model
// =============================================================================
// Simulates a 64KB DRAM for KV Cache verification.
// Handles AXI4 Read (AR/R) and Write (AW/W/B) channels independently.
//
// Key behavior:
//   - Responds to every ARVALID/AWVALID within 2 cycles (zero wait state)
//   - Write data stored to mem[]; read data returned from mem[]
//   - Logs every completed write txn (for KV cache address verification)
//   - Preload function: initializes KV history before decode step starts
//
// AXI4 burst: ARLEN/AWLEN=15 → 16 beats × 8B = 128B per burst.
// =============================================================================
`ifndef DEC_AXI4_BFM_SV
`define DEC_AXI4_BFM_SV
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

class dec_axi4_bfm extends uvm_component;
    `uvm_component_utils(dec_axi4_bfm)

    virtual decoder_if vif;

    // 64 KB DRAM model — address masked to [15:0]
    bit [7:0] mem [0:65535];

    // Transaction logging
    int wr_txn_count;
    int rd_txn_count;

    // Last write address (for KV address checking)
    logic [31:0] last_wr_addr;
    logic [31:0] last_rd_addr;

    function new(string name = "dec_axi4_bfm", uvm_component parent = null);
        super.new(name, parent);
        wr_txn_count = 0;
        rd_txn_count = 0;
        last_wr_addr = 0;
        last_rd_addr = 0;
        // Initialize mem with walking pattern for debug
        foreach (mem[i]) mem[i] = 8'(i & 8'hFF);
    endfunction

    virtual function void build_phase(uvm_component phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual decoder_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "dec_axi4_bfm: no virtual decoder_if found")
    endfunction

    // Preload KV history data at given base address
    function void preload_kv(
        input int       base_addr,
        input bit [7:0] data [],
        input int       len
    );
        for (int i = 0; i < len && i < 65536; i++)
            mem[(base_addr + i) & 16'hFFFF] = data[i];
        `uvm_info("BFM",
            $sformatf("Preloaded %0d bytes at 0x%08h", len, base_addr),
            UVM_HIGH)
    endfunction

    virtual task run_phase(uvm_component phase);
        // Initialize all slave-side signals
        vif.ARREADY <= 0;
        vif.RDATA   <= 0;
        vif.RVALID  <= 0;
        vif.RLAST   <= 0;
        vif.AWREADY <= 0;
        vif.WREADY  <= 0;
        vif.BVALID  <= 0;
        // Both channels run in parallel
        fork
            run_read_channel();
            run_write_channel();
        join_none
    endtask

    // ── AXI4 Read slave ──────────────────────────────────────────────────
    task run_read_channel();
        logic [31:0] rd_addr;
        int          rd_beats;
        int          b;
        logic [63:0] beat_data;

        forever begin
            @(posedge vif.clk);
            if (vif.ARVALID === 1'b1) begin
                rd_addr  = vif.ARADDR;
                rd_beats = vif.ARLEN + 1;
                last_rd_addr = rd_addr;
                // Accept address
                #1;
                vif.ARREADY <= 1;
                @(posedge vif.clk); #1;
                vif.ARREADY <= 0;
                // Supply data beats
                for (b = 0; b < rd_beats; b++) begin
                    beat_data = 0;
                    for (int i = 0; i < 8; i++)
                        beat_data[i*8 +: 8] =
                            mem[(rd_addr + b*8 + i) & 16'hFFFF];
                    vif.RDATA  <= beat_data;
                    vif.RVALID <= 1;
                    vif.RLAST  <= (b == rd_beats - 1);
                    @(posedge vif.clk);
                    // Wait for RREADY
                    while (vif.RREADY !== 1'b1) @(posedge vif.clk);
                    #1;
                end
                vif.RVALID <= 0;
                vif.RLAST  <= 0;
                rd_txn_count++;
                `uvm_info("BFM",
                    $sformatf("READ  txn=%0d addr=0x%08h beats=%0d",
                               rd_txn_count, rd_addr, rd_beats), UVM_HIGH)
            end
        end
    endtask

    // ── AXI4 Write slave ─────────────────────────────────────────────────
    task run_write_channel();
        logic [31:0] wr_addr;
        int          wr_beats;
        int          b;

        forever begin
            @(posedge vif.clk);
            if (vif.AWVALID === 1'b1) begin
                wr_addr  = vif.AWADDR;
                wr_beats = vif.AWLEN + 1;
                last_wr_addr = wr_addr;
                // Accept address
                #1;
                vif.AWREADY <= 1;
                @(posedge vif.clk); #1;
                vif.AWREADY <= 0;
                // Accept data beats
                for (b = 0; b < wr_beats; b++) begin
                    // Wait for WVALID
                    while (vif.WVALID !== 1'b1) @(posedge vif.clk);
                    // Store to mem
                    for (int i = 0; i < 8; i++)
                        mem[(wr_addr + b*8 + i) & 16'hFFFF] =
                            vif.WDATA[i*8 +: 8];
                    #1;
                    vif.WREADY <= 1;
                    @(posedge vif.clk); #1;
                    vif.WREADY <= 0;
                end
                // Write response
                @(posedge vif.clk); #1;
                vif.BVALID <= 1;
                @(posedge vif.clk);
                while (vif.BREADY !== 1'b1) @(posedge vif.clk);
                #1;
                vif.BVALID <= 0;
                wr_txn_count++;
                `uvm_info("BFM",
                    $sformatf("WRITE txn=%0d addr=0x%08h beats=%0d",
                               wr_txn_count, wr_addr, wr_beats), UVM_MEDIUM)
            end
        end
    endtask

    virtual function void report_phase(uvm_component phase);
        `uvm_info("BFM",
            $sformatf("AXI4 BFM: %0d write txns  %0d read txns",
                       wr_txn_count, rd_txn_count), UVM_LOW)
    endfunction

endclass
`endif // DEC_AXI4_BFM_SV
