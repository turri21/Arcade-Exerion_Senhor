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
	input clk_sys,   //clkm_20MHZ
	input clk_sys40, //clk_sys40
	input	clkaudio,  //clk_53p28
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
	output signed [15:0] audio_l,  //from jt49_1 .sound
	output signed [15:0] audio_r,  //from jt49_2 .sound
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
reg [10:0] vramaddr;

wire 	[7:0] u6k_data; //foreground character ROM output data
reg 	[7:0] u7K_data;
reg 	[7:0] vramdata0out;
wire 	[7:0] U6N_VRAM_Q;

wire clk1_10MHZ,clk2_6MHZ,clk2_6AMHZ,clk3_3MHZ;

wire PUR = 1'b1;
wire SSEL;


wire [7:0] U9R_Q;

wire [15:0] Z80A_addrbus;
reg [7:0] Z80A_databus_in;
wire [7:0] Z80A_databus_out;

//core clock generation logic based on jtframe code
reg [4:0] cen40cnt =5'd0;

wire clkm_20MHZ=clk_sys;

reg clksp_20MHZ,clksp_10MHZ,clksp_10MHZn;

always @(posedge clk_sys40) begin
	cen40cnt  <= cen40cnt+5'd1;
end

always @(posedge clk_sys40) begin

   clksp_20MHZ 		<= cen40cnt[0] == 1'd0;		
   clksp_10MHZ 		<= cen40cnt[1:0] == 2'd0;			
   clksp_10MHZn 		<= cen40cnt[1:0] == 2'd2;		
end

//core clock generation logic based on jtframe code
reg [4:0] cencnt =5'd0;
reg AYclk_cen,cpuclk_3p33,cpuclk_3p33n,ayclk_1p66;

always @(posedge clkaudio) begin
	cencnt  <= cencnt+5'd1;
end

always @(posedge clkaudio) begin
   AYclk_cen      <= cencnt[0] == 1'd0;
   cpuclk_3p33 	<= cencnt[3:0] == 4'd0;		
	cpuclk_3p33n 	<= cencnt[3:0] == 4'd8;		
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

/*
ls107 U2B_B(
   .clear(PUR), 
   .clk(clkm_20MHZ), 
   .j(U2A_Aq), 
   .k(U2A_Aq), 
   .q(U2B_Bq), 
   .qnot(U2B_Bnq),
	.q_immediate(U2B_Bqi)
);*/

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

//coin input
reg nCOIN;

assign core_pix_clk=clk2_6MHZ;

always @(posedge nVDSP) nCOIN <= m_coin;

//First Z80 CPU responsible for main game logic, sound, sprites
T80pa Z80A(
	.RESET_n(RESET_n),
	.WAIT_n(wait_n),
	.INT_n(PUR),
	.BUSRQ_n(PUR),
	.NMI_n(PUR&nCOIN), //+1 coin
	.CLK(clkaudio), 
	.CEN_p(cpuclk_3p33), 
	.CEN_n(cpuclk_3p33n), 
	//.CLK_n(clk3_3MHZ),
	.MREQ_n(Z80_MREQ),
	.DI(Z80A_databus_in),
	.DO(Z80A_databus_out),
	.A(Z80A_addrbus),
	.WR_n(Z80_WR),
	.RD_n(Z80_RD)
);

//joystick inputs from MiSTer framework
wire m_coin   		= CONTROLS[8];
									
