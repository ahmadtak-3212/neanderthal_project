import RVUtil::*;
import BRAM::*;
import FIFO::*;
import SpecialFIFOs::*;
import DelayLine::*;
import MemTypes::*;
import Cache::*;

// interface MainMem;
//     method Action put(MainMemReq req);
//     method ActionValue#(MainMemResp) get();
// endinterface

// interface MainMemFast;
//     method Action put(ProcReq req);
//     method ActionValue#(Word) get();
// endinterface

typedef struct { 
    MainMemReq req;
    Bit#(1) port1; // 1 port 1, 0 port 2
} FPGAMemReq deriving (Eq, FShow, Bits);


interface MainMem2;
    method Action put1(MainMemReq req);
    method Action put2(MainMemReq req);
    method ActionValue#(MainMemResp) get1();
    method ActionValue#(MainMemResp) get2();
endinterface

module mkMainMem2(MainMem2);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM1Port#(Bit#(4), MainMemResp) bram <- mkBRAM1Server(cfg);
    DelayLine#(4, MainMemResp) dl1 <- mkDL(); // Delay by 2 cycles
    DelayLine#(4, MainMemResp) dl2 <- mkDL(); // Delay by 2 cycles
    
    FIFO#(FPGAMemReq) reqQ <- mkFIFO1;
    
    rule deq1 if(reqQ.first.port1 == 1);
        let r <- bram.portA.response.get();
        reqQ.deq();
        dl1.put(r);
    endrule 

    rule deq2 if(reqQ.first.port1 == 0);
        let r <- bram.portA.response.get();
        reqQ.deq();
        dl2.put(r);
    endrule 

    method Action put1(MainMemReq req);
        reqQ.enq(FPGAMemReq{req: req, port1: 1});
        bram.portA.request.put(BRAMRequest{
            write: unpack(req.write),
            responseOnWrite: False,
            address: req.addr[3:0],
            datain: req.data
        });
    endmethod

    method Action put2(MainMemReq req);
        reqQ.enq(FPGAMemReq{req: req, port1: 0});
        bram.portA.request.put(BRAMRequest{
            write: unpack(req.write),
            responseOnWrite: False,
            address: req.addr[3:0],
            datain: req.data
        });
    endmethod

    method ActionValue#(MainMemResp) get1();
        let r <- dl1.get();
        return r;
    endmethod

    method ActionValue#(MainMemResp) get2();
        let r <- dl2.get();
        return r;
    endmethod

endmodule
