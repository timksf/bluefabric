package AddrMapDecoder;

typedef struct {
    Bool     hit;
    Bit#(aw) target_index;
    Bit#(aw) global_addr;
    Bit#(aw) offset;
} AddrMapHit_t#(numeric type aw) deriving(Bits, Eq, FShow);

interface AddrMapDecoder_ifc#(numeric type aw);
    (* always_ready *)
    method AddrMapHit_t#(aw) lookup(Bit#(aw) address, Bit#(aw) bytes);
endinterface

(* always_ready, always_enabled *)
interface AddrMapDecoderFab_ifc#(numeric type aw);
    (* prefix = "" *)
    method Action decode(
        (* port = "address" *) Bit#(aw) address,
        (* port = "bytes" *) Bit#(aw) bytes
    );

    method Bool hit;
    method Bit#(aw) target_index;
    method Bit#(aw) global_addr;
    method Bit#(aw) offset;
endinterface

module mkAddrMapDecoderFab#(
    AddrMapDecoder_ifc#(aw) decoder
)(AddrMapDecoderFab_ifc#(aw));

    Wire#(AddrMapHit_t#(aw)) w_result <- mkDWire(unpack(0));

    method Action decode(Bit#(aw) address, Bit#(aw) bytes);
        w_result <= decoder.lookup(address, bytes);
    endmethod

    method hit          = w_result.hit;
    method target_index = w_result.target_index;
    method global_addr  = w_result.global_addr;
    method offset       = w_result.offset;

endmodule

endpackage
