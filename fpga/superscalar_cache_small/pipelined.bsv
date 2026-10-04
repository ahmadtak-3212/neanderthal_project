import FIFO::*;
import SpecialFIFOs::*;
import RegFile::*;
import RVUtil::*;
import Vector::*;
import KonataHelper::*;
import Printf::*;
import MemTypes::*;
import Ehr::*;
import Supfifo::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(65) data; } Mem2 deriving (Eq, FShow, Bits);
typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);

interface RVIfc;
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
                 Bit#(2) epoch; 
                 KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
             } F2D deriving (Eq, FShow, Bits);

typedef struct { 
    DecodedInst dinst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(2) epoch;
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
    Bit#(32) pc;
} E2W deriving (Eq, FShow, Bits);

(* synthesize *)
module mkpipelined(RVIfc);
    // Interface with memory and devices
    FIFO#(Mem2) toImem <- mkBypassFIFO;
    SupFifo#(Mem) fromImem <- mkBypassSupFifo;
    SupFifo#(Mem) toDmem <- mkBypassSupFifo;
    FIFO#(Mem) fromDmem <- mkBypassFIFO;
    SupFifo#(Mem) toMMIO <- mkBypassSupFifo;
    FIFO#(Mem) fromMMIO <- mkBypassFIFO;
    let debug = True;
    let mmio_debug = True;
    let konata_debug = False;

    Reg#(Bit#(32)) totalExecuteCount <- mkReg(0);
    Reg#(Bit#(32)) doubleExecuteCount <- mkReg(0);
    Reg#(Bit#(32)) totalWritebackCount <- mkReg(0);
    Reg#(Bit#(32)) doubleWritebackCount <- mkReg(0);

    //Program Counter
    Ehr#(3, Bit#(32)) program_counter <- mkEhr(32'h0000000);
    
    //Register File
    Vector#(32, Ehr#(3, Bit#(32))) rf <- replicateM(mkEhr(0));

    //Queues for Pipeling 
    SupFifo#(F2D) f2d <- mkSupFifo;
    SupFifo#(D2E) d2e <- mkSupFifo;
    SupFifo#(E2W) e2w <- mkSupFifo;

    //Epoch
    Ehr#(3, Bit#(2)) mEpoch <- mkEhr(0);

    Ehr#(3, Bool) execute_flag <- mkEhr(False);

    //Scoreboard
    Vector#(32, Ehr#(6, Bool)) sb <- replicateM(mkEhr(False));

	// Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
	Ehr#(2, KonataId) fresh_id <- mkEhr(0);
    Ehr#(2, KonataId) commit_id <- mkEhr(0);
	//Reg#(KonataId) commit_id <- mkReg(0);
    //Reg#(KonataId) commit2_id <- mkReg(0);
	FIFO#(KonataId) retired <- mkFIFO;
    FIFO#(KonataId) retired2 <- mkFIFO;
	FIFO#(KonataId) squashed_execute <- mkFIFO;
    FIFO#(KonataId) squashed2_execute <- mkFIFO;
    FIFO#(KonataId) squashed_decode <- mkFIFO;
    FIFO#(KonataId) squashed2_decode <- mkFIFO;

    //Tics
    Reg#(Bool) starting <- mkReg(True);
    Bit#(32) maxCount = 1000;
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
        
		let iid <- fetch1Konata(lfh, fresh_id[0], 0);
        if (konata_debug) labelKonataLeft(lfh, iid, $format("PC %x",program_counter[0]));
        if(debug && count < maxCount) $display("Fetch %x", program_counter[0]);
        toImem.enq(Mem2{byte_en: 0,  addr: program_counter[0], data: 0});
        f2d.enq1(F2D{pc: program_counter[0], ppc: program_counter[0] + 4, epoch: mEpoch[0], k_id: iid});
        if  (program_counter[0][3:2] != 3 ) begin 
            let iid2 <- fetch2Konata(lfh, fresh_id[1], 0);
            if (konata_debug) label2KonataLeft(lfh, iid2, $format("PC %x",program_counter[0]+4));
            if(debug && count < maxCount) $display("Fetch %x", program_counter[0]+4);
            f2d.enq2(F2D{pc: program_counter[0] + 4, ppc: program_counter[0] + 8, epoch: mEpoch[0], k_id: iid2});
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
        let current_id_1 = f2d_data_1.k_id;

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
        let current_id_2 = f2d_data_2.k_id;
        
        //Decodeing
        let rs1_idx_2 = getInstFields(imemInst2).rs1;
        let rs2_idx_2 = getInstFields(imemInst2).rs2;
        let rd_2 = getInstFields(imemInst2).rd;
        let rs1_2 = (rs1_idx_2 == 0 ? 0 : rf[rs1_idx_2][2]);
        let rs2_2 = (rs2_idx_2 == 0 ? 0 : rf[rs2_idx_2][2]);
        let dInst_2 = decodeInst(imemInst2);

        //Debug 1
        if (debug && count < maxCount) $display(pc_1, " [Decode] ", fshow(dInst_1));
        if (konata_debug) decodeKonata(lfh, current_id_1);
        if (konata_debug) labelKonataLeft(lfh,current_id_1, $format("Instr bits: %x",dInst_1.inst));
        if (konata_debug) labelKonataLeft(lfh, current_id_1, $format(" Potential r1: %x, Potential r2: %x" , rs1_1, rs2_1)); 

        //Debug 2
        if (debug && count < maxCount) $display(pc_2, " [Decode] ", fshow(dInst_2));
        if (konata_debug) decode2Konata(lfh, current_id_2);
        if (konata_debug) label2KonataLeft(lfh,current_id_2, $format("Instr bits: %x",dInst_2.inst));
        if (konata_debug) label2KonataLeft(lfh, current_id_2, $format(" Potential r1: %x, Potential r2: %x" , rs1_2, rs2_2)); 

        
        //if(noDependency(sb,ins1) && noDependency(sb, ins2) and noDependency(ins1, ins2))
        if(fEpoch_1 == mEpoch[2] && fEpoch_2 == mEpoch[2]
            && !(sb[rs1_idx_1][4] || sb[rs2_idx_1][4] || sb[rd_1][4]) 
            && !(sb[rs1_idx_2][4] || sb[rs2_idx_2][4] || sb[rd_2][4]) 
            && !(rs1_idx_2 == rd_1 || rs2_idx_2 == rd_1 ) ) begin 
            
            if(dInst_1.valid_rd && rd_1 != 0) begin
                sb[rd_1][4] <= True;
            end 
            
            
            if(dInst_2.valid_rd && rd_2 != 0) begin
                sb[rd_2][5] <= True;
            end 

            d2e.enq1(D2E{dinst: dInst_1, pc: pc_1, ppc: ppc_1, epoch: fEpoch_1, rv1: rs1_1, rv2: rs2_1, rd_idx: rd_1, k_id: current_id_1});
            d2e.enq2(D2E{dinst: dInst_2, pc: pc_2, ppc: ppc_2, epoch: fEpoch_2, rv1: rs1_2, rv2: rs2_2, rd_idx: rd_2, k_id: current_id_2});
            f2d.deq1();
            f2d.deq2();
            fromImem.deq1();
            fromImem.deq2();
        //if(noDependency(ins1, sb))
        end else if (fEpoch_1 == mEpoch[2] && !(sb[rs1_idx_1][4] || sb[rs2_idx_1][4] || sb[rd_1][4])) begin 

            if(dInst_1.valid_rd && rd_1 != 0) begin
                sb[rd_1][4] <= True;
            end 
            if (debug && count < maxCount) $display(pc_1, " enqueued");
            d2e.enq1(D2E{dinst: dInst_1, pc: pc_1, ppc: ppc_1, epoch: fEpoch_1, rv1: rs1_1, rv2: rs2_1, rd_idx: rd_1, k_id: current_id_1});
            f2d.deq1();
            fromImem.deq1();
        end else if (fEpoch_1 != mEpoch[2]) begin //wrong path instruction, drop it
            f2d.deq1();
            fromImem.deq1();
            if (konata_debug) squashed_decode.enq(current_id_1);
            if (debug && count < maxCount) $display(pc_1, " killed");
            if (fEpoch_2 != mEpoch[2]) begin  //second instruction is also wrong, drop it
                if (konata_debug) squashed2_decode.enq(current_id_2);
                if (debug && count < maxCount) $display(pc_2, " killed");
                f2d.deq2();
                fromImem.deq2();
            end
        end
    endrule

