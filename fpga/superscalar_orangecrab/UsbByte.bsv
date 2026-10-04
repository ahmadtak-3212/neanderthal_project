interface Usb;
    interface Inout#(Bit#(1)) pin_usb_p;
    interface Inout#(Bit#(1)) pin_usb_n;
    /* interface Inout#(Bit#(1)) usb_pullup; */
endinterface

/* (* always_ready, always_enabled *) */
interface UsbCore;
    interface Inout#(Bit#(1)) usb_d_p;
    interface Inout#(Bit#(1)) usb_d_n;
    method Action reset(Bit#(1) rst_i);

    (* always_ready *)
    method Action uart_in(Bit#(8) e);

    (* always_ready *)
    method Bit#(1) uart_in_ready();

    (* always_ready *)
    method Bit#(1) uart_out_ready();
  /* input [7:0] uart_in_data, */
  /* input       uart_in_valid, */
  /* output      uart_in_ready, */

    (* always_ready *)
    method ActionValue#(Bit#(8)) uart_out();
  /* output [7:0] uart_out_data, */
  /* output       uart_out_valid, */
  /* input        uart_out_ready, */
endinterface


// Import BVI for the usb_bridge_top
import "BVI" usb_uart =
module mkUsbCore(UsbCore ifc);
    Bit#(3) defaultproto = 0;
    default_clock clk (clk_48mhz);
    default_reset no_reset;

    ifc_inout usb_d_p(pin_usb_p);// = usb_d_p;
    ifc_inout usb_d_n(pin_usb_n);// = usb_d_n;

    method reset(reset) enable((*inhigh*) EN_rst_i);
    method uart_in(uart_in_data)  enable (uart_in_valid);
    method uart_in_ready uart_in_ready;
    method uart_out_data uart_out()  enable (uart_out_ready);
    method uart_out_valid uart_out_ready;

    /* method uart_out_valid uart_out_ready; */

    /* method uart_in(uart_in_data) enable (uart_in_valid); */
    /* method uart_out_data uart_out()  enable (uart_out_ready); */
    /*  */
    /* schedule (reset, uart_in, uart_out, uart_in_ready, uart_out_ready) */
    /*           CF */
    /*         (reset,  uart_out,  uart_in_ready, uart_out_ready) ; */
    schedule (reset, uart_in, uart_out, uart_in_ready, uart_out_ready)
              CF
            (reset,  uart_in_ready, uart_out_ready) ;

    schedule (uart_in) CF (uart_out);

     schedule (uart_in)
              C
            (uart_in) ;

     schedule (uart_out)
              C
            (uart_out) ;

endmodule


