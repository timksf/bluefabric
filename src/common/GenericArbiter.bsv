package GenericArbiter;

(* always_ready, always_enabled *)
interface GenericArbiter_ifc#(numeric type n);
    (* prefix = "" *) 
    method Action prequest((* port = "request" *) Bit#(n) request);
    (* prefix = "" *) 
    method Action padvance((* port = "advance" *) Bool advance);
    method Bit#(n) grant;
endinterface

/*
 * Round-robin selection with transaction ownership. A new grant is selected
 * combinationally and then retained until the caller advances the arbiter
 * after the granted transaction has completed.
 */
module mkGenericArbiter(GenericArbiter_ifc#(n))
    provisos(
        Add#(1, nminone_, n)
    );

    //round robin pointer
    Reg#(Bit#(TLog#(n))) rg_next_requester <- mkReg(0);
    Reg#(Bit#(n))        rg_grant          <- mkReg(0);

    Wire#(Bit#(n)) w_request    <- mkBypassWire;
    Wire#(Bool)    w_advance    <- mkBypassWire;

    function Bit#(TLog#(n)) add_wrapped_requester(Bit#(TLog#(n)) base, Integer offset);
        Bit#(TAdd#(TLog#(n), 1)) sum = zeroExtend(base) + fromInteger(offset);
        if(sum >= fromInteger(valueof(n)))
            sum = sum - fromInteger(valueof(n));
        return truncate(sum);
    endfunction

    function Bit#(TLog#(n)) next_requester(Bit#(TLog#(n)) requester);
        return requester == fromInteger(valueof(n) - 1) ? 0 : requester + 1;
    endfunction

    //look for first active request starting from offset
    function Bit#(n) select_request(Bit#(n) request, Bit#(TLog#(n)) start);
        Maybe#(Bit#(TLog#(n))) selected = tagged Invalid;

        for(Integer offset = 0; offset < valueof(n); offset = offset + 1) begin
            let requester = add_wrapped_requester(start, offset);
            if(!isValid(selected) && request[requester] == 1)
                selected = tagged Valid requester;
        end

        Bit#(n) result = 0;
        if(selected matches tagged Valid .requester)
            result[requester] = 1;
        return result;
    endfunction

    Bit#(n) candidate_request = select_request(w_request, rg_next_requester);
    Bit#(n) selected_request  = rg_grant != 0 ? rg_grant : candidate_request;

    rule r_update_grant;
        if(w_advance && selected_request != 0) begin
            Bit#(TLog#(n)) next = rg_next_requester;
            rg_grant <= 0;
            for(Integer i = 0; i < valueof(n); i = i + 1) begin
                if(selected_request[i] == 1)
                    next = next_requester(fromInteger(i));
            end
            rg_next_requester <= next;
        end else if(rg_grant == 0 && selected_request != 0) begin
            rg_grant <= selected_request;
        end
    endrule

    method Action prequest(Bit#(n) request);
        w_request <= request;
    endmethod

    method Action padvance(Bool advance);
        w_advance <= advance;
    endmethod

    method Bit#(n) grant = selected_request;

endmodule

endpackage
