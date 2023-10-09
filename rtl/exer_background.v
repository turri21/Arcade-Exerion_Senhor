module exer_background(
	input RESET_n,
	input clk_sys,
	input clk_cpuf,	
	input clk2_6MHZ,
	input clk3_3MHZ,
	input clk3_3MHZn,
	

	
	input rSSEL,
	input nVDSP,
	input SNHI,
	input r2UP,
	input nr2UP,
	input [3:0] pixH,
	input [7:0] Z80A_IO2,
	
	input [24:0] dn_addr,
	input 		 dn_wr,
	input [7:0]  dn_data,
	input ep1_cs_i,
	input ep2_cs_i,
	input ep3_cs_i,
	input ep4_cs_i,	
	input ep6_cs_i,			//background layer program ROM
	
	output [3:0] ZC
);


wire [15:0] Z80B_addrbus;
reg [7:0] Z80B_databus_in;
wire [7:0] Z80B_databus_out;
wire [7:0] bg_prom_prog2_out;
wire [7:0] U4V_Z80B_RAM_out;

wire Z80B_MREQ,Z80B_WR,Z80B_RD;
wire SLSE;
reg [1:0] S0,S1,S2,S3;

assign SLSE = clk2_6MHZ|rSSEL; 

//Second Z80 CPU responsible for rendering the background graphic layers
T80pa Z80B(
	.RESET_n(RESET_n),
	.WAIT_n(1'b1),
	.INT_n(1'b1),
	.BUSRQ_n(1'b1),
	.NMI_n(1'b1),
	.CLK(clk_cpuf), 
	.CEN_p(clk3_3MHZ), 
	.CEN_n(clk3_3MHZn), 
	
	//.CLK_n(clk3_3MHZ), //clk3_3MHZ
	.MREQ_n(Z80B_MREQ),
	.DI(Z80B_databus_in),
	.DO(Z80B_databus_out),
	.A(Z80B_addrbus),
	.WR_n(Z80B_WR),
	.RD_n(Z80B_RD)
);

//CPUB (background layer) address decoder
reg BG_PROM,BG_RAM,BG_IO2,BG_BUS,BG_VDSP;
always @(*) begin
	BG_PROM	 = (Z80B_addrbus[15:13] == 3'b000)	? 1'b0 : 1'b1; //0000 - 1FFF - Background Program ROM
	BG_RAM	 = (Z80B_addrbus[15:13] == 3'b010)	? 1'b0 : 1'b1; //4000 - 5FFF - Background Program RAM
	BG_IO2	 = (Z80B_addrbus[15:13] == 3'b011)	? 1'b0 : 1'b1; //6000 - 7FFF - IO
	BG_BUS	 = (Z80B_addrbus[15:13] == 3'b100)	? 1'b0 : 1'b1; //8000 - 9FFF - 
	BG_VDSP   = (Z80B_addrbus[15:13] == 3'b101)	? 1'b0 : 1'b1; //A000 - BFFF - 
end

// **Z80B********* SECOND CPU IC SELECTION LOGIC FOR BACKGROUND GRAPHICS *****************

always @(posedge clk_sys) begin
			Z80B_databus_in <= 	(!BG_PROM & !Z80B_MREQ) 				? bg_prom_prog2_out:
										(!Z80B_RD & !BG_RAM)    				? U4V_Z80B_RAM_out:
										(!Z80B_RD & !BG_IO2)   					? Z80A_IO2:
										(!Z80B_RD & !BG_VDSP)					? ({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,nVDSP,SNHI}):
																						8'b00000000;
end
																						
eprom_6 prom_prog2 //background layer program ROM
(
	.ADDR(Z80B_addrbus[12:0]),//
	.CLK(clk_sys),//
	.DATA(bg_prom_prog2_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clk_sys),//
	.DATA_IN(dn_data),
	.CS_DL(ep6_cs_i),
	.WR(dn_wr)
);

reg [11:0] SLD;
reg CDCK;

always @(*) begin
	 if (!SLSE) begin
		case (U7V_q[3:0])
		  4'b0000: {CDCK,SLD[11:0]}=13'b1111111111110; //0x8000
		  4'b0001: {CDCK,SLD[11:0]}=13'b1111111111101; //0x8001
		  4'b0010: {CDCK,SLD[11:0]}=13'b1111111111011; //0x8002
		  4'b0011: {CDCK,SLD[11:0]}=13'b1111111110111; //0x8003
		  4'b0100: {CDCK,SLD[11:0]}=13'b1111111101111; //0x8004
		  4'b0101: {CDCK,SLD[11:0]}=13'b1111111011111; //0x8005
		  4'b0110: {CDCK,SLD[11:0]}=13'b1111110111111; //0x8006
		  4'b0111: {CDCK,SLD[11:0]}=13'b1111101111111; //0x8007
		  4'b1000: {CDCK,SLD[11:0]}=13'b1111011111111; //0x8008
		  4'b1001: {CDCK,SLD[11:0]}=13'b1110111111111; //0x8009
		  4'b1010: {CDCK,SLD[11:0]}=13'b1101111111111; //0x800A
		  4'b1011: {CDCK,SLD[11:0]}=13'b1011111111111; //0x800B
		  4'b1100: {CDCK,SLD[11:0]}=13'b0111111111111; //0x800C
		  default: {CDCK,SLD[11:0]}=13'b1111111111111; //0x800D-0x800F
		endcase
	 end
	 else begin
		{CDCK,SLD[11:0]}= 13'b1111111111111;
	 end
end

reg [7:0] U3K_Q; //background scene selection
always @(posedge CDCK) U3K_Q<=BGRAM_out; //U3K

wire [3:0] U4KJ_Q;

prom6301_4KJ U4KJ(
	.addr({U3K_Q[3:0],|S3,|S2,|S1,|S0}),
	.clk(clk_sys),
	.n_cs(1'b0), 
	.q(U4KJ_Q)
);

reg [1:0] U4ML;
wire u4ML_EN;

ttl_7474 #(.BLOCKS(1), .DELAY_RISE(0), .DELAY_FALL(0)) U8T_B(
	.n_pre(1'b1),
	.n_clr(~nVDSP),
	.d(1'b1),
	.clk(SNHI),
	.q(),
	.n_q(u4ML_EN)
);

always @(*) begin
   if (u4ML_EN) 
        U4ML  <= 2'b00;
	else
		case (U4KJ_Q[1:0])
			2'b00: U4ML <= S0;
			2'b01: U4ML <= S1;
			2'b10: U4ML <= S2;
			2'b11: U4ML <= S3;
		endcase
end



wire [7:0] BGRAM_out;


m6116_ram U4V_Z80B_RAM( 	//Background Z80B CPU work RAM
	.data(Z80B_databus_out),
	.addr({Z80B_addrbus[10:0]}),
	.cen(1'b1),
	.clk(clk_sys),
	.nWE(Z80B_WR | BG_RAM), //write to main CPU work RAM
	.q(U4V_Z80B_RAM_out)
);

reg [3:0] U7V_q;
always @(*)	U7V_q 	<= (rSSEL) ? {Z80B_addrbus[3:0]} : {pixH[3:0]};	

eprom_1 bg_gfx4B
(
	.ADDR({BG4BaddrH[7:0],BG4BaddrL[6:2]}),//
	.CLK(clk_sys),		//
	.CEN(BG4BaddrL[7]),
	.DATA(bg_gfx4B_out),	//
	.ADDR_DL(dn_addr),
	.CLK_DL(clk_sys),	//
	.DATA_IN(dn_data),
	.CS_DL(ep1_cs_i),
	.WR(dn_wr)
);

eprom_2 bg_gfx4D
(
	.ADDR({BG4DaddrH[7:0],BG4DaddrL[6:2]}),//
	.CLK(clk_sys),//
	.CEN(BG4DaddrL[7]),	
	.DATA(bg_gfx4D_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clk_sys),//
	.DATA_IN(dn_data),
	.CS_DL(ep2_cs_i),
	.WR(dn_wr)
);

eprom_3 bg_gfx4E
(
	.ADDR({BG4EaddrH[7:0],BG4EaddrL[6:2]}),//
	.CLK(clk_sys),//
	.CEN(BG4EaddrL[7]),	//!BG4EaddrL[7]
	.DATA(bg_gfx4E_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clk_sys),//
	.DATA_IN(dn_data),
	.CS_DL(ep3_cs_i),
	.WR(dn_wr)
);

eprom_4 bg_gfx4H
(
	.ADDR({BG4HaddrH[7:0],BG4HaddrL[6:2]}),//
	.CLK(clk_sys),//
	.CEN(BG4HaddrL[7]),	 //
	.DATA(bg_gfx4H_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clk_sys),//
	.DATA_IN(dn_data),
	.CS_DL(ep4_cs_i),
	.WR(dn_wr)
);

reg [7:0] U5B_out,U5D_out,U5E_out,U5H_out;

wire L4B_clk1,L4B_clk2;
wire L4D_clk1,L4D_clk2;
wire L4E_clk1,L4E_clk2;
wire L4H_clk1,L4H_clk2;

assign L4B_clk1 = (nr2UP^BG4BaddrL[4]);
assign L4B_clk2 = (nr2UP^BG4BaddrL[1]);
assign L4D_clk1 = (nr2UP^BG4DaddrL[4]);
assign L4D_clk2 = (nr2UP^BG4DaddrL[1]);
assign L4E_clk1 = (nr2UP^BG4EaddrL[4]);
assign L4E_clk2 = (nr2UP^BG4EaddrL[1]);
assign L4H_clk1 = (nr2UP^BG4HaddrL[4]);
assign L4H_clk2 = (nr2UP^BG4HaddrL[1]);

always @(posedge L4B_clk2) U5B_out<=bg_gfx4B_out; 
always @(posedge L4D_clk2) U5D_out<=bg_gfx4D_out;  
always @(posedge L4E_clk2) U5E_out<=bg_gfx4E_out; 
always @(posedge L4H_clk2) U5H_out<=bg_gfx4H_out;

//display background layer graphics when ena_ signals are high
wire ena_4B,ena_4D,ena_4E,ena_4H;
 
async_preset_counter L8(
    .clk1(L4B_clk1),      			// Clock input
	 .clk2(L4B_clk2),      			// Clock input
    .load(!SLD[8]),     			// Async load input to preset the counter
    .preset_value(BGRAM_out), 	// 5-bit preset value
    .ena_bg(ena_4B)
);

async_preset_counter L9(
    .clk1(L4D_clk1),      			// Clock input
    .clk2(L4D_clk2),      			// Clock input	 
    .load(!SLD[9]),     			// Async load input to preset the counter
    .preset_value(BGRAM_out), 	// 5-bit preset value
    .ena_bg(ena_4D)
);

async_preset_counter L10(
    .clk1(L4E_clk1),      			// Clock input
    .clk2(L4E_clk2),      			// Clock input	 
    .load(!SLD[10]),     			// Async load input to preset the counter
    .preset_value(BGRAM_out), 	// 5-bit preset value
    .ena_bg(ena_4E)
);

async_preset_counter L11(
    .clk1(L4H_clk1),      			// Clock input
    .clk2(L4H_clk2),      			// Clock input	 
    .load(!SLD[11]),     			// Async load input to preset the counter
    .preset_value(BGRAM_out), 	// 5-bit preset value
    .ena_bg(ena_4H)
);



always @(*) begin
   if (ena_4B) 
        {S0}  <= 2'b00;
	else
		case (BG4BaddrL[1:0])
			2'b00: {S0} <= {U5B_out[4],U5B_out[0]};
			2'b01: {S0} <= {U5B_out[5],U5B_out[1]};
			2'b10: {S0} <= {U5B_out[6],U5B_out[2]};
			2'b11: {S0} <= {U5B_out[7],U5B_out[3]};
		endcase
end

always @(*) begin //U5C
   if (ena_4D) 
        {S1}  <= 2'b00;
	else
		case (BG4DaddrL[1:0])
			2'b00: {S1} <= {U5D_out[4],U5D_out[0]};
			2'b01: {S1} <= {U5D_out[5],U5D_out[1]};
			2'b10: {S1} <= {U5D_out[6],U5D_out[2]};
			2'b11: {S1} <= {U5D_out[7],U5D_out[3]};
		endcase
end

always @(*) begin //U5F
   if (ena_4E)
        {S2}  <= 2'b00;
	else
		case (BG4EaddrL[1:0])
			2'b00: {S2} <= {U5E_out[4],U5E_out[0]};
			2'b01: {S2} <= {U5E_out[5],U5E_out[1]};
			2'b10: {S2} <= {U5E_out[6],U5E_out[2]};
			2'b11: {S2} <= {U5E_out[7],U5E_out[3]};
		endcase
end

always @(*) begin //U5J
   if (ena_4H)
        {S3}  <= 2'b00;
	else
		case (BG4HaddrL[1:0])
			2'b00: {S3} <= {U5H_out[4],U5H_out[0]};
			2'b01: {S3} <= {U5H_out[5],U5H_out[1]};
			2'b10: {S3} <= {U5H_out[6],U5H_out[2]};
			2'b11: {S3} <= {U5H_out[7],U5H_out[3]};
		endcase
end
//************************* BACKGROUND LAYER SECTIONS ************************
wire [7:0] bg_gfx4B_out,bg_gfx4D_out,bg_gfx4E_out,bg_gfx4H_out;
reg  [7:0] BG4BaddrL,BG4BaddrH,BG4DaddrL,BG4DaddrH,BG4EaddrL,BG4EaddrH,BG4HaddrL,BG4HaddrH;
reg  [7:0] BG4BaddrL_base,BG4DaddrL_base,BG4EaddrL_base,BG4HaddrL_base;

always @(negedge SLD[1]) BG4BaddrH <= BGRAM_out;
always @(negedge SLD[3]) BG4DaddrH <= BGRAM_out;
always @(negedge SLD[5]) BG4EaddrH <= BGRAM_out;
always @(negedge SLD[7]) BG4HaddrH <= BGRAM_out;

always @(posedge SLD[0]) BG4BaddrL_base <= BGRAM_out;
always @(posedge SLD[2]) BG4DaddrL_base <= BGRAM_out;
always @(posedge SLD[4]) BG4EaddrL_base <= BGRAM_out;
always @(posedge SLD[6]) BG4HaddrL_base <= BGRAM_out;

always @(posedge clk2_6MHZ) begin
	BG4BaddrL <= (rSSEL) ?   (r2UP) ? BG4BaddrL-8'd1 : BG4BaddrL+8'd1 : BG4BaddrL_base;
	BG4DaddrL <= (rSSEL) ?   (r2UP) ? BG4DaddrL-8'd1 : BG4DaddrL+8'd1 : BG4DaddrL_base;
	BG4EaddrL <= (rSSEL) ?   (r2UP) ? BG4EaddrL-8'd1 : BG4EaddrL+8'd1 : BG4EaddrL_base;
	BG4HaddrL <= (rSSEL) ?   (r2UP) ? BG4HaddrL-8'd1 : BG4HaddrL+8'd1 : BG4HaddrL_base;
end

ls89_ram_x2 U6UT_BG_RAM(
	.data(Z80B_databus_out),
	.addr(U7V_q),
	.clk(clk_sys),
	.nWE(Z80B_WR | BG_BUS), //write background scratch ram
	.q(BGRAM_out)
);

//background layer output
prom6301_3L U3L(
	.addr({U3K_Q[7:4],U4KJ_Q[1:0],U4ML[1:0]}),
	.clk(clk_sys),  ///clk_sys
	.n_cs(1'b0), 
	.q(ZC)
);

endmodule
