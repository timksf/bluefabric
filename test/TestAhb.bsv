package TestAhb;

import Connectable :: *;
import GetPut :: *;

import Ahb :: *;
import AhbMaster :: *;
import AhbSlave :: *;

interface TestAhbSlave_ifc;
    (* prefix = "S_AHB" *)
    interface AhbSlaveFabric_ifc#(16, 32) s_ahb;
endinterface

interface TestAhbMaster_ifc;
    (* prefix = "M_AHB" *)
    interface AhbMasterFabric_ifc#(16, 32) m_ahb;

    (* always_ready *) method Bool done;
    (* always_ready *) method Bit#(8) errors;
endinterface

module mkTestAhbSlaveWith#(Bool pipeline_request)(TestAhbSlave_ifc);
    AhbSlave_ifc#(16, 32) i_slave <- mkAhbSlave(pipeline_request);

    rule r_respond;
        let request <- i_slave.request.get;
        i_slave.response.put(AhbResponse_t {
            read_data   : zeroExtend(request.address) ^ request.write_data,
            slave_error : request.address[4] == 1
        });
    endrule

    interface s_ahb = i_slave.fabric;
endmodule

(* synthesize *)
module mkTestAhbSlave(TestAhbSlave_ifc);
    let i_dut <- mkTestAhbSlaveWith(True);
    return i_dut;
endmodule

(* synthesize *)
module mkTestAhbSlaveBypass(TestAhbSlave_ifc);
    let i_dut <- mkTestAhbSlaveWith(False);
    return i_dut;
endmodule

(* synthesize *)
module mkTestAhbMaster(TestAhbMaster_ifc);
    AhbMaster_ifc#(16, 32) i_master <- mkAhbMaster(4);

    Reg#(Bit#(4)) rg_issued   <- mkReg(0);
    Reg#(Bit#(4)) rg_received <- mkReg(0);
    Reg#(Bit#(8)) rg_errors   <- mkReg(0);
    Reg#(Bool)    rg_paused   <- mkReg(False);

    AhbRequest_t#(16, 32) next_request = AhbRequest_t {
        address    : 16'h0100 + (zeroExtend(rg_issued) << 2),
        write      : rg_issued[0] == 1,
        write_data : 32'hA5000000 | zeroExtend(rg_issued),
        size       : AHB_WORD,
        protection : unpack(rg_issued),
        lock       : rg_issued == 5
    };

    rule r_pause_burst if(rg_issued == 4 && !rg_paused);
        rg_paused <= True;
    endrule

    rule r_issue_single if(
        rg_issued < 8 &&
        (rg_issued < 2 || rg_issued >= 6)
    );
        i_master.request.put(ahb_single_request(next_request));
        rg_issued <= rg_issued + 1;
    endrule

    rule r_issue_burst if(
        rg_issued >= 2 && rg_issued < 6 &&
        (rg_issued != 4 || rg_paused)
    );
        i_master.request.put(AhbMasterRequest_t {
            request : next_request,
            burst   : AHB_INCR4,
            last    : rg_issued == 5
        });
        rg_issued <= rg_issued + 1;
    endrule

    rule r_check_response;
        let response <- i_master.response.get;
        let expected_data = 32'h55000000 | zeroExtend(rg_received);
        let expected_error = rg_received == 3;

        Bool read_data_error = rg_received[0] == 0 &&
            response.read_data != expected_data;

        if(read_data_error || response.slave_error != expected_error)
            rg_errors <= rg_errors + 1;

        rg_received <= rg_received + 1;
    endrule

    method Bool done = rg_received == 8;
    method Bit#(8) errors = rg_errors;

    interface m_ahb = i_master.fabric;
endmodule

(* synthesize *)
module mkTestAhbConnection(Empty);
    AhbMaster_ifc#(16, 32) i_master <- mkAhbMaster(2);
    AhbSlave_ifc#(16, 32) i_slave <- mkAhbSlave(True);
    mkConnection(i_master.fabric, i_slave.fabric);
endmodule

endpackage
