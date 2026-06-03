// mf_pllbase.v - PLL wrapper for Zaxxon (Sega) Pocket core
// 74.25 MHz in -> 24 MHz (zaxxon clock_24) + 72 MHz (SDRAM, proven)
//               + 6 MHz (clk_vid, pixel) + 6 MHz 90deg (clk_vid_90)
`timescale 1 ps / 1 ps
module mf_pllbase (
    input  wire  refclk,
    input  wire  rst,
    output wire  outclk_0,  // 24.000 MHz - zaxxon.clock_24
    output wire  outclk_1,  // 72.000 MHz - agg23 SDRAM controller
    output wire  outclk_2,  // 6.000 MHz  - pixel clock (pix_ena rate)
    output wire  outclk_3,  // 6.000 MHz 90 deg - APF DDR pixel clock
    output wire  locked
);

mf_pllbase_0002 mf_pllbase_inst (
    .refclk   (refclk),
    .rst      (rst),
    .outclk_0 (outclk_0),
    .outclk_1 (outclk_1),
    .outclk_2 (outclk_2),
    .outclk_3 (outclk_3),
    .locked   (locked)
);

endmodule
