import BRAM::*;
import FIFO::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Vector::*;
import Ehr::*;

typedef Bit#(22) TagSize;
typedef Bit#(4) IdxSize;
typedef Bit#(4) OffsetSize;
typedef enum {Ready, StartMiss_BRAMReq, StartMiss_BRAMResp, SendFillReq, WaitFillResp, HitQ, WaitStore} ReqStatus deriving (Bits, Eq);

interface Cache2;
    method Action putFromProc(ProcReq2 req);
    method ActionValue#(OneOrTwoWords) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp resp);
endinterface

module mkCache2(Cache2);
  BRAM_Configure cfg = defaultValue();
  BRAM1Port#(IdxSize, Vector#(16, Word)) cache_data <- mkBRAM1Server(cfg);  //each cache line of data is 16 32-bit words (512 bits)

  Vector#(16, Reg#(TagSize)) tagArray <- replicateM(mkReg(0));
  Vector#(16, Reg#(Bool)) validArray <- replicateM(mkReg(False));
  Vector#(16, Reg#(Bool)) dirtyArray <- replicateM(mkReg(False));

  Reg#(ProcReq2) missReq <- mkRegU;
  Ehr#(2, ReqStatus) mshr <- mkEhr(Ready);

  FIFO#(OneOrTwoWords) hitQ <- mkBypassFIFO;
  FIFO#(OffsetSize) loadOffsetQ <- mkFIFO;
  FIFO#(MainMemReq) memReqQ <- mkFIFO;
  FIFO#(MainMemResp) memRespQ <- mkFIFO; 

  Reg#(Bit#(32)) hitCount <- mkReg(0);
  Reg#(Bit#(32)) missCount <- mkReg(0);

  rule bram_to_hitQ if (mshr[0] == HitQ);
    Vector#(16, Word) line <- cache_data.portA.response.get();
    //$display("Line: ", fshow(line));
    let req_offset = loadOffsetQ.first();
    loadOffsetQ.deq();
    Word first_word = line[req_offset];

    let second_word_exists = 0;
    Word second_word = 0;
    if (req_offset != 15) begin
      second_word = line[req_offset+1];
      second_word_exists = 1;
    end
    
    OneOrTwoWords data = {first_word, second_word_exists, second_word};
    //$display("Return data: ", fshow(data));
    hitQ.enq(data);
    mshr[0] <= Ready;
  endrule


  rule startMiss_BRAMReq if (mshr[0] == StartMiss_BRAMReq);
    let req_idx = missReq.addr[9:6];
    let old_line_valid = validArray[req_idx];
    let old_line_dirty = dirtyArray[req_idx];

    if (old_line_dirty && old_line_valid) begin    //the old cache line is dirty and must be written back to memory
      cache_data.portA.request.put(BRAMRequest{write: False,   //read the current cache line
                         responseOnWrite: False,
                         address: req_idx,
                         datain: ?});

      mshr[0] <= StartMiss_BRAMResp;
    end

    else mshr[0] <= SendFillReq;    //if the old cache line is not dirty, then no writeback needed

  endrule


  rule startMiss_BRAMResp if (mshr[0] == StartMiss_BRAMResp);
    Vector#(16, Word) old_line <- cache_data.portA.response.get();  //get old cache line
    MainMemResp old_data = pack(old_line);   //convert vector of 16 words into 512 bits

    let req_idx = missReq.addr[9:6];
    let old_tag = tagArray[req_idx];
    LineAddr old_addr = {old_tag, req_idx};   //concat tag and idx together to get the address

    memReqQ.enq(MainMemReq {write: 1,              //writeback old cache line to memory
                addr: old_addr,
                data: old_data});

    mshr[0] <= SendFillReq;

  endrule

  rule sendFillReq if (mshr[0] == SendFillReq);
    memReqQ.enq(MainMemReq {write: 0,              //load new line from memory
                addr: missReq.addr[31:6],          //take top 26 bits (the line address)
                data: ?});

    mshr[0] <= WaitFillResp;
  endrule


  rule waitFillResp if (mshr[0] == WaitFillResp);
    memRespQ.deq();
    MainMemResp mem_data = memRespQ.first();
    //$display("Mem Resp ", mem_data);
    Vector#(16, Word) new_line = unpack(mem_data); //unpack the 512-bit response into a vector of 16 words
    //$display("New Line ", fshow(new_line));
    let req_store = missReq.write;
    let req_offset = missReq.addr[5:2];
    let req_idx = missReq.addr[9:6];
    let req_tag = missReq.addr[31:10];
    let req_data = missReq.data;

    tagArray[req_idx] <= req_tag;
    validArray[req_idx] <= True;


    //$display("Offset: ", fshow(req_offset));
    //$display("Idx: ", fshow(req_idx));
    //$display("Tag: ", fshow(req_tag));
    //$display("New Line: ", fshow(new_line));

    dirtyArray[req_idx] <= False;
    cache_data.portA.request.put(BRAMRequest{write: True,   //write new data to cache
                        responseOnWrite: False,
                        address: req_idx,
                        datain: new_line});
    
    Word first_word = new_line[req_offset];

    let second_word_exists = 0;
    Word second_word = 0;
    if (req_offset != 15) begin
        second_word = new_line[req_offset+1];
        second_word_exists = 1;
    end
    //$display("Return data: ", fshow(data));

    OneOrTwoWords return_data = {first_word, second_word_exists, second_word};

    //$display("Return data: ", fshow(return_data));
    hitQ.enq(return_data);
    //end

    mshr[0] <= Ready;

  endrule

/*
  rule displayPercents;
    if (missCount == 100) begin
      $display("Misses: %d Hits: %d", missCount, hitCount);
    end
  endrule
*/

  method Action putFromProc(ProcReq2 req) if (mshr[1] == Ready);
    let req_store = req.write; //1 if store, 0 if load
    Word req_addr = req.addr;
    OneOrTwoWords req_data = req.data;

    let req_offset = req_addr[5:2];
    let req_idx = req_addr[9:6];
    let req_tag = req_addr[31:10];
    let cur_tag = tagArray[req_idx];
    let cur_valid = validArray[req_idx];
    //$display("Load/Store: %d, Tag: %d, Idx: %d, Offset: %d", req_store, req_tag, req_idx, req_offset);

    if (cur_tag == req_tag && cur_valid) begin  //cache hit 
        //$display("Cache Load Hit");
        hitCount <= hitCount + 1;
        cache_data.portA.request.put(BRAMRequest{write: False,   //read corresponding line (512 bits) from cache
                            responseOnWrite: False,
                            address: req_idx,
                            datain: ?});

        loadOffsetQ.enq(req_offset);   //store the line offset so that it can be used later

        mshr[1] <= HitQ;
    end

    else begin     //cache miss
        //$display("Cache Load Miss");
        missCount <= missCount + 1;
        mshr[1] <= StartMiss_BRAMReq;
        missReq <= req;
    end
    
  endmethod

  method ActionValue#(OneOrTwoWords) getToProc();
    hitQ.deq();
    return hitQ.first();
  endmethod

  method ActionValue#(MainMemReq) getToMem();
    memReqQ.deq();
    return memReqQ.first();
  endmethod

  method Action putFromMem(MainMemResp resp);
    memRespQ.enq(resp);
  endmethod


endmodule