/*
    rule execute if (!starting);
        let ins1 = d2e.first1();
        D2E ins2 = unpack(0);
        let d2e_notEmpty2 = d2e.notEmpty2();
        if (d2e_notEmpty2) ins2 = d2e.first2();

        totalExecuteCount <= totalExecuteCount + 1;

        d2e.deq1();

        //Debug 
        if (debug && count < maxCount) $display(ins1.pc, " [Execute] ", fshow(ins1.dinst));
		if (konata_debug) executeKonata(lfh, ins1.k_id);

        if (debug && count < maxCount) $display(ins1.pc, " dequeued.");

        if(ins1.epoch != mEpoch[0]) begin  //if first instruction epoch doesn't match, kill it
            if (debug && count < maxCount) $display(ins1.pc, " killed.");
            sb[ins1.rd_idx][2] <= False;
            if (d2e_notEmpty2 && ins2.epoch != mEpoch[0]) begin      //if second instruction epoch doesn't match, kill it
                doubleExecuteCount <= doubleExecuteCount + 1;
                if (debug && count < maxCount) $display(ins2.pc, " killed.");
                d2e.deq2();
                sb[ins2.rd_idx][3] <= False;
            end
        end 

        else if (d2e_notEmpty2 && isALU(ins1.dinst) && isALU(ins2.dinst) && ins2.epoch == mEpoch[0]) begin 
            //Execute Both
            doubleExecuteCount <= doubleExecuteCount + 1;
            d2e.deq2();

            if (debug && count < maxCount) $display(ins2.pc, " [Execute] ", fshow(ins2.dinst));
            if (konata_debug) executeKonata(lfh, ins2.k_id);

            // Instruction 1 
            let imm_1 = getImmediate(ins1.dinst);
            Bool mmio_1 = False;
            let data_1 = execALU32(ins1.dinst.inst, ins1.rv1, ins1.rv2, imm_1, ins1.pc);
            let isUnsigned_1 = 0;
            let funct3_1 = getInstFields(ins1.dinst.inst).funct3;
            let size_1 = funct3_1[1:0];
            let addr_1 = ins1.rv1 + imm_1;
            Bit#(2) offset_1 = addr_1[1:0];
            
            if (debug && count < maxCount) $display(ins1.pc, "Register Source 1: %d", ins1.rv1);
            if (debug && count < maxCount) $display(ins1.pc, "Register Source 2: %d", ins1.rv2);
            if (debug && count < maxCount) $display(ins1.pc, "Immediate: %d", imm_1);
            if (konata_debug) labelKonataLeft(lfh, ins1.k_id, $format(" ALU output: %x" , data_1));
        
            e2w.enq1(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned_1), size : size_1, offset : offset_1, mmio: mmio_1}, data: data_1, dinst: ins1.dinst, k_id: ins1.k_id, pc: ins1.pc});

            // Instruction 2 
            let imm_2 = getImmediate(ins2.dinst);
            Bool mmio_2 = False;
            let data_2 = execALU32(ins2.dinst.inst, ins2.rv1, ins2.rv2, imm_2, ins2.pc);
            let isUnsigned_2 = 0;
            let funct3_2 = getInstFields(ins2.dinst.inst).funct3;
            let size_2 = funct3_2[1:0];
            let addr_2 = ins2.rv1 + imm_2;
            Bit#(2) offset_2 = addr_2[1:0];
            
            if (debug && count < maxCount) $display(ins2.pc, "Register Source 1: %d", ins2.rv1);
            if (debug && count < maxCount) $display(ins2.pc, "Register Source 2: %d", ins2.rv2);
            if (debug && count < maxCount) $display(ins2.pc, "Immediate: %d", imm_2);
            if (konata_debug) labelKonataLeft(lfh, ins2.k_id, $format(" ALU output: %x" , data_2));
            

            e2w.enq2(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned_2), size : size_2, offset : offset_2, mmio: mmio_2}, data: data_2, dinst: ins2.dinst, k_id: ins2.k_id, pc: ins2.pc});
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
                
                //if (debug && count < maxCount) $display(pc, "Register Source 1: %d", rv1);
                if (debug && count < maxCount) $display(ins1.pc, "Memory address ", addr_1);
                //if (debug && count < maxCount) $display(pc, "Register Source 2: %d", rv2);
                //if (debug && count < maxCount) $display(pc, "Immediate: %d", imm);
                if (isMMIO(addr_1)) begin 
                    if (mmio_debug) $display(count, " [Execute] MMIO", fshow(req_1));
                    toMMIO.enq(req_1);
                    if (konata_debug) labelKonataLeft(lfh,ins1.k_id, $format(" MMIO ", fshow(req_1)));
                    mmio_1 = True;
                end else begin 
                    if (konata_debug) labelKonataLeft(lfh,ins1.k_id, $format(" MEM ", fshow(req_1)));
                    toDmem.enq(req_1);
                end
            end
            else if (isControlInst(ins1.dinst)) begin
                    if (konata_debug) labelKonataLeft(lfh,ins1.k_id, $format(" Ctrl instr "));
                    data_1 = ins1.pc + 4;
            end else begin 
                if (konata_debug) labelKonataLeft(lfh,ins1.k_id, $format(" Standard instr "));
            end
            let controlResult_1 = execControl32(ins1.dinst.inst, ins1.rv1, ins1.rv2, imm_1, ins1.pc);
            let nextPc_1 = controlResult_1.nextPC;
            if(ins1.ppc != nextPc_1) begin
                if (debug && count < maxCount) $display("wrong path detected");
                if(debug && count < maxCount) $display("New PC: ", fshow(nextPc_1));
                mEpoch[0] <= mEpoch[0] + 1;
                program_counter[1] <= nextPc_1;
            end 
            
            if (konata_debug) labelKonataLeft(lfh, ins1.k_id, $format(" ALU output: %x" , data_1));
            if (debug && count < maxCount) $display(ins1.pc, " enqueued.");
            e2w.enq1(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned_1), size : size_1, offset : offset_1, mmio: mmio_1}, data: data_1, dinst: ins1.dinst, k_id: ins1.k_id, pc: ins1.pc});
        end 
        
    endrule
*/

    rule execute1 if (!starting);
        totalExecuteCount <= totalExecuteCount + 1;
        d2e.deq1();
        let d2e_data = d2e.first1();
        let dInst = d2e_data.dinst;
        let dEpoch = d2e_data.epoch;
        let pc = d2e_data.pc;
        let ppc = d2e_data.ppc;
        let rv1 = d2e_data.rv1;
        let rv2 = d2e_data.rv2;
        let rd_idx = d2e_data.rd_idx;
        let current_id = d2e_data.k_id;

        if (debug && count < maxCount) $display(pc, " [Execute] ", fshow(dInst), fshow(dEpoch));
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

            //if (debug && count < maxCount) $display(pc, "Register Source 1: %d", rv1);
            //if (debug && count < maxCount) $display(pc, "Register Source 2: %d", rv2);
            //if (debug && count < maxCount) $display(pc, "Immediate: %d", imm);

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
                //if (debug && count < maxCount) $display(pc, "Memory address ", addr);
                //if (debug && count < maxCount) $display(pc, "Register Source 2: %d", rv2);
                //if (debug && count < maxCount) $display(pc, "Immediate: %d", imm);
                if (isMMIO(addr)) begin 
                    if (mmio_debug) $display(count, " [Execute] MMIO", fshow(req));
                    toMMIO.enq1(req);
                    if (konata_debug) labelKonataLeft(lfh,current_id, $format(" MMIO ", fshow(req)));
                    mmio = True;
                end else begin 
                    if (konata_debug) labelKonataLeft(lfh,current_id, $format(" MEM ", fshow(req)));
                    toDmem.enq1(req);
                end
                execute_flag[1] <= True;
            end
            else if (isControlInst(dInst)) begin
                    if (konata_debug) labelKonataLeft(lfh,current_id, $format(" Ctrl instr "));
                    data = pc + 4;
                    execute_flag[1] <= True;
            end else begin 
                if (konata_debug) labelKonataLeft(lfh,current_id, $format(" Standard instr "));
                execute_flag[1] <= True;
            end
            let controlResult = execControl32(dInst.inst, rv1, rv2, imm, pc);
            let nextPc = controlResult.nextPC;
            if(ppc != nextPc) begin
                if(debug && count < maxCount) $display("New PC: ", fshow(nextPc));
                mEpoch[0] <= mEpoch[0] + 1;
                program_counter[1] <= nextPc;
            end 
            
            if (konata_debug) labelKonataLeft(lfh,current_id, $format(" ALU output: %x" , data));
            if (debug && count < maxCount) $display(d2e_data.pc, " enqueued.");
            e2w.enq1(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio}, data: data, dinst: dInst, k_id: current_id, pc: pc});
        end else begin 
            if(dInst.valid_rd && rd_idx != 0) begin 
                sb[d2e_data.rd_idx][2] <= False;
            end
            if (konata_debug) squashed_execute.enq(current_id);
        end 
        

    endrule

    rule execute1_flag_setter;
        execute_flag[0] <= False;
    endrule

    rule execute2 if (!starting && execute_flag[2]);
        
        let d2e_data = d2e.first2();
        let dInst = d2e_data.dinst;
        let dEpoch = d2e_data.epoch;
        let pc = d2e_data.pc;
        let ppc = d2e_data.ppc;
        let rv1 = d2e_data.rv1;
        let rv2 = d2e_data.rv2;
        let rd_idx = d2e_data.rd_idx;
        let current_id = d2e_data.k_id;

        if (debug && count < maxCount) $display(pc, " [Execute2] ", fshow(dInst), fshow(dEpoch));
		if (konata_debug) execute2Konata(lfh, current_id);
        //Execute 

        let can_do_two = True;

        if (!isMemoryInst(dInst)) begin
            d2e.deq2();
            doubleExecuteCount <= doubleExecuteCount + 1;
            if (dEpoch == mEpoch[1]) begin 
                
                let imm = getImmediate(dInst);
                Bool mmio = False;
                let data = execALU32(dInst.inst, rv1, rv2, imm, pc);
                let isUnsigned = 0;
                let funct3 = getInstFields(dInst.inst).funct3;
                let size = funct3[1:0];
                let addr = rv1 + imm;
                Bit#(2) offset = addr[1:0];

                //if (debug && count < maxCount) $display(pc, "Register Source 1: %d", rv1);
                //if (debug && count < maxCount) $display(pc, "Register Source 2: %d", rv2);
                //if (debug && count < maxCount) $display(pc, "Immediate: %d", imm);

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
                    //if (debug && count < maxCount) $display(pc, "Memory address ", addr);
                    //if (debug && count < maxCount) $display(pc, "Register Source 2: %d", rv2);
                    //if (debug && count < maxCount) $display(pc, "Immediate: %d", imm);
                    if (isMMIO(addr)) begin 
                        if (mmio_debug) $display(count, " [Execute] MMIO", fshow(req));
                        toMMIO.enq2(req);
                        if (konata_debug) label2KonataLeft(lfh,current_id, $format(" MMIO ", fshow(req)));
                        mmio = True;
                    end else begin 
                        if (konata_debug) label2KonataLeft(lfh,current_id, $format(" MEM ", fshow(req)));
                        toDmem.enq2(req);
                    end
                end
                else if (isControlInst(dInst)) begin
                        if (konata_debug) label2KonataLeft(lfh,current_id, $format(" Ctrl instr "));
                        data = pc + 4;
                end else begin 
                    if (konata_debug) label2KonataLeft(lfh,current_id, $format(" Standard instr "));
                end
                let controlResult = execControl32(dInst.inst, rv1, rv2, imm, pc);
                let nextPc = controlResult.nextPC;
                if(ppc != nextPc) begin
                    if(debug && count < maxCount) $display("New PC: ", fshow(nextPc));
                    mEpoch[1] <= mEpoch[1] + 1;
                    program_counter[2] <= nextPc;
                end 
                
                if (konata_debug) label2KonataLeft(lfh,current_id, $format(" ALU output: %x" , data));
                if (debug && count < maxCount) $display(d2e_data.pc, " enqueued.");
                e2w.enq2(E2W{mem_business: MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio}, data: data, dinst: dInst, k_id: current_id, pc: pc});
            
            end else begin 
                if(dInst.valid_rd && rd_idx != 0) begin 
                    sb[d2e_data.rd_idx][3] <= False;
                end
                if (konata_debug) squashed2_execute.enq(current_id);
            end 
        end

    endrule

    rule writeback if (!starting);
        // TODO
        let ins1 = e2w.first1();
        E2W ins2 = unpack(0);
        let e2w_notEmpty2 = e2w.notEmpty2();
        if (e2w_notEmpty2) ins2 = e2w.first2();
        e2w.deq1();

        totalWritebackCount <= totalWritebackCount + 1;

        if (konata_debug) writebackKonata(lfh,ins1.k_id);
        if (konata_debug) retired.enq(ins1.k_id);

        if(debug && count < maxCount) $display(ins1.pc, " [Writeback]", fshow(ins1.dinst));
        if (!ins1.dinst.legal) begin
			if(debug && count < maxCount) $display("[Writeback] Illegal Inst, Drop and fault: ", fshow(ins1.dinst));
			//program_counter <= 0;	// Fault
	    end

        // if (notMemory(ins1) and notMemory(ins2))
        if(e2w_notEmpty2 && !isMemoryInst(ins1.dinst) && !isMemoryInst(ins2.dinst) ) begin 
            doubleWritebackCount <= doubleWritebackCount + 1;

            if (konata_debug) writeback2Konata(lfh,ins2.k_id);
            if (konata_debug) retired2.enq(ins2.k_id);
            if(debug && count < maxCount) $display(ins2.pc, " [Writeback]", fshow(ins2.dinst));

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

            if(debug && count < maxCount) $display("Mem Inst: ", fshow(resp_1));

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
        

        // Similarly, to register an execute event for an instruction:
	   	//	writebackKonata(lfh,k_id);


	   	// In writeback is also the moment where an instruction retires (there are no more stages)
	   	// Konata requires us to register the event as well using the following: 
		//retired.enq(k_id);
	endrule
		

	// ADMINISTRATION:

    rule administrative_konata_commit1;
		    retired.deq();
		    let f = retired.first();
		    commitKonata(lfh, f, commit_id[0]);
	endrule

    rule administrative_konata_commit2;
		    retired2.deq();
		    let f = retired2.first();
		    commit2Konata(lfh, f, commit_id[1]);
	endrule
		
	rule administrative_konata_flush1;
		    squashed_decode.deq();
		    let f = squashed_decode.first();
		    squashKonata(lfh, f);
	endrule

    rule administrative_konata_flush2;
		    squashed2_decode.deq();
		    let f = squashed2_decode.first();
		    squash2Konata(lfh, f);
	endrule

    rule administrative_konata_flush3;
		    squashed_execute.deq();
		    let f = squashed_execute.first();
		    squashKonata(lfh, f);
	endrule

    rule administrative_konata_flush4;
		    squashed2_execute.deq();
		    let f = squashed2_execute.first();
		    squash2Konata(lfh, f);
	endrule

    rule exexcuteDoublePercents;
        if (count == 1000) begin
            $display("Times in Execute: %d Double Execute: %d", totalExecuteCount, doubleExecuteCount);
        end
    endrule

    rule writebackDoublePercents;
        if (count == 1000) begin
            $display("Times in Writeback: %d Double Writeback: %d", totalWritebackCount, doubleWritebackCount);
        end
    endrule
		
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
		toDmem.deq1();
		return toDmem.first1();
    endmethod
    method Action getDResp(Mem a);
		fromDmem.enq(a);
    endmethod
    method ActionValue#(Mem) getMMIOReq();
		toMMIO.deq1();
		return toMMIO.first1();
    endmethod
    method Action getMMIOResp(Mem a);
		fromMMIO.enq(a);
    endmethod
endmodule
