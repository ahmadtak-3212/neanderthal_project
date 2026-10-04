import FIFO::*;
import SpecialFIFOs::*;
import RegFile::*;
import RVUtil::*;
import Vector::*;
import Printf::*;
import MemTypes::*;
import Ehr::*;
import Supfifo::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(65) data; } Mem2 deriving (Eq, FShow, Bits);
typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);

interface RVIfc;
    method Bit#(32) getPC();
    method ActionValue#(Mem2) getIReq();
    method Action getIResp(Mem2 a);
    method ActionValue#(Mem) getDReq();
    method Action getDResp(Mem a);
    method ActionValue#(Mem) getMMIOReq();
    method Action getMMIOResp(Mem a);
endinterface


typedef struct { Bool isUnsigned; Bit#(2) size; Bit#(2) offset; Bool mmio; } MemBusiness deriving (Eq, FShow, Bits);

function Bool isMMIO(Bit#(32) addr);
    Bool x = case (addr) 
        32'hf000fff0: True;
        32'hf000fff4: True;
        32'hf000fff8: True;
        default: False;
    endcase;
    return x;
endfunction

typedef struct { Bit#(32) pc;
                 Bit#(32) ppc;
                 Bit#(1) epoch; 
             } F2D deriving (Eq, FShow, Bits);

typedef struct { 
    DecodedInst dinst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(1) epoch;
    Bit#(32) rv1; 
    Bit#(32) rv2; 
    Bit#(5) rd_idx;
    } D2E deriving (Eq, FShow, Bits);

typedef struct { 
    MemBusiness mem_business;
    Bit#(32) data;
    DecodedInst dinst;
    Bit#(32) pc;
} E2W deriving (Eq, FShow, Bits);

(* synthesize *)
module mkpipelined(RVIfc);
    // Interface with memory and devices
    FIFO#(Mem2) toImem <- mkBypassFIFO;
    SupFifo#(Mem) fromImem <- mkSupFifo;
    FIFO#(Mem) toDmem <- mkBypassFIFO;
    FIFO#(Mem) fromDmem <- mkBypassFIFO;
    FIFO#(Mem) toMMIO <- mkBypassFIFO;
    FIFO#(Mem) fromMMIO <- mkBypassFIFO;

    //Program Counter
    Ehr#(2, Bit#(32)) program_counter <- mkEhr(32'h0000000);
    
    //Register File
    Vector#(32, Ehr#(3, Bit#(32))) rf <- replicateM(mkEhr(0));

    //Queues for Pipeling 
    SupFifo#(F2D) f2d <- mkSupFifo;
    SupFifo#(D2E) d2e <- mkSupFifo;
    SupFifo#(E2W) e2w <- mkSupFifo;

    //Epoch
    Ehr#(2, Bit#(1)) mEpoch <- mkEhr(0);

    //Scoreboard
    Vector#(32, Ehr#(6, Bool)) sb <- replicateM(mkEhr(False));

    Reg#(Bool) starting <- mkReg(False);
    
    rule fetch if (!starting);
        toImem.enq(Mem2{byte_en: 0,  addr: program_counter[0], data: 0});
        f2d.enq1(F2D{pc: program_counter[0], ppc: program_counter[0] + 4, epoch: mEpoch[0]});
        if  (program_counter[0][5:2] != 15 ) begin 
            f2d.enq2(F2D{pc: program_counter[0] + 4, ppc: program_counter[0] + 8, epoch: mEpoch[0]});
            program_counter[0] <= program_counter[0] + 8;
        end else begin 
            program_counter[0] <= program_counter[0] + 4;
        end 
    endrule

    rule decode if (!starting);
        //First Instruction
        let imemInst1 = fromImem.first1().data;
        let imemInst2 = fromImem.first2().data;

        // F2D Data 1
        let f2d_data_1 = f2d.first1();
        let pc_1 = f2d_data_1.pc;
        let ppc_1 = f2d_data_1.ppc;
        let fEpoch_1 = f2d_data_1.epoch;

        //Decoding
        let rs1_idx_1 = getInstFields(imemInst1).rs1;
        let rs2_idx_1 = getInstFields(imemInst1).rs2;
        let rd_1 = getInstFields(imemInst1).rd;
        let rs1_1 = (rs1_idx_1 == 0 ? 0 : rf[rs1_idx_1][2]);
        let rs2_1 = (rs2_idx_1 == 0 ? 0 : rf[rs2_idx_1][2]);
        let dInst_1 = decodeInst(imemInst1);

        //F2D Data 2
        let f2d_data_2 = f2d.first2();
        let pc_2 = f2d_data_2.pc;
        let ppc_2 = f2d_data_2.ppc;
        let fEpoch_2 = f2d_data_2.epoch;
        
        //Decodeing
        let rs1_idx_2 = getInstFields(imemInst2).rs1;
        let rs2_idx_2 = getInstFields(imemInst2).rs2;
        let rd_2 = getInstFields(imemInst2).rd;
        let rs1_2 = (rs1_idx_2 == 0 ? 0 : rf[rs1_idx_2][2]);
        let rs2_2 = (rs2_idx_2 == 0 ? 0 : rf[rs2_idx_2][2]);
        let dInst_2 = decodeInst(imemInst2);

        //if(noDependency(sb,ins1) && noDependency(sb, ins2) and noDependency(ins1, ins2))
        if(fEpoch_1 == mEpoch[1] && fEpoch_2 == mEpoch[1]
            && !(sb[rs1_idx_1][4] || sb[rs2_idx_1][4] || sb[rd_1][4]) 
            && !(sb[rs1_idx_2][4] || sb[rs2_idx_2][4] || sb[rd_2][4]) 
            && !(rs1_idx_2 == rd_1 || rs2_idx_2 == rd_1 ) ) begin 
            
            if(dInst_1.valid_rd && rd_1 != 0) begin
                sb[rd_1][4] <= True;
            end 
        
            if(dInst_2.valid_rd && rd_2 != 0) begin
                sb[rd_2][5] <= True;
            end 

            d2e.enq1(D2E{dinst: dInst_1, pc: pc_1, ppc: ppc_1, epoch: fEpoch_1, rv1: rs1_1, rv2: rs2_1, rd_idx: rd_1});
            d2e.enq2(D2E{dinst: dInst_2, pc: pc_2, ppc: ppc_2, epoch: fEpoch_2, rv1: rs1_2, rv2: rs2_2, rd_idx: rd_2});
            f2d.deq1();
            f2d.deq2();
            fromImem.deq1();
            fromImem.deq2();
        //if(noDependency(ins1, sb))
        end else if (fEpoch_1 == mEpoch[1] && !(sb[rs1_idx_1][4] || sb[rs2_idx_1][4] || sb[rd_1][4])) begin 

            if(dInst_1.valid_rd && rd_1 != 0) begin
                sb[rd_1][4] <= True;
            end 
        
            d2e.enq1(D2E{dinst: dInst_1, pc: pc_1, ppc: ppc_1, epoch: fEpoch_1, rv1: rs1_1, rv2: rs2_1, rd_idx: rd_1});
            f2d.deq1();
            fromImem.deq1();
        end else if (fEpoch_1 != mEpoch[1]) begin //wrong path instruction, drop it
            f2d.deq1();
            fromImem.deq1();
            
            if (fEpoch_2 != mEpoch[1]) begin  //second instruction is also wrong, drop it
                f2d.deq2();
                fromImem.deq2();
            end
        end
    endrule

    rule execute if (!starting);
        let ins1 = d2e.first1();
        D2E ins2 = unpack(0);
        let d2e_notEmpty2 = d2e.notEmpty2();
        if (d2e_notEmpty2) ins2 = d2e.first2();
    
        d2e.deq1();
        if(ins1.epoch != mEpoch[0]) begin  //if first instruction epoch doesn't match, kill it
            sb[ins1.rd_idx][2] <= False;
            if (d2e_notEmpty2 && ins2.epoch != mEpoch[0]) begin      //if second instruction epoch doesn't match, kill it
             
                d2e.deq2();
                sb[ins2.rd_idx][3] <= False;
            end
        end 

        else if (d2e_notEmpty2 && isALU(ins1.dinst) && isALU(ins2.dinst) && ins2.epoch == mEpoch[0]) begin 
            //Execute Both
            d2e.deq2();


            // Instruction 1 
            let imm_1 = getImmediate(ins1.dinst);
            Bool mmio_1 = False;
            let data_1 = execALU32(ins1.dinst.inst, ins1.rv1, ins1.rv2, imm_1, ins1.pc);
            let isUnsigned_1 = 0;
            let funct3_1 = getInstFields(ins1.dinst.inst).funct3;
            let size_1 = funct3_1[1:0];
            let addr_1 = ins1.rv1 + imm_1;
            Bit#(2) offset_1 = addr_1[1:0];
            
         
            e2w.enq1(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned_1), size : size_1, offset : offset_1, mmio: mmio_1}, data: data_1, dinst: ins1.dinst, pc: ins1.pc});

            // Instruction 2 
            let imm_2 = getImmediate(ins2.dinst);
            Bool mmio_2 = False;
            let data_2 = execALU32(ins2.dinst.inst, ins2.rv1, ins2.rv2, imm_2, ins2.pc);
            let isUnsigned_2 = 0;
            let funct3_2 = getInstFields(ins2.dinst.inst).funct3;
            let size_2 = funct3_2[1:0];
            let addr_2 = ins2.rv1 + imm_2;
            Bit#(2) offset_2 = addr_2[1:0];
            
         
            e2w.enq2(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned_2), size : size_2, offset : offset_2, mmio: mmio_2}, data: data_2, dinst: ins2.dinst, pc: ins2.pc});
        end
        
        else begin 
            //Original
            let imm_1 = getImmediate(ins1.dinst);
            Bool mmio_1 = False;
            let data_1 = execALU32(ins1.dinst.inst, ins1.rv1, ins1.rv2, imm_1, ins1.pc);
            let isUnsigned_1 = 0;
            let funct3_1 = getInstFields(ins1.dinst.inst).funct3;
            let size_1 = funct3_1[1:0];
            let addr_1 = ins1.rv1 + imm_1;
            Bit#(2) offset_1 = addr_1[1:0];

            if (isMemoryInst(ins1.dinst)) begin
                // Technical details for load byte/halfword/word
                let shift_amount_1 = {offset_1, 3'b0};
                let byte_en_1 = 0;
                case (size_1) matches
                2'b00: byte_en_1 = 4'b0001 << offset_1;
                2'b01: byte_en_1 = 4'b0011 << offset_1;
                2'b10: byte_en_1 = 4'b1111 << offset_1;
                endcase

                data_1 = ins1.rv2 << shift_amount_1;
                addr_1 = {addr_1[31:2], 2'b0};
                isUnsigned_1 = funct3_1[2];

                let type_mem_1 = (ins1.dinst.inst[5] == 1) ? 1 : 0;
                let req_1 = Mem {byte_en : type_mem_1,
                        addr : addr_1,
                        data : data_1};
                
               
                if (isMMIO(addr_1)) begin 
                   
                    toMMIO.enq(req_1);
              
                    mmio_1 = True;
                end else begin 
                  
                    toDmem.enq(req_1);
                end
            end
            else if (isControlInst(ins1.dinst)) begin
                    
                    data_1 = ins1.pc + 4;
            end else begin 
                
            end
            let controlResult_1 = execControl32(ins1.dinst.inst, ins1.rv1, ins1.rv2, imm_1, ins1.pc);
            let nextPc_1 = controlResult_1.nextPC;
            if(ins1.ppc != nextPc_1) begin
             
                mEpoch[0] <= mEpoch[0] + 1;
                program_counter[1] <= nextPc_1;
            end 
            
          
            e2w.enq1(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned_1), size : size_1, offset : offset_1, mmio: mmio_1}, data: data_1, dinst: ins1.dinst, pc: ins1.pc});
        end 
        
    endrule

    rule writeback if (!starting);
        // TODO
        let ins1 = e2w.first1();
        E2W ins2 = unpack(0);
        let e2w_notEmpty2 = e2w.notEmpty2();
        if (e2w_notEmpty2) ins2 = e2w.first2();
        e2w.deq1();

     


        // if (notMemory(ins1) and notMemory(ins2))
        if(e2w_notEmpty2 && !isMemoryInst(ins1.dinst) && !isMemoryInst(ins2.dinst) ) begin 

            if (ins2.dinst.valid_rd) begin
                let fields = getInstFields(ins2.dinst.inst);
                let rd_idx = fields.rd;
                if (rd_idx != 0) begin 
                    rf[rd_idx][1] <= ins2.data;
                    sb[rd_idx][1] <= False;
                end 
            end	    
            e2w.deq2();
        //else just do inst 1
        end else if (isMemoryInst(ins1.dinst) && (ins1.mem_business.mmio || ins1.dinst.valid_rd )) begin // (* // write_val *)
            let mem_business = ins1.mem_business;
            let resp_1 = ?;
		    if (ins1.mem_business.mmio) begin 
                resp_1 = fromMMIO.first();
		        fromMMIO.deq();
		    end else begin 
                resp_1 = fromDmem.first();
		        fromDmem.deq();
		    end

          
            let mem_data_1 = resp_1.data;
            mem_data_1 = mem_data_1 >> {mem_business.offset ,3'b0};
            case ({pack(ins1.mem_business.isUnsigned), ins1.mem_business.size}) matches
                3'b000 : ins1.data = signExtend(mem_data_1[7:0]);
                3'b001 : ins1.data = signExtend(mem_data_1[15:0]);
                3'b100 : ins1.data = zeroExtend(mem_data_1[7:0]);
                3'b101 : ins1.data = zeroExtend(mem_data_1[15:0]);
                3'b010 : ins1.data = mem_data_1;
            endcase
        
		end 
        if (ins1.dinst.valid_rd) begin
            let fields = getInstFields(ins1.dinst.inst);
            let rd_idx = fields.rd;
            if (rd_idx != 0) begin 
                rf[rd_idx][0] <= ins1.data;
                sb[rd_idx][0] <= False;
            end
        end
        
	endrule
		

    method Bit#(32) getPC();
        return program_counter[0];
    endmethod
    method ActionValue#(Mem2) getIReq();
		toImem.deq();
		return toImem.first();
    endmethod
    method Action getIResp(Mem2 a);
        OneOrTwoWords data = a.data;
        let imemInst1 = data[64:33];
        let isTwoWords = data[32];
        let imemInst2 = data[31:0];

    	fromImem.enq1(Mem{byte_en: a.byte_en,  addr: a.addr, data: imemInst1});

        if (isTwoWords == 1) begin
            fromImem.enq2(Mem{byte_en: a.byte_en,  addr: a.addr + 4, data: imemInst2});
        end
    endmethod
    method ActionValue#(Mem) getDReq();
		toDmem.deq();
		return toDmem.first();
    endmethod
    method Action getDResp(Mem a);
		fromDmem.enq(a);
    endmethod
    method ActionValue#(Mem) getMMIOReq();
		toMMIO.deq();
		return toMMIO.first();
    endmethod
    method Action getMMIOResp(Mem a);
		fromMMIO.enq(a);
    endmethod
endmodule
