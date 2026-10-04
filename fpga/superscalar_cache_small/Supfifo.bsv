import FIFOF::*;
import SpecialFIFOs::*;
import Ehr::*;
import Vector::*;

interface SupFifo#(type t);
    method Action enq1(t x);
    method Action enq2(t x);
    method Action deq1;
    method Action deq2;
    method t first1;
    method t first2;
    method Bool notEmpty2;
endinterface

module mkSupFifo(SupFifo#(t)) provisos (Bits#(t,tSz), Eq#(t));
    Ehr#(2, Bit#(1)) enqueueFifo <- mkEhr(unpack(0));
    Ehr#(2, Bit#(1)) dequeueFifo <- mkEhr(unpack(0));

    Vector#(2, FIFOF#(t)) internalFifos <- replicateM(mkFIFOF);

    Bit#(1) fifoIdxEnq1 = enqueueFifo[0];
    Bit#(1) fifoIdxEnq2 = enqueueFifo[0] + 1;
    Bool can_enq1 = internalFifos[fifoIdxEnq1].notFull;
    Bool can_enq2 = internalFifos[fifoIdxEnq2].notFull;
    
    Bit#(1) fifoIdxDeq1 = dequeueFifo[0];
    Bit#(1) fifoIdxDeq2 = dequeueFifo[0] + 1;
    Bool can_deq1 = internalFifos[fifoIdxDeq1].notEmpty;
    Bool can_deq2 = internalFifos[fifoIdxDeq2].notEmpty;

    Ehr#(2, Maybe#(t)) want_enq1 <- mkEhr(tagged Invalid);
    Ehr#(2, Maybe#(t)) want_enq2 <- mkEhr(tagged Invalid);
    Ehr#(2, Bool) want_deq1 <- mkEhr(False);
    Ehr#(2, Bool) want_deq2 <- mkEhr(False);

    rule canonicalize;
        if (want_enq1[1] matches tagged Valid .el) begin
            enqueueFifo[0] <= enqueueFifo[0]+1;
            internalFifos[fifoIdxEnq1].enq(el);
        end
        if (want_deq1[1]) begin
            dequeueFifo[0] <= dequeueFifo[0] + 1;
            internalFifos[fifoIdxDeq1].deq;
        end
        want_enq1[1] <= tagged Invalid;
        want_deq1[1] <= False;
  
        if (want_enq2[1] matches tagged Valid .el) begin
            enqueueFifo[1] <= enqueueFifo[1]+1;
            internalFifos[fifoIdxEnq2].enq(el);
        end
        if (want_deq2[1]) begin
            dequeueFifo[1] <= dequeueFifo[1] + 1;
            internalFifos[fifoIdxDeq2].deq;
        end
        want_enq2[1] <= tagged Invalid;
        want_deq2[1] <= False;
    endrule

    method Action enq1(t x) if (want_enq1[0] == tagged Invalid && can_enq1);
        want_enq1[0] <= Valid(x);
	endmethod

    method Action enq2(t x) if (want_enq2[0] == tagged Invalid && can_enq2);
        want_enq2[0] <= Valid(x);
    endmethod


    method t first1();
        return internalFifos[fifoIdxDeq1].first;
    endmethod

    method t first2();
        return internalFifos[fifoIdxDeq2].first;
    endmethod

    method Bool notEmpty2();
        return can_deq2;
    endmethod

    method Action deq1 if(can_deq1 && !want_deq1[0]);
        want_deq1[0] <= True;
    endmethod

    method Action deq2 if(can_deq2 && !want_deq2[0]);
        want_deq2[0] <= True;
    endmethod
endmodule

module mkBypassSupFifo(SupFifo#(t)) provisos (Bits#(t,tSz), Eq#(t));
    // TODO: This was barely tested
    Ehr#(2, Bit#(1)) enqueueFifo <- mkEhr(unpack(0));
    Ehr#(2, Bit#(1)) dequeueFifo <- mkEhr(unpack(0));

    Vector#(2, FIFOF#(t)) internalFifos <- replicateM(mkUGFIFOF);

    Bit#(1) fifoIdxEnq1 = enqueueFifo[0];
    Bit#(1) fifoIdxEnq2 = enqueueFifo[0] + 1;
    Bool can_enq1 = internalFifos[fifoIdxEnq1].notFull;
    Bool can_enq2 = internalFifos[fifoIdxEnq2].notFull;
    
    Bit#(1) fifoIdxDeq1 = dequeueFifo[0];
    Bit#(1) fifoIdxDeq2 = dequeueFifo[0] + 1;
    Bool can_deq1 = internalFifos[fifoIdxDeq1].notEmpty;
    Bool can_deq2 = internalFifos[fifoIdxDeq2].notEmpty;

    Ehr#(2, Maybe#(t)) want_enq1 <- mkEhr(tagged Invalid);
    Ehr#(2, Maybe#(t)) want_enq2 <- mkEhr(tagged Invalid);
    Ehr#(2, Bool) want_deq1 <- mkEhr(False);
    Ehr#(2, Bool) want_deq2 <- mkEhr(False);

    (* fire_when_enabled, no_implicit_conditions *)
    rule canonicalize;
        if (want_enq1[1] matches tagged Valid .el) begin
            enqueueFifo[0] <= enqueueFifo[0]+1;
            internalFifos[fifoIdxEnq1].enq(el);
        end
        if (want_deq1[1]) begin
            dequeueFifo[0] <= dequeueFifo[0] + 1;
            internalFifos[fifoIdxDeq1].deq;
        end
        want_enq1[1] <= tagged Invalid;
        want_deq1[1] <= False;
  
        if (want_enq2[1] matches tagged Valid .el) begin
            enqueueFifo[1] <= enqueueFifo[1]+1;
            internalFifos[fifoIdxEnq2].enq(el);
        end
        if (want_deq2[1]) begin
            dequeueFifo[1] <= dequeueFifo[1] + 1;
            internalFifos[fifoIdxDeq2].deq;
        end
        want_enq2[1] <= tagged Invalid;
        want_deq2[1] <= False;
    endrule

    method Action enq1(t x) if (want_enq1[0] == tagged Invalid && can_enq1);
        want_enq1[0] <= Valid(x);
	endmethod

    method Action enq2(t x) if (want_enq2[0] == tagged Invalid && can_enq2);
        want_enq2[0] <= Valid(x);
    endmethod


    method t first1() if ((can_deq1 || want_enq1[1] != tagged Invalid));
        if (can_deq1) return internalFifos[fifoIdxDeq1].first;
        else begin if (want_enq1[1] matches tagged Valid .x) return x;
        else return ?;
    end
    endmethod

    method t first2() if ((can_deq2 || want_enq2[1] != tagged Invalid) || (!can_deq2 && can_deq1 && want_enq1[1] != tagged Invalid));
        if (can_deq2) return internalFifos[fifoIdxDeq2].first;
        else begin 
            if (can_deq1 && !can_deq2 &&& want_enq1[1] matches tagged Valid .x) return x;
            else begin
                if (want_enq2[1] matches tagged Valid .x) return x;
                else return ?;
            end
        end
    endmethod

    method Bool notEmpty2();
        return can_deq2;
    endmethod

    method Action deq1 if((want_enq1[1] != tagged Invalid || can_deq1) && !want_deq1[0] );
        want_deq1[0] <= True;
    endmethod

    method Action deq2 if((want_enq2[1] != tagged Invalid || can_deq2 || (!can_deq2 && can_deq1 && want_enq1[1] != tagged Invalid)) && !want_deq2[0]);
        want_deq2[0] <= True;
    endmethod
endmodule

