`timescale 1ns/1ps


module ALU (
    input  [7:0] A,
    input  [7:0] B,
    input  [3:0] Sel,
    output reg [7:0] Out,
    output reg [3:0] Flag
);

reg [8:0] ext9;
reg [15:0] prod16;

always @(*) begin
    Out  = 8'd0;
    Flag = 4'b0000;
    ext9 = 9'd0;
    prod16 = 16'd0;

    case (Sel)
        4'd0: begin
            ext9 = {1'b0, A} + {1'b0, B};
            Out = ext9[7:0];
            Flag[1] = ext9[8];
        end
        4'd1: begin
            ext9 = {1'b0, A} - {1'b0, B};
            Out = ext9[7:0];
            Flag[3] = (A < B) ? 1'b1 : 1'b0;
        end
        4'd2: begin
            prod16 = A * B;
            Out = prod16[7:0];
            Flag[2] = |prod16[15:8];
        end
        4'd3: begin
            if (B == 8'd0) begin
                Out = 8'd0;
                Flag[3] = 1'b1;
            end else begin
                Out = A / B;
            end
        end
        4'd4: begin
            ext9 = ({1'b0, A} << B);
            Out = ext9[7:0];
            Flag[1] = ext9[8];
        end
        4'd5: begin
            ext9 = ({A, 1'b0} >> B);
            Out = ext9[8:1];
            Flag[1] = ext9[0];
        end
        4'd6: Out = A & B;
        4'd7: Out = A | B;
        4'd8: Out = A ^ B;
        4'd9: Out = ~(A ^ B);
        4'd10: Out = ~(A & B);
        4'd11: Out = (A == B) ? 8'd1 : 8'd0;
        4'd12: Out = (A > B)  ? 8'd1 : 8'd0;
        default: Out = 8'd0;
    endcase

    if (Sel <= 4'd12 && Out == 8'd0)
        Flag[0] = 1'b1;
end

endmodule


//
module Serial_Tranceiver #(
    parameter DW = 32
) (
    input wire [DW-1:0] DataIn,
    input wire Sample,
    input wire StartTx,
    input wire Reset,
    input wire Clk,
    input wire ClkTx,
    output reg TxBusy,
    output reg Dout,
    output reg TxDone
);

localparam [1:0] IDLE     = 2'b00;
localparam [1:0] LOAD     = 2'b01;
localparam [1:0] TRANSMIT = 2'b10;

reg [1:0] current_state, next_state;
reg [DW-1:0] internal_reg;
reg [$clog2(DW):0] bit_counter;
reg finish_flag;

always @(posedge Clk or posedge Reset) begin
    if (Reset)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

always @* begin
    next_state = current_state;
    case (current_state)
        IDLE: begin
            if (Sample)
                next_state = LOAD;
            else if (StartTx)
                next_state = TRANSMIT;
        end
        LOAD: next_state = IDLE;
        TRANSMIT: if (finish_flag) next_state = IDLE;
    endcase
end

always @(posedge Clk) begin
    if (Reset) begin
        internal_reg <= {DW{1'b0}};
        TxDone <= 1'b0;
    end else begin
        case (current_state)
            IDLE: TxDone <= 1'b0;
            LOAD: internal_reg <= DataIn;
        endcase
    end
end

always @(posedge ClkTx or posedge Reset) begin
    if (Reset) begin
        Dout <= 1'b0;
        TxBusy <= 1'b0;
        finish_flag <= 1'b0;
        bit_counter <= DW-1;
    end else begin
        case (current_state)
            TRANSMIT: begin
                if (!finish_flag) begin
                    TxBusy <= 1'b1;
                    Dout <= internal_reg[bit_counter];
                    if (bit_counter > 0)
                        bit_counter <= bit_counter - 1;
                    else
                        finish_flag <= 1'b1;
                end else begin
                    TxBusy <= 1'b0;
                    TxDone <= 1'b1;
                    Dout <= 1'b0;
                end
            end
            default: begin
                TxBusy <= 1'b0;
                Dout <= 1'b0;
                TxDone <= 1'b0;
                bit_counter <= DW-1;
                finish_flag <= 1'b0;
            end
        endcase
    end
end

endmodule


//
module Frequency_Divider (
    input  wire       Clk,
    input  wire       Rst,
    input  wire [3:0] Din,
    output wire       ClkOut
);

reg div2;
reg toggle;

always @(posedge Clk or posedge Rst) begin
    if (Rst) begin
        toggle <= 0;
        div2   <= 0;
    end else begin
        toggle <= ~toggle;
        if (toggle)
            div2 <= ~div2;
    end
end

assign ClkOut = (Din[0]) ? Clk : div2;

endmodule

module Memory #(
    parameter WIDTH = 8
)(
    input wire clk,
    input wire reset,
    input wire valid,
    input wire R_W,
    input wire [WIDTH-1:0] addr,
    input wire [31:0] din,
    output reg [31:0] dout
);

reg [31:0] mem [0:(1<<WIDTH)-1];
integer i;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        for (i = 0; i < (1<<WIDTH); i = i + 1)
            mem[i] <= 32'b0;
        dout <= 32'b0;
    end else if (valid) begin
        if (R_W) begin
            mem[addr] <= din;
        end else begin
            dout <= mem[addr];
        end
    end
end

endmodule


//
module Concatenator (
    input wire [7:0] InA,
    input wire [7:0] InB,
    input wire [7:0] InC,
    input wire [3:0] InD,
    input wire [3:0] InE,
    output wire [31:0] Out
);

assign Out = {InE, InD, InC, InB, InA};

endmodule


//
module Controller (
    input  wire Reset,
    input  wire Clk,
    input  wire Active,
    input  wire Mode,
    input  wire ValidCmd,
    input  wire RW,
    input  wire TxDone,
    output reg  AccessMem,
    output reg  RWMem,
    output reg  SampleData,
    output reg  TransferData,
    output reg  Busy
);

localparam S_IDLE        = 3'd0;
localparam S_WRITE_MEM   = 3'd1;
localparam S_READ_MEM    = 3'd2;
localparam S_SAMPLE      = 3'd3;
localparam S_WAIT_READY  = 3'd4;
localparam S_START_XFER  = 3'd5;
localparam S_WAIT_TXDONE = 3'd6;

reg [2:0] state, next_state;

always @(posedge Clk or posedge Reset) begin
    if (Reset)
        state <= S_IDLE;
    else
        state <= next_state;
end

always @* begin
    next_state = state;
    case (state)
        S_IDLE: begin
            if (ValidCmd && Active) begin
                if (Mode) begin
                    if (RW)
                        next_state = S_WRITE_MEM;
                    else
                        next_state = S_READ_MEM;
                end else begin
                    next_state = S_SAMPLE;
                end
            end
        end
        S_WRITE_MEM:   next_state = S_IDLE;
        S_READ_MEM:    next_state = S_IDLE;
        S_SAMPLE:      next_state = S_WAIT_READY;
        S_WAIT_READY: next_state = S_START_XFER;
        S_START_XFER:  next_state = S_WAIT_TXDONE;
        S_WAIT_TXDONE: if (TxDone) next_state = S_IDLE;
    endcase
end

always @(posedge Clk or posedge Reset) begin
    if (Reset) begin
        AccessMem <= 0;
        RWMem <= 0;
        SampleData <= 0;
        TransferData <= 0;
        Busy <= 0;
    end else begin
        AccessMem <= 0;
        RWMem <= 0;
        SampleData   <= 0;
        TransferData <= 0;
        Busy <= 0;

        case (state)
            S_IDLE: begin
                Busy <= 0;
            end
            S_WRITE_MEM: begin
                AccessMem <= 1;
                RWMem <= 1;
                Busy <= 1;
            end
            S_READ_MEM: begin
                AccessMem <= 1;
                RWMem <= 0;
                Busy <= 1;
            end
            S_SAMPLE: begin
                SampleData <= 1;
                Busy <= 1;
            end
            S_WAIT_READY: begin
                Busy <= 1;
            end
            S_START_XFER: begin
                TransferData <= 1;
                Busy <= 1;
            end
            S_WAIT_TXDONE: begin
                Busy <= 1;
            end
        endcase
    end
end

endmodule

module Binary_Calculator(
    input wire Clk,
    input wire Rst,
    input wire ValidCmd,
    input wire Active,
    input wire Mode,
    input wire RW,
    input wire [3:0] DivCtrl,
    input wire [7:0] Addr,
    input wire [31:0] DataIn,
    output wire [31:0] DataOut,
    output wire Dout,
    output wire Busy
);

wire AccessMem;
wire RWMem;
wire SampleData;
wire TransferData;
wire [31:0] dout;
wire [31:0] concat_out;
wire [7:0] alu_out;
wire [3:0] alu_flag;
wire ClkTx;
wire TxDone;
  
reg [31:0] data_reg;
reg [7:0] addr_reg;
reg [7:0] regA;
reg [7:0] regB;
reg [3:0] regSel;
reg current_mode;

//registrul modului curent
always @(posedge Clk or posedge Rst) begin
    if (Rst) begin
        current_mode <= 0;
    end else if (ValidCmd && Active) begin
        current_mode <= Mode;
    end
end

//registre de date si adrese
always @(posedge Clk or posedge Rst) begin
    if (Rst) begin
        data_reg <= 32'd0;
        addr_reg <= 8'd0;
    end else begin
        if (AccessMem) 
            addr_reg <= Addr;
        if (SampleData)
            data_reg <= concat_out;
    end
end

//registrele ALU se actualizeaza in timpul operatiunilor de scriere
always @(posedge Clk or posedge Rst) begin
    if (Rst) begin
        regA <= 8'd0;
        regB <= 8'd0;
        regSel <= 4'd0;
    end else if (AccessMem && RWMem && current_mode) begin
        if (Addr == 8'd0)
            regA <= DataIn[7:0];
        else if (Addr == 8'd1)
            regB <= DataIn[7:0];
        else if (Addr == 8'd2)
            regSel <= DataIn[3:0];
    end
end

  
//module instantiate
ALU alu ( 
    .A(regA),
    .B(regB),
    .Sel(regSel),
    .Out(alu_out),
    .Flag(alu_flag)
);
  
  Serial_Tranceiver #(.DW(32)) serial_tranceiver ( 
    .DataIn(data_reg),
    .Sample(SampleData),
    .StartTx(TransferData),
    .Reset(Rst),
    .Clk(Clk),
    .ClkTx(ClkTx),
    .TxBusy(),
    .Dout(Dout),
    .TxDone(TxDone)
);
  
Frequency_Divider frequency_divider ( 
    .Clk(Clk),
    .Rst(Rst),
    .Din(DivCtrl),
    .ClkOut(ClkTx)
);

Concatenator concatenator ( 
    .InA(alu_out),
    .InB(8'd0),
    .InC(8'd0),
    .InD(alu_flag),
    .InE(4'd0),
    .Out(concat_out)
);

  Memory #(.WIDTH(8)) memory ( 
    .clk(Clk),
    .reset(Rst),
    .valid(AccessMem),
    .R_W(RWMem),
    .addr(Addr),
    .din(DataIn),
    .dout(dout)
);

Controller controller ( 
    .Reset(Rst),
    .Clk(Clk),
    .Active(Active),
    .Mode(Mode),
    .ValidCmd(ValidCmd),
    .RW(RW),
    .TxDone(TxDone),
    .AccessMem(AccessMem),
    .RWMem(RWMem),
    .SampleData(SampleData),
    .TransferData(TransferData),
    .Busy(Busy)
);

//iesirea
assign DataOut = dout;

endmodule