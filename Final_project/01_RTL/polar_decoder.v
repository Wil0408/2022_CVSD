module polar_decoder (
    input           clk,
    input           rst_n,
    input           module_en,
    output          proc_done,
    output  [ 10:0] raddr,
    input   [191:0] rdata,
    output  [  5:0] waddr,
    output  [139:0] wdata
    );
// IO description
// input  wire         clk;
// input  wire         rst_n;
// input  wire         module_en;
// input  wire [191:0] rdata;
// output wire [ 10:0] raddr;
// output wire [  5:0] waddr;
// output wire [139:0] wdata;
// output wire         proc_done;

parameter   IDLE = 0,
	    LOAD_PACKET = 1,
	    LOAD_INFO   = 2,
	    LOAD_LLR    = 3,
	    // N128_DECODE = 4,
	    // N256_DECODE = 5,
	    // N512_DECODE = 6,
	    INTER_BUF   = 4,
	    DECODE      = 5,
	    FINISH      = 7;

// global
reg     [4:0]   cnt, cnt_nxt;
reg     [3:0]   stage_cnt, stage_cnt_nxt;
reg     [6:0]   cur_packet, cur_packet_nxt;
reg     [8:0]   stage_flag, stage_flag_nxt;

// info
reg     [9:0]   N;  // u9.0
reg     [7:0]   K;  // u7.0

// computing
wire    signed  [21:0]  f_z_nxt[0:15];
wire                    f_msb[0:15];
wire            [20:0]  f_min[0:15];
wire            [20:0]  f_min_inv[0:15];
reg     signed  [21:0]  f_a[0:15], f_b[0:15];
wire            [20:0]  f_a_abs[0:15], f_b_abs[0:15];
// reg     signed  [21:0]  f_z[0:15];

wire    signed  [21:0]  g_z_nxt[0:15];
reg     signed  [21:0]  g_a[0:15], g_b[0:15];
// reg     signed  [21:0]  g_z[0:15];
reg                     g_u[0:15];

integer i, j;

// ========================================
// FSM
// ========================================

reg     [2:0]   state, state_nxt;
reg     [6:0]   packet_num; // u6.0

