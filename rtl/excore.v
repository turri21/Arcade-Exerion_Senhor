//============================================================================
//  Arcade: Exerion
//
//  Manufaturer: Jaleco 
//  Type: Arcade Game
//  Genre: Shooter
//  Orientation: Vertical
//
//  Hardware Description by Anton Gale
//  https://github.com/antongale/EXERION
//
//============================================================================
`timescale 1ns/1ps

module exerion_fpga(
	input clk_sys,
	input	clkaudio,
	output [2:0] RED,     	//from fpga core to sv
	output [2:0] GREEN,		//from fpga core to sv
	output [1:0] BLUE,		//from fpga core to sv
	output core_pix_clk,		//from fpga core to sv	
	output H_SYNC,				//from fpga core to sv
	output V_SYNC,				//from fpga core to sv
	output H_BLANK,
	output V_BLANK,
	input RESET_n,				//from sv to core, check implementation
	input pause,
	input [8:0] CONTROLS,	
	input [7:0] DIP1,
	input [7:0] DIP2,
	input [24:0] dn_addr,
	input 		 dn_wr,
	input [7:0]  dn_data,
	output [15:0] audio_l,  //from jt49_1 .sound
	output [15:0] audio_r,  //from jt49_2 .sound
	input [15:0] hs_address,
	output [7:0] hs_data_out,
	input [7:0] hs_data_in,
	input hs_write
);

//pixel counters
reg [8:0] pixH = 9'b000000000;
reg [7:0] pixV = 8'b00000000;

reg [8:0] rpixelbusH;
reg [7:0] rpixelbusV;
wire [10:0] vramaddr;
wire RAMA_WR,RAMB_WR; 

wire 	[7:0] u6k_data; //foreground character ROM output data
reg 	[7:0] u7K_data;
reg 	[7:0] vramdata0out;
wire 	[7:0] U6N_VRAM_Q;

wire clk1_10MHZ,clk2_6MHZ,clk2_6AMHZ,clk3_3MHZ;

wire PUR = 1'b1;
wire SSEL;


wire [7:0] U9R_Q;

wire [15:0] Z80A_addrbus;
wire [7:0] Z80A_databus_in;
wire [7:0] Z80A_databus_out;

wire [15:0] Z80B_addrbus;
wire [7:0] Z80B_databus_in;
wire [7:0] Z80B_databus_out;

//SLAPFIGHT CLOCKS
reg clkf_cpu, maincpuclk_6M, aucpuclk_3M, aucpuclk_3Mb, ayclk_1p66;
reg clk_6M_1,pixel_clk,clk_6M_3;
//core clock generation logic based on jtframe code
reg [4:0] cen40cnt =5'd0;

wire clkm_20MHZ=clk_sys;

always @(posedge clk_sys) begin
	cen40cnt  <= cen40cnt+5'd1;
end

always @(posedge clk_sys) begin

   //clkm_20MHZ 		<= cen40cnt[0] == 1'd0;		
end

//core clock generation logic based on jtframe code
reg [4:0] cencnt =5'd0;

always @(posedge clkaudio) begin
	cencnt  <= cencnt+5'd1;
end

always @(posedge clkaudio) begin

   ayclk_1p66 		<= cencnt[4:0] == 5'd0;		
end

//clocks
wire U2A_Aq,U2A_Anq,U2A_Aqi;
wire U2A_Bq,U2A_Bnq,U2A_Bqi;
wire U2B_Aq,U2B_Anq,U2B_Aqi;
wire U2B_Bq,U2B_Bnq,U2B_Bqi;

ls107 U2A_B(
   .clear(PUR), 
   .clk(clkm_20MHZ), 
   .j(U2A_Anq|!PUR), 
   .k(U2A_Anq|!PUR), 
   .q(U2A_Bq), 
   .qnot(U2A_Bnq),
	.q_immediate(U2A_Bqi)
);

ls107 U2A_A(
   .clear(PUR), 
   .clk(clkm_20MHZ), 
   .j(U2A_Bq), 
   .k(PUR), 
   .q(U2A_Aq), 
   .qnot(U2A_Anq),
	.q_immediate(U2A_Aqi)
);

ls107 U2B_B(
   .clear(PUR), 
   .clk(clkm_20MHZ), 
   .j(U2A_Aq), 
   .k(U2A_Aq), 
   .q(U2B_Bq), 
   .qnot(U2B_Bnq),
	.q_immediate(U2B_Bqi)
);

ls107 U2B_A(
   .clear(PUR), 
   .clk(clkm_20MHZ), 
   .j(PUR), 
   .k(PUR), 
   .q(U2B_Aq), 
   .qnot(U2B_Anq),
	.q_immediate(U2B_Aqi)
);

buf (clk1_10MHZ,U2B_Aq);  	//10MHz Clock
not (clk2_6MHZ,U2A_Aq);		//6.66Mhz Clock
buf (clk3_3MHZ,U2B_Bnq);	//3.33Mhz Clock

wire Z80_MREQ,Z80_WR,Z80_RD;
wire Z80B_MREQ,Z80B_WR,Z80B_RD;
reg Z80_DO_En;

//coin input
wire nCOIN;

assign core_pix_clk=clk2_6MHZ;

//coin
ttl_7474 #(.BLOCKS(1), .DELAY_RISE(0), .DELAY_FALL(0)) U1D_A (
	.n_pre(PUR),
	.n_clr(PUR),
	.d(!m_coin),
	.clk(nVDSP),
	.q(),
	.n_q(nCOIN)
);

//First Z80 CPU responsible for main game logic, sound, sprites
T80as Z80A(
	.RESET_n(RESET_n),
	.WAIT_n(wait_n),
	.INT_n(PUR),
	.BUSRQ_n(PUR),
	.NMI_n(PUR&nCOIN), //+1 coin
	.CLK_n(clk3_3MHZ),
	.MREQ_n(Z80_MREQ),
	.DI(Z80A_databus_in),
	.DO(Z80A_databus_out),
	.A(Z80A_addrbus),
	.WR_n(Z80_WR),
	.RD_n(Z80_RD)
);

//Second Z80 CPU responsible for rendering the background graphic layers
T80as Z80B(
	.RESET_n(RESET_n),
	.WAIT_n(PUR),
	.INT_n(PUR),
	.BUSRQ_n(PUR),
	.NMI_n(PUR),
	.CLK_n(clk3_3MHZ), //clk3_3MHZ
	.MREQ_n(Z80B_MREQ),
	.DI(Z80B_databus_in),
	.DO(Z80B_databus_out),
	.A(Z80B_addrbus),
	.WR_n(Z80B_WR),
	.RD_n(Z80B_RD)
);

wire [3:0] U3RB_Q;

//joystick inputs from MiSTer framework
wire m_coin   		= CONTROLS[8];
									
wire ZA_ROM, ZA_RAM, RAMA, RAMB, IN1, IN2, IN3, IO1, IO2, AY1, AY2;
assign ZA_ROM 	= ((Z80A_addrbus[15:13] == 3'b000)|(Z80A_addrbus[15:13] == 3'b001)|(Z80A_addrbus[15:13] == 3'b010))	
																				? 1'b0 : 1'b1; //0000 - 5FFF - Main Program ROM
assign ZA_RAM 	= (Z80A_addrbus[15:13] == 3'b011)				? 1'b0 : 1'b1; //6000 - 7FFF - Main Program ROM
assign RAMA		= (Z80A_addrbus[15:11] == 5'b10000)				? 1'b0 : 1'b1; //8000 - 87FF
assign RAMB		= (Z80A_addrbus[15:11] == 5'b10001)				? 1'b0 : 1'b1; //8800 - 8FFF
assign IN1	  	= (Z80A_addrbus[15:11] == 5'b10100)				? 1'b0 : 1'b1; //A000
assign IN2	  	= (Z80A_addrbus[15:11] == 5'b10101)				? 1'b0 : 1'b1; //A800
assign IN3	  	= (Z80A_addrbus[15:11] == 5'b10110)				? 1'b0 : 1'b1; //B000
assign IO1	  	= (Z80A_addrbus[15:11] == 5'b11000)				? 1'b0 : 1'b1; //c000 (Write Only)
assign IO2	  	= (Z80A_addrbus[15:11] == 5'b11001)				? 1'b0 : 1'b1; //c800 (Write Only)
assign AY1		= (Z80A_addrbus[15:11] == 5'b11010)				? 1'b0 : 1'b1; //D000 - D001
assign AY2		= (Z80A_addrbus[15:11] == 5'b11011)				? 1'b0 : 1'b1; //D800 - D801

//sound chip selection logic
reg IOA0,IOA1,IOA2,IOA3;
always @(*) begin
	IOA0 <= !(Z80A_addrbus[0]|AY1);
	IOA1 <= !(Z80A_addrbus[1]|AY1);
	IOA2 <= !(Z80A_addrbus[0]|AY2);
	IOA3 <= !(Z80A_addrbus[1]|AY2);
end

assign RAMA_WR = RAMA|Z80_WR;
assign RAMB_WR = RAMB|Z80_WR;

//CPU data bus read selection logic
// **Z80A* PRIMARY CPU IC SELECTION LOGIC FOR TILE, SPRITE, SOUND & GAME EXECUTION ********
assign Z80A_databus_in = 	(!ZA_ROM&!Z80_MREQ)	? 	prom_prog1_out :
									(!ZA_RAM & !Z80_RD)  ? 	U4N_Z80A_RAM_out :
									(!Z80_RD & !RAMA)		?  U6N_VRAM_Q : 		//VRAM
									(!Z80_RD & !RAMB)		?  rSPRITE_databus : //U11SR_SPRAM_Q
									(!Z80_RD & !IN1)		?	(CONTROLS[7:0]) :	//JOYSTICK 1 & 2 - ST2, ST1,    FIRB,FIRA,LF,  RG,  DN,  UP
									(!Z80_RD & !IN2)		?	DIP1 :						
									(!Z80_RD & !IN3)		?	{1'b0,1'b0,1'b0,1'b0,DIP2[1],DIP2[0],DIP2[2],nVDSP} :
									(!IOA1 & IOA0)			? 	AY_12F_databus_out :
									(!IOA3 & IOA2)			? 	AY_12V_databus_out :
																8'b00000000;
									
// **Z80B********* SECOND CPU IC SELECTION LOGIC FOR BACKGROUND GRAPHICS *****************
assign	Z80B_databus_in = 	(!BG_PROM & !Z80B_MREQ) 				? bg_prom_prog2_out:
										(!Z80B_RD & !BG_RAM)    				? U4V_Z80B_RAM_out:
										(!Z80B_RD & !BG_IO2)   					? Z80A_IO2:
										(!Z80B_RD & !BG_VDSP)					? ({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,nVDSP,SNHI}):
																						8'b00000000;

wire wait_n = !pause;
wire SLSE;

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
	.clk(clkm_20MHZ),
	.n_cs(1'b0), 
	.q(U4KJ_Q)
);

reg [1:0] U4ML;

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
//background layer output
prom6301_3L U3L(
	.addr({U3K_Q[7:4],U4KJ_Q[1:0],U4ML[1:0]}),
	.clk(clkm_20MHZ),  ///clkm_20MHZ
	.n_cs(1'b0), 
	.q(ZC)
);

//CPUB (background layer) external I/O chip selects
wire BG_PROM,BG_RAM,BG_IO2,BG_BUS,BG_VDSP;

assign BG_PROM	 = (Z80B_addrbus[15:13] == 3'b000)	? 1'b0 : 1'b1; //0000 - 1FFF - Background Program ROM
assign BG_RAM	 = (Z80B_addrbus[15:13] == 3'b010)	? 1'b0 : 1'b1; //4000 - 5FFF - Background Program RAM
assign BG_IO2	 = (Z80B_addrbus[15:13] == 3'b011)	? 1'b0 : 1'b1; //6000 - 7FFF - IO
assign BG_BUS	 = (Z80B_addrbus[15:13] == 3'b100)	? 1'b0 : 1'b1; //8000 - 9FFF - 
assign BG_VDSP  = (Z80B_addrbus[15:13] == 3'b101)	? 1'b0 : 1'b1; //A000 - BFFF - 

wire [7:0] BGRAM_out;

//Background Z80B CPU work RAM
m6116_ram U4V_Z80B_RAM(
	.data(Z80B_databus_out),
	.addr({Z80B_addrbus[10:0]}),
	.cen(1'b1),
	.clk(clkm_20MHZ),
	.nWE(Z80B_WR | BG_RAM), //write to main CPU work RAM
	.q(U4V_Z80B_RAM_out)
);

//Z80A CPU main program program ROM
eprom_8 prom_prog1
(
	.ADDR(Z80A_addrbus[14:0]),//
	.CLK(clkm_20MHZ),//
	.DATA(prom_prog1_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clkm_20MHZ),//
	.DATA_IN(dn_data),
	.CS_DL(ep8_cs_i),
	.WR(dn_wr)
);

wire [7:0] prom_prog1_out;
wire [7:0] prom_prog2_out;
wire [7:0] bg_prom_prog2_out;
wire [7:0] U4N_Z80A_RAM_out;
wire [7:0] U4V_Z80B_RAM_out;

//background layer program ROM
eprom_6 prom_prog2
(
	.ADDR(Z80B_addrbus[12:0]),//
	.CLK(clkm_20MHZ),//
	.DATA(bg_prom_prog2_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clkm_20MHZ),//
	.DATA_IN(dn_data),
	.CS_DL(ep6_cs_i),
	.WR(dn_wr)
);

//main CPU (Z80A) work RAM - dual port RAM for hi-score logic
dpram_dc #(.widthad_a(11)) U4N_Z80A_RAM
(
	.clock_a(clkm_20MHZ),
	.address_a(Z80A_addrbus[10:0]),
	.data_a(Z80A_databus_out),
	.wren_a(!Z80_WR & !ZA_RAM),
	.q_a(U4N_Z80A_RAM_out),
	
	.clock_b(clkm_20MHZ),
	.address_b(hs_address[10:0]),
	.data_b(hs_data_in),
	.wren_b(hs_write),
	.q_b(hs_data_out)
);

ls138x U9R( 
  .nE1(~pixH[8]), 
  .nE2(~pixH[8]), 
  .E3(pixH[7]), 
  .A(pixH[6:4]), 
  .Y(U9R_Q) //U9R_Q4, U9R_Q5
);

wire u4ML_EN;

ttl_7474 #(.BLOCKS(1), .DELAY_RISE(0), .DELAY_FALL(0)) U8T_B(
	.n_pre(PUR),
	.n_clr(~nVDSP),
	.d(PUR),
	.clk(SNHI),
	.q(),
	.n_q(u4ML_EN)
);

wire SNHI = ((pixH[8:6]==3'b111)&!nVDSP) ? 1'b0 : 1'b1;

//VRAM
m6116_ram U6N_VRAM(
	.data(Z80A_databus_out),
	.addr(vramaddr),
	.clk(clkm_20MHZ),
	.cen(1'b1),
	.nWE(RAMA_WR),
	.q(U6N_VRAM_Q)
);	

always @(negedge pixH[2]) vramdata0out<=U6N_VRAM_Q;

//foreground character ROM
eprom_7 u6k
(
	.ADDR({char_ROMA12,vramdata0out[7:4],rpixelbusV[2:0],vramdata0out[3:0],rpixelbusH[2]}),//
	.CLK(clkm_20MHZ),//
	.DATA(u6k_data),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clkm_20MHZ),//
	.DATA_IN(dn_data),
	.CS_DL(ep7_cs_i),
	.WR(dn_wr)
);

//wire npix1=~pixH[1];

reg [3:0] U7L;
reg [1:0] U8K;

always @(negedge pixH[1]) begin
	u7K_data <= u6k_data ;
	U7L <= vramdata0out[7:4];
end

always @(*) begin //U5J
	case (rpixelbusH[1:0])
		2'b00: U8K <= {u7K_data[4],u7K_data[0]};
		2'b01: U8K <= {u7K_data[5],u7K_data[1]};
		2'b10: U8K <= {u7K_data[6],u7K_data[2]};
		2'b11: U8K <= {u7K_data[7],u7K_data[3]};
	endcase
end

//foreground / text / bullet layer output
prom6301_L8 UL8(
	.addr({U8L_A7,U8L_A6,U8K[1:0],U7L[3:0]}),
	.clk(clkm_20MHZ),
	.n_cs(1'b0), 
	.q(ZA)
);

reg nVDSP,nHDSP;
assign H_BLANK = nHDSP;
assign V_BLANK = nVDSP;
reg  [4:0] clr_addr,sp_clr_addr,bg_clr_addr;
wire [3:0] ZA;
reg  [3:0] ZB;
wire [3:0] ZC;

//select layer with priority

 always @(posedge clk2_6MHZ) begin
	//equivalent of VID_B.  If the 5th bit is used the upper part of the pallet ROM is
	//utilized and the sprite layer is selected.
	sp_clr_addr <= (ZB[3:0]) 		? 	{1'b1,ZB[3:0]}	: 5'b00000;
 end

 always @(posedge clk2_6MHZ) begin

	//the background layer is drawn when a background pixel is present.  The
	//background layer uses the bottom half of the pallet ROM (darker shades)
	bg_clr_addr <= (ZC[3:0])		? 	{1'b0,ZC[3:0]}	: 5'b00000;
 end
 
 //send synchronized pixel to the screen
 always @(posedge clk2_6MHZ) begin 

	nHDSP <= pixH<107 | pixH>428; //horizontal blanking
	nVDSP <= pixV<16 | pixV>239;  //vertical blanking

	
	//set color of pixel with the following priority: Forground, Sprites, Background
	clr_addr <= 	(nHDSP|nVDSP) 			? 	 5'b00000     	:
						(ZA[3:0])				? 	{1'b1,ZA[3:0]} :
						(sp_clr_addr[4]) 		? 	sp_clr_addr 	:	bg_clr_addr;

 end 
	 
//colour prom
prom6331_E1 UE1(
	.addr(clr_addr),
	.clk(clkm_20MHZ),
	.n_cs(1'b0),
	.q({BLUE,GREEN,RED})
);

wire rSSEL;

reg r2UP,nr2UP; //player 2 active (flips controls & screen logic)

wire [8:0] pixHcntz;
wire [7:0] pixVcntz;

reg char_ROMA12, U8L_A6, U8L_A7, CD4,CD5;

always @(posedge IO1) begin
	r2UP<=Z80A_databus_out[0];			//screen inversion for player 2
	nr2UP<=!Z80A_databus_out[0];
	U8L_A6<=Z80A_databus_out[1];
	U8L_A7<=Z80A_databus_out[2];
	char_ROMA12<=Z80A_databus_out[3];
	CD4<=Z80A_databus_out[6];
	CD5<=Z80A_databus_out[7];
end

reg [7:0] Z80A_IO2;

always @(posedge IO2) Z80A_IO2 = Z80A_databus_out;

reg spnH4CA,spnH8CA;
assign pixHcntz=pixH+9'd1;
assign pixVcntz=pixV+8'd1;

always @(posedge clk2_6MHZ) begin
	//simplified pixel clock counter. The horizontal counts from 88 to 511, the vertical counts from 0 to 255
	if (pixH==9'b111111111) 
	begin
		pixH <= 9'b00101100z;
		pixV <= pixVcntz;//pixVcnt+1;
	end
	else pixH <= pixHcntz;

	spnH4CA<=~&pixH[4:1];
	spnH8CA<=~&pixH[8:5];

end

wire [3:0] U7V_q;
assign	rSSEL 	= U9R_Q[4]|nVDSP;  //used to load the per line memory location for the background layer 
assign	U7V_q 	= (rSSEL) ? {Z80B_addrbus[3:0]} : {pixH[3:0]};	
assign	vramaddr = (RAMA) ? {rpixelbusV[7:3],rpixelbusH[8:3]} : Z80A_addrbus[10:0];

always @(*) begin
  if (r2UP) begin
	rpixelbusH <= ~pixH;
	rpixelbusV <= ~pixV;  
  end
  else begin
	rpixelbusH <= pixH;
	rpixelbusV <= pixV;  
  end
end

/* SPRITE VIB-B BOARD IMPLEMENTATION */
//The 10Mhz, 6Mhz and offset 6Mhz clocks are used to draw the sprites
//sprite RAM
wire [7:0] U11SR_SPRAM_Q;

m2114_ram U11SR(
	.data(Z80A_databus_out),
	.addr({spramaddr_cnt[8:2]}),
	.clk(clkm_20MHZ),
	.nWE(RAMB_WR | spRAMsel), //U10S_QB
	.q(U11SR_SPRAM_Q)
);


reg [3:0] U11H_cnt;
reg [3:0] U12H_cnt;

wire sROM_bitA, sROM_bitB, sROM_A0, sROM_A1;

assign sROM_bitA = (BIG2) ? U11H_cnt[1]^UDINV2 : U11H_cnt[0]^UDINV2; //10J
assign sROM_bitB = (BIG2) ? U11H_cnt[2]^UDINV2 : U11H_cnt[1]^UDINV2; //10J
assign sROM_A0 =   (BIG1) ? U12H_cnt[3]^UDINV1 : U12H_cnt[2]^UDINV1; //12J
assign sROM_A1 =   (BIG1) ?       UDPNT^UDINV1 : U12H_cnt[3]^UDINV1; //12J

always @(posedge P3) begin			//U12L
	CHLF<=rSPRITE_databus[7];
	sROM_A11<=rSPRITE_databus[6];
	sROM_A10<=rSPRITE_databus[5];
	sROM_A9<=CAD9;
	CHDN<=rSPRITE_databus[3];
	sROM_A4<=rSPRITE_databus[2];
	sROM_A3<=rSPRITE_databus[1];
	sROM_A2<=rSPRITE_databus[0];
end

reg CHLF,sROM_A11,sROM_A10,sROM_A9,CHDN,sROM_A4,sROM_A3,sROM_A2;
wire [7:0] sprom_data;

eprom_5 prom_SPRITE
(
	.ADDR({CHDN,CHLF,sROM_A11,sROM_A10,sROM_A9,sum4,sum3,sum2,sum1,sROM_A4,sROM_A3,sROM_A2,sROM_A1,sROM_A0}),//
	.CLK(clkm_20MHZ),//
	.DATA(sprom_data),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clkm_20MHZ),//
	.DATA_IN(dn_data),
	.CS_DL(ep5_cs_i),
	.WR(dn_wr)
);

reg [7:0] U8H_Q;

always @(negedge U12H_cnt[1]) U8H_Q<=sprom_data;

reg [1:0] U11J;
always @(*) begin 
   if (ERS) 
        {U11J}  <= 2'b00;
	else
		case ({sROM_bitB,sROM_bitA})
			2'b00: {U11J} <= {U8H_Q[4],U8H_Q[0]};
			2'b01: {U11J} <= {U8H_Q[5],U8H_Q[1]};
			2'b10: {U11J} <= {U8H_Q[6],U8H_Q[2]};
			2'b11: {U11J} <= {U8H_Q[7],U8H_Q[3]};
		endcase
end

wire [3:0] U10H_data;

prom6301_H10 U10H(
	.addr({CD5,CD4,U11J[1:0],CD3,CD2,CD1,CD0}),
	.clk(clkm_20MHZ),
	.n_cs(1'b0), 
	.q({U10H_data})
);

reg [3:0] spbitdata_10;
reg [3:0] spbitdata_11;

reg U9H_A_nq,U9F_A_q,U9F_B_nq;
wire U9H_d;

assign U9H_d = |U11J;


always @(posedge clk1_10MHZ) U9H_A_nq <= 	~U9H_d;

always @(posedge clk1_10MHZ) begin
	spbitdata_11 <= (rpixelbusV[0]) ? 4'b0000 : U10H_data;
	spbitdata_10 <= (rpixelbusV[0]) ? U10H_data :4'b0000 ;
end


always @(posedge U10nRCO or negedge RAMB or negedge spRAMsel) U9F_A_q <= 	(!RAMB) ?	1'b1 : (!spRAMsel) ? 1'b0 : spRAMsel;
always @(posedge spnH4CA or negedge RAMB) U9F_B_nq <= 	~((!RAMB) ?	1'b1 : spnH8CA);

wire [8:0] U12_sum;

assign  U12_sum = {1'b0, rSPRITE_databus} + {1'b0, rpixelbusV} + 1'b1;

//sprite control signals
reg U12P_H0,U12P_CA0,U12P_CA1,U12P_Y2,U12P_BIG,U12P_UDPNT,U12P_RLINV,U12P_UDINV;
reg BIG1,UDINV1,sum1,sum2,sum3,sum4,UDPNT;
reg BIG2,UDINV2,ERS,CD3,CD2,CD1,CD0;

always @(posedge P1) {U12P_UDINV,U12P_RLINV,U12P_UDPNT,U12P_BIG,U12P_Y2,U12P_CA1,U12P_CA0,U12P_H0} <= rSPRITE_databus; //U12P
always @(posedge P3) {sum4,sum3,sum2,sum1,UDPNT,BIG1,UDINV1} <= {U12U_Q[3]^U12P_RLINV,U12U_Q[2]^U12P_RLINV,U12U_Q[1]^U12P_RLINV,U12U_Q[0]^U12P_RLINV,U12P_UDPNT,U12P_BIG,U12P_UDINV}; //U10N
always @(posedge P4) {UDINV2,BIG2,ERS,CD3,CD2,CD1,CD0} <= {U12P_UDINV,U12P_BIG,U11V_ZB,CHDN,CHLF,U12P_CA1,U12P_CA0}; //U10P

reg [3:0] U12U_Q;
reg [3:0] U12T_Q;

always @(negedge P2) begin
	U12U_Q <= (U12P_BIG) ? {U12_sum[4:1]} 			: U12_sum[3:0]; //U12U
	U12T_Q <= (U12P_BIG) ? {1'b0,U12_sum[7:5]}	: U12_sum[7:4]; //U12T
end

reg U11V_ZB,CAD9;

always @(U12P_Y2,U12T_Q,U12P_RLINV,rSPRITE_databus) {U11V_ZB,CAD9} <= (U12P_Y2) ? {U12T_Q[1]|U12T_Q[2]|U12T_Q[3],U12T_Q[0]^U12P_RLINV} : {U12T_Q[0]|U12T_Q[1]|U12T_Q[2]|U12T_Q[3],rSPRITE_databus[4]}; //U11V

reg sp10_UD,sp10_nLD,sp10_CK,sp10_WE;
reg sp11_UD,sp11_nLD,sp11_CK,sp11_WE;

//sprite ram bit selection logic - U11E feeds the _10 bus

always @(*) begin
		sp10_WE  <= rpixelbusV[0] ? (clk1_10MHZ|U9H_A_nq|U9F_A_q) : clk2_6MHZ;
		sp10_CK  <= rpixelbusV[0] ? (clk1_10MHZ|U9F_B_nq|U9F_A_q) : clk2_6MHZ;
		sp10_nLD <= rpixelbusV[0] ? U10nRCO : 1'b1;
		sp11_WE  <= rpixelbusV[0] ? clk2_6MHZ : (clk1_10MHZ|U9H_A_nq|U9F_A_q);
		sp11_CK  <= rpixelbusV[0] ? clk2_6MHZ : (clk1_10MHZ|U9F_B_nq|U9F_A_q);
		sp11_nLD <= rpixelbusV[0] ? 1'b1 : U10nRCO;

		sp10_UD  <= ( rpixelbusV[0])  ? 1'b1 : nr2UP; //1'b1; 
		sp11_UD  <= (!rpixelbusV[0])  ? 1'b1 : nr2UP; //1'b1; 		
end

reg [8:0] spramaddrb_10_cnt;
reg [8:0] spramaddrb_10_up;
//this 'should' mimic the U12A, U12D & D12E counters  
always @(posedge sp10_CK) spramaddrb_10_cnt <= spramaddrb_10_up;

reg [8:0] spramaddrb_11_cnt;
reg [8:0] spramaddrb_11_up;


always @(posedge sp11_CK) spramaddrb_11_cnt = spramaddrb_11_up;

wire [3:0] spram_out_10;
wire [3:0] spram_out_11;

always @(posedge clk2_6MHZ) {ZB} <= (rpixelbusV[0]) ? {spram_out_11} : {spram_out_10}; //U9A

always @(negedge clk1_10MHZ) begin
	U10nRCO<=!(spramaddr_cnt[0]&spramaddr_cnt[1]&spramaddr_cnt[2]&spramaddr_cnt[3]);
end

wire P4,P3,P2,P1;
wire U10U_Q4,U10U_Q5,U10U_Q6,U10U_Q7;

ls138x U10U( //#(.WIDTH_OUT(8), .DELAY_RISE(0), .DELAY_FALL(0)) 
  .nE1(clk1_10MHZ), //
  .nE2(spramaddr_cnt[0]), //
  .E3(spramaddr_cnt[1]), //
  .A({1'b0,spramaddr_cnt[3:2]}), //
  .Y({U10U_Q7,U10U_Q6,U10U_Q5,U10U_Q4,P4,P3,P2,P1})
);

always @(posedge clk1_10MHZ) begin

//U11H     - 161 counter that increments on the 10Mhz clock and is reset to 0 by P4, this can be a simple add counter
//U10J     - Takes the output of U11H and switches the output based on signal 'BIG2'
//U9JA & D - The outputs of U10J are XORed with control signal 'UDINV2'

	U11H_cnt <= (!P4) ? 4'b0000 : U11H_cnt2;
	
//U12H - 161 counter that increments on the 10Mhz clock and is reset to 0 by P3, this can be a simple add counter
//U12J     - Takes the output of U12H and UDPNT and switches the output based on signal 'BIG1'
//U9JC & B - The outputs of U12J are XORed with control signal 'UDINV1	'

	U12H_cnt <= (!P3) ? 4'b0000 : U12H_cnt2;

//Sprite RAM address selection logic
	spRAMbit0 <= (!spRAMsel) ? U12P_H0 : 1'b0; //U10S_QB 
	spRAMsel <= spramaddr_cnt[9];
	spramaddr_cntz3 <= spramaddr_cntz2; //spramaddr_cntz2;
end


reg spRAMbit0;
reg spRAMsel;

reg [3:0] U11H_cnt2;
reg [3:0] U12H_cnt2;
reg [9:0] spramaddr_cnt;
reg [9:0] spramaddr_cntz2;
reg [9:0] spramaddr_cntz3 ;

always @(posedge clkm_20MHZ) begin
	rSPRITE_databus <= (!spRAMsel) ? ((!RAMB_WR) ? Z80A_databus_out : U11SR_SPRAM_Q) : ({r2UP,1'b0,r2UP,r2UP,1'b0,r2UP,1'b0,1'b0}) ;
	U11H_cnt2 <= (!P4) ? 4'b0000 : U11H_cnt+4'd1;
	U12H_cnt2 <= (!P3) ? 4'b0000 : U12H_cnt+4'd1;
	spramaddr_cntz2 <= spramaddr_cnt+10'b0000000001;
	spramaddr_cnt   <= (U9F_B_nq) ?  10'b0000000000 : (!RAMB) ? ({1'b0,Z80A_addrbus[6:0],1'b0,1'b0}) : spramaddr_cntz3 ; 	

	//generate address for fast sprite ram
	spaddr_x <= {rSPRITE_databus[7:0],spRAMbit0};
	spramaddrb_10_up <= 	(!sp10_nLD) ? spaddr_x : 
							   ((sp10_UD)  ? spramaddrb_10_cnt + 9'd1 : spramaddrb_10_cnt - 9'd1);

	spramaddrb_11_up <= 	(!sp11_nLD) ? spaddr_x : 
								((sp11_UD)  ? spramaddrb_11_cnt + 9'd1 : spramaddrb_11_cnt - 9'd1);

	
end

reg [8:0] spaddr_x;

wire U10RCO;
reg U10nRCO=1'b1;
reg [7:0] rSPRITE_databus;

// *************** SOUND CHIPS *****************
wire [7:0] AY_12V_ioa_in;
wire [7:0] AY_12V_ioa_out;
wire [7:0] AY_12V_iob_in;
wire [7:0] AY_12V_iob_out;

wire [7:0] AY_12F_databus_out;
wire [7:0] AY_12V_databus_out;

wire AY12F_sample,AY12V_sample;
wire [9:0] sound_outF;
wire [9:0] sound_outV;


jt49_bus AY_12F(
    .rst_n(RESET_n),
    .clk(clkaudio),    				// signal on positive edge //U1D_B_q
    .clk_en(ayclk_1p66),  						/* synthesis direct_enable = 1 */
    
    .bdir(IOA1),						// bus control pins of original chip
    .bc1(IOA0),
	 .din(Z80A_databus_out),
    .sel(1'b1), 						// if sel is low, the clock is divided by 2
    .dout(AY_12F_databus_out),
    
	 .sound(sound_outF),  			// combined channel output
    .A(),    				// linearised channel output
    .B(),
    .C(),
    .sample(AY12F_sample)

);

jt49_bus AY_12V(
    .rst_n(RESET_n),
    .clk(clkaudio),    				// signal on positive edge
    .clk_en(ayclk_1p66),  						/* synthesis direct_enable = 1 */
    
    .bdir(IOA3),	 					// bus control pins of original chip
    .bc1(IOA2),
	 .din(Z80A_databus_out),
    .sel(1'b1), 						// if sel is low, the clock is divided by 2
    .dout(AY_12V_databus_out),
    
	 .sound(sound_outV),  			// combined channel output
    .A(),      			// linearised channel output
    .B(),
    .C(),
    .sample(),

    .IOA_in(AY_12V_ioa_in),		//IO to ICX security chip
    .IOA_out(AY_12V_ioa_out),

    .IOB_in(AY_12V_iob_in),
    .IOB_out(AY_12V_iob_out)
);

assign audio_l = (pause) ? 0 : ({1'd0, sound_outF, 5'd0});
assign audio_r = (pause) ? 0 : ({1'd0, sound_outV, 5'd0});
		  
reg [7:0] tmrmask ;//= 8'b00000000;
reg [2:0] tmrcounter;
reg [2:0] tmrcnt2;
reg [7:0] zAY_12V_iob_out;
reg [7:0] outercounter;

always @(posedge ayclk_1p66/*U1D_B_q*/) begin

	tmrcounter <= tmrcounter +3'd1;
	if (tmrcounter==0)	tmrmask <= AY_12V_iob_out^8'h40;
	tmrmask<=tmrmask^8'h40;
	
end

assign AY_12V_iob_in = (tmrcounter==3'b111) ? AY_12V_iob_out : 8'd0;
assign AY_12V_ioa_in = tmrmask;//AY_12V_iob_out^8'h40;  // tmrmask;//AY_12V_ioa_out^8'h40; //8'hBE^   tmrmask;//


//************************* BACKGROUND LAYER SECTIONS ************************
wire [7:0] bg_gfx4B_out;
wire [7:0] bg_gfx4D_out;
wire [7:0] bg_gfx4E_out;
wire [7:0] bg_gfx4H_out;

//------------------------------------------------- MiSTer data write selector -------------------------------------------------//
//Instantiate MiSTer data write selector to generate write enables for loading ROMs into the FPGA's BRAM
wire ep1_cs_i, ep2_cs_i, ep3_cs_i, ep4_cs_i, ep5_cs_i, ep6_cs_i, ep7_cs_i, ep8_cs_i;

selector DLSEL
(
	.ioctl_addr(dn_addr),
	.ep1_cs(ep1_cs_i),
	.ep2_cs(ep2_cs_i),
	.ep3_cs(ep3_cs_i),
	.ep4_cs(ep4_cs_i),
	.ep5_cs(ep5_cs_i),
	.ep6_cs(ep6_cs_i),
	.ep7_cs(ep7_cs_i),	
	.ep8_cs(ep8_cs_i)
);

eprom_1 bg_gfx4B
(
	.ADDR({BG4BaddrH[7:0],BG4BaddrL[6:2]}),//
	.CLK(clkm_20MHZ),		//
	.CEN(BG4BaddrL[7]),
	.DATA(bg_gfx4B_out),	//
	.ADDR_DL(dn_addr),
	.CLK_DL(clkm_20MHZ),	//
	.DATA_IN(dn_data),
	.CS_DL(ep1_cs_i),
	.WR(dn_wr)
);

eprom_2 bg_gfx4D
(
	.ADDR({BG4DaddrH[7:0],BG4DaddrL[6:2]}),//
	.CLK(clkm_20MHZ),//
	.CEN(BG4DaddrL[7]),	
	.DATA(bg_gfx4D_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clkm_20MHZ),//
	.DATA_IN(dn_data),
	.CS_DL(ep2_cs_i),
	.WR(dn_wr)
);

eprom_3 bg_gfx4E
(
	.ADDR({BG4EaddrH[7:0],BG4EaddrL[6:2]}),//
	.CLK(clkm_20MHZ),//
	.CEN(BG4EaddrL[7]),	//!BG4EaddrL[7]
	.DATA(bg_gfx4E_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clkm_20MHZ),//
	.DATA_IN(dn_data),
	.CS_DL(ep3_cs_i),
	.WR(dn_wr)
);

eprom_4 bg_gfx4H
(
	.ADDR({BG4HaddrH[7:0],BG4HaddrL[6:2]}),//
	.CLK(clkm_20MHZ),//
	.CEN(BG4HaddrL[7]),	 //
	.DATA(bg_gfx4H_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clkm_20MHZ),//
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

assign SLSE = clk2_6MHZ|rSSEL; 

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

reg [1:0] S0,S1,S2,S3;

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

reg [7:0] BG4BaddrL,BG4BaddrH,BG4DaddrL,BG4DaddrH,BG4EaddrL,BG4EaddrH,BG4HaddrL,BG4HaddrH;

always @(negedge SLD[1]) BG4BaddrH <= BGRAM_out;
always @(negedge SLD[3]) BG4DaddrH <= BGRAM_out;
always @(negedge SLD[5]) BG4EaddrH <= BGRAM_out;
always @(negedge SLD[7]) BG4HaddrH <= BGRAM_out;


reg [7:0] BG4BaddrL_base,BG4DaddrL_base,BG4EaddrL_base,BG4HaddrL_base;

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
	.clk(clkm_20MHZ),
	.nWE(Z80B_WR | BG_BUS), //write background scratch ram
	.q(BGRAM_out)
);

//sprite alternating line buffers
m2511_ram_4 sprites_10(
	.data(spbitdata_10),	
	.clk(clkm_20MHZ),
	.addr({spramaddrb_10_cnt[8:0]}),
	.nWE(sp10_WE),
	.q(spram_out_10)
);

m2511_ram_4 sprites_11(
	.data(spbitdata_11),	
	.clk(clkm_20MHZ),
	.addr({spramaddrb_11_cnt[8:0]}),
	.nWE(sp11_WE),
	.q(spram_out_11)
);

//  ****** FINAL 7-BIT ANALOGUE OUTPUT *******
assign	H_SYNC = !U9R_Q[5];								//horizontal sync
assign	V_SYNC = ((!(&pixV[7:3]))|pixV[2]); 	//vertical sync

endmodule
