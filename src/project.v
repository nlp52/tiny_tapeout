/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    Top t(
        .clk_input(clk),
        .rst_input(rst_n),

        .ps2_clk_input(ui_in[0]),
        .ps2_data_input(ui_in[1]),
        .display_code_output(uo_out[6:0])

    )
  

  // List all unused inputs to prevent warnings
    wire _unused = &{ena, ui_in[7:2], uio_in[7:0], uio_out[7:0], uo_out[7]};

endmodule


////////////////////////////  SEVEN SEGMENT  /////////////////////////////
module Top (
  input  logic       clk_input,
  input  logic       rst_input,

  input  logic       ps2_clk_input,
  input  logic       ps2_data_input,
  output logic [6:0] display_code_output
);

logic  [6:0]   received_data_wire;
logic          valid_wire;

Ps2DataCollection collector
(
  .clk(clk_input),
  .rst(rst_input),

  .ps2_clk(ps2_clk_input),
  .ps2_data(ps2_data_input),

  .received_data(received_data_wire),
  .valid()
);

LetterToSevenSeg converter(
  .clk(clk_input),
  .valid(valid_wire),
	.received_data(received_data_wire),
  .display_code(display_code_output)
);

endmodule

///////////////////////////////////////////////////////////////////

//========================================================================
// PS2_Data_Collection
//========================================================================

module Ps2DataCollection
(
  input  logic       clk,
  input  logic       rst,

  input  logic       ps2_clk,
  input  logic       ps2_data,

  output logic [7:0] received_data,
  output logic       valid
);

  //FSM STATES
  localparam WAIT_BREAK_CODE	 = 3'h0;
  localparam CHECK_START_BIT     = 3'h1;
  localparam RECIEVE_DATA 		 = 3'h2;
  localparam CHECK_DATA_PARITY   = 3'h3;
  localparam CHECK_DATA_STOP 	 = 3'h4;

  //INTERNAL WIRES
  logic	[3:0]	data_count;
  logic	[7:0]	data_shift_reg;
  logic [2:0]	reg_ps2_clk;
  logic			pos_edge_ps2_clk; 
  logic       break_code_found;			

  //FSM internal states
	logic [2:0] current_state;
	logic [2:0] next_state;

  //FSM
  always_ff @(posedge clk)
  begin
	if (rst)
		current_state <= WAIT_BREAK_CODE;
	else
		current_state <= next_state;
  end

  always_comb
  begin
	case (current_state)
	WAIT_BREAK_CODE:
	    begin 
			if (data_shift_reg == 8'hF0)
				next_state = CHECK_START_BIT; //use wait intstead of start
			else 
				next_state = WAIT_BREAK_CODE;
		end
	CHECK_START_BIT:
		begin
			if ((pos_edge_ps2_clk) && (~ps2_data))
				next_state = RECIEVE_DATA;
			else
				next_state = CHECK_START_BIT;
		end
	RECIEVE_DATA:
		begin
			if ((data_count == 4'h8) && (pos_edge_ps2_clk))
				next_state = CHECK_DATA_PARITY;
			else
			  next_state = RECIEVE_DATA;
		end
	CHECK_DATA_PARITY:
	  begin
			if (pos_edge_ps2_clk && (^data_shift_reg == ps2_data)) //odd partity
				next_state = CHECK_DATA_STOP;
			else if (pos_edge_ps2_clk)
				next_state = WAIT_BREAK_CODE;
			else
				next_state = CHECK_DATA_PARITY;
		end
  CHECK_DATA_STOP:
	  begin
			if ((pos_edge_ps2_clk) && ps2_data)
				next_state = WAIT_BREAK_CODE;
			else
				next_state = CHECK_DATA_STOP;
		end
	default:
		begin
			next_state = WAIT_BREAK_CODE;
		end
	endcase 

end

/*****************************************************************************
 *                             Sequential logic                              *
 *****************************************************************************/

//synchronizing ps2 clk
always_ff @(posedge clk) 
begin
	reg_ps2_clk <= {reg_ps2_clk[1:0], ps2_clk};
end

//data count
always_ff @(posedge clk)
begin
	if (rst == 1'b1)
		data_count	<= 4'h0;
	else if ((current_state == RECIEVE_DATA) && pos_edge_ps2_clk)
		data_count	<= data_count + 4'h1;
	else if (current_state != RECIEVE_DATA)
		data_count	<= 4'h0;
end


always_ff @(posedge clk) begin
    if (rst) begin
        data_shift_reg <= 8'h00;
    end else begin
        if (pos_edge_ps2_clk) begin
            case (current_state)
                WAIT_BREAK_CODE: begin
                    data_shift_reg <= {ps2_data, data_shift_reg[7:1]};
                end
                RECIEVE_DATA: begin
                    if (data_count <4'h8)
                        data_shift_reg <= {ps2_data, data_shift_reg[7:1]};
                end
                // Other states can keep the data_shift_reg unchanged
                default: begin
                    data_shift_reg <= data_shift_reg;
                end
            endcase
        end
    end
end

//setting the valid bit on posedge of clk


logic seen_stop_one;  // Track if we've seen a 1 in stop state

always_ff @(posedge clk) begin
    if (rst == 1'b1) begin
        valid <= 1'b0;
        seen_stop_one <= 1'b0;
    end
    else begin
        // Reset seen_stop_one when leaving stop state
        if (current_state != CHECK_DATA_STOP)
            seen_stop_one <= 1'b0;
            
        // Assert valid only on first cycle we see ps2_data become 1
        if (current_state == CHECK_DATA_STOP && ps2_data == 1'b1 && !valid && !seen_stop_one) begin
            valid <= 1'b1;
            seen_stop_one <= 1'b1;  // Remember we've seen a 1
        end
        else
            valid <= 1'b0;
    end
end


/*****************************************************************************
 *                            Combinational logic                            *
 *****************************************************************************/
 
 assign pos_edge_ps2_clk = (reg_ps2_clk[2:1]==2'b01); //positive edge collection
 assign received_data = data_shift_reg;
//assign valid = current_state == CHECK_DATA_STOP && ps2_data == 1'b1 && !seen_stop_one;

endmodule

//////////////////////////////////////////////////////////////////

module Top (
  input  logic       clk_input,
  input  logic       rst_input,

  input  logic       ps2_clk_input,
  input  logic       ps2_data_input,
  output logic [6:0] display_code_output
);

logic  [6:0]   received_data_wire;
logic          valid_wire;



Ps2DataCollection collector
(
  .clk(clk_input),
  .rst(rst_input),

  .ps2_clk(ps2_clk_input),
  .ps2_data(ps2_data_input),

  .received_data(received_data_wire),
  .valid()
);

LetterToSevenSeg converter(
  .clk(clk_input),
  .valid(valid_wire),
	.received_data(received_data_wire),
  .display_code(display_code_output)
);

endmodule