reg ZA_ROM, ZA_RAM, RAMA, RAMB, IN1, IN2, IN3, IO1, IO2, AY1, AY2;
always @(*) begin
	ZA_ROM 	= ((Z80A_addrbus[15:13] == 3'b000)|(Z80A_addrbus[15:13] == 3'b001)|(Z80A_addrbus[15:13] == 3'b010))	
																			? 1'b0 : 1'b1; //0000 - 5FFF - Main Program ROM
	ZA_RAM 	= (Z80A_addrbus[15:13] == 3'b011)				? 1'b0 : 1'b1; //6000 - 7FFF - Main Program RAM
	RAMA		= (Z80A_addrbus[15:11] == 5'b10000)				? 1'b0 : 1'b1; //8000 - 87FF
	RAMB		= (Z80A_addrbus[15:11] == 5'b10001)				? 1'b0 : 1'b1; //8800 - 8FFF
	IN1	  	= (Z80A_addrbus[15:11] == 5'b10100)				? 1'b0 : 1'b1; //A000
	IN2	  	= (Z80A_addrbus[15:11] == 5'b10101)				? 1'b0 : 1'b1; //A800
	IN3	  	= (Z80A_addrbus[15:11] == 5'b10110)				? 1'b0 : 1'b1; //B000
	IO1	  	= (Z80A_addrbus[15:11] == 5'b11000)				? 1'b0 : 1'b1; //c000 (Write Only)
	IO2	  	= (Z80A_addrbus[15:11] == 5'b11001)				? 1'b0 : 1'b1; //c800 (Write Only)
	AY1		= (Z80A_addrbus[15:11] == 5'b11010)				? 1'b0 : 1'b1; //D000 - D001
	AY2		= (Z80A_addrbus[15:11] == 5'b11011)				? 1'b0 : 1'b1; //D800 - D801

end

//CPU data bus read selection logic
// **Z80A* PRIMARY CPU IC SELECTION LOGIC FOR TILE, SPRITE, SOUND & GAME EXECUTION ********
always @(posedge clkaudio) begin
		Z80A_databus_in <= 	(!ZA_ROM&!Z80_MREQ)	? 	prom_prog1_out :
									(!ZA_RAM & !Z80_RD)  ? 	U4N_Z80A_RAM_out :
									(!Z80_RD & !RAMA)		?  U6N_VRAM_Q : 		//VRAM
									(!Z80_RD & !RAMB)		?  rSPRITE_databus : //U11SR_SPRAM_Q
									(!Z80_RD & !IN1)		?	(CONTROLS[7:0]) :	//JOYSTICK 1 & 2 - ST2, ST1,    FIRB,FIRA,LF,  RG,  DN,  UP
									(!Z80_RD & !IN2)		?	DIP1 :						
									(!Z80_RD & !IN3)		?	{1'b0,1'b0,1'b0,1'b0,DIP2[1],DIP2[0],DIP2[2],nVDSP} :
									(!IOA1 & IOA0)			? 	AY_12F_databus_out :
									(!IOA3 & IOA2)			? 	AY_12V_databus_out :
																8'b00000000;
		RAMA_WR <= RAMA|Z80_WR;
		RAMB_WR <= RAMB|Z80_WR;

end									

wire wait_n;
reg RAMA_WR,RAMB_WR;

assign	wait_n = !pause;


//Z80A CPU main program program ROM
eprom_8 prom_prog1
(
	.ADDR(Z80A_addrbus[14:0]),//
	.CLK(clk_sys40),//
	.DATA(prom_prog1_out),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clk_sys40),//
	.DATA_IN(dn_data),
	.CS_DL(ep8_cs_i),
	.WR(dn_wr)
);

wire [7:0] prom_prog1_out;
wire [7:0] prom_prog2_out;
wire [7:0] U4N_Z80A_RAM_out;

//main CPU (Z80A) work RAM - dual port RAM for hi-score logic
dpram_dc #(.widthad_a(11)) U4N_Z80A_RAM
(
	.clock_a(clk_sys40),
	.address_a(Z80A_addrbus[10:0]),
	.data_a(Z80A_databus_out),
	.wren_a(!Z80_WR & !ZA_RAM),
	.q_a(U4N_Z80A_RAM_out),

	.clock_b(clk_sys40),
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

reg SNHI,rSSEL;
reg [12:0] fgramaddr;
//wire
//assign	
always @(posedge clk_sys) begin
 SNHI 			<= ((pixH[8:6]==3'b111)&!nVDSP) ? 1'b0 : 1'b1;
 rSSEL 			<= U9R_Q[4]|nVDSP;  //used to load the per line memory location for the background layer -> SIGNAL TO BACKGROUND LAYER

end

always @(posedge clkaudio)  vramaddr 		<= (RAMA) ? {rpixelbusV[7:3],rpixelbusH[8:3]} : Z80A_addrbus[10:0];

always @(posedge clkaudio)  fglayeraddr	<= {U8L_A76[1:0],U8K[1:0],U7L[3:0]};

//VRAM
m6116_ram U6N_VRAM(
	.data(Z80A_databus_out),
	.addr(vramaddr),
	.clk(clkaudio),
	.cen(1'b1),
	.nWE(RAMA_WR),
	.q(U6N_VRAM_Q)
);	

always @(negedge pixH[2]) vramdata0out<=U6N_VRAM_Q; //pixH[2]
always @(posedge clk_sys)  fgramaddr  	<= {char_ROMA12,vramdata0out[7:4],rpixelbusV[2:0],vramdata0out[3:0],rpixelbusH[2]};


//foreground character ROM
eprom_7 u6k
(
	.ADDR(fgramaddr),//
	.CLK(clk_sys),//
	.DATA(u6k_data),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clk_sys40),//
	.DATA_IN(dn_data),
	.CS_DL(ep7_cs_i),
	.WR(dn_wr)
);

//wire npix1=~pixH[1];

reg [3:0] U7L;
reg [1:0] U8K;
reg [7:0] fglayeraddr;

always @(negedge pixH[1]) begin
	u7K_data <= u6k_data ;
	U7L <= vramdata0out[7:4];
end

always @(posedge clk_sys) begin //U5J
	case (rpixelbusH[1:0])
		2'b00: U8K = {u7K_data[4],u7K_data[0]};
		2'b01: U8K = {u7K_data[5],u7K_data[1]};
		2'b10: U8K = {u7K_data[6],u7K_data[2]};
		2'b11: U8K = {u7K_data[7],u7K_data[3]};
	endcase
end


//foreground / text / bullet layer output
prom6301_L8 UL8(
	.addr(fglayeraddr),
	.clk(clk_sys),
	.n_cs(1'b0), 
	.q(ZA)
);



//wire rSSEL;

reg r2UP,nr2UP; //player 2 active (flips controls & screen logic)

wire [8:0] pixHcntz;
wire [7:0] pixVcntz;

reg char_ROMA12 ;
reg [1:0] U8L_A76,CD54;

always @(posedge IO1) begin
	r2UP<=Z80A_databus_out[0];			//screen inversion for player 2
	nr2UP<=!Z80A_databus_out[0];
	U8L_A76[1:0]<=Z80A_databus_out[2:1];
	char_ROMA12<=Z80A_databus_out[3];
	CD54[1:0]<=Z80A_databus_out[7:6];
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




always @(posedge clk_sys) begin
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
	.clk(clk_sys40),
	.nWE(RAMB_WR | spRAMsel), //U10S_QB
	.q(U11SR_SPRAM_Q)
);


reg [3:0] U11H_cnt,U12H_cnt;

wire sROM_bitA, sROM_bitB, sROM_A0, sROM_A1;

assign sROM_bitA = (BIG2) ? U11H_cnt[1]^UDINV2 : U11H_cnt[0]^UDINV2; //10J
assign sROM_bitB = (BIG2) ? U11H_cnt[2]^UDINV2 : U11H_cnt[1]^UDINV2; //10J
assign sROM_A0 =   (BIG1) ? U12H_cnt[3]^UDINV1 : U12H_cnt[2]^UDINV1; //12J
assign sROM_A1 =   (BIG1) ?       UDPNT^UDINV1 : U12H_cnt[3]^UDINV1; //12J

always @(posedge P[3]) begin			//U12L
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
	.CLK(clk_sys40),//
	.DATA(sprom_data),//
	.ADDR_DL(dn_addr),
	.CLK_DL(clk_sys40),//
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
	.addr({CD54[1:0],U11J[1:0],CD3,CD2,CD1,CD0}),
	.clk(clk_sys40),
	.n_cs(1'b0), 
	.q({U10H_data})
);

reg [3:0] spbitdata_10,spbitdata_11;

reg U9H_A_nq,U9F_A_q,U9F_B_nq;
wire U9H_d;

assign U9H_d = |U11J;


always @(posedge clksp_10MHZ) U9H_A_nq <= 	~U9H_d;

always @(posedge clksp_10MHZ) begin
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
reg BIG2,UDINV2,ERS,CD3,CD2,CD1,CD0,U11V_ZB,CAD9;
reg [7:0] U12_Q;

always @(posedge P[1]) {U12P_UDINV,U12P_RLINV,U12P_UDPNT,U12P_BIG,U12P_Y2,U12P_CA1,U12P_CA0,U12P_H0} <= rSPRITE_databus; //U12P
always @(negedge P[2]) U12_Q <= (U12P_BIG) ? {1'b0,U12_sum[7:1]} : U12_sum[7:0]; //U12U
always @(posedge P[3]) {sum4,sum3,sum2,sum1,UDPNT,BIG1,UDINV1} <= {U12_Q[3]^U12P_RLINV,U12_Q[2]^U12P_RLINV,U12_Q[1]^U12P_RLINV,U12_Q[0]^U12P_RLINV,U12P_UDPNT,U12P_BIG,U12P_UDINV}; //U10N
always @(posedge P[4]) {UDINV2,BIG2,ERS,CD3,CD2,CD1,CD0} <= {U12P_UDINV,U12P_BIG,U11V_ZB,CHDN,CHLF,U12P_CA1,U12P_CA0}; //U10P




always @(*) {U11V_ZB,CAD9} <= (U12P_Y2) ? {|U12_Q[7:5],U12_Q[4]^U12P_RLINV} : {|U12_Q[7:4],rSPRITE_databus[4]}; //U11V

reg sp10_UD,sp10_nLD,sp10_CK,sp10_WE;
reg sp11_UD,sp11_nLD,sp11_CK,sp11_WE;

//sprite ram bit selection logic - U11E feeds the _10 bus

always @(*) begin
		sp10_WE  <= rpixelbusV[0] ? (clksp_10MHZ|U9H_A_nq|U9F_A_q) : clk2_6MHZ;
		sp10_CK  <= rpixelbusV[0] ? (clksp_10MHZ|U9F_B_nq|U9F_A_q) : clk2_6MHZ;
		sp10_nLD <= rpixelbusV[0] ? U10nRCO : 1'b1;
		sp11_WE  <= rpixelbusV[0] ? clk2_6MHZ : (clksp_10MHZ|U9H_A_nq|U9F_A_q);
		sp11_CK  <= rpixelbusV[0] ? clk2_6MHZ : (clksp_10MHZ|U9F_B_nq|U9F_A_q);
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
always @(negedge clksp_10MHZ) U10nRCO=!(&spramaddr_cnt[3:0]);

reg [4:0] P;

always @(negedge clksp_10MHZ) begin
	 if (spramaddr_cnt[1:0]==2'b10) begin
		case (spramaddr_cnt[3:2])
		  2'b00: P[4:1]=4'b1110;
		  2'b01: P[4:1]=4'b1101;
		  2'b10: P[4:1]=4'b1011;
		  2'b11: P[4:1]=4'b0111;
		endcase
	 end
	 else begin //
		P[4:1] = 4'b1111;
	 end
end

always @(posedge clksp_10MHZ) begin

//U11H     - 161 counter that increments on the 10Mhz clock and is reset to 0 by P4, this can be a simple add counter
//U10J     - Takes the output of U11H and switches the output based on signal 'BIG2'
//U9JA & D - The outputs of U10J are XORed with control signal 'UDINV2'

	U11H_cnt <= (!P[4]) ? 4'b0000 : U11H_cnt2;
	
//U12H - 161 counter that increments on the 10Mhz clock and is reset to 0 by P3, this can be a simple add counter
//U12J     - Takes the output of U12H and UDPNT and switches the output based on signal 'BIG1'
//U9JC & B - The outputs of U12J are XORed with control signal 'UDINV1	'

	U12H_cnt <= (!P[3]) ? 4'b0000 : U12H_cnt2;

//Sprite RAM address selection logic
	spRAMbit0 <= (!spRAMsel) ? U12P_H0 : 1'b0; //U10S_QB 
	spRAMsel <= spramaddr_cnt[9];
	spramaddr_cntz3 <= spramaddr_cntz2; //spramaddr_cntz2;
end

always @(posedge clksp_10MHZn) begin
	U11H_cnt2 <= (!P[4]) ? 4'b0000 : U11H_cnt+4'd1;
	U12H_cnt2 <= (!P[3]) ? 4'b0000 : U12H_cnt+4'd1;
end
	
reg spRAMbit0;
reg spRAMsel;

reg [3:0] U11H_cnt2;
reg [3:0] U12H_cnt2;
reg [9:0] spramaddr_cnt;
reg [9:0] spramaddr_cntz2;
reg [9:0] spramaddr_cntz3 ;

always @(*)/*posedge clksp_20MHZclkm_20MHZ) */ begin
	rSPRITE_databus <= (!spRAMsel) ? ((!RAMB_WR) ? Z80A_databus_out : U11SR_SPRAM_Q) : ({r2UP,1'b0,r2UP,r2UP,1'b0,r2UP,1'b0,1'b0}) ;

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
wire signed [15:0] audio_snd;
//sound chip selection logic
reg IOA0,IOA1,IOA2,IOA3;

always @(posedge cpuclk_3p33) begin
	IOA0 		= !(Z80A_addrbus[0]|AY1); //D000
	IOA1 		= !(Z80A_addrbus[1]|AY1); //D001
	IOA2 		= !(Z80A_addrbus[0]|AY2); //D800
	IOA3 		= !(Z80A_addrbus[1]|AY2); //D801
end

jt49_bus AY_12F(
    .rst_n(RESET_n),
    .clk(clkaudio),    				// signal on positive edge //U1D_B_q
    .clk_en(cpuclk_3p33),  						/* synthesis direct_enable = 1 */
    
    .bdir(IOA1),						// bus control pins of original chip
    .bc1(IOA0),
	 .din(Z80A_databus_out),
    .sel(1'b0), 						// if sel is low, the clock is divided by 2
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
    .clk_en(cpuclk_3p33),  						/* synthesis direct_enable = 1 */
    
    .bdir(IOA3),	 					// bus control pins of original chip
    .bc1(IOA2),
	 .din(Z80A_databus_out),
    .sel(1'b0), 						// if sel is low, the clock is divided by 2
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

jtframe_jt49_filters u_filters1(
            .rst    ( !RESET_n    ),
            .clk    ( clkaudio    ),
            .din0   ( sound_outF ),
            .din1   ( sound_outV ), //sound_outAY3 - {1'b0,AY1_IOA_out,1'b0}
            .sample ( AY12F_sample  ), //AY12F_sample
            .dout   ( audio_snd    )
);

assign audio_l = (pause) ? 16'd0 : audio_snd;
assign audio_r = (pause) ? 16'd0 : audio_snd;

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
//sprite alternating line buffers
m2511_ram_4 sprites_10(
	.data(spbitdata_10),	
	.clk(clk_sys40),
	.addr({spramaddrb_10_cnt[8:0]}),
	.nWE(sp10_WE),
	.q(spram_out_10)
);

m2511_ram_4 sprites_11(
	.data(spbitdata_11),	
	.clk(clk_sys40),
	.addr({spramaddrb_11_cnt[8:0]}),
	.nWE(sp11_WE),
	.q(spram_out_11)
);


exer_background ex_bg(
	.RESET_n(RESET_n),
	.clk_sys(clk_sys40),
	.clk2_6MHZ(clk2_6MHZ),
	.clk_cpuf(clkaudio),
	.clk3_3MHZ(cpuclk_3p33),
	.clk3_3MHZn(cpuclk_3p33n),
	.rSSEL(rSSEL),
	.nVDSP(nVDSP),
	.SNHI(SNHI),
	.r2UP(r2UP),
	.nr2UP(nr2UP),
	.pixH(pixH[3:0]),
	.Z80A_IO2(Z80A_IO2),
	
	.dn_addr(dn_addr),
	.dn_wr(dn_wr),
	.dn_data(dn_data),
	.ep1_cs_i(ep1_cs_i),
	.ep2_cs_i(ep2_cs_i),
	.ep3_cs_i(ep3_cs_i),
	.ep4_cs_i(ep4_cs_i),	
	.ep6_cs_i(ep6_cs_i),			//background layer program ROM
	
	.ZC(ZC)
);

//  ****** FINAL 7-BIT ANALOGUE OUTPUT *******
assign	H_SYNC = !U9R_Q[5];								//horizontal sync
assign	V_SYNC = ((!(&pixV[7:3]))|pixV[2]); 		//vertical sync
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
	.clk(clk_sys40),
	.n_cs(1'b0),
	.q({BLUE,GREEN,RED})
);
endmodule
