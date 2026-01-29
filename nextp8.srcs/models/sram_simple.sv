// Simple SRAM model for testbenches
// Parameterized memory with 68K boot vector validation

module sram_simple #(
    parameter ADDR_WIDTH = 21,
    parameter DATA_WIDTH = 16,
    parameter MEM_FILE = "memory.mem"  // Memory initialization file
) (
    input  wire                       read_en_i,
    input  wire                       write_en_i,
    input  wire [ADDR_WIDTH-1:0]      addr_i,
    input  wire                       lb_i,
    input  wire                       ub_i,
    input  wire [DATA_WIDTH-1:0]      data_in_i,
    output reg  [DATA_WIDTH-1:0]      data_out_o
);

    // Declare the memory array
    reg [DATA_WIDTH-1:0] mem [2**ADDR_WIDTH-1:0];

    // Behavioral model for read and write
    always @(posedge write_en_i) begin
        // Write operation
        if (lb_i)
            mem[addr_i][7:0] <= data_in_i[7:0];
        if (ub_i)
            mem[addr_i][15:8] <= data_in_i[15:8];
    end

    // Read operation (combinational)
    always @(*) begin
        if (read_en_i && ~write_en_i) begin
            data_out_o = mem[addr_i];
        end else begin
            data_out_o = 'bz; // High impedance
        end
    end

    integer i;
    integer mem_fd;
    initial begin
        // Initialize memory to zero
        for (i=0; i<(2**ADDR_WIDTH); i=i+1) begin
            mem[i] = 16'h0000;
        end
        
        // Load ROM from .mem file
        $display("Loading %s...", MEM_FILE);
        mem_fd = $fopen(MEM_FILE, "r");
        if (mem_fd == 0) begin
            $fatal(1, "[SRAM] ERROR: Memory init file %s not found; aborting simulation", MEM_FILE);
        end
        $fclose(mem_fd);
        $readmemh(MEM_FILE, mem);
        $display("ROM loaded");
        
        // ROM sanity checks (68K boot vector validation)
        begin
            reg [31:0] initial_sp, initial_pc;
            reg [15:0] code_at_pc;
            
            initial_sp = {mem[0], mem[1]};  // First 32-bit word: initial SP
            initial_pc = {mem[2], mem[3]};  // Second 32-bit word: initial PC
            
            if (initial_sp == 32'h0) begin
                $fatal(1, "[SRAM] ERROR: ROM validation failed - Initial SP is zero");
            end
            if (initial_pc == 32'h0) begin
                $fatal(1, "[SRAM] ERROR: ROM validation failed - Initial PC is zero");
            end
            if (initial_pc >= initial_sp) begin
                $fatal(1, "[SRAM] ERROR: ROM validation failed - Initial PC (0x%08x) >= Initial SP (0x%08x)", initial_pc, initial_sp);
            end
            
            // Check that there's actual code at the PC address (word-addressed)
            code_at_pc = mem[initial_pc[20:1]];
            if (code_at_pc == 16'h0) begin
                $fatal(1, "[SRAM] ERROR: ROM validation failed - Code at PC (0x%08x) is zero", initial_pc);
            end
            
            $display("[SRAM] ROM validation passed: SP=0x%08x PC=0x%08x Code@PC=0x%04x", initial_sp, initial_pc, code_at_pc);
        end
    end

endmodule
