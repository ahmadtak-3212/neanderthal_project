typedef Bit#(26) LineAddr;
typedef Bit#(32) Word;
typedef Bit#(512) MainMemResp;
typedef struct { Bit#(1) write; LineAddr addr; MainMemResp data; } MainMemReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { Bit#(1) write; Word addr; Word data; } ProcReq deriving (Eq, FShow, Bits, Bounded);



