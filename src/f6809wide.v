// 6809 MPU binary compatible soft core
// 64-bit instruction bus & 16-bit data bus
// Copyright 2026 © Yasuo Kuwahara

// MIT License

// not implemented: SYNC, DAA, H flag

module f6809wide(clk, reset, pc_out, insn_in,
	wr_l, wr_u, adr_out, data_in, data_out,
	irq, iack, firq, fiack, nmi, nmiack);
input clk, reset, irq, firq, nmi;
input [63:0] insn_in;
input [15:0] data_in;
output wr_l, wr_u, iack, fiack, nmiack;
output [15:0] pc_out, adr_out, data_out;

localparam C = 0;
localparam V = 1;
localparam Z = 2;
localparam N = 3;
localparam I = 4;
localparam F = 6;
localparam E = 7;

function [7:0] sel4x8;
	input [1:0] sel;
	input [31:0] a;
	begin
		case (sel)
			2'b00: sel4x8 = a[7:0];
			2'b01: sel4x8 = a[15:8];
			2'b10: sel4x8 = a[23:16];
			2'b11: sel4x8 = a[31:24];
		endcase
	end
endfunction

function [15:0] sel4x16;
	input [1:0] sel;
	input [63:0] a;
	begin
		case (sel)
			2'b00: sel4x16 = a[15:0];
			2'b01: sel4x16 = a[31:16];
			2'b10: sel4x16 = a[47:32];
			2'b11: sel4x16 = a[63:48];
		endcase
	end
endfunction

function [7:0] sel8x8;
	input [2:0] sel;
	input [63:0] a;
	begin
		case (sel)
			3'b000: sel8x8 = a[7:0];
			3'b001: sel8x8 = a[15:8];
			3'b010: sel8x8 = a[23:16];
			3'b011: sel8x8 = a[31:24];
			3'b100: sel8x8 = a[39:32];
			3'b101: sel8x8 = a[47:40];
			3'b110: sel8x8 = a[55:48];
			3'b111: sel8x8 = a[63:56];
		endcase
	end
endfunction

function [15:0] regsel;
	input [3:0] sel;
	input [31:0] a8;
	input [79:0] a16;
	begin
		case (sel)
			4'h0: regsel = a8[31:16];
			4'h1: regsel = a16[79:64];
			4'h2: regsel = a16[63:48];
			4'h3: regsel = a16[47:32];
			4'h4: regsel = a16[31:16];
			4'h5: regsel = a16[15:0];
			4'h8: regsel = { 8'hff, a8[31:24] };
			4'h9: regsel = { 8'hff, a8[23:16] };
			4'ha: regsel = { a8[15:8], a8[15:8] };
			4'hb: regsel = { a8[7:0], a8[7:0] };
			default: regsel = 16'hffff;
		endcase
	end
endfunction

reg [7:0] a, b, cc, dp;
reg [15:0] x, y, u, s, pc;

// DECODE

wire [7:0] p = force_nop ? 8'h12 : sel8x8(pc[2:0], insn_in);
wire [7:0] p2 = sel8x8(pc[2:0], { insn_in[7:0], insn_in[63:8] });
wire [39:0] insn = {
	p,
	p2,
	sel8x8(pc[2:0], { insn_in[15:0], insn_in[63:16] }),
	sel8x8(pc[2:0], { insn_in[23:0], insn_in[63:24] }),
	sel8x8(pc[2:0], { insn_in[31:0], insn_in[63:32] })
};

wire pre = p[7:1] == 7'b0001000;
wire pre10 = pre & ~p[0];
wire pre11 = pre & p[0];
wire nopre = ~pre;

wire [7:0] o = pre ? p2 : p;
wire [7:0] mode = pre ? insn[23:16] : p2;
wire [15:0] imm = pre & idx ? insn[15:0] : pre | idx ? insn[23:8] : insn[31:16];

