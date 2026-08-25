package TestApb;

import GetPut :: *;

import Apb :: *;
import ApbMaster :: *;
import ApbSlave :: *;

interface TestApbSlave_ifc;
    (* prefix = "S_APB" *)
    interface ApbSlaveFabric_ifc#(16, 32, 4) s_apb;
endinterface

interface TestApbMaster_ifc;
    (* prefix = "M_APB" *)
    interface ApbMasterFabric_ifc#(16, 32, 4) m_apb;

    (* always_ready *) method Bool done;
    (* always_ready *) method Bit#(8) errors;
endinterface

module mkTestApbSlaveWith#(Bool register_request)(TestApbSlave_ifc);
    ApbSlave_ifc#(16, 32, 4) i_slave <- mkApbSlave(register_request);

    rule r_respond;
        let request <- i_slave.request.get;
        i_slave.response.put(ApbResponse_t {
            read_data    : zeroExtend(request.address) ^ request.write_data,
            slave_error  : request.address[4] == 1,
            read_user    : request.address_user,
            response_user: request.write_user
        });
    endrule

    interface s_apb = i_slave.fabric;
endmodule

(* synthesize *)
module mkTestApbSlave(TestApbSlave_ifc);
    let i_dut <- mkTestApbSlaveWith(True);
    return i_dut;
endmodule

(* synthesize *)
module mkTestApbSlaveBypass(TestApbSlave_ifc);
    let i_dut <- mkTestApbSlaveWith(False);
    return i_dut;
endmodule

(* synthesize *)
module mkTestApbMaster(TestApbMaster_ifc);
    ApbMaster_ifc#(16, 32, 4) i_master <- mkApbMaster(2);

    Reg#(Bit#(4)) rg_issued   <- mkReg(0);
    Reg#(Bit#(4)) rg_received <- mkReg(0);
    Reg#(Bit#(8)) rg_errors   <- mkReg(0);

    rule r_issue (rg_issued < 8);
        i_master.request.put(ApbRequest_t {
            address      : 16'h0100 + (zeroExtend(rg_issued) << 2),
            write        : rg_issued[0] == 1,
            write_data   : 32'hA5000000 | zeroExtend(rg_issued),
            write_strobe : 4'hF,
            protection   : truncate(rg_issued),
            address_user : rg_issued,
            write_user   : rg_issued + 1
        });
        rg_issued <= rg_issued + 1;
    endrule

    rule r_check_response;
        let response <- i_master.response.get;
        let expected_data = 32'h55000000 | zeroExtend(rg_received);
        let expected_error = rg_received == 3;
        let expected_read_user = rg_received + 1;
        let expected_response_user = rg_received + 2;

        if(response.read_data != expected_data ||
                response.slave_error != expected_error ||
                response.read_user != expected_read_user ||
                response.response_user != expected_response_user)
            rg_errors <= rg_errors + 1;

        rg_received <= rg_received + 1;
    endrule

    method Bool done = rg_received == 8;
    method Bit#(8) errors = rg_errors;

    interface m_apb = i_master.fabric;
endmodule

endpackage
