#
# user core constraints — Zaxxon Pocket core
#
# All clock domains are asynchronous to each other.
# ic = core_top instance in apf_top; mp1 = PLL instance in core_top.
# PLL outputs: [0]=clk_24, [1]=clk_sdram(72), [2]=clk_vid(6), [3]=clk_vid_90(6).

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mclk_r }