localparam ADD8 = 0;
localparam ADD16 = 1;
localparam ADDSUB8 = 2;
localparam ADDSUB16 = 3;
localparam ANDORCC_CWAI = 4;
localparam SUB8 = 5;
localparam SUB8COM = 6;
localparam SUB16 = 7;
localparam SUBCMP16 = 8;
localparam LEA = 9;
localparam LEFT = 10;
localparam MUL = 11;
localparam RIGHT = 12;
localparam SEX = 13;
localparam I1MAX = 13;
//
localparam ABX = 14;
localparam ADDDSUBD = 15;
localparam ANDORCC = 16;
localparam BSR = 17;
localparam BSRJSR = 18;
localparam COM = 19;
localparam CWAI = 20;
localparam DEC = 21;
localparam EXGTFR = 22;
localparam INC = 23;
localparam JMP = 24;
localparam JMPJSR = 25;
localparam JSR = 26;
localparam LBRALBSR = 27;
localparam LBSR = 28;
localparam LD16 = 29;
localparam LDD = 30; 
localparam LDXYUS = 31;
localparam LEAXY = 32;
localparam MOV8 = 33;
localparam MOV16 = 34;
localparam PSH = 35;
localparam PSHPUL = 36;
localparam PUL = 37;
localparam RTI = 38;
localparam RTS = 39;
localparam ST8 = 40;
localparam ST16 = 41;
localparam SWI = 42;
localparam IMAX = 42;
//
wire [15:0] mov_lut = 16'h0570, unary_lut = 16'h00f1;
wire [IMAX:0] i;
assign i[MOV8] = p[7] & mov_lut[p[3:0]] | unary_lut[p[7:4]] & p[3:0] == 4'b1101;
assign i[MOV16] = o[7] & o[3:0] == 4'b1110 | &p[7:6] & p[3:0] == 4'b1100;
assign i[ST8] = p[7] & p[3:0] == 4'b0111;
assign i[ST16] = o[7] & &o[3:0] | &p[7:6] & p[3:0] == 4'b1101;
assign i[LDD] = &p[7:6] & p[3:0] == 4'b1100;
assign i[LDXYUS] = o[7] & o[3:0] == 4'b1110;
assign i[LD16] = i[LDD] | i[LDXYUS];
assign i[ADD8] = p[7] & p[3:2] == 2'b10 & p[0] | unary_lut[p[7:4]] & &p[3:0];
assign i[SUB8] = p[7] & p[3:0] <= 2 | unary_lut[p[7:4]] & ~|p[3:0];
assign i[ADDSUB8] = i[ADD8] | i[SUB8];
assign i[COM] = unary_lut[p[7:4]] & p[3:0] == 4'b0011;
assign i[SUB8COM] = i[SUB8] | i[COM];
assign i[INC] = unary_lut[p[7:4]] & p[3:0] == 4'b1100;
assign i[DEC] = unary_lut[p[7:4]] & p[3:0] == 4'b1010;
assign i[MUL] = p == 8'h3d;
assign i[SEX] = p == 8'h1d;
assign i[ABX] = p == 8'h3a;
assign i[LEFT] = unary_lut[p[7:4]] & p[3:1] == 3'b100;
assign i[RIGHT] = unary_lut[p[7:4]] & p[3:2] == 2'b01;
assign i[SUB16] = o[7:6] == 2'b10 & (o[3:0] == 4'b0011 | o[3:0] == 4'b1100);
assign i[ADD16] = p[7:6] == 2'b11 & p[3:0] == 4'b0011;
assign i[ADDSUB16] = i[ADD16] | i[SUB16];
assign i[ADDDSUBD] = p[7] & p[3:0] == 4'b0011;
assign i[SUBCMP16] = o[7:6] == 2'b10 & (o[3:0] == 4'b0011 | o[3:0] == 4'b1100);
assign i[LEA] = p[7:2] == 6'b001100;
assign i[LEAXY] = i[LEA] & ~p[1];
assign i[EXGTFR] = p[7:1] == 7'b0001111;
assign i[PSHPUL] = p[7:2] == 6'b001101;
assign i[PSH] = i[PSHPUL] & ~p[0];
assign i[PUL] = i[PSHPUL] & p[0];
assign i[JMP] = unary_lut[p[7:4]] & p[3:0] == 4'b1110;
assign i[BSR] = p == 8'h8d;
assign i[JSR] = p[7:6] == 2'b10 & |p[5:4] & p[3:0] == 4'b1101;
assign i[BSRJSR] = i[BSR] | i[JSR];
assign i[JMPJSR] = i[JMP] | i[JSR];
assign i[LBRALBSR] = p[7:1] == 7'b0001011;
assign i[LBSR] = i[LBRALBSR] & p[0]; 
assign i[RTS] = p == 8'h39;
assign i[RTI] = p == 8'h3b;
assign i[ANDORCC] = p[7:3] == 5'b00011 & ^p[2:1] & ~p[0];
assign i[CWAI] = o == 8'h3c;
assign i[ANDORCC_CWAI] = i[ANDORCC] | i[CWAI];
assign i[SWI] = o == 8'h3f;

// instruction byte count

