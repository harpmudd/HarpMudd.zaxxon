// =============================================================================
// core_top.v - Zaxxon (Sega, 1982) for Analogue Pocket
//
// Z80 isometric shooter. zaxxon.vhd is self-contained: it takes dl_addr[17:0]/
// dl_data/dl_wr and loads every ROM region into internal dpram (Sega-encrypted
// CPU + char/bg/sprite/map/palette). core_top forwards the loader bus.
//
// Zaxxon's sound is DIGITIZED SAMPLES (no PSG). zaxxon.vhd reads them via
// wave_addr/wave_rd/wave_data. The ~782 KB sample WAV blob is too big for BRAM,
// so it lives in the Pocket SDRAM (agg23 controller, proven 2026-06-02). It is
// loaded via a 2nd APF data slot, written into SDRAM, and read back during play.
//
//   Clocks: 24 MHz (zaxxon), 72 MHz (SDRAM), 6 MHz pixel (+90deg).
//   Game ROM (slot @ bridge 0x0xxxxxxx) -> BRAM via dl_addr (clk_24 loader).
//   Samples  (slot @ bridge 0x1xxxxxxx) -> SDRAM (clk_sdram loader -> p0 write).
//   Play: zaxxon wave_addr/wave_rd (24M) --CDC--> SDRAM read -> wave_data.
// =============================================================================

