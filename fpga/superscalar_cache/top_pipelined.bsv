import RVUtil::*;
import BRAM::*;
import pipelined::*;
import FIFO::*;
import Cache::*;
import TwoWordCache::*;
import MainMem::*;
import MemTypes::*;
import DelayLine::*;
typedef Bit#(32) Word;


module mktop_pipelined(Empty);
    // Instantiate the dual ported memory
    MainMem2 dram <- mkMainMemFPGA;
    //I-Cache
    Cache2 i_cache <- mkCache2;
    //D-Cache
    Cache1 d_cache <- mkCache1;

    RVIfc rv_core <- mkpipelined;
    Reg#(Mem2) ireq <- mkRegU;
    Reg#(Mem) dreq <- mkRegU;
    FIFO#(Mem) mmioreq <- mkFIFO;
    let debug = False;
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    rule tic;
	    cycle_count <= cycle_count + 1;
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
        if (debug) $display("Get IReq", fshow(req));
        ireq <= req;
        //TODO check req struct
        i_cache.putFromProc(ProcReq2{write: req.byte_en[0], addr: req.addr, data: req.data});

    endrule
    
    rule responseI;
        let x <- i_cache.getToProc();
        let req = ireq;
        if (debug) $display("Get IResp ", fshow(req), fshow(x));
        req.data = x;
        rv_core.getIResp(req);
    endrule

    rule requestD;
        let req <- rv_core.getDReq();
        dreq <= req;
        if (debug) $display("Get DReq", fshow(req));
        d_cache.putFromProc(ProcReq{write: req.byte_en[0], addr: req.addr, data: req.data});
    endrule

    rule responseD;
        let x <- d_cache.getToProc();
        let req = dreq;
        if (debug) $display("Get IResp ", fshow(req), fshow(x));
        req.data = x;
        rv_core.getDResp(req);
    endrule
  
    rule requestMMIO;
        let req <- rv_core.getMMIOReq;
        if (debug) $display("Get MMIOReq", fshow(req));
        if (req.byte_en == 'hf) begin
            if (req.addr == 'hf000_fff4) begin
                // Write integer to STDERR
                        $fwrite(stderr, "%0d", req.data);
                        $fflush(stderr);
            end
        end
        if (req.addr ==  'hf000_fff0) begin
                // Writing to STDERR
                $fwrite(stderr, "%c", req.data[7:0]);
                $fflush(stderr);
        end else
            if (req.addr == 'hf000_fff8) begin
            // Exiting Simulation
                if (req.data == 0) begin
                        $fdisplay(stderr, "  [0;32mPASS[0m");
                end
                else
                    begin
                        $fdisplay(stderr, "  [0;31mFAIL[0m (%0d)", req.data);
                    end
                $fflush(stderr);
                $finish;
            end

        mmioreq.enq(req);
    endrule

    rule responseMMIO;
        let req = mmioreq.first();
        mmioreq.deq();
        if (debug) $display("Put MMIOResp", fshow(req));
        rv_core.getMMIOResp(req);
    endrule
    
endmodule
