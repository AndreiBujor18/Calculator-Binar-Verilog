`timescale 1ns/1ps

module Binary_Calculator_tb;
  reg Clk;
  reg Rst;
    
  reg ValidCmd;
  reg Active;
  reg Mode;
  reg RW;
  reg [3:0] DivCtrl;
    
  reg [7:0] Addr;
  reg [31:0] DataIn;
  wire [31:0] DataOut;
    
  wire Dout;
  wire Busy;

  Binary_Calculator dut (
    .Clk(Clk),
    .Rst(Rst),
    .ValidCmd(ValidCmd),
    .Active(Active),
    .Mode(Mode),
    .RW(RW),
    .DivCtrl(DivCtrl),
    .Addr(Addr),
    .DataIn(DataIn),
    .DataOut(DataOut),
    .Dout(Dout),
     .Busy(Busy)
  );

  initial begin
    Clk = 0;
    forever #5 Clk = ~Clk;
  end

  initial begin
    Rst = 1;
    ValidCmd = 0;
    Active = 0;
    Mode = 0;
    RW = 0;
    DivCtrl = 4'b0000;
    Addr = 0;
    DataIn = 0;
        
    $dumpfile("wave.vcd");
    $dumpvars(0, Binary_Calculator_tb);

    #20;
    Rst = 0;
    #20;

    //frequency divider bypass mode
    DivCtrl = 4'b0001;
    #100;
    $display("\nFrequency Divider Bypass Mode: ClkOut = Clk");
    $display("Cand DivCtrl[0]=1, ClkOut ar trb sa urmareasca Clk direct");

    //memory and ALU operations
    $display("Memory write operations");
    write_mem(0, 8);//scrie a
    write_mem(1, 2);//b
    write_mem(2, 0);//add

    $display("\nMemory Read operations");
    read_mem(0);//citesta a
    read_mem(1);//b
    read_mem(2);//sel

    $display("\nALU operatii verificare");
    $display("Expected: 8 + 2 = 10");
    #40;
    $display("ALU Result: OUT = %d, FLAG = %4b", dut.alu.Out, dut.alu.Flag);

    $display("\nSerial transfer");
    start_serial_transfer();
    wait_for_busy(0);
    $display("Transfer completed\n");

    //teste
    $display("ALU operatii:");
    test_alu(6, 7, 0, "ADD: 6 + 7 = 13");
    test_alu(12, 3, 1, "SUB: 12 - 3 = 9");
    test_alu(3, 6, 2, "MUL: 3 * 6 = 18");
    test_alu(15, 3, 3, "DIV: 15 / 3 = 5");
    test_alu(10, 1, 4, "SHL: 1010 << 1 = 0100");
    test_alu(10, 1, 5, "SHR: 1010 >> 1 = 0101");
    test_alu(4, 2, 6, "AND: 4 & 2 = 0");
    test_alu(5, 3, 7, "OR: 5 | 3 = 7");
    test_alu(5, 3, 8, "XOR: 5 ^ 3 = 6");
    test_alu(5, 5, 11, "CMP_EQ: 5 == 5 = 1");
    test_alu(10, 5, 12, "CMP_GT: 10 > 5 = 1");
        
    //la limita
    test_alu(255, 1, 0, "ADD overflow: 255 + 1 = 0 (Carry)");
    test_alu(0, 0, 1, "SUB: 0 - 0 = 0");
    test_alu(16, 0, 3, "DIV by zero: Error flag");
    test_alu(128, 1, 5, "SHR: 128 >> 1 = 64");

    $finish;
  end

    task write_mem;
        input [7:0] address;
        input [31:0] value;
        begin
            @(negedge Clk);
            Mode = 1;
            RW = 1;
            ValidCmd = 1;
            Active = 1;
            Addr = address;
            DataIn = value;
            @(posedge Clk);
            #1 ValidCmd = 0;
            Active = 0;
            wait_for_busy(0);
            #20;
          $display("Write: Addr=%h, Data=%h", address, value);
        end
    endtask

    task read_mem;
        input [7:0] address;
        begin
            @(negedge Clk);
            Mode = 1;
            RW = 0;
            ValidCmd = 1;
            Active = 1;
            Addr = address;
            @(posedge Clk);
            #1 ValidCmd = 0;
            Active = 0;
            wait_for_busy(0);
            #20;
          $display("Read: Addr=%h, Data=%h", address, DataOut);
        end
    endtask

    task start_serial_transfer;
        begin
            @(negedge Clk);
            Mode = 0;
            ValidCmd = 1;
            Active = 1;
            RW = 0;
            @(posedge Clk);
            #1 ValidCmd = 0;
            Active = 0;
            $display("Starting serial transfer...");
        end
    endtask

    task wait_for_busy;
        input expected;
        integer timeout;
        begin
            timeout = 0;
            while (Busy !== expected) begin
                @(posedge Clk);
                timeout = timeout + 1;
                if (timeout > 2000) begin
                    $display("[ERROR] Timeout waiting for Busy=%b", expected);
                    $finish;
                end
            end
        end
    endtask

    task test_alu;
        input [7:0] a;
        input [7:0] b;
        input [3:0] op;
        input [80:0] op_name;
        begin
            write_mem(0, a);
            write_mem(1, b);
            write_mem(2, op);
            #40;
            $display("%s", op_name);
            $display("Result: OUT=%0d (0x%h), FLAG=%4b", 
                     dut.alu.Out, dut.alu.Out, dut.alu.Flag);
            start_serial_transfer();
            wait_for_busy(0);
            #20;
        end
    endtask

endmodule