`default_nettype none

module core_top (

input  wire        clk_74a,
input  wire        clk_74b,

inout  wire [7:0]  cart_tran_bank2,    output wire cart_tran_bank2_dir,
inout  wire [7:0]  cart_tran_bank3,    output wire cart_tran_bank3_dir,
inout  wire [7:0]  cart_tran_bank1,    output wire cart_tran_bank1_dir,
inout  wire [7:4]  cart_tran_bank0,    output wire cart_tran_bank0_dir,
inout  wire        cart_tran_pin30,    output wire cart_tran_pin30_dir,
output wire        cart_pin30_pwroff_reset,
inout  wire        cart_tran_pin31,    output wire cart_tran_pin31_dir,

input  wire        port_ir_rx,
output wire        port_ir_tx,
output wire        port_ir_rx_disable,

inout  wire        port_tran_si,       output wire port_tran_si_dir,
inout  wire        port_tran_so,       output wire port_tran_so_dir,
inout  wire        port_tran_sck,      output wire port_tran_sck_dir,
inout  wire        port_tran_sd,       output wire port_tran_sd_dir,

output wire [21:16] cram0_a,    inout  wire [15:0] cram0_dq,
input  wire          cram0_wait, output wire        cram0_clk,
output wire          cram0_adv_n, output wire       cram0_cre,
output wire          cram0_ce0_n, output wire       cram0_ce1_n,
output wire          cram0_oe_n,  output wire       cram0_we_n,
output wire          cram0_ub_n,  output wire       cram0_lb_n,

output wire [21:16] cram1_a,    inout  wire [15:0] cram1_dq,
input  wire          cram1_wait, output wire        cram1_clk,
output wire          cram1_adv_n, output wire       cram1_cre,
output wire          cram1_ce0_n, output wire       cram1_ce1_n,
output wire          cram1_oe_n,  output wire       cram1_we_n,
output wire          cram1_ub_n,  output wire       cram1_lb_n,

// SDRAM — DRIVEN (samples store)
output wire [12:0] dram_a,    output wire [1:0]  dram_ba,
inout  wire [15:0] dram_dq,   output wire [1:0]  dram_dqm,
output wire        dram_clk,  output wire        dram_cke,
output wire        dram_ras_n, output wire       dram_cas_n,
output wire        dram_we_n,

output wire [16:0] sram_a,    inout  wire [15:0] sram_dq,
output wire        sram_oe_n, output wire        sram_we_n,
output wire        sram_ub_n, output wire        sram_lb_n,

input  wire        vblank,
output wire        vpll_feed,
output wire        dbg_tx,
input  wire        dbg_rx,
output wire        user1,
input  wire        user2,
inout  wire        aux_sda,
output wire        aux_scl,

output wire [23:0] video_rgb,
output wire        video_rgb_clock,
output wire        video_rgb_clock_90,
output wire        video_de,
output wire        video_skip,
output wire        video_vs,
output wire        video_hs,

output wire        audio_mclk,
input  wire        audio_adc,
output wire        audio_dac,
output wire        audio_lrck,

output wire        bridge_endian_little,
input  wire [31:0] bridge_addr,
input  wire        bridge_rd,
output reg  [31:0] bridge_rd_data,
input  wire        bridge_wr,
input  wire [31:0] bridge_wr_data,

input  wire [31:0] cont1_key,
input  wire [31:0] cont2_key,
input  wire [31:0] cont3_key,
input  wire [31:0] cont4_key,
input  wire [31:0] cont1_joy,
input  wire [31:0] cont2_joy,
input  wire [31:0] cont3_joy,
input  wire [31:0] cont4_joy,
input  wire [15:0] cont1_trig,
input  wire [15:0] cont2_trig,
input  wire [15:0] cont3_trig,
input  wire [15:0] cont4_trig

);

// -- Tie off unused physical ports (NOT dram_*) ------------------------------
assign port_ir_tx              = 1'b0;
assign port_ir_rx_disable      = 1'b1;

assign cart_tran_bank3         = 8'hZZ;   assign cart_tran_bank3_dir     = 1'b0;
assign cart_tran_bank2         = 8'hZZ;   assign cart_tran_bank2_dir     = 1'b0;
assign cart_tran_bank1         = 8'hZZ;   assign cart_tran_bank1_dir     = 1'b0;
assign cart_tran_bank0         = 4'hF;    assign cart_tran_bank0_dir     = 1'b1;
assign cart_tran_pin30         = 1'b0;    assign cart_tran_pin30_dir     = 1'bZ;
assign cart_pin30_pwroff_reset = 1'b0;
assign cart_tran_pin31         = 1'bZ;    assign cart_tran_pin31_dir     = 1'b0;

assign port_tran_so            = 1'bZ;    assign port_tran_so_dir        = 1'b0;
assign port_tran_si            = 1'bZ;    assign port_tran_si_dir        = 1'b0;
assign port_tran_sck           = 1'bZ;    assign port_tran_sck_dir       = 1'b0;
assign port_tran_sd            = 1'bZ;    assign port_tran_sd_dir        = 1'b0;

assign cram0_a = 6'h0;  assign cram0_dq = 16'hZZZZ; assign cram0_clk = 1'b0;
assign cram0_adv_n = 1'b1; assign cram0_cre = 1'b0;
assign cram0_ce0_n = 1'b1; assign cram0_ce1_n = 1'b1;
assign cram0_oe_n = 1'b1; assign cram0_we_n = 1'b1;
assign cram0_ub_n = 1'b1; assign cram0_lb_n = 1'b1;

assign cram1_a = 6'h0;  assign cram1_dq = 16'hZZZZ; assign cram1_clk = 1'b0;
assign cram1_adv_n = 1'b1; assign cram1_cre = 1'b0;
assign cram1_ce0_n = 1'b1; assign cram1_ce1_n = 1'b1;
assign cram1_oe_n = 1'b1; assign cram1_we_n = 1'b1;
assign cram1_ub_n = 1'b1; assign cram1_lb_n = 1'b1;

assign sram_a = 17'h0; assign sram_dq = 16'hZZZZ;
assign sram_oe_n = 1'b1; assign sram_we_n = 1'b1;
assign sram_ub_n = 1'b1; assign sram_lb_n = 1'b1;

assign vpll_feed = 1'bZ;
assign dbg_tx    = 1'bZ;
assign user1     = 1'bZ;
assign aux_scl   = 1'bZ;

assign bridge_endian_little = 1'b0;

// -- PLL ---------------------------------------------------------------------
wire clk_24;       // zaxxon clock_24
wire clk_sdram;    // 72 MHz SDRAM
wire clk_vid;      // 6 MHz pixel
wire clk_vid_90;
wire pll_locked;
wire pll_locked_s;

mf_pllbase mp1 (
    .refclk (clk_74a), .rst (1'b0),
    .outclk_0 (clk_24), .outclk_1 (clk_sdram),
    .outclk_2 (clk_vid), .outclk_3 (clk_vid_90),
    .locked (pll_locked)
);

synch_3 s_pll (pll_locked, pll_locked_s, clk_74a);

// -- APF bridge command handler ----------------------------------------------
wire        reset_n;
wire [31:0] cmd_bridge_rd_data;

wire        status_boot_done  = pll_locked_s;
wire        status_setup_done = rom_loaded_s;
wire        status_running    = 1'b1;

wire        dataslot_requestread;
wire [15:0] dataslot_requestread_id;
wire        dataslot_requestread_ack  = 1'b1;
wire        dataslot_requestread_ok   = 1'b1;
wire        dataslot_requestwrite;
wire [15:0] dataslot_requestwrite_id;
wire [31:0] dataslot_requestwrite_size;
wire        dataslot_requestwrite_ack = 1'b1;
wire        dataslot_requestwrite_ok  = 1'b1;
wire        dataslot_update;
wire [15:0] dataslot_update_id;
wire [31:0] dataslot_update_size;
wire        dataslot_allcomplete;
wire [31:0] rtc_epoch_seconds, rtc_date_bcd, rtc_time_bcd;
wire        rtc_valid;
wire        savestate_supported   = 1'b0;
wire [31:0] savestate_addr=0, savestate_size=0, savestate_maxloadsize=0;
wire        savestate_start;
wire        savestate_start_ack=0, savestate_start_busy=0, savestate_start_ok=0, savestate_start_err=0;
wire        savestate_load;
wire        savestate_load_ack=0, savestate_load_busy=0, savestate_load_ok=0, savestate_load_err=0;
wire        osnotify_inmenu;
reg         target_dataslot_read=0, target_dataslot_write=0, target_dataslot_getfile=0, target_dataslot_openfile=0;
wire        target_dataslot_ack, target_dataslot_done;
wire [2:0]  target_dataslot_err;
reg  [15:0] target_dataslot_id=0;
reg  [31:0] target_dataslot_slotoffset=0, target_dataslot_bridgeaddr=0, target_dataslot_length=0;
wire [31:0] target_buffer_param_struct, target_buffer_resp_struct;
wire [9:0]  datatable_addr;
wire        datatable_wren;
wire [31:0] datatable_data, datatable_q;

core_bridge_cmd icb (
    .clk(clk_74a), .reset_n(reset_n), .bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr), .bridge_rd(bridge_rd), .bridge_rd_data(cmd_bridge_rd_data),
    .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
    .status_boot_done(status_boot_done), .status_setup_done(status_setup_done), .status_running(status_running),
    .dataslot_requestread(dataslot_requestread), .dataslot_requestread_id(dataslot_requestread_id),
    .dataslot_requestread_ack(dataslot_requestread_ack), .dataslot_requestread_ok(dataslot_requestread_ok),
    .dataslot_requestwrite(dataslot_requestwrite), .dataslot_requestwrite_id(dataslot_requestwrite_id),
    .dataslot_requestwrite_size(dataslot_requestwrite_size), .dataslot_requestwrite_ack(dataslot_requestwrite_ack),
    .dataslot_requestwrite_ok(dataslot_requestwrite_ok),
    .dataslot_update(dataslot_update), .dataslot_update_id(dataslot_update_id), .dataslot_update_size(dataslot_update_size),
    .dataslot_allcomplete(dataslot_allcomplete),
    .rtc_epoch_seconds(rtc_epoch_seconds), .rtc_date_bcd(rtc_date_bcd), .rtc_time_bcd(rtc_time_bcd), .rtc_valid(rtc_valid),
    .savestate_supported(savestate_supported), .savestate_addr(savestate_addr), .savestate_size(savestate_size),
    .savestate_maxloadsize(savestate_maxloadsize), .savestate_start(savestate_start), .savestate_start_ack(savestate_start_ack),
    .savestate_start_busy(savestate_start_busy), .savestate_start_ok(savestate_start_ok), .savestate_start_err(savestate_start_err),
    .savestate_load(savestate_load), .savestate_load_ack(savestate_load_ack), .savestate_load_busy(savestate_load_busy),
    .savestate_load_ok(savestate_load_ok), .savestate_load_err(savestate_load_err), .osnotify_inmenu(osnotify_inmenu),
    .target_dataslot_read(target_dataslot_read), .target_dataslot_write(target_dataslot_write),
    .target_dataslot_getfile(target_dataslot_getfile), .target_dataslot_openfile(target_dataslot_openfile),
    .target_dataslot_ack(target_dataslot_ack), .target_dataslot_done(target_dataslot_done), .target_dataslot_err(target_dataslot_err),
    .target_dataslot_id(target_dataslot_id), .target_dataslot_slotoffset(target_dataslot_slotoffset),
    .target_dataslot_bridgeaddr(target_dataslot_bridgeaddr), .target_dataslot_length(target_dataslot_length),
    .target_buffer_param_struct(target_buffer_param_struct), .target_buffer_resp_struct(target_buffer_resp_struct),
    .datatable_addr(datatable_addr), .datatable_wren(datatable_wren), .datatable_data(datatable_data), .datatable_q(datatable_q)
);

always @(*) begin
    casex (bridge_addr)
        32'hF8xxxxxx: bridge_rd_data = cmd_bridge_rd_data;
        default:      bridge_rd_data = 32'h0;
    endcase
end

// rom_loaded -> all slots complete. Synced to the clock domains that need it.
reg  rom_loaded_74 = 1'b0;
always @(posedge clk_74a) if (dataslot_allcomplete) rom_loaded_74 <= 1'b1;
wire rom_loaded_s = rom_loaded_74;             // clk_74a (bridge)
wire rom_loaded_24, loaded_sdram;
synch_3 s_ld24 (rom_loaded_74, rom_loaded_24, clk_24);
synch_3 s_ldsd (rom_loaded_74, loaded_sdram,  clk_sdram);

// -- Game ROM loader (clk_24) : bridge 0x0xxxxxxx -> zaxxon dl_addr[17:0] -----
wire [17:0] dn_addr;
wire [7:0]  dn_data;
wire        dn_wr;
data_loader #(.ADDRESS_MASK_UPPER_4(4'h0), .ADDRESS_SIZE(17), .OUTPUT_WORD_SIZE(1)) u_rom_loader (
    .clk_74a(clk_74a), .clk_memory(clk_24),
    .bridge_wr(bridge_wr), .bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr), .bridge_wr_data(bridge_wr_data),
    .write_en(dn_wr), .write_addr(dn_addr), .write_data(dn_data)
);

// -- Samples loader (clk_sdram) : bridge 0x1xxxxxxx -> SDRAM ------------------
wire [19:0] samp_addr;
wire [7:0]  samp_data;
wire        samp_wr;
// WRITE_MEM_CLOCK_DELAY(16): >=16 clk_sdram cycles (222ns @72MHz) between byte
// writes — comfortably longer than one agg23 single-word write, so the samples
// stream can never outrun the SDRAM. Bridge (SPI) delivery is the real limiter.
data_loader #(.ADDRESS_MASK_UPPER_4(4'h1), .ADDRESS_SIZE(19), .OUTPUT_WORD_SIZE(1), .WRITE_MEM_CLOCK_DELAY(16)) u_samp_loader (
    .clk_74a(clk_74a), .clk_memory(clk_sdram),
    .bridge_wr(bridge_wr), .bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr), .bridge_wr_data(bridge_wr_data),
    .write_en(samp_wr), .write_addr(samp_addr), .write_data(samp_data)
);

// -- Reset (active high to zaxxon) -------------------------------------------
wire reset_n_sys;
synch_3 s_resetn (reset_n, reset_n_sys, clk_24);
reg [7:0] reset_ctr = 8'hFF;
wire      game_reset = !((reset_ctr == 8'h0) && rom_loaded_24 && reset_n_sys);
always @(posedge clk_24) begin
    if (!pll_locked)            reset_ctr <= 8'hFF;
    else if (reset_ctr != 8'h0) reset_ctr <= reset_ctr - 1'd1;
end

// -- agg23 SDRAM controller (clk_sdram) --------------------------------------
wire        sdram_init_complete;
reg  [24:0] p0_addr;
reg  [15:0] p0_data;
reg  [1:0]  p0_byte_en;
wire [15:0] p0_q;
reg         p0_wr_req, p0_rd_req;
wire        p0_available, p0_ready;

sdram #(.CLOCK_SPEED_MHZ(72), .BURST_LENGTH(1), .CAS_LATENCY(2)) u_sdram (
    .clk(clk_sdram), .reset(~pll_locked), .init_complete(sdram_init_complete),
    .p0_addr(p0_addr), .p0_data(p0_data), .p0_byte_en(p0_byte_en), .p0_q(p0_q),
    .p0_wr_req(p0_wr_req), .p0_rd_req(p0_rd_req),
    .p0_available(p0_available), .p0_ready(p0_ready),
    .SDRAM_DQ(dram_dq), .SDRAM_A(dram_a), .SDRAM_DQM(dram_dqm), .SDRAM_BA(dram_ba),
    .SDRAM_nCS(), .SDRAM_nWE(dram_we_n), .SDRAM_nRAS(dram_ras_n), .SDRAM_nCAS(dram_cas_n),
    .SDRAM_CKE(dram_cke), .SDRAM_CLK(dram_clk)
);

// -- Wave read CDC: zaxxon (24M) wave_rd/wave_addr -> clk_sdram ---------------
wire [19:0] wave_addr;
wire        wave_rd;
reg  [2:0]  wave_rd_sync;       // wave_rd into clk_sdram
reg  [19:0] wave_addr_sd;
always @(posedge clk_sdram) begin
    wave_rd_sync <= {wave_rd_sync[1:0], wave_rd};
    wave_addr_sd <= wave_addr;   // stable when wave_rd asserted; sampled near the edge
end
wire wave_rd_edge = wave_rd_sync[1] & ~wave_rd_sync[2];

reg [15:0] wave_data_reg;        // latched read result; read by zaxxon (quasi-static)
wire [15:0] wave_data = wave_data_reg;

// -- p0 mux: LOAD = sample writes, PLAY = wave reads -------------------------
reg        samp_pending = 0;
reg [19:0] samp_addr_l;
reg [7:0]  samp_data_l;
reg        rd_busy = 0;
always @(posedge clk_sdram) begin
    p0_wr_req <= 1'b0;
    p0_rd_req <= 1'b0;

    if (samp_wr) begin samp_pending <= 1'b1; samp_addr_l <= samp_addr; samp_data_l <= samp_data; end

    if (!loaded_sdram) begin
        // LOAD: drain one pending byte write into SDRAM (writes are sparse)
        if (samp_pending && p0_available && sdram_init_complete) begin
            p0_addr    <= {6'd0, samp_addr_l[19:1]};
            p0_byte_en <= samp_addr_l[0] ? 2'b10 : 2'b01;
            p0_data    <= {samp_data_l, samp_data_l};
            p0_wr_req  <= 1'b1;
            samp_pending <= 1'b0;
        end
    end else begin
        // PLAY: issue a 16-bit read on each wave_rd edge, latch the result
        if (!rd_busy) begin
            if (wave_rd_edge && p0_available) begin
                p0_addr   <= {6'd0, wave_addr_sd[19:1]};
                p0_rd_req <= 1'b1;
                rd_busy   <= 1'b1;
            end
        end else if (p0_ready) begin
            wave_data_reg <= p0_q;
            rd_busy       <= 1'b0;
        end
    end
end

// -- Controller mapping (Zaxxon: 4-way + fire; coin/start) -------------------
wire m_coin1  = cont1_key[14];
wire m_start1 = cont1_key[15];
wire m_start2 = cont2_key[15];
// Zaxxon/Super Zaxxon = aircraft-style altitude control: push UP on the stick to
// DIVE, pull DOWN to CLIMB. Invert the d-pad Y axis so the Pocket matches the
// arcade. Future Spy is a straight vertical shooter -> normal (non-inverted) Y
// (mirrors MiSTer's mod_futurespy up/down swap).
wire m_up     = mod_futurespy ? cont1_key[0] : cont1_key[1];
wire m_down   = mod_futurespy ? cont1_key[1] : cont1_key[0];
wire m_left   = cont1_key[2];
wire m_right  = cont1_key[3];
wire m_fire_a = cont1_key[4];
wire m_fire_b = cont1_key[5];

wire [7:0] sw1 = 8'h7F;   // .mra DIP default
wire [7:0] sw2 = 8'h33;   // 1c/1cr (hardcoded in MiSTer top)

// -- Zaxxon game core (clk_24) -----------------------------------------------
wire [2:0]  vid_r, vid_g;
wire [1:0]  vid_b;
wire        vid_hs, vid_vs, vid_hblank, vid_vblank, vid_ce;
wire [15:0] audio_l_raw, audio_r_raw;

// -- Variant select -----------------------------------------------------------
// pack_rom stamps a variant byte at ROM image offset 0x24200 (well before the
// padded end so the loader FIFO/rom_loaded race can't drop it):
//   0 = Zaxxon   1 = Super Zaxxon   2 = Future Spy
// Snooped off the load stream (clk_24). It never reaches zaxxon.vhd -- dl_wr below
// is gated to dn_addr < 0x24200 -- and is stable before the CPU runs (game held in
// reset until rom_loaded_24). Super Zaxxon / Future Spy also select the encrypted
// CPU-ROM decode inside zaxxon.vhd via these mod lines.
reg [7:0] variant_zx = 8'd0;
always @(posedge clk_24)
    if (dn_wr && !rom_loaded_24 && dn_addr == 18'h24200)
        variant_zx <= dn_data;
wire mod_superzaxxon = (variant_zx == 8'd1);
wire mod_futurespy   = (variant_zx == 8'd2);

zaxxon zaxxon_core (
    .clock_24      (clk_24),
    .reset         (game_reset),
    .pause         (1'b0),
    .mod_superzaxxon(mod_superzaxxon),
    .mod_futurespy (mod_futurespy),

    .video_r       (vid_r),
    .video_g       (vid_g),
    .video_b       (vid_b),
    .video_clk     (),
    .video_csync   (),
    .video_hblank  (vid_hblank),
    .video_vblank  (vid_vblank),
    .video_hs      (vid_hs),
    .video_vs      (vid_vs),
    .video_ce      (vid_ce),

    .audio_out_l   (audio_l_raw),
    .audio_out_r   (audio_r_raw),

    .coin1 (m_coin1), .coin2 (1'b0), .start1 (m_start1), .start2 (m_start2),
    .left (m_left), .right (m_right), .up (m_up), .down (m_down), .fire1 (m_fire_a), .fire2 (m_fire_b),
    .left_c (m_left), .right_c (m_right), .up_c (m_up), .down_c (m_down), .fire1_c (m_fire_a), .fire2_c (m_fire_b),

    .sw1_input (sw1), .sw2_input (sw2),
    .service (1'b0), .flip_screen (1'b0),

    .dl_addr (dn_addr), .dl_wr (dn_wr && !rom_loaded_24 && dn_addr < 18'h24200), .dl_data (dn_data),

    .wave_addr (wave_addr), .wave_rd (wave_rd), .wave_data (wave_data),

    .hs_address (12'h0), .hs_data_out (), .hs_data_in (8'h0), .hs_write (1'b0)
);

// -- Video output (3-3-2 RGB, sample on clk_vid = pixel rate) -----------------
wire [7:0] rgb_r = {vid_r, vid_r, vid_r[2:1]};
wire [7:0] rgb_g = {vid_g, vid_g, vid_g[2:1]};
wire [7:0] rgb_b = {vid_b, vid_b, vid_b, vid_b};
wire [23:0] rgb_out = (vid_hblank | vid_vblank) ? 24'h0 : {rgb_r, rgb_g, rgb_b};

reg [23:0] vid_rgb_r;
reg        vid_hs_r, vid_vs_r, vid_de_r;
always @(posedge clk_vid) begin
    vid_rgb_r <= rgb_out;
    vid_hs_r  <= vid_hs;
    vid_vs_r  <= vid_vs;
    vid_de_r  <= ~(vid_hblank | vid_vblank);
end
assign video_rgb          = vid_rgb_r;
assign video_rgb_clock    = clk_vid;
assign video_rgb_clock_90 = clk_vid_90;
assign video_de           = vid_de_r;
assign video_skip         = 1'b0;
assign video_vs           = vid_vs_r;
assign video_hs           = vid_hs_r;

// -- Audio (signed 16-bit, samples premixed; box-filter to ~47 kHz) ----------
// clk_24 / 512 = 46.875 kHz. Sum of 512 signed 16-bit fits in 25 bits.
reg  [8:0]  aud_div   = 9'd0;
reg  signed [24:0] aud_acc_l = 0, aud_acc_r = 0;
reg  [15:0] audio_l_s = 0, audio_r_s = 0;
always @(posedge clk_24) begin
    aud_div <= aud_div + 1'd1;
    if (aud_div == 9'd0) begin
        audio_l_s <= aud_acc_l[24:9];
        audio_r_s <= aud_acc_r[24:9];
        aud_acc_l <= $signed(audio_l_raw);
        aud_acc_r <= $signed(audio_r_raw);
    end else begin
        aud_acc_l <= aud_acc_l + $signed(audio_l_raw);
        aud_acc_r <= aud_acc_r + $signed(audio_r_raw);
    end
end

sound_i2s #(.CHANNEL_WIDTH(16), .SIGNED_INPUT(1)) u_sound_i2s (
    .clk_74a(clk_74a), .clk_audio(clk_24),
    .audio_l(audio_l_s), .audio_r(audio_r_s),
    .audio_mclk(audio_mclk), .audio_dac(audio_dac), .audio_lrck(audio_lrck)
);

endmodule