always @* begin
        cur_packet_nxt = cur_packet;

        case(state)
        IDLE: begin
            state_nxt = (module_en)? LOAD_PACKET: IDLE;
        end
        LOAD_PACKET: begin
            state_nxt = LOAD_INFO;
        end
        LOAD_INFO: begin
            state_nxt = (cnt == 1)? LOAD_LLR: LOAD_INFO;
        end
        LOAD_LLR: begin
            if (N[7] == 1) begin
                state_nxt = (cnt == 3)? INTER_BUF: LOAD_LLR;
            end
            else if (N[8] == 1) begin
                state_nxt = (cnt == 7)? INTER_BUF: LOAD_LLR;
            end
            else begin
                state_nxt = (cnt == 15)? INTER_BUF: LOAD_LLR;
            end
        end
        INTER_BUF: begin
            state_nxt = DECODE;
        end
        DECODE: begin
            if (stage_flag[8:0] == 9'b000000001) begin
                state_nxt = (cur_packet == packet_num-1)? FINISH: LOAD_INFO;
                cur_packet_nxt = cur_packet+1;
            end
            else begin
                state_nxt = DECODE;
            end
        end
        FINISH: begin
            state_nxt = (cnt == 1)? IDLE: FINISH;
            cur_packet_nxt = (cnt == 1)? 0: cur_packet;
        end
        default: begin
            state_nxt = IDLE;
        end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= 0;
            packet_num <= 0;
            cur_packet <= 0;
            N       <= 0;
            K       <= 0;
        end
        else begin
            state <= state_nxt;
            packet_num <= (state == LOAD_PACKET)? rdata : packet_num;
            cur_packet <= cur_packet_nxt;
            N <= (state == LOAD_INFO && cnt == 1)? rdata[ 9:0] : N;
            K <= (state == LOAD_INFO && cnt == 1)? rdata[16:10] : K;
        end
    end

    // ========================================
    // Counter
    // ========================================

    always @* begin
        case (state)
        LOAD_INFO: begin
            cnt_nxt = (cnt == 1)? 0: cnt+1;
        end
        LOAD_LLR: begin
            if (N[7] == 1) begin
                cnt_nxt = (cnt == 3)? 0: cnt+1;
            end
            else if (N[8] == 1) begin
                cnt_nxt = (cnt == 7)? 0: cnt+1;
            end
            else begin
                cnt_nxt = (cnt == 15)? 0: cnt+1;
            end
        end
        DECODE: begin
            case (stage_cnt)
            8: cnt_nxt = (cnt == 15)? 0: cnt+1;
            7: cnt_nxt = (cnt == 7 )? 0: cnt+1;
            6: cnt_nxt = (cnt == 3 )? 0: cnt+1;
            5: cnt_nxt = (cnt == 1 )? 0: cnt+1;
            default: cnt_nxt = 0;
            endcase
        end
        FINISH: begin
            cnt_nxt = (cnt == 1)? 0: cnt+1;
        end
        default: begin
            cnt_nxt = 0;
        end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 0;
        end
        else begin
            cnt     <= cnt_nxt;
        end
    end

    // ========================================
    // Stage flag
    // ========================================

    always @* begin
        stage_flag_nxt = stage_flag;

        if (state == DECODE) begin
            if (stage_cnt == 8 && cnt == 15) begin
                stage_flag_nxt[8] = ~stage_flag[8];
            end
            else if (stage_cnt == 7 && cnt == 7) begin
                stage_flag_nxt[7] = ~stage_flag[7];
            end
            else if (stage_cnt == 6 && cnt == 3) begin
                stage_flag_nxt[6] = ~stage_flag[6];
            end
            else if (stage_cnt == 5 && cnt == 1) begin
                stage_flag_nxt[5] = ~stage_flag[5];
            end
            else if (stage_cnt <= 4) begin
                stage_flag_nxt[stage_cnt] = ~stage_flag[stage_cnt];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage_flag <= 0;
        end
        else begin
            stage_flag <= stage_flag_nxt;
        end
    end

    // ========================================
    // Stage counter
    // ========================================

    always @* begin
        if (state == DECODE) begin
            if (stage_cnt == 0) begin
                if (stage_flag[0] == 1'b0) begin
                    stage_cnt_nxt = 0;
                end
                else if (stage_flag[1] == 1'b1) begin
                    stage_cnt_nxt = 1;
                end
                else if (stage_flag[2] == 1'b1) begin
                    stage_cnt_nxt = 2;
                end
                else if (stage_flag[3] == 1'b1) begin
                    stage_cnt_nxt = 3;
                end
                else if (stage_flag[4] == 1'b1) begin
                    stage_cnt_nxt = 4;
                end
                else if (stage_flag[5] == 1'b1) begin
                    stage_cnt_nxt = 5;
                end
                else if (stage_flag[6] == 1'b1) begin
                    stage_cnt_nxt = 6;
                end
                else if (stage_flag[7] == 1'b1) begin
                    stage_cnt_nxt = 7;
                end
                else begin
                    if (N[7] == 1'b1) begin
                        stage_cnt_nxt = 6;
                    end
                    else if (N[8] == 1'b1) begin
                        stage_cnt_nxt = 7;
                    end
                    else begin
                        stage_cnt_nxt = 8;
                    end
                end
            end
            else begin
                if (stage_cnt == 8) begin
                    stage_cnt_nxt = (cnt == 15)? stage_cnt-1: stage_cnt;
                end
                else if (stage_cnt == 7) begin
                    stage_cnt_nxt = (cnt == 7)? stage_cnt-1: stage_cnt;
                end
                else if (stage_cnt == 6) begin
                    stage_cnt_nxt = (cnt == 3)? stage_cnt-1: stage_cnt;
                end
                else if (stage_cnt == 5) begin
                    stage_cnt_nxt = (cnt == 1)? stage_cnt-1: stage_cnt;
                end
                else begin
                    stage_cnt_nxt = stage_cnt-1;
                end
            end
        end
        else if (state == INTER_BUF) begin
            if (N[7] == 1'b1) begin
                stage_cnt_nxt = 6;
            end
            else if (N[8] == 1'b1) begin
                stage_cnt_nxt = 7;
            end
            else begin
                stage_cnt_nxt = 8;
            end
        end
        else begin
            stage_cnt_nxt = 0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage_cnt   <= 0;
        end
        else begin
            stage_cnt   <= stage_cnt_nxt;
        end
    end

    // ========================================
    // Restart flag
    // ========================================    

    reg     restart_flag, restart_flag_nxt;
    reg     restart_flag_delay;

    always @* begin
        restart_flag_nxt = restart_flag;

        if (state == DECODE) begin
            if (N[7]) begin
                if (stage_cnt == 2 && stage_flag[6:0] == 7'b1000100) begin
                    restart_flag_nxt = 1;
                end
                else if (stage_cnt == 1 && stage_flag[6:0] == 7'b1000010) begin
                    restart_flag_nxt = 0;
                end
            end
            else if (N[8]) begin
                if (stage_cnt == 0 && stage_flag[7:0] == 8'b10000111) begin
                    restart_flag_nxt = 1;
                end
                else if (stage_cnt == 1 && stage_flag[7:0] == 8'b10000010) begin
                    restart_flag_nxt = 0;
                end
            end
            else begin
                if (stage_cnt == 0 && stage_flag[8:0] == 9'b100001011) begin
                    restart_flag_nxt = 1;
                end
                else if (stage_cnt == 1 && stage_flag[8:0] == 9'b100000010) begin
                    restart_flag_nxt = 0;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            restart_flag <= 0;
            restart_flag_delay <= 0;
        end 
        else begin
            restart_flag <= restart_flag_nxt;
            restart_flag_delay <= restart_flag;
        end
    end

    // ========================================
    // LLR mem
    // ========================================

    reg     [10:0]  read_addr, read_addr_nxt;

    assign raddr = read_addr;

    always @* begin
        read_addr_nxt = read_addr;

        case(state)
        IDLE: begin
            read_addr_nxt = 0;
        end
        LOAD_PACKET: begin
            // read_addr_nxt = 1+(cur_packet<<5)+cur_packet;
            read_addr_nxt = 1;
        end
        LOAD_INFO: begin
            read_addr_nxt = read_addr+1;
        end
        LOAD_LLR: begin
            if (N[7] == 1) begin
                read_addr_nxt = read_addr+1;
            end
            else if (N[8] == 1) begin
                read_addr_nxt = read_addr+1;
            end
            else begin
                read_addr_nxt = read_addr+1;
            end
        end
        INTER_BUF: begin
            read_addr_nxt = read_addr+1;
        end
        DECODE: begin
            if (N[7] == 1'b1) begin
                if (stage_cnt == 6 && cnt < 2) begin
                    read_addr_nxt = read_addr+1;
                end
                else if (stage_cnt == 6 && cnt == 2) begin
                    read_addr_nxt = (stage_flag[6])? read_addr+24: read_addr-8;
                end
                else if (restart_flag || (stage_cnt == 0 && stage_flag[6:1] == 6'b100000)) begin
                    read_addr_nxt = read_addr+1;
                end
            end
            else if (N[8] == 1'b1) begin
                if (stage_cnt == 7 && cnt < 6) begin
                    read_addr_nxt = read_addr+1;
                end
                else if (stage_cnt == 7 && cnt == 6) begin
                    read_addr_nxt = (stage_flag[7])? read_addr+16: read_addr-16;
                end
                else if (restart_flag || (stage_cnt == 0 && stage_flag[7:1] == 7'b1000000)) begin
                    read_addr_nxt = read_addr+1;
                end
            end
            else begin
                if (stage_cnt == 8 && cnt < 14) begin
                    read_addr_nxt = read_addr+1;
                end
                else if (stage_cnt == 8 && cnt == 14) begin
                    read_addr_nxt = (stage_flag[8])? read_addr+0: read_addr-32;
                end
                else if (restart_flag || (stage_cnt == 0 && stage_flag[8:1] == 8'b10000000)) begin
                    read_addr_nxt = read_addr+1;
                end
            end
        end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_addr        <= 0;
        end
        else begin
            read_addr        <= read_addr_nxt;
        end
    end

    // ========================================
    // u generator
    // ========================================

    reg     u   [0:511];
    reg     u_0 [0:511];
    reg     u_1 [0:511];
    reg     u_2 [0:511];
    reg     u_3 [0:511];
    reg     u_4 [0:511];
    reg     u_5 [0:511];
    reg     u_6 [0:511];
    reg     u_7 [0:511];
    reg     u_8 [0:511];

    always @* begin
        // stage1: use u_0[i-1]
        for (i=0; i<512; i=i+1) begin
            u_0[i] = u[i];
        end

        // stage2: use u_1[i-2]
        for (i=0; i<512; i=i+1) begin
            if (i[0]) u_1[i] = u_0[i];
            else      u_1[i] = u_0[i]^u_0[i+  1];
        end

        // stage3: use u_2[i-4]
        for (i=0; i<512; i=i+1) begin
            if (i[1]) u_2[i] = u_1[i];
            else      u_2[i] = u_1[i]^u_1[i+  2];
        end

        // stage4: use u_3[i-8]
        for (i=0; i<512; i=i+1) begin
            if (i[2]) u_3[i] = u_2[i];
            else      u_3[i] = u_2[i]^u_2[i+  4];
        end

        // stage5: use u_4[i-16]
        for (i=0; i<512; i=i+1) begin
            if (i[3]) u_4[i] = u_3[i];
            else      u_4[i] = u_3[i]^u_3[i+  8];
        end

        // stage6: use u_5[i-32]
        for (i=0; i<512; i=i+1) begin
            if (i[4]) u_5[i] = u_4[i];
            else      u_5[i] = u_4[i]^u_4[i+ 16];
        end

        // stage7: use u_6[i-64]
        for (i=0; i<512; i=i+1) begin
            if (i[5]) u_6[i] = u_5[i];
            else      u_6[i] = u_5[i]^u_5[i+ 32];
        end

        // stage8: use u_7[i-128]
        for (i=0; i<512; i=i+1) begin
            if (i[6]) u_7[i] = u_6[i];
            else      u_7[i] = u_6[i]^u_6[i+ 64];
        end

        // stage9: use u_8[i-256]
        for (i=0; i<512; i=i+1) begin
            if (i[7]) u_8[i] = u_7[i];
            else      u_8[i] = u_7[i]^u_7[i+128];
        end
    end

    // ========================================
    // stage buffer
    // ========================================

    reg signed    [12:0]  stage_buf_8[0:255];
    reg signed    [13:0]  stage_buf_7[0:127];
    reg signed    [14:0]  stage_buf_6[0:63];
    reg signed    [15:0]  stage_buf_5[0:31];
    reg signed    [16:0]  stage_buf_4[0:15];
    reg signed    [17:0]  stage_buf_3[0:7];
    reg signed    [18:0]  stage_buf_2[0:3];
    reg signed    [19:0]  stage_buf_1[0:1];
    // reg signed    [20:0]  stage_buf_0[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<256; i=i+1) begin
                stage_buf_8[i] <= 0;
            end

            for (i=0; i<128; i=i+1) begin
                stage_buf_7[i] <= 0;
            end

            for (i=0; i<64; i=i+1) begin
                stage_buf_6[i] <= 0;
            end

            for (i=0; i<32; i=i+1) begin
                stage_buf_5[i] <= 0;
            end

            for (i=0; i<16; i=i+1) begin
                stage_buf_4[i] <= 0;
            end

            for (i=0; i<8; i=i+1) begin
                stage_buf_3[i] <= 0;
            end

            for (i=0; i<4; i=i+1) begin
                stage_buf_2[i] <= 0;
            end

            for (i=0; i<2; i=i+1) begin
                stage_buf_1[i] <= 0;
            end

            // for (i=0; i<1; i=i+1) begin
            //     stage_buf_0[i] <= 0;
            // end
        end
        else begin
            if (state == LOAD_LLR || (state == DECODE && restart_flag_delay == 1'b1)) begin
                // stage_buf_8
                if (N[8] == 1) begin
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_8[{4'b0111,i[3:0]}] <= $signed(rdata[(12*i[3:0])+:12]);
                    end

                    for (i=0; i<7; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_8[(i<<4)+j] <= stage_buf_8[((i+1)<<4)+j];
                        end
                    end
                end
                else begin
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_8[{4'b1111,i[3:0]}] <= $signed(rdata[(12*i[3:0])+:12]);
                    end

                    for (i=0; i<15; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_8[(i<<4)+j] <= stage_buf_8[((i+1)<<4)+j];
                        end
                    end
                end

                // stage_buf_7
                if (N[7] == 1) begin
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_7[{3'b011,i[3:0]}] <= $signed(rdata[(12*i[3:0])+:12]);
                    end
                    
                    for (i=0; i<3; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_7[(i<<4)+j] <= stage_buf_7[((i+1)<<4)+j];
                        end
                    end
                end
            end
            else if (state == DECODE) begin
                if (stage_cnt == 8) begin
                    // group 0-16 shift, store
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_8[{4'b1111,i[3:0]}] <= (stage_flag[8])? g_z_nxt[i]: f_z_nxt[i];
                    end
                    for (i=0; i<15; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_8[(i<<4)+j] <= stage_buf_8[((i+1)<<4)+j];
                        end
                    end
                end
                else if (stage_cnt == 7) begin
                    // group 0-7 shift, input
                    for (j=0; j<16; j=j+1) begin
                        stage_buf_8[{4'b0111,j[3:0]}] <= stage_buf_8[j];
                    end
                    for (i=0; i<7; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_8[(i<<4)+j] <= stage_buf_8[((i+1)<<4)+j];
                        end
                    end

                    // group 8-15 shift, input
                    for (j=0; j<16; j=j+1) begin
                        stage_buf_8[{4'b1111,j[3:0]}] <= stage_buf_8[{4'b1000,j[3:0]}];
                    end
                    for (i=8; i<15; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_8[(i<<4)+j] <= stage_buf_8[((i+1)<<4)+j];
                        end
                    end

                    // group 0-7 shift, store
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_7[{3'b111,i[3:0]}] <= (stage_flag[7])? g_z_nxt[i]: f_z_nxt[i];
                    end
                    for (i=0; i<7; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_7[(i<<4)+j] <= stage_buf_7[((i+1)<<4)+j];
                        end
                    end
                end
                else if (stage_cnt == 6) begin
                    // group 0-3 shift, input
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_7[{3'b011,i[3:0]}] <= stage_buf_7[i];
                    end
                    for (i=0; i<3; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_7[(i<<4)+j] <= stage_buf_7[((i+1)<<4)+j];
                        end
                    end

                    // group 4-7 shift, input
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_7[{3'b111,i[3:0]}] <= stage_buf_7[{3'b100,i[3:0]}];
                    end
                    for (i=4; i<7; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_7[(i<<4)+j] <= stage_buf_7[((i+1)<<4)+j];
                        end
                    end
                end
            end


            if (state == DECODE) begin
                if (stage_cnt == 8) begin
                    // buffer input data, input
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_4[i] <= $signed(rdata[(12*i[3:0])+:12]);
                    end
                end
                else if (stage_cnt == 7) begin
                    // buffer input data, input
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_4[i] <= $signed(rdata[(12*i[3:0])+:12]);
                    end
                end
                else if (stage_cnt == 6) begin
                    // group 0-3 shift, store
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_6[{2'b11,i[3:0]}] <= (stage_flag[6])? g_z_nxt[i]: f_z_nxt[i];
                    end
                    for (i=0; i<3; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_6[(i<<4)+j] <= stage_buf_6[((i+1)<<4)+j];
                        end
                    end

                    // buffer input data, input
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_4[i] <= $signed(rdata[(12*i[3:0])+:12]);
                    end
                end
                else if (stage_cnt == 5) begin
                    // group 0-1 shift, input
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_6[{2'b01,i[3:0]}] <= stage_buf_6[{2'b00,i[3:0]}];
                    end
                    for (i=0; i<1; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_6[(i<<4)+j] <= stage_buf_6[((i+1)<<4)+j];
                        end
                    end

                    // group 2-3 shift, input
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_6[{2'b11,i[3:0]}] <= stage_buf_6[{2'b10,i[3:0]}];
                    end
                    for (i=2; i<3; i=i+1) begin
                        for (j=0; j<16; j=j+1) begin
                            stage_buf_6[(i<<4)+j] <= stage_buf_6[((i+1)<<4)+j];
                        end
                    end

                    // group 0-1 shift store
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_5[{1'b1,i[3:0]}] <= (stage_flag[5])? g_z_nxt[i]: f_z_nxt[i];
                    end
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_5[{1'b0,i[3:0]}] <= stage_buf_5[{1'b1,i[3:0]}];
                    end
                end
                else if (stage_cnt == 4) begin
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_4[i] <= (stage_flag[4])? g_z_nxt[i]: f_z_nxt[i];
                    end
                end
                else if (stage_cnt == 3) begin
                    for (i=0; i<8; i=i+1) begin
                        stage_buf_3[i] <= (stage_flag[3])? g_z_nxt[i]: f_z_nxt[i];
                    end
                end
                else if (stage_cnt == 2) begin
                    for (i=0; i<4; i=i+1) begin
                        stage_buf_2[i] <= (stage_flag[2])? g_z_nxt[i]: f_z_nxt[i];
                    end
                end
                else if (stage_cnt == 1) begin
                    for (i=0; i<2; i=i+1) begin
                        stage_buf_1[i] <= (stage_flag[1])? g_z_nxt[i]: f_z_nxt[i];
                    end
                end
                else if (stage_cnt == 0 && stage_flag[5:1] == 0) begin
                    for (i=0; i<16; i=i+1) begin
                        stage_buf_4[i] <= $signed(rdata[(12*i[3:0])+:12]);
                    end
                end
            end
            else if (state == INTER_BUF) begin
                for (i=0; i<16; i=i+1) begin
                    stage_buf_4[i] <= $signed(rdata[(12*i[3:0])+:12]);
                end
            end
        end
    end

    // ========================================
    // LLR decoder (f)
    // ========================================

    generate
    genvar gen_i;
    for (gen_i=0; gen_i<16; gen_i=gen_i+1) begin: f_gen
        assign f_a_abs[gen_i] = (f_a[gen_i][21])? ~f_a[gen_i][20:0]+1: f_a[gen_i][20:0];
        assign f_b_abs[gen_i] = (f_b[gen_i][21])? ~f_b[gen_i][20:0]+1: f_b[gen_i][20:0];

        assign f_msb[gen_i] = f_a[gen_i][21]^f_b[gen_i][21];
        assign f_min[gen_i] = (f_a_abs[gen_i][20:0]>f_b_abs[gen_i][20:0])? f_b_abs[gen_i][20:0]:
                                                                           f_a_abs[gen_i][20:0];
        assign f_min_inv[gen_i] = ~f_min[gen_i]+1;
        assign f_z_nxt[gen_i] = (f_msb[gen_i])? {1'b1,f_min_inv[gen_i]}: {1'b0,f_min[gen_i]};
    end
    endgenerate

    always @* begin
        for (i=0; i<16; i=i+1) begin
            f_a[i] = 0;
            f_b[i] = 0;
        end

        if (stage_cnt == 8) begin
            for (i=0; i<16; i=i+1) begin
                f_a[i] = stage_buf_8[i];
                f_b[i] = stage_buf_4[i];
            end
        end
        else if (stage_cnt == 7) begin
            for (i=0; i<16; i=i+1) begin
                f_a[i] = stage_buf_8[i[3:0]];
                f_b[i] = (N[8])? stage_buf_4[i]: stage_buf_8[{1'b1,3'b0,i[3:0]}];
            end
        end
        else if (stage_cnt == 6) begin
            for (i=0; i<16; i=i+1) begin
                f_a[i] = stage_buf_7[i[3:0]];
                f_b[i] = (N[7])? stage_buf_4[i]: stage_buf_7[{1'b1,2'b0,i[3:0]}];
            end
        end
        else if (stage_cnt == 5) begin
            for (i=0; i<16; i=i+1) begin
                f_a[i] = stage_buf_6[i[3:0]];
                f_b[i] = stage_buf_6[{1'b1,1'b0,i[3:0]}];
            end
        end
        else if (stage_cnt == 4) begin
            for (i=0; i<16; i=i+1) begin
                f_a[i] = stage_buf_5[i];
                f_b[i] = stage_buf_5[i+16];
            end
        end
        else if (stage_cnt == 3) begin
            for (i=0; i<8; i=i+1) begin
                f_a[i] = stage_buf_4[i];
                f_b[i] = stage_buf_4[i+8];
            end
        end
        else if (stage_cnt == 2) begin
            for (i=0; i<4; i=i+1) begin
                f_a[i] = stage_buf_3[i];
                f_b[i] = stage_buf_3[i+4];
            end
        end
        else if (stage_cnt == 1) begin
            for (i=0; i<2; i=i+1) begin
                f_a[i] = stage_buf_2[i];
                f_b[i] = stage_buf_2[i+2];
            end
        end
        else if (stage_cnt == 0) begin
            for (i=0; i<1; i=i+1) begin
                f_a[i] = stage_buf_1[i];
                f_b[i] = stage_buf_1[i+1];
            end
        end
    end

    // ========================================
    // LLR decoder (g)
    // ========================================

    generate
    genvar gen_j;
    for (gen_j=0; gen_j<16; gen_j=gen_j+1) begin: g_gen
        assign g_z_nxt[gen_j] = (g_u[gen_j])? $signed(g_b[gen_j])-$signed(g_a[gen_j]):
                                              $signed(g_b[gen_j])+$signed(g_a[gen_j]);
    end
    endgenerate

    always @* begin
        for (i=0; i<16; i=i+1) begin
            g_a[i] = 0;
            g_b[i] = 0;
            g_u[i] = 0;
        end

        if (stage_cnt == 8) begin
            for (i=0; i<16; i=i+1) begin
                g_a[i] = stage_buf_8[i];
                g_b[i] = stage_buf_4[i];
                // g_u[i] = u_8[i[7:0]];
                g_u[i] = u_8[{cnt[3:0],i[3:0]}];
            end
        end
        else if (stage_cnt == 7) begin
            for (i=0; i<16; i=i+1) begin
                g_a[i] = stage_buf_8[i[3:0]];
                g_b[i] = (N[8])? stage_buf_4[i]: stage_buf_8[{1'b1,3'b0,i[3:0]}];
                g_u[i] = u_7[{~stage_flag[8],1'b0,{cnt[2:0],i[3:0]}}];
            end
        end
        else if (stage_cnt == 6) begin
            for (i=0; i<16; i=i+1) begin
                g_a[i] = stage_buf_7[i[3:0]];
                g_b[i] = (N[7])? stage_buf_4[i]: stage_buf_7[{1'b1,2'b0,i[3:0]}];
                g_u[i] = u_6[{~stage_flag[8:7],1'b0,{cnt[1:0],i[3:0]}}];
            end
        end
        else if (stage_cnt == 5) begin
            for (i=0; i<16; i=i+1) begin
                g_a[i] = stage_buf_6[i[3:0]];
                g_b[i] = stage_buf_6[{1'b1,1'b0,i[3:0]}];
                g_u[i] = u_5[{~stage_flag[8:6],1'b0,{cnt[0],i[3:0]}}];
            end
        end
        else if (stage_cnt == 4) begin
            for (i=0; i<16; i=i+1) begin
                g_a[i] = stage_buf_5[i];
                g_b[i] = stage_buf_5[i+16];
                g_u[i] = u_4[{~stage_flag[8:5],1'b0,i[3:0]}];
            end
        end
        else if (stage_cnt == 3) begin
            for (i=0; i<8; i=i+1) begin
                g_a[i] = stage_buf_4[i];
                g_b[i] = stage_buf_4[i+8];
                g_u[i] = u_3[{~stage_flag[8:4],1'b0,i[2:0]}];
            end
        end
        else if (stage_cnt == 2) begin
            for (i=0; i<4; i=i+1) begin
                g_a[i] = stage_buf_3[i];
                g_b[i] = stage_buf_3[i+4];
                g_u[i] = u_2[{~stage_flag[8:3],1'b0,i[1:0]}];
            end
        end
        else if (stage_cnt == 1) begin
            for (i=0; i<2; i=i+1) begin
                g_a[i] = stage_buf_2[i];
                g_b[i] = stage_buf_2[i+2];
                g_u[i] = u_1[{~stage_flag[8:2],1'b0,i[0]}];
            end
        end
        else if (stage_cnt == 0) begin
            for (i=0; i<1; i=i+1) begin
                g_a[i] = stage_buf_1[i];
                g_b[i] = stage_buf_1[i+1];
                g_u[i] = u_0[{~stage_flag[8:1],1'b0}];
            end
        end
    end

    // ========================================
    // reliability LUT
    // ========================================

    wire    [8:0]   reliab;
    wire            frozen_bit;

    assign  frozen_bit = reliab < (N-K);

    reliability_LUT reliability_LUT_inst(
        .N(N[9:8]),
        .index({~stage_flag[8:1],stage_flag[0]}),
        .reliability(reliab)
    );

    // ========================================
    // h function
    // ========================================

    wire    h;

    assign  h = (frozen_bit)? 0:
                (stage_flag[0])? g_z_nxt[0][21]:
                f_z_nxt[0][21];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<512; i=i+1) begin
                u[i] <= 0;
            end
        end
        else begin
            if (state == DECODE) begin
                if (stage_cnt == 0) begin
                    u[{~stage_flag[8:1],stage_flag[0]}] <= h;
                end
            end
        end
    end

    // ========================================
    // Decoded memory
    // ========================================
    
    reg     [5:0]   write_addr;
    reg     [139:0] write_data;
    reg     [7:0]   dec_idx;

    assign waddr = write_addr;
    assign wdata = write_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_addr  <= 0;
            write_data  <= 0;
            dec_idx     <= 0;
        end
        else begin
            write_addr  <= cur_packet;
            if (state == LOAD_INFO || state == FINISH) begin
                write_data  <= 0;
                dec_idx     <= 0;
            end
            else begin
                if (state == DECODE) begin
                    if (stage_cnt == 0 && frozen_bit == 0) begin
                        write_data[dec_idx] <= h;
                        dec_idx <= dec_idx+1;
                    end
                end
            end
        end
    end

    // ========================================
    // proc_done
    // ========================================

    reg     done;

    assign proc_done = done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done    <= 0;
        end
        else begin
            done    <= (state == FINISH && cnt == 0)? 1: 0; 
        end
    end

endmodule
