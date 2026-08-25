package Ahb;

typedef enum {
    AHB_BYTE,
    AHB_HALFWORD,
    AHB_WORD,
    AHB_DOUBLEWORD,
    AHB_4_WORD_LINE,
    AHB_8_WORD_LINE,
    AHB_512_BITS,
    AHB_1024_BITS
} AhbSize_t deriving(Bits, Eq, FShow);

typedef enum {
    AHB_OPCODE_FETCH,
    AHB_DATA_ACCESS
} AhbAccess_t deriving(Bits, Eq, FShow);

typedef enum {
    AHB_USER_ACCESS,
    AHB_PRIVILEGED_ACCESS
} AhbPrivilege_t deriving(Bits, Eq, FShow);

typedef enum {
    AHB_NON_BUFFERABLE,
    AHB_BUFFERABLE
} AhbBufferability_t deriving(Bits, Eq, FShow);

typedef enum {
    AHB_NON_CACHEABLE,
    AHB_CACHEABLE
} AhbCacheability_t deriving(Bits, Eq, FShow);

typedef struct {
    AhbCacheability_t cacheability;
    AhbBufferability_t bufferability;
    AhbPrivilege_t    privilege;
    AhbAccess_t       access;
} AhbProtection_t deriving(Bits, Eq, FShow);

function AhbProtection_t ahb_protection(
    AhbAccess_t access,
    AhbPrivilege_t privilege,
    AhbBufferability_t bufferability,
    AhbCacheability_t cacheability
);
    return AhbProtection_t {
        cacheability : cacheability,
        bufferability: bufferability,
        privilege    : privilege,
        access       : access
    };
endfunction

typedef struct {
    Bit#(aw)        address;
    Bool            write;
    Bit#(dw)        write_data;
    AhbSize_t       size;
    AhbProtection_t protection;
    Bool            lock;
} AhbRequest_t#(numeric type aw, numeric type dw) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(dw) read_data;
    Bool     slave_error;
} AhbResponse_t#(numeric type dw) deriving(Bits, Eq, FShow);

typedef enum {
    AHB_IDLE,
    AHB_BUSY,
    AHB_NONSEQ,
    AHB_SEQ
} AhbTransfer_t deriving(Bits, Eq, FShow);

typedef enum {
    AHB_SINGLE,
    AHB_INCR,
    AHB_WRAP4,
    AHB_INCR4,
    AHB_WRAP8,
    AHB_INCR8,
    AHB_WRAP16,
    AHB_INCR16
} AhbBurst_t deriving(Bits, Eq, FShow);

typedef struct {
    AhbRequest_t#(aw, dw)   request;
    AhbBurst_t              burst;
    Bool                    last;
} AhbMasterRequest_t#(numeric type aw, numeric type dw) deriving(Bits, Eq, FShow);

function AhbMasterRequest_t#(aw, dw) ahb_single_request(AhbRequest_t#(aw, dw) request);
    return AhbMasterRequest_t {
        request : request,
        burst   : AHB_SINGLE,
        last    : True
    };
endfunction

typedef struct {
    AhbRequest_t#(aw, dw) request;
    AhbTransfer_t         transfer;
    AhbBurst_t            burst;
} AhbTransferRequest_t#(numeric type aw, numeric type dw) deriving(Bits, Eq, FShow);

function Bit#(aw) ahb_next_burst_address(Bit#(aw) address, AhbSize_t size, AhbBurst_t burst);
    Bit#(aw) increment = 1 << pack(size);
    Bit#(aw) wrap_mask = 0;

    case(burst)
        AHB_WRAP4:  wrap_mask = (increment << 2) - 1;
        AHB_WRAP8:  wrap_mask = (increment << 3) - 1;
        AHB_WRAP16: wrap_mask = (increment << 4) - 1;
        default:    wrap_mask = 0;
    endcase

    Bit#(aw) next_address = address + increment;
    return wrap_mask == 0 ? next_address : (address & ~wrap_mask) | (next_address & wrap_mask);
endfunction

endpackage
