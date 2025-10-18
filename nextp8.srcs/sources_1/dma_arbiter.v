//==============================================================
// dma_arbiter.v
//
// Pulse-based DMA arbiter with fixed priority and burst support
//
// Copyright (C) 2025 Chris January
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//==============================================================
`timescale 1ns/1ps
`default_nettype wire

module dma_arbiter #(
    parameter NUM_MANAGERS = 2,          // Number of DMA managers (clients)
    parameter ADDR_WIDTH = 31            // DMA address width (word address)
) (
    input wire clk,
    input wire resetn,
    
    // Manager interfaces (pulse-based requests)
    // Concatenated: {mgr[N-1], ..., mgr[1], mgr[0]}
    input  wire [NUM_MANAGERS*ADDR_WIDTH-1:0] mgr_dma_addr,  // DMA addresses from managers (concatenated)
    input  wire [NUM_MANAGERS-1:0]            mgr_dma_req,   // DMA request pulses from managers
    output reg  [NUM_MANAGERS-1:0]            mgr_dma_ack,   // DMA acknowledge pulses to managers
    
    // Subordinate interface (aggregated output)
    output reg [ADDR_WIDTH-1:0]  sub_dma_addr,   // Aggregated DMA address to subordinate
    output reg                   sub_dma_req,    // Aggregated DMA request to subordinate
    input  wire                  sub_dma_ack     // DMA acknowledge from subordinate
);

    // Latched requests from each manager (capture pulses until serviced)
    reg [ADDR_WIDTH-1:0] mgr_dma_addr_latched [0:NUM_MANAGERS-1];
    reg                  mgr_dma_req_latched  [0:NUM_MANAGERS-1];
    
    // Arbiter state
    localparam OWNER_WIDTH = $clog2(NUM_MANAGERS);
    reg [OWNER_WIDTH-1:0] dma_owner;      // Current owner (0 to NUM_MANAGERS-1)
    reg                   dma_pending;    // DMA request in progress (waiting for ack)
    
    integer i;
    
    //==============================================================
    // Latch DMA request pulses from all managers
    //==============================================================
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (i = 0; i < NUM_MANAGERS; i = i + 1) begin
                mgr_dma_req_latched[i] <= 1'b0;
                mgr_dma_addr_latched[i] <= {ADDR_WIDTH{1'b0}};
            end
        end else begin
            for (i = 0; i < NUM_MANAGERS; i = i + 1) begin
                // Latch request when it pulses
                if (mgr_dma_req[i]) begin
                    mgr_dma_req_latched[i] <= 1'b1;
                    // Extract address for manager i from concatenated input
                    mgr_dma_addr_latched[i] <= mgr_dma_addr[i*ADDR_WIDTH +: ADDR_WIDTH];
                end 
                // Clear when arbiter picks it up (owned and not pending)
                else if (mgr_dma_req_latched[i] && (dma_owner == i)) begin
                    mgr_dma_req_latched[i] <= 1'b0;
                end
            end
        end
    end
    
    //==============================================================
    // DMA arbiter FSM
    //==============================================================
    integer j;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            dma_owner <= {OWNER_WIDTH{1'b0}};
            sub_dma_addr <= {ADDR_WIDTH{1'b0}};
            sub_dma_req <= 1'b0;
            dma_pending <= 1'b0;
            for (j = 0; j < NUM_MANAGERS; j = j + 1) begin
                mgr_dma_ack[j] <= 1'b0;
            end
        end else begin
            // Clear ack pulses by default
            for (j = 0; j < NUM_MANAGERS; j = j + 1) begin
                mgr_dma_ack[j] <= 1'b0;
            end
            
            // Owner has the bus
            if (mgr_dma_req_latched[dma_owner]) begin
                // New request from current owner - capture address and pulse req
                sub_dma_addr <= mgr_dma_addr_latched[dma_owner];
                sub_dma_req <= 1'b1;
                dma_pending <= 1'b1;
            end else if (dma_pending) begin
                // Waiting for ack - clear pulse but stay as owner
                sub_dma_req <= 1'b0;
                if (sub_dma_ack) begin
                    // Ack received
                    mgr_dma_ack[dma_owner] <= 1'b1;
                    dma_pending <= 1'b0;
                end
            end else begin
                // No pending request and no new pulse - see if any other manager needs service
                sub_dma_req <= 1'b0;
                dma_pending <= 1'b0;
                // Priority arbitration: check managers in order
                for (j = NUM_MANAGERS - 1; j >= 0; j = j - 1) begin
                    if (mgr_dma_req_latched[j]) begin
                        dma_owner <= j[OWNER_WIDTH-1:0];
                    end
                end
            end
        end
    end

endmodule
