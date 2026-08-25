package ApbAddrMap;

import Connectable :: *;
import Vector :: *;

import ApbMaster :: *;
import ApbSlave :: *;
import ApbSlaveMux :: *;
import AddrMapDecoder :: *;
import BlueAddrMap :: *;

interface ApbAddrMapTargets_ifc#(numeric type n, numeric type aw, numeric type dw, numeric type uw);
    interface Vector#(n, ApbSlaveFabric_ifc#(aw, dw, uw)) targets;
endinterface

interface ApbAddrMap_ifc#(numeric type n, numeric type aw, numeric type dw, numeric type uw, type internal_ifc);
    interface ApbSlaveFabric_ifc#(aw, dw, uw) slave;
    interface internal_ifc internal;
endinterface

module [Module] create_apb_addr_map#(
    AddrMapCtx_t#(aw, ApbSlaveFabric_ifc#(aw, dw, uw), internal_ifc) ctx
)(ApbAddrMap_ifc#(n, aw, dw, uw, internal_ifc));

    AddrMapWithTargets_ifc#(
        n,
        aw,
        ApbSlaveFabric_ifc#(aw, dw, uw),
        internal_ifc
    ) i_map <- create_addr_map_with_targets(ctx);
    ApbSlaveMux_ifc#(n, aw, dw, uw) i_mux <- mkApbSlaveMux(i_map.decoder.lookup);

    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        mkConnection(i_mux.masters[i], i_map.targets[i]);
    end

    interface slave    = i_mux.slave;
    interface internal = i_map.internal;

endmodule

endpackage
