import UsbByte::*;
import GetPut::*;
// import Orange::*;
// import AXI4_Lite_Master::*;
// import AXI4_Lite_Slave::*;
// import AXI4_Lite_Types::*;
import Connectable::*;
import DefaultValue::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import BRAM::*;
import RVUtil::*;
import pipelined::*;
import FIFO::*;
import Cache::*;
import TwoWordCache::*;
import MainMem::*;
import MemTypes::*;
import DelayLine::*;


interface OrangeCrab;
    (* prefix = "" *)
    interface Usb usb;
    
    (* always_ready, prefix = "" *)
    method Bit#(1) pin_pu;

    (* always_ready, prefix = "" *)
    method Bit#(1) rgb_led0_r();
    (* always_ready, prefix = "" *)
    method Bit#(1) rgb_led0_g();
    (* always_ready, prefix = "" *)
    method Bit#(1) rgb_led0_b();

    // (* prefix = "" *)
    // interface DramPins dram;
endinterface

// Import BVI for the usb_bridge_top

(* synthesize, default_clock_osc = "pin_clk", default_reset = "usr_btn" *)
module top(OrangeCrab ifc);
    Reg#(Bit#(8)) cnt <- mkReg(0);
    Reg#(Bit#(16)) rcnt <- mkReg(0);
    // USB Core
    UsbCore usb_core <- mkUsbCore();
    Inout#(Bit#(1)) usbp = usb_core.usb_d_p; 
    Inout#(Bit#(1)) usbn = usb_core.usb_d_n; 

    /* BRAM_Configure cfg = defaultValue(); */
    /* BRAM2PortBE#(Bit#(8), Bit#(32), 4) bram <- mkBRAM2ServerBE(cfg); */

    Reg#(Bit#(8)) r <- mkReg(0);
    Reg#(Bit#(8)) g <- mkReg(0);
    Reg#(Bit#(8)) b <- mkReg(0);

    //Reg#(Bit#(8)) req <- mkReg(0);

    FIFO#(Bit#(8)) to_host <- mkFIFO1; // ASCII To computer
    FIFOF#(Bit#(8)) from_host <- mkSizedFIFOF(8);

    /* Modifiable */

    // Instantiate the dual ported memory
    MainMem2 dram <- mkMainMem2;
    //I-Cache
    Cache2 i_cache <- mkCache2;
    //D-Cache
    Cache1 d_cache <- mkCache1;

    RVIfc rv_core <- mkpipelined;
    Reg#(Mem2) ireq <- mkRegU;
    Reg#(Mem) dreq <- mkRegU;
    FIFO#(Mem) mmioreq <- mkFIFO1;
    Reg#(Bit#(24)) cycle_count <- mkReg(0);

    rule tic;
	    cycle_count <= cycle_count + 1;
        // if (cycle_count == 0 ) begin
        //     r <= (r == 255) ? 0: 255;
        // end 
    endrule
    
    rule connectICacheDram;
        let lineReq <- i_cache.getToMem();
        dram.put1(lineReq);
    endrule
    rule connectDramICache;
        let resp <- dram.get1();
        i_cache.putFromMem(resp);
    endrule

    rule connectDCacheDram;
        let lineReq <- d_cache.getToMem();
        dram.put2(lineReq);
    endrule
    rule connectDramDCache;
        let resp <- dram.get2();
        d_cache.putFromMem(resp);
    endrule
    rule requestI;
        let req <- rv_core.getIReq();
        ireq <= req;
        i_cache.putFromProc(ProcReq2{write: req.byte_en[0], addr: req.addr, data: req.data});
    endrule
    
    rule responseI;
        let x <- i_cache.getToProc();
        let req = ireq;
     
        req.data = x;
        rv_core.getIResp(req);
    endrule

    rule requestD;
        let req <- rv_core.getDReq();
        dreq <= req;
       
        d_cache.putFromProc(ProcReq{write: req.byte_en[0], addr: req.addr, data: req.data});
    endrule

    rule responseD;
        let x <- d_cache.getToProc();
        let req = dreq;
        
        req.data = x;
        rv_core.getDResp(req);
    endrule
    rule requestMMIO;
        let req <- rv_core.getMMIOReq;
        if (req.addr == 'hf000_fff4) begin
            case (req.data)
                32'd0: to_host.enq(8'd48);
                32'd1: to_host.enq(8'd49);
                32'd2: to_host.enq(8'd50);
                32'd3: to_host.enq(8'd51);
                32'd4: to_host.enq(8'd52);
                32'd5: to_host.enq(8'd53);
                32'd6: to_host.enq(8'd54);
                32'd7: to_host.enq(8'd55);
                32'd8: to_host.enq(8'd56);
                32'd9: to_host.enq(8'd57);
                default: to_host.enq(8'd48);
            endcase
        end else if (req.addr ==  'hf000_fff0) begin
            to_host.enq(req.data[7:0]);
        end else if (req.addr == 'hf000_fff8) begin
            if(req.data == 0) begin 
                // g <= 255;
            end else begin 
                // b <= 255;
            end
        end
        mmioreq.enq(req);
    endrule

    rule responseMMIO;
        let req = mmioreq.first();
        mmioreq.deq();
        rv_core.getMMIOResp(req);
    endrule




    /* Do not Touch Section */
    //dont touch
    rule reset_setup;
        cnt <= cnt + 1;
        let reset = ~rcnt[5];
        rcnt <= rcnt + zeroExtend(reset);
        usb_core.reset(reset);
    endrule

    //dont touch
    //recieving from host
    rule get_k;
        Bit#(8) addr = 0;
        if (from_host.notFull) begin
            addr <- usb_core.uart_out();
            if (usb_core.uart_out_ready() == 1) begin 
                from_host.enq(addr);
                // r <= ~r;
            end
        end
    endrule
    
    // dont touch 
    // sending to host
    rule output_uart;
        usb_core.uart_in(to_host.first());
        if (usb_core.uart_in_ready() == 1) 
            to_host.deq();
    endrule

    method Bit#(1) rgb_led0_r();
        return ~pack(cnt < r);
    endmethod

    method Bit#(1) rgb_led0_g();
        return ~pack(cnt < g);
    endmethod

    method Bit#(1) rgb_led0_b();
        return ~pack(cnt < b);
    endmethod

    method Bit#(1) pin_pu;
        return 1;
    endmethod
    
    interface usb = interface Usb;
        interface pin_usb_p = usbp;
        interface pin_usb_n = usbn;
    endinterface;

    // interface dram = system.dram;        

endmodule
