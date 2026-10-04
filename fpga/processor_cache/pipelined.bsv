import FIFO::*;
import SpecialFIFOs::*;
import RegFile::*;
import RVUtil::*;
import Vector::*;
import KonataHelper::*;
import Printf::*;
import Ehr::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);

interface RVIfc;
    method ActionValue#(Mem) getIReq();
    method Action getIResp(Mem a);
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
                 KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
             } F2D deriving (Eq, FShow, Bits);

typedef struct { 
    DecodedInst dinst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(1) epoch;
    Bit#(32) rv1; 
    Bit#(32) rv2; 
    Bit#(5) rd_idx;
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
    } D2E deriving (Eq, FShow, Bits);

typedef struct { 
    MemBusiness mem_business;
    Bit#(32) data;
    DecodedInst dinst;
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
} E2W deriving (Eq, FShow, Bits);

interface Scoreboard;
    method Action insert(Bit#(5) rd_idx);
    method Action remove1(Bit#(5) rd_idx);
    method Action remove2(Bit#(5) rd_idx);
    method Bool search1(Bit#(5) rs1_idx);
    method Bool search2(Bit#(5) rs2_idx);
    method Bool search3(Bit#(5) rd_idx);
endinterface

module mkScoreboard(Scoreboard);
    Vector#(32, Ehr#(3, Bool)) sb <- replicateM(mkEhr(False)); 
    
    method Action insert(Bit#(5) rd_idx);
        sb[rd_idx][2] <= True;
    endmethod
    method Action remove1(Bit#(5) rd_idx);
        sb[rd_idx][0] <= False;
    endmethod
    method Action remove2(Bit#(5) rd_idx);
        sb[rd_idx][1] <= False;
    endmethod
    method Bool search1(Bit#(5) rsrc_idx1);
        return sb[rsrc_idx1][2];
    endmethod
    method Bool search2(Bit#(5) rsrc_idx2);
        return sb[rsrc_idx2][2];
    endmethod 
    method Bool search3(Bit#(5) rd_idx);
        return sb[rd_idx][2];
    endmethod 

    
endmodule

(* synthesize *)
module mkpipelined(RVIfc);
    // Interface with memory and devices
    FIFO#(Mem) toImem <- mkBypassFIFO;
    FIFO#(Mem) fromImem <- mkBypassFIFO;
    FIFO#(Mem) toDmem <- mkBypassFIFO;
    FIFO#(Mem) fromDmem <- mkBypassFIFO;
    FIFO#(Mem) toMMIO <- mkBypassFIFO;
    FIFO#(Mem) fromMMIO <- mkBypassFIFO;
    let debug = True;
    let mmio_debug = True;
    let konata_debug = True;

    Ehr#(2, Bit#(32)) program_counter <- mkEhr(32'h0000000);
    Vector#(32, Ehr#(2, Bit#(32))) rf <- replicateM(mkEhr(0));
    //Vector#(32, Ehr#(3, Bool)) scoreboard <- replicateM(mkEhr(False));
    //Control Registers
    // Reg#(Bit#(32)) rv1 <- mkReg(0);
	// Reg#(Bit#(32)) rv2 <- mkReg(0);
	//Reg#(Bit#(5)) rvd_idx <- mkReg(0);
	// Reg#(DecodedInst) dInst <- mkReg(unpack(0));
	// Reg#(MemBusiness) mem_business <- mkReg(?);
    
    //Queues for Pipeling 
    FIFO#(F2D) f2d <- mkFIFO;
    FIFO#(D2E) d2e <- mkFIFO;
    FIFO#(E2W) e2w <- mkFIFO;

    //Epoch
    //Reg#(Bit#(1)) mEpoch <- mkReg(0);
    Ehr#(2, Bit#(1)) mEpoch <- mkEhr(0);
     //Scoreboard
    Scoreboard scoreboard <- mkScoreboard;

	// Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
	Reg#(KonataId) commit_id <- mkReg(0);
	FIFO#(KonataId) retired <- mkFIFO;
	FIFO#(KonataId) squashed <- mkFIFO;
    FIFO#(KonataId) squashed2 <- mkFIFO;
    
    Reg#(Bool) starting <- mkReg(True);

    Bit#(32) maxCount = 600;
    Reg#(Bit#(32)) count <- mkReg(0);

    rule doTic;
        if (debug && count < maxCount) begin
            $display("Cycle %d", count);
        end
        count <= count + 1;
    endrule

	rule do_tic_logging;
        if (starting) begin
            let f <- $fopen(dumpFile, "w") ;
            lfh <= f;
            $fwrite(f, "Kanata\t0004\nC=\t1\n");
            starting <= False;
        end
		konataTic(lfh);
	endrule
	//Each state can run concurrently might not need guards
    rule fetch if (!starting);
        // You should put the pc that you fetch in pc_fetched
        // Below is the code to support Konata's visualization
        program_counter[0] <= program_counter[0] + 4;
		let iid <- fetch1Konata(lfh, fresh_id, 0);
        if (konata_debug) labelKonataLeft(lfh, iid, $format("PC %x",program_counter[0]));
        if(debug && count < maxCount) $display("Fetch %x", program_counter[0]);
        toImem.enq(Mem{byte_en: 0,  addr: program_counter[0], data: 0});
        f2d.enq(F2D{pc: program_counter[0], ppc: program_counter[0] + 4, epoch: mEpoch[0], k_id: iid});
        // This will likely end with something like:
        // f2d.enq(F2D{ ..... k_id: iid});
        // iid is the unique identifier used by konata, that we will pass around everywhere for each instruction
    endrule

    rule decode if (!starting);
        // TODO
        // To add a decode event in Konata you will likely do something like:
        //  let from_fetch = f2d.first();
   	    //	decodeKonata(lfh, from_fetch.k_id);
        //  labelKonataLeft(lfh,from_fetch.k_id, $format("Any information you would like to put in the left pane in Konata, attached to the current instruction"));
        let imemInst = fromImem.first().data;
        
        let f2d_data = f2d.first();
        let pc = f2d_data.pc;
        let ppc = f2d_data.ppc;
        let fEpoch = f2d_data.epoch;
        let current_id = f2d_data.k_id;
        if(fEpoch == mEpoch[1]) begin 
            
            let rs1_idx = getInstFields(imemInst).rs1;
            let rs2_idx = getInstFields(imemInst).rs2;
            let rd_idx = getInstFields(imemInst).rd;
		    let rs1 = (rs1_idx == 0 ? 0 : rf[rs1_idx][1]);
		    let rs2 = (rs2_idx == 0 ? 0 : rf[rs2_idx][1]);
            let dInst = decodeInst(imemInst);
            
            //Debug 
            if (debug && count < maxCount) $display(pc, " [Decode] ", fshow(dInst));
            if (konata_debug) decodeKonata(lfh, current_id);
            if (konata_debug) labelKonataLeft(lfh,current_id, $format("Instr bits: %x",dInst.inst));
            if (konata_debug) labelKonataLeft(lfh, current_id, $format(" Potential r1: %x, Potential r2: %x" , rs1, rs2));
            
            if(!( scoreboard.search1(rs1_idx) || scoreboard.search2(rs2_idx) || scoreboard.search3(rd_idx))) begin 
               if(dInst.valid_rd && rd_idx != 0) begin
                    scoreboard.insert(rd_idx);
               end 
               f2d.deq();
               fromImem.deq();
               d2e.enq(D2E{dinst: dInst, pc: pc ,ppc: ppc, epoch: fEpoch, rv1: rs1, rv2: rs2,rd_idx: rd_idx, k_id: current_id});
            end 
        end else begin   //wrong epoch
            f2d.deq();
            fromImem.deq();
            if (konata_debug) squashed.enq(current_id);
        end 
    endrule

    rule execute if (!starting);
        // TODO

        // Similarly, to register an execute event for an instruction:
    	// executeKonata(lfh, k_id);
    	// where k_id is the unique konata identifier that has been passed around that came from the fetch stage


    	// Execute is also the place where we advise you to kill mispredicted instructions
    	// (instead of Decode + Execute like in the class)
    	// When you kill (or squash) an instruction, you should register an event for Konata:
    	
        // squashed.enq(current_inst.k_id);

        // This will allow Konata to display those instructions in grey
        let d2e_data = d2e.first();
        d2e.deq();
        let dInst = d2e_data.dinst;
        let dEpoch = d2e_data.epoch;
        let pc = d2e_data.pc;
        let ppc = d2e_data.ppc;
        let rv1 = d2e_data.rv1;
        let rv2 = d2e_data.rv2;
        let rd_idx = d2e_data.rd_idx;
        let current_id = d2e_data.k_id;

        if (debug && count < maxCount) $display(pc, " [Execute] ", fshow(dInst));
		if (konata_debug) executeKonata(lfh, current_id);
        //Execute 
        if (dEpoch == mEpoch[0]) begin 
        
            let imm = getImmediate(dInst);
            Bool mmio = False;
            let data = execALU32(dInst.inst, rv1, rv2, imm, pc);
            let isUnsigned = 0;
            let funct3 = getInstFields(dInst.inst).funct3;
            let size = funct3[1:0];
            let addr = rv1 + imm;
            Bit#(2) offset = addr[1:0];

            if (debug && count < maxCount) $display(pc, "Register Source 1: %d", rv1);
            if (debug && count < maxCount) $display(pc, "Register Source 2: %d", rv2);
            if (debug && count < maxCount) $display(pc, "Immediate: %d", imm);

            if (isMemoryInst(dInst)) begin
                // Technical details for load byte/halfword/word
                let shift_amount = {offset, 3'b0};
                let byte_en = 0;
                case (size) matches
                2'b00: byte_en = 4'b0001 << offset;
                2'b01: byte_en = 4'b0011 << offset;
                2'b10: byte_en = 4'b1111 << offset;
                endcase
                data = rv2 << shift_amount;
                addr = {addr[31:2], 2'b0};
                isUnsigned = funct3[2];
                //let type_mem = (dInst.inst[5] == 1) ? byte_en : 0;
                let type_mem = (dInst.inst[5] == 1) ? 1 : 0;
                let req = Mem {byte_en : type_mem,
                        addr : addr,
                        data : data};
                
                //if (debug && count < maxCount) $display(pc, "Register Source 1: %d", rv1);
                if (debug && count < maxCount) $display(pc, "Memory address ", addr);
                //if (debug && count < maxCount) $display(pc, "Register Source 2: %d", rv2);
                //if (debug && count < maxCount) $display(pc, "Immediate: %d", imm);
                if (isMMIO(addr)) begin 
                    if (mmio_debug) $display(count, " [Execute] MMIO", fshow(req));
                    toMMIO.enq(req);
                    if (konata_debug) labelKonataLeft(lfh,current_id, $format(" MMIO ", fshow(req)));
                    mmio = True;
                end else begin 
                    if (konata_debug) labelKonataLeft(lfh,current_id, $format(" MEM ", fshow(req)));
                    toDmem.enq(req);
                end
            end
            else if (isControlInst(dInst)) begin
                    if (konata_debug) labelKonataLeft(lfh,current_id, $format(" Ctrl instr "));
                    data = pc + 4;
            end else begin 
                if (konata_debug) labelKonataLeft(lfh,current_id, $format(" Standard instr "));
            end
            let controlResult = execControl32(dInst.inst, rv1, rv2, imm, pc);
            let nextPc = controlResult.nextPC;
            if(ppc != nextPc) begin
                if(debug && count < maxCount) $display("New PC: ", fshow(nextPc));
                mEpoch[0] <= mEpoch[0] + 1;
                program_counter[1] <= nextPc;
            end 
            
            if (konata_debug) labelKonataLeft(lfh,current_id, $format(" ALU output: %x" , data));
            e2w.enq(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio}, data: data, dinst: dInst, k_id: current_id});
        end else begin 
            if(dInst.valid_rd && rd_idx != 0) begin 
                scoreboard.remove1(rd_idx);
            end
            if (konata_debug) squashed2.enq(current_id);
        end 

    endrule

    rule writeback if (!starting);
        // TODO
        let e2w_data = e2w.first();
        e2w.deq();
        let mem_business = e2w_data.mem_business;
        let data = e2w_data.data; 
        let dInst = e2w_data.dinst;
        let current_id = e2w_data.k_id;
       
        if (konata_debug) writebackKonata(lfh,current_id);
        if (konata_debug) retired.enq(current_id);
        let fields = getInstFields(dInst.inst);
        if (isMemoryInst(dInst) && (mem_business.mmio || dInst.valid_rd)) begin // (* // write_val *)
            
            let resp = ?;
		    if (mem_business.mmio) begin 
                resp = fromMMIO.first();
		        fromMMIO.deq();
		    end else begin 
                resp = fromDmem.first();
		        fromDmem.deq();
		    end

            if(debug && count < maxCount) $display("Mem Inst: ", fshow(resp));

            let mem_data = resp.data;
            mem_data = mem_data >> {mem_business.offset ,3'b0};
            case ({pack(mem_business.isUnsigned), mem_business.size}) matches
	     	3'b000 : data = signExtend(mem_data[7:0]);
	     	3'b001 : data = signExtend(mem_data[15:0]);
	     	3'b100 : data = zeroExtend(mem_data[7:0]);
	     	3'b101 : data = zeroExtend(mem_data[15:0]);
	     	3'b010 : data = mem_data;
             endcase
		end
		if(debug && count < maxCount) $display("[Writeback]", fshow(dInst));
        if (!dInst.legal) begin
			if(debug && count < maxCount) $display("[Writeback] Illegal Inst, Drop and fault: ", fshow(dInst));
			//program_counter <= 0;	// Fault
	    end
		if (dInst.valid_rd) begin
            let rd_idx = fields.rd;
            if (rd_idx != 0) begin 
                rf[rd_idx][0] <=data;
                scoreboard.remove2(rd_idx);
            end
		end
        

        // Similarly, to register an execute event for an instruction:
	   	//	writebackKonata(lfh,k_id);


	   	// In writeback is also the moment where an instruction retires (there are no more stages)
	   	// Konata requires us to register the event as well using the following: 
		//retired.enq(k_id);
	endrule
		

	// ADMINISTRATION:

    rule administrative_konata_commit;
		    retired.deq();
		    let f = retired.first();
		    commitKonata(lfh, f, commit_id);
	endrule
		
	rule administrative_konata_flush;
		    squashed.deq();
		    let f = squashed.first();
		    squashKonata(lfh, f);
	endrule

    rule administrative_konata_flush2;
		    squashed2.deq();
		    let f = squashed2.first();
		    squashKonata(lfh, f);
	endrule
		
    method ActionValue#(Mem) getIReq();
		toImem.deq();
		return toImem.first();
    endmethod
    method Action getIResp(Mem a);
    	fromImem.enq(a);
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