wire [15:0] byte2_lut1 = 16'hd400, byte2_lut3 = 16'h10ff;
wire [15:0] byte2_lut8c = 16'haff7, byte3_lut = 16'h5008;
wire byte2 = o[7] ? (^o[5:4] | ~|o[5:4] & byte2_lut8c[o[3:0]]) :
	o[6] ? o[5:4] == 2'b10 :
	~o[4] | (o[5] ? byte2_lut3[o[3:0]] : byte2_lut1[o[3:0]]);
wire byte3 = o[7] ? ~|o[5:4] & byte3_lut[o[3:0]] | &o[5:4] :
	o[6:1] == 6'b001011 | &o[6:4] | pre & o[6:4] == 3'b010;
wire idx = o[5] & (|o[7:6] ? ~o[4] : o[4:2] == 3'b100);
wire ext_ind = idx & mode == 8'h9f;
wire add_idx = idx & mode[7] & mode[3] & ~mode[1] | ext_ind; 
wire [2:0] bytes = { byte2 | byte3, ~byte2 | byte3 } +
	{ add_idx & mode[0], add_idx & ~mode[0] } + pre;

// state

wire [15:0] dbl_state_lut = 16'h00c1;
wire dbl_state = dbl_state_lut[o[7:4]] & o[3:0] <= 12 |
	i[EXGTFR] & p2[3:0] == 4'b0101;
reg state;
always @(posedge clk)
	if (reset | state) state <= 1'b0;
	else if (dbl_state) state <= 1'b1;

reg [2:0] active_sr;
always @(posedge clk)
	if (reset | go_vect) active_sr <= 0;
	else if (~&vect_n) active_sr <= { active_sr[1:0], 1'b1 };
wire active = active_sr[2];

// interrupt

reg [2:0] vect_n;
reg ack, ack_cwai;
wire accept = active & ~(dbl_state & ~state) &
	~|listreg_d & ~&listsel & ~ind & ~i[RTS] & ~i[RTI];
wire valid_intr = irq & ~cc[I] | firq & ~cc[F] | nmi;
wire go_vect = ack & ~|listreg_d;
always @(posedge clk)
	if (reset) begin
		ack <= 0;
		ack_cwai <= 0;
		vect_n <= 0;
	end
	else if (go_vect) ack <= 0;
	else if (ack_cwai) ack_cwai <= 0;
	else if (accept & valid_intr | i[SWI] | i[CWAI]) begin
		ack <= 1;
		vect_n <= nmi ? 1 : firq ? 4 : irq ? 3 :
			i[SWI] ? pre10 ? 5 : pre11 ? 6 : 2 : 7;
	end
	else if (~active & &vect_n & (nmi | firq | irq)) begin
		ack_cwai <= 1;
		vect_n <= nmi ? 1 : firq ? 4 : 3;
	end
assign nmiack = (ack | ack_cwai) & vect_n == 1;
assign swiack = ack & vect_n == 2;
assign iack = (ack | ack_cwai) & vect_n == 3;
assign fiack = (ack | ack_cwai) & vect_n == 4;

// EA

wire [15:0] ea_lut8_16 = 16'h3b60, ea_lut16 = 16'h2a00;
wire [15:0] ea_r = sel4x16(mode[6:5], { fwd_s, fwd_u, fwd_y, fwd_x });
wire predec = mode[7] & mode[4:1] == 4'b0001;
wire [15:0] ea_rp = ea_r - { predec & mode[0], predec & ~mode[0] };
wire [15:0] ea_add_a = mode[7] & mode[3:1] == 3'b110 ? nextpc_normal : ea_rp;
wire [7:0] ofs8 = mode[3] ? imm[15:8] : mode[0] ? fwd_b : fwd_a;
wire [15:0] ofs16 = mode[1] ? { fwd_a, fwd_b } : imm;
wire [15:0] ea_add_b = mode[7] & ea_lut8_16[mode[3:0]] ?
	ea_lut16[mode[3:0]] ? ofs16 : { {8{ ofs8[7] }}, ofs8 } :
	{ {11{ ~mode[7] & mode[4] }}, {5{ ~mode[7] }} & mode[4:0] };
wire [15:0] ea_add_y = ea_add_a + ea_add_b;
wire [15:0] ea = idx ? ea_add_y : &o[5:4] ? imm : { fwd_dp, imm[15:8] };

wire t_ind = idx & mode[7] & mode[4];
reg ind1;
always @(posedge clk)
	ind1 <= ~ind1 & t_ind;
wire ind = t_ind & ~ind1;

// PSH/PUL

reg [7:0] listreg;
wire [7:0] list = |listreg ?
	listreg & (fiack | i[RTI] & ~fwd_cc[E] ? 8'h81 : 8'hff) :
	ack | i[RTI] ? 8'hff :
	i[PSHPUL] ? p2 : 8'h00;
wire [7:0] listreg_d = list & ~(1 << listsel);
always @(posedge clk)
	if (reset) listreg <= 0;
	else if (i[PSHPUL] | i[RTI] | ack) listreg <= listreg_d;
wire psh_ex = (i[PSH] | ack) & |list;
wire pul_ex = (i[PUL] | i[RTI]) & |list;
wire [2:0] pshsel = { |list[7:4],
	|list[7:6] | ~|list[7:4] & |list[3:2],
	list[7] | ~|list[7:6] & list[5] |
		~|list[7:4] & list[3] | ~|list[7:2] & list[1] };
wire [2:0] pulsel_n = { |list[3:0],
	|list[1:0] | ~|list[3:0] & |list[5:4],
	list[0] | ~|list[1:0] & list[2] |
		~|list[3:0] & list[4] | ~|list[5:0] & list[6] };
wire [2:0] listsel = p[0] ? ~pulsel_n : pshsel;
wire [2:0] pulsel = ~pulsel_n;

// PC

reg exec_ret1;
always @(posedge clk)
	exec_ret1 <= pul_ex & &listsel | i[RTS];
wire force_nop = ~active | exec_ret1 | ack;
wire [7:0] cond = { fwd_cc[N] ^ fwd_cc[V] | fwd_cc[Z],
	fwd_cc[N] ^ fwd_cc[V], fwd_cc[N], fwd_cc[V], fwd_cc[Z], fwd_cc[C],
	fwd_cc[Z] | fwd_cc[C], 1'b0 };
wire cond_ok = cond[o[3:1]] ~^ o[0];
wire [15:0] nextpc_normal = pc + bytes;
wire [15:0] nextpc_rel8 = nextpc_normal + { {8{ p2[7] }}, p2 };
wire [15:0] nextpc_rel16 = nextpc_normal + imm;
wire [15:0] nextpc = p[7:4] == 4'b0010 & cond_ok | i[BSR] ? nextpc_rel8 :
	pre10 & p2[7:4] == 4'b0010 & cond_ok | i[LBRALBSR] ? nextpc_rel16 :
	i[JMPJSR] & ind1 | exec_ret1 ? data_in :
	i[JMPJSR] ? ea :
	state & i[EXGTFR] ? r0 :
	nextpc_normal;
assign pc_out = active & ~(dbl_state & ~state) &
	~|listreg_d & ~ind & ~ack & ~i[RTI] ? nextpc : pc;
always @(posedge clk)
	pc <= active ? pc_out : data_in;

// address selector

wire [15:0] pshpul_sp = i[PSHPUL] & p[1] ? fwd_u : fwd_s;
wire t_psh = i[BSRJSR] | i[LBSR] | listsel[2];
wire psh_call = psh_ex | i[BSRJSR] | i[LBSR];
wire pul_ret = pul_ex | i[RTS];
assign adr_out = active ?
	~ind & (psh_call | pul_ret) ?
	pshpul_sp - { ~pul_ret & t_psh, ~pul_ret & ~t_psh } :
	ind1 ? data_in : ext_ind ? imm : ea :
	{ 12'hfff, ~vect_n, 1'b0 };

// write data (write only)

wire [7:0] wd8 = psh_ex ?
	sel4x8(listsel[1:0], { fwd_dp, fwd_b, fwd_a, fwd_cc }) :
	p[7] ? p[6] ? fwd_b : fwd_a : 0;
wire [1:0] sel_wd16 = psh_call ?
	{ i[BSRJSR] | i[LBSR] | listsel[1], i[BSRJSR] | i[LBSR] | listsel[0] } :
	{ o[6], ~o[6] & pre10 };
wire [15:0] wd16_su = i[PSHPUL] & p[1] ? fwd_s : fwd_u;
wire [15:0] wd16 = psh_call | o[1] ?
	sel4x16(sel_wd16, { ack ? pc : nextpc_normal, wd16_su, fwd_y, fwd_x }) :
	{ fwd_a, fwd_b };
wire wr_s0_l = ~state & ~ind & o[7] & |o[5:4] & &o[3:2] & o[0] |
	psh_ex & listsel[2] | i[BSR] | i[LBSR];
wire wr_s0_u = ~state & ~ind & p[7] & p[3:0] == 4'b0111 |
	psh_ex | dbl_state_lut[p[7:4]] & &p[3:0];
wire [15:0] wd_s0 = { wr_s0_l ? wd16[15:8] : wd8, wd16[7:0] };

//
// EXEC
//

reg pre10_1, pre11_1;
reg [7:0] o1;
reg [15:0] imm1;
reg [I1MAX:0] i1;
reg dbl_state1;
always @(posedge clk) begin
	pre10_1 <= pre10;
	pre11_1 <= pre11;
	o1 <= o;
	dbl_state1 <= dbl_state;
	i1 <= i[I1MAX:0];
	imm1 <= imm;
end

// ALU (8bit)

wire [15:0] unary_m_lut = 16'h3409;
wire [15:0] unary_vab_lut = 16'h0400, unary_vm_lut = 16'h0009;
wire [15:0] cy_lut = 16'h0204, cy_v_lut = 16'h1001;
wire [15:0] sel_logic_lut = 16'h0570;
wire [15:0] sel_shift_lut = 16'h03d0;
wire unary_m = unary_m_lut[o[3:0]];
wire unary_vab = unary_vab_lut[o[3:0]];
wire unary_vm = unary_vm_lut[o[3:0]];
wire t_unary_ab = o[7:5] == 3'b010;
reg unary_ab, add_a_and, add_b_and, add_a_xor, add_b_xor;
reg add_c_and, add_c_xor, alu_b_sel, sel_logic, sel_shift;
always @(posedge clk) begin
	unary_ab <= t_unary_ab;
	alu_b_sel <= o[7] & ~|o[5:4];
	add_a_and <= ~(~o[7] & (&o[3:0] | unary_m & ~t_unary_ab));
	add_b_and <= ~(~o[7] & (&o[3:0] | unary_m & t_unary_ab));
	add_a_xor <= ~o[7] & (t_unary_ab ? unary_vm : unary_vab);
	add_b_xor <= o[7] ? o[3:0] <= 2 : (t_unary_ab ? unary_vab : unary_vm);
	add_c_and <= o[7] & cy_lut[o[3:0]];
	add_c_xor <= o[7] ? o[3:0] <= 2 : cy_v_lut[o[3:0]];
	sel_logic <= o[7] & sel_logic_lut[o[3:0]];
	sel_shift <= unary_lut[o[7:4]] & sel_shift_lut[o[3:0]];
end
wire [7:0] alu_a = (o1[7] ? o1[6] : o1[4]) ? b : a;
wire [7:0] alu_b = alu_b_sel ? imm1[15:8] : data_in[15:8];
wire [7:0] logic_y = o1[2] ?
	o1[1] ? alu_b : alu_a & alu_b :
	o1[1] ? alu_a | alu_b : alu_a ^ alu_b;
wire [7:0] shift_a = unary_ab ? alu_a : alu_b;
wire [7:0] shift_y = o1[3] ? { shift_a[6:0], cc[C] & o1[0] } :
	{ o1[1] & (o1[0] ? shift_a[7] : cc[C]), shift_a[7:1] };
wire [7:0] add_a = alu_a & {8{ add_a_and }} ^ {8{ add_a_xor }};
wire [7:0] add_b = alu_b & {8{ add_b_and }} ^ {8{ add_b_xor }};
wire add_c = cc[C] & add_c_and ^ add_c_xor;
wire [8:0] add_y = add_a + add_b + add_c;
wire [7:0] alu_y = sel_shift | sel_logic ?
	sel_shift ? shift_y : logic_y : add_y[7:0];

// ALU (16bit)

reg add16_a_valid, sel16_d, sel16_data;
reg [15:0] ea1;
always @(posedge clk) begin
	add16_a_valid <= ~(i[LD16] | i[LEA]);
	sel16_d <= ~pre11 & o[0];
	sel16_data <= |o[5:4];
	ea1 <= ea;
end
wire [15:0] add16_at = pre11_1 ? o1[2] ? s : u : pre10_1 ? y : x;
wire [15:0] add16_a = add16_a_valid ? sel16_d ? { a, b } : add16_at : 0;
wire [15:0] add16_bt = o1[7] ? sel16_data ? data_in : imm1 : { 8'b0, b };
wire [15:0] add16_b = add16_bt ^ {16{ i1[SUBCMP16] }};
wire [16:0] add16_y = add16_a + add16_b + i1[SUBCMP16];
wire [15:0] mul_y = a * b;
wire [15:0] alu16_y = i1[MUL] ? mul_y :
	i1[SEX] ? { {8{ b[7] }}, b } :
	i1[LEA] ? ea1 : add16_y;

// write data (after read)

reg t_wr_s1_u;
always @(posedge clk)
	t_wr_s1_u <= dbl_state & ~i[EXGTFR];
wire wr_s1_u = state & t_wr_s1_u;
assign wr_l = wr_s0_l;
assign wr_u = wr_s0_u | wr_s1_u | wr_s0_l;
assign data_out = wr_s1_u ? { alu_y, 8'h00 } : wd_s0;

//
// UPDATE
//

// EXG/TFR

wire [15:0] dec_r0 = 16'b1 << p2[7:4];
wire [15:0] dec_r1 = 16'b1 << p2[3:0];
reg [7:0] p2_1;
reg [15:0] dec_tfr1;
always @(posedge clk) begin
	p2_1 <= p2;
	dec_tfr1 <= dec_r1;
end
wire [15:0] r0 = regsel(p2_1[7:4], { a, b, cc, dp }, { x, y, u, s, pc });
wire [15:0] r1 = regsel(p2_1[3:0], { a, b, cc, dp }, { x, y, u, s, pc });

//

wire load_ab4 = p[7:5] == 3'b010 & p[3:0] != 4'b1101;
wire load_ab6 = p[7] & ~(p[3] ? p[2] : p[0]);
wire idx_pp = idx & mode[7] & ~|mode[4:2];
reg load_d1, load_d_et1, psh_ex1, pul_ex1;
reg [2:0] pp_add1;
always @(posedge clk) begin
	load_d1 <= i[LDD] | i[ADDDSUBD] | i[MUL] | i[SEX];
	load_d_et1 <= i[EXGTFR] & (~o[0] & dec_r0[0] | dec_r1[0]);
	pp_add1 <= { idx_pp & mode[1] | psh_ex | i[BSRJSR] | i[LBSR],
		idx_pp & |mode[1:0] | psh_ex |
			i[BSRJSR] | i[LBSR] | i[RTS] | pul_ex & listsel[2],
		idx_pp & ~mode[0] | (psh_ex | pul_ex) & ~listsel[2] };
	psh_ex1 <= psh_ex;
	pul_ex1 <= pul_ex;
end
wire ren = ~dbl_state1 | state;

// A register

reg load_a1, load_a_pul1, load_a_et1;
always @(posedge clk) begin
	load_a1 <= ~ind & (load_ab4 & ~o[4] | load_ab6 & ~o[6]);
	load_a_pul1 <= ~ind & pul_ex & pulsel == 1;
	load_a_et1 <= ~ind & i[EXGTFR] & (~o[0] & dec_r0[8] | dec_r1[8]);
end
wire [7:0] fwd_a = load_a1 ? alu_y : load_d1 ? alu16_y[15:8] :
	load_d_et1 ? dec_tfr1[0] ? r0[15:8] : r1[15:8] :
	load_a_et1 ? dec_tfr1[8] ? r0[7:0] : r1[7:0] :
	load_a_pul1 ? data_in[15:8] :
	a;
always @(posedge clk)
	if (ren) a <= fwd_a;

// B register

reg load_b1, load_b_pul1, load_b_et1;
always @(posedge clk) begin
	load_b1 <= ~ind & (load_ab4 & o[4] | load_ab6 & o[6]);
	load_b_pul1 <= ~ind & pul_ex & pulsel == 2;
	load_b_et1 <= ~ind & i[EXGTFR] & (~o[0] & dec_r0[9] | dec_r1[9]);
end
wire [7:0] fwd_b = load_b1 ? alu_y : load_d1 ? alu16_y[7:0] :
	load_b_et1 | load_d_et1 ?
	(load_d_et1 ? dec_tfr1[0] : dec_tfr1[9]) ? r0[7:0] : r1[7:0] :
	load_b_pul1 ? data_in[15:8] :
	b;
always @(posedge clk)
	if (ren) b <= fwd_b;

// X register

reg load_x1, load_x_pul1, load_x_add1, load_x_et1;
always @(posedge clk) begin
	load_x1 <= ~ind & (i[LDXYUS] & ~pre10 & ~o[6] |
		i[LEA] & p[1:0] == 2'b00 | i[ABX]);
	load_x_pul1 <= ~ind & pul_ex & pulsel == 4;
	load_x_add1 <= ~ind & idx_pp & mode[6:5] == 2'b00;
	load_x_et1 <= ~ind & i[EXGTFR] & (~o[0] & dec_r0[1] | dec_r1[1]);
end
wire [15:0] fwd_x = load_x1 ? alu16_y :
	load_x_et1 ? dec_tfr1[1] ? r0 : r1 :
	load_x_pul1 ? data_in :
	load_x_add1 ? x + { {13{ pp_add1[2] }}, pp_add1 } :
	x;
always @(posedge clk)
	if (ren) x <= fwd_x;

// Y register

reg load_y1, load_y_pul1, load_y_add1, load_y_et1;
always @(posedge clk) begin
	load_y1 <= ~ind &
		(i[LDXYUS] & pre10 & ~o[6] | i[LEA] & p[1:0] == 2'b01);
	load_y_pul1 <= ~ind & pul_ex & pulsel == 5;
	load_y_add1 <= ~ind & idx_pp & mode[6:5] == 2'b01;
	load_y_et1 <= ~ind & i[EXGTFR] & (~o[0] & dec_r0[2] | dec_r1[2]);
end
wire [15:0] fwd_y = load_y1 ? alu16_y :
	load_y_et1 ? dec_tfr1[2] ? r0 : r1 :
	load_y_pul1 ? data_in :
	load_y_add1 ? y + { {13{ pp_add1[2] }}, pp_add1 } :
	y;
always @(posedge clk)
	if (ren) y <= fwd_y;

// U register

reg load_u1, load_u_pul1, load_u_add1, load_u_et1;
always @(posedge clk) begin
	load_u1 <= ~ind &
		(i[LDXYUS] & ~pre10 & o[6] | i[LEA] & p[1:0] == 2'b11);
	load_u_pul1 <= ~ind & pul_ex & ^o[2:1] & pulsel == 6;
	load_u_add1 <= ~ind & (idx_pp & mode[6:5] == 2'b10 |
		(psh_ex | pul_ex) & o[1] & ~i[RTI] & ~ack);
	load_u_et1 <= ~ind & i[EXGTFR] & (~o[0] & dec_r0[3] | dec_r1[3]);
end
wire [15:0] fwd_u = load_u1 ? alu16_y :
	load_u_et1 ? dec_tfr1[3] ? r0 : r1 :
	load_u_pul1 ? data_in :
	load_u_add1 ? u + { {13{ pp_add1[2] }}, pp_add1 } :
	u;
always @(posedge clk)
	if (ren) u <= fwd_u;

// S register

reg load_s1, load_s_pul1, load_s_add1, load_s_et1;
always @(posedge clk) begin
	load_s1 <= ~ind &
		(i[LDXYUS] & pre10 & o[6] | i[LEA] & p[1:0] == 2'b10);
	load_s_pul1 <= ~ind & pul_ex & &o[2:1] & pulsel == 6;
	load_s_add1 <= ~ind & (idx_pp & mode[6:5] == 2'b11 |
		(psh_ex | pul_ex) & ~o[1] |
		i[BSRJSR] | i[LBSR] | i[RTS] | i[RTI] | ack);
	load_s_et1 <= ~ind & i[EXGTFR] & (~o[0] & dec_r0[4] | dec_r1[4]);
end
wire [15:0] fwd_s = load_s1 ? alu16_y :
	load_s_et1 ? dec_tfr1[4] ? r0 : r1 :
	load_s_pul1 ? data_in :
	load_s_add1 ? s + { {13{ pp_add1[2] }}, pp_add1 } :
	s;
always @(posedge clk)
	if (ren) s <= fwd_s;

// DP register

reg load_dp_pul1, load_dp_et1;
always @(posedge clk) begin
	load_dp_pul1 <= ~ind & pul_ex & pulsel == 3;
	load_dp_et1 <= ~ind & i[EXGTFR] & (~o[0] & dec_r0[11] | dec_r1[11]);
end
wire [7:0] fwd_dp = load_dp_et1 ? dec_tfr1[11] ? r0[7:0] : r1[7:0] :
	load_dp_pul1 ? data_in[15:8] :
	dp;
always @(posedge clk)
	if (reset) dp <= 0;
	else if (ren) dp <= fwd_dp;

// CC register

wire zn8 = i[MOV8] | i[ADD8] | i[SUB8] |
	i[COM] | i[LEFT] | i[RIGHT] | i[INC] | i[DEC];
wire zn16 = i[ADD16] | i[SUB16] | i[MOV16] | i[SEX];
reg load_cc_pul1, load_cc_et1, zn8_1, zn8st1, zn16_1, zn16st1, zn16leaxy1;
reg t_z8st1, t_z16st1, t_n8st1, t_n16st1;
always @(posedge clk) begin
	load_cc_pul1 <= ~ind & pul_ex & pulsel == 0;
	load_cc_et1 <= ~ind & i[EXGTFR] & (~o[0] & dec_r0[10] | dec_r1[10]);
	zn8_1 <= zn8;
	zn8st1 <= i[ST8];
	zn16_1 <= zn16;
	zn16st1 <= i[ST16];
	zn16leaxy1 <= zn16 | i[LEAXY];
	t_z8st1 <= ~|wd8;
	t_z16st1 <= ~|wd16;
	t_n8st1 <= wd8[7];
	t_n16st1 <= wd16[15];
end

wire v8 = add_a[7] & add_b[7] & ~add_y[7] |
	~add_a[7] & ~add_b[7] & add_y[7];
wire v16 = add16_a[15] & add16_b[15] & ~add16_y[15] |
	~add16_a[15] & ~add16_b[15] & add16_y[15];

wire t_c = i1[ADD8] & add_y[8] | i1[SUB8COM] & ~add_y[8] |
	i1[ADD16] & add16_y[16] | i1[SUB16] & ~add16_y[16] |
	i1[LEFT] & shift_a[7] | i1[RIGHT] & shift_a[0] |
	i1[MUL] & mul_y[7];
wire t_v = i1[ADDSUB8] & v8 |
	i1[ADDSUB16] & v16 |
	i1[LEFT] & ^shift_a[7:6];
wire t_z = zn8_1 & ~|alu_y | zn16leaxy1 & ~|alu16_y |
	zn8st1 & t_z8st1 | zn16st1 & t_z16st1 |
	i1[MUL] & ~|mul_y;
wire t_n = zn8_1 & alu_y[7] | zn16_1 & alu16_y[15] |
	zn8st1 & t_n8st1 | zn16st1 & t_n16st1;

wire t_update = i[ADD8] | i[ADD16] | i[SUB8] | i[SUB16] | i[COM] | i[LEFT];
reg update_c, update_v, update_z, update_n, update_i, update_f, update_e;
always @(posedge clk) begin
	update_c <= ~ind & (t_update | i[RIGHT] | i[MUL]);
	update_v <= ~ind & (t_update | i[MOV8] | i[MOV16] | i[INC] | i[DEC]);
	update_z <= ~ind & (zn8 | zn16 | i[LEAXY] | i[MUL]);
	update_n <= ~ind & (zn8 | zn16);
	update_i <= ~ind & (iack | swiack) & ~|listreg_d;
	update_f <= ~ind & (fiack | swiack) & ~|listreg_d;
	update_e <= ~ind & ack;
end

wire [7:0] fwd_cc = load_cc_et1 ? dec_tfr1[10] ? r0[7:0] : r1[7:0] :
	i1[ANDORCC_CWAI] ? o1[2] ? cc & imm1[15:8] : cc | imm1[15:8] :
	load_cc_pul1 ? data_in[15:8] : {
	ren & update_e ? ~fiack : cc[7],
	ren & update_f ? 1'b1 : cc[6],
	cc[5],
	ren & update_i ? 1'b1 : cc[4],
	ren & update_n ? t_n : cc[3],
	ren & update_z ? t_z : cc[2],
	ren & update_v ? t_v : cc[1],
	ren & update_c ? t_c : cc[0]
};

always @(posedge clk)
	if (reset) cc <= 8'hff;
	else cc <= fwd_cc;


wire [7:0] cs = fwd_cc[C] === 1 ? "C" : fwd_cc[C] === 0 ? "-" : "?";
wire [7:0] vs = fwd_cc[V] === 1 ? "V" : fwd_cc[V] === 0 ? "-" : "?";
wire [7:0] zs = fwd_cc[Z] === 1 ? "Z" : fwd_cc[Z] === 0 ? "-" : "?";
wire [7:0] ns = fwd_cc[N] === 1 ? "N" : fwd_cc[N] === 0 ? "-" : "?";
wire [7:0] is = fwd_cc[I] === 1 ? "I" : fwd_cc[I] === 0 ? "-" : "?";
wire [7:0] fs = fwd_cc[F] === 1 ? "F" : fwd_cc[F] === 0 ? "-" : "?";
wire [7:0] es = fwd_cc[E] === 1 ? "E" : fwd_cc[E] === 0 ? "-" : "?";
initial $monitor("%x %x %x %x %x %x %x %x %x %s%s%s-%s%s%s%s %x%xM %x %x %x",
	pc, force_nop, o, fwd_a, fwd_b, fwd_x, fwd_y, fwd_u, fwd_s,
	es, fs, is, ns, zs, vs, cs, wr_u, wr_l, adr_out, data_out, data_in);
endmodule
