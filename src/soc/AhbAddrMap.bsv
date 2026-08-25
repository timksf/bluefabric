package AhbAddrMap;

import Connectable :: *;
import Vector :: *;

import AhbMaster :: *;
import AhbSlave :: *;
import AhbSlaveMux :: *;
import AddrMapDecoder :: *;
import BlueAddrMap :: *;

interface AhbAddrMapTargets_ifc#(numeric type n, numeric type aw, numeric type dw);
    interface Vector#(n, AhbSlaveFabric_ifc#(aw, dw)) targets;
endinterface

interface AhbAddrMap_ifc#(numeric type n, numeric type aw, numeric type dw, type internal_ifc);
    interface AhbSlaveFabric_ifc#(aw, dw) slave;
    interface internal_ifc internal;
endinterface

module [Module] create_ahb_addr_map#(
    AddrMapCtx_t#(aw, AhbSlaveFabric_ifc#(aw, dw), internal_ifc) ctx
)(AhbAddrMap_ifc#(n, aw, dw, internal_ifc));

    AddrMapWithTargets_ifc#(
        n,
        aw,
        AhbSlaveFabric_ifc#(aw, dw),
        internal_ifc
    ) i_map <- create_addr_map_with_targets(ctx);
    AhbSlaveMux_ifc#(n, aw, dw) i_mux <- mkAhbSlaveMux(i_map.decoder.lookup);

    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        mkConnection(i_mux.masters[i], i_map.targets[i]);
    end

    interface slave    = i_mux.slave;
    interface internal = i_map.internal;

endmodule

endpackage
