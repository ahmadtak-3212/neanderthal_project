interface Litedram;
    (* always_ready, prefix = "" *)
    method Bit#(1) pll_locked();
    (* prefix = "" *)
    interface Dram ddr_pins;
    
    (* always_ready, prefix = "" *)
    method Bit#(1) init_done;
    (* always_ready, prefix = "" *)
    method Bit#(1) init_error;

    method Action user_command(Bit#(23) addr, Bit#(1) we);
    method Action write(Bit#(128) data, Bit#(16) we);
    method ActionValue#(Bit#(128)) read();

    interface Clock user_clk;
    interface Reset user_rst; 

    (* always_ready, prefix = "" *)
    /* (* always_ready, always_enabled, prefix = "" *) */
    method Action wb_ctrl_adr(Bit#(30) i);
    (* always_ready, prefix = "" *)
    /* (* always_ready, always_enabled, prefix = "" *) */
    method Action wb_ctrl_dat_w(Bit#(32) i);
    (* always_ready, prefix = "" *)
    method Bit#(32) wb_ctrl_dat_r;
    /* (* always_ready, always_enabled, prefix = "" *) */
    (* always_ready, prefix = "" *)
    method Action wb_ctrl_sel(Bit#(4) i);
    (* always_ready, prefix = "" *)
    method Action wb_ctrl_cyc;
    (* always_ready, prefix = "" *)
    method Action wb_ctrl_stb;
    (* always_ready, prefix = "" *)
    method Bit#(1) wb_ctrl_ack;
    /* (* always_ready, always_enabled, prefix = "" *) */
    (* always_ready, prefix = "" *)
    method Action wb_ctrl_we();
    /* (* always_ready, always_enabled, prefix = "" *) */
    (* always_ready, prefix = "" *)
    method Action wb_ctrl_cti(Bit#(3) i);
    /* (* always_ready, always_enabled, prefix = "" *) */
    (* always_ready,  prefix = "" *)
    method Action wb_ctrl_bte(Bit#(2) i);
    (* always_ready, prefix = "" *)
    method Bit#(1) wb_ctrl_err;
endinterface

import "BVI" litedram =
module mkLitedram(Clock clk, Reset rst, Litedram ifc);
    default_clock clk(clk);
    default_reset rst(rst);
    interface Dram ddr_pins;
        method ddram_a ddram_a;
        method ddram_ba  ddram_ba;
        method ddram_ras_n  ddram_ras_n;
        method ddram_cas_n  ddram_cas_n;
        method ddram_we_n  ddram_we_n;
        method ddram_cs_n  ddram_cs_n;
        method ddram_dm  ddram_dm;
        method ddram_dq(ddram_dq) enable ((* inhigh *)  EN_ddram_dq);
        method ddram_dqs_p(ddram_dqs_p) enable ((* inhigh *)  EN_ddram_dqs_p);
        method ddram_dqs_n(ddram_dqs_n) enable ((* inhigh *)  EN_ddram_dqs_n);
        method ddram_clk_p ddram_clk_p;
        method ddram_clk_n(ddram_clk_n)enable ((* inhigh *)  EN_ddram_clk_n);
        method ddram_cke(ddram_cke) enable ((* inhigh *)  EN_ddram_cke);
        method ddram_odt(ddram_odt) enable ((* inhigh *)  EN_ddram_odt);
        method ddram_reset_n(ddram_reset_n) enable ((* inhigh *)  EN_ddram_reset_n);
    endinterface

    output_clock user_clk(user_clk);
    output_reset user_rst(user_rst);


    method init_done init_done;
    method init_error init_error;

    method user_command(user_port_native_0_cmd_addr, user_port_native_0_cmd_we) enable (user_port_native_0_cmd_valid) ready(user_port_native_0_cmd_ready);
    method write(user_port_native_0_wdata_data, user_port_native_0_wdata_we) enable (user_port_native_0_wdata_valid) ready (user_port_native_0_wdata_ready);
    method user_port_native_0_rdata_data read() enable (user_port_native_0_rdata_ready)  ready (user_port_native_0_rdata_valid);


    method pll_locked pll_locked();
    method wb_ctrl_adr(wb_ctrl_adr) enable ((*inhigh *) EN_1);
    method wb_ctrl_dat_w(wb_ctrl_dat_w) enable ((*inhigh *) EN_2);
    method wb_ctrl_dat_r wb_ctrl_dat_r;
    method wb_ctrl_sel(wb_ctrl_sel) enable ((*inhigh *) EN_3);
    method wb_ctrl_cyc() enable (wb_ctrl_cyc);
    method wb_ctrl_stb() enable (wb_ctrl_stb);
    method wb_ctrl_ack wb_ctrl_ack;
    method wb_ctrl_we() enable (wb_ctrl_we);
    method wb_ctrl_cti(wb_ctrl_cti) enable ((*inhigh *) EN_7);
    method wb_ctrl_bte(wb_ctrl_bte) enable ((*inhigh *) EN_8);
    method wb_ctrl_err wb_ctrl_err;
    schedule (ddr_pins_ddram_a, ddr_pins_ddram_ba, ddr_pins_ddram_ras_n, ddr_pins_ddram_cas_n, ddr_pins_ddram_we_n, ddr_pins_ddram_cs_n, ddr_pins_ddram_dm, ddr_pins_ddram_clk_p, init_done, init_error, pll_locked, wb_ctrl_dat_r, wb_ctrl_ack, wb_ctrl_err, ddr_pins_ddram_dq, ddr_pins_ddram_dqs_p, ddr_pins_ddram_dqs_n, ddr_pins_ddram_clk_n, ddr_pins_ddram_cke, ddr_pins_ddram_odt, ddr_pins_ddram_reset_n, user_command, write, read, wb_ctrl_adr, wb_ctrl_dat_w, wb_ctrl_sel, wb_ctrl_cyc, wb_ctrl_stb, wb_ctrl_we, wb_ctrl_cti, wb_ctrl_bte )
        CF 
            (ddr_pins_ddram_a, ddr_pins_ddram_ba, ddr_pins_ddram_ras_n, ddr_pins_ddram_cas_n, ddr_pins_ddram_we_n, ddr_pins_ddram_cs_n, ddr_pins_ddram_dm, ddr_pins_ddram_clk_p, init_done, init_error, pll_locked, wb_ctrl_dat_r, wb_ctrl_ack, wb_ctrl_err, ddr_pins_ddram_dq, ddr_pins_ddram_dqs_p, ddr_pins_ddram_dqs_n, ddr_pins_ddram_clk_n, ddr_pins_ddram_cke, ddr_pins_ddram_odt, ddr_pins_ddram_reset_n, user_command, write, read, wb_ctrl_adr, wb_ctrl_dat_w, wb_ctrl_sel, wb_ctrl_cyc, wb_ctrl_stb, wb_ctrl_we, wb_ctrl_cti, wb_ctrl_bte);

endmodule
