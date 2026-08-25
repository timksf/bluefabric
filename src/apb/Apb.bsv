package Apb;

/*
 * Transaction records include the APB4 protection and byte-strobe signals.
 * The user fields map directly to the optional APB5 PAUSER/PWUSER and
 * PRUSER/PBUSER signals; user_w may be zero when those signals are omitted.
 */
typedef struct {
    Bit#(addr_w)               address;
    Bool                       write;
    Bit#(data_w)               write_data;
    Bit#(TDiv#(data_w, 8))     write_strobe;
    Bit#(3)                    protection;
    Bit#(user_w)               address_user;
    Bit#(user_w)               write_user;
} ApbRequest_t#(
    numeric type addr_w,
    numeric type data_w,
    numeric type user_w
) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(data_w) read_data;
    Bool         slave_error;
    Bit#(user_w) read_user;
    Bit#(user_w) response_user;
} ApbResponse_t#(
    numeric type data_w,
    numeric type user_w
) deriving(Bits, Eq, FShow);

endpackage
