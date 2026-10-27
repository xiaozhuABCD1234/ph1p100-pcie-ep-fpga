// CFG0 WR
task cfg0w;
    input [31:0] address;
    input [31:0] data;
    begin

    automatic reg [31:0]  data_tmp=0;
    pcie_tlp_write(32'h41, 32'h01);
    pcie_tlp_write(32'h42, address);
    pcie_tlp_write(32'h43, data);
    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[4] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end

    end
endtask


// CFG0 RD
task cfg0r;
    input  [31:0] address;
    output [31:0] data;
    begin
    automatic reg [31:0]  data_tmp=0;
    pcie_tlp_write(32'h51, 32'h01);
    pcie_tlp_write(32'h52, address);
    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[5] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end
    pcie_tlp_read(32'h53,  data);
    end
endtask

// IO WR
task iow;
    input [31:0] address;
    input [31:0] data;
    begin

    automatic reg [31:0]  data_tmp=0;
    pcie_tlp_write(32'h21, 32'h01);
    pcie_tlp_write(32'h22, address);
    pcie_tlp_write(32'h23, data);
    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[2] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end

    end
endtask

// IO RD
task ior;
    input  [31:0] address;
    output [31:0] data;
    begin
    automatic reg [31:0]  data_tmp=0;
    pcie_tlp_write(32'h31, 32'h01);
    pcie_tlp_write(32'h32, address);
    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[3] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end
    pcie_tlp_read(32'h33,  data);
    end
endtask

// MEM WR
task memwr_prbs;
    input [63:0]    address;
    input [31:0]    data;
    input [12:0]    data_len;
    begin
    automatic reg [31:0]      data_tmp=0;
    automatic reg [31:0]      data_len_tmp=0;
    integer i;

    data_tmp     = data;
    data_len_tmp = data_len[12:2] + (|data_len[1:0]);

    pcie_tlp_write(32'h01, 32'h01);
    pcie_tlp_write(32'h02, address[31:0]);
    pcie_tlp_write(32'h03, address[63:32]);
    pcie_tlp_write(32'h04, {19'd0,data_len[12:0]});

    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[0] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end

    $display("tb info : rc write ep with prbs mode address %h with 0x%h len " , address, data_len);
    end
endtask

// MEM WR
task memwr_prbs_error;
    input [63:0]    address;
    input [31:0]    data;
    input [12:0]    data_len;
    begin
    automatic reg [31:0]      data_tmp=0;
    automatic reg [31:0]      data_len_tmp=0;
    integer i;

    data_tmp     = data;
    data_len_tmp = data_len[12:2] + (|data_len[1:0]);

    pcie_tlp_write(32'h01, 32'h01);
    pcie_tlp_write(32'h07, 32'h01);
    pcie_tlp_write(32'h02, address[31:0]);
    pcie_tlp_write(32'h03, address[63:32]);
    pcie_tlp_write(32'h04, {19'd0,data_len[12:0]});
    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[0] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end

    pcie_tlp_write(32'h07, 32'h00);
    $display("tb info : rc write ep with prbs mode inject error address %h with 0x%h len " , address, data_len);
    end
endtask


task memwr_user;
    input [63:0]    address;
    input [31:0]    data;
    input [12:0]    data_len;
    begin
    automatic reg [31:0]      data_tmp=0;
    automatic reg [31:0]      data_len_tmp=0;
    integer i;

    data_tmp     = data;
    data_len_tmp = data_len[12:2] + (|data_len[1:0]);

    pcie_tlp_write(32'h01, 32'h01);
    pcie_tlp_write(32'h02, address[31:0]);
    pcie_tlp_write(32'h03, address[63:32]);
    pcie_tlp_write(32'h04, {19'd0,data_len[12:0]});
    pcie_tlp_write(32'h06, 32'h01);

    for(i=0;i<data_len_tmp;i=i+1) begin
    pcie_tlp_write(32'h05, data_tmp);
    data_tmp = data_tmp + 1'b1;
    end

    pcie_tlp_write(32'h00, 32'h1);
    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[0] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end
    pcie_tlp_write(32'h06, 32'h00);

    $display("tb info : rc write ep with user mode address %h with 0x%h len " , address, data_len);
    end
endtask

task memrd_prbs;
    input  [63:0]    address;
    output [31:0]    data;
    input  [12:0]    data_len;
    begin

    automatic reg [31:0]      data_tmp=0;
    automatic reg [31:0]      data_len_tmp=0;
    integer i;

    data_len_tmp = data_len[12:2] + (|data_len[1:0]);
    pcie_tlp_write(32'h11, 32'h01);
    pcie_tlp_write(32'h12, address[31:0]);
    pcie_tlp_write(32'h13, address[63:32]);
    pcie_tlp_write(32'h14, {20'd0,data_len[12:0]});
    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[1] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end

    $display("tb info : rc read  ep with prbs mode address %h with 0x%h len " , address, data_len);

    end
endtask

task memrd_prbs_error;
    input  [63:0]    address;
    output [31:0]    data;
    input  [12:0]    data_len;
    begin

    automatic reg [31:0]      data_tmp=0;
    automatic reg [31:0]      data_len_tmp=0;
    integer i;

    data_len_tmp = data_len[12:2] + (|data_len[1:0]);
    pcie_tlp_write(32'h11, 32'h01);
    pcie_tlp_write(32'h12, address[31:0]);
    pcie_tlp_write(32'h13, address[63:32]);
    pcie_tlp_write(32'h14, {20'd0,data_len[12:0]});
    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[1] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end
    pcie_tlp_read(32'h15, data);
    pcie_tlp_write(32'h17, 32'h1);

    $display("tb info : rc read  ep with prbs mode inject error address %h with 0x%h len " , address, data_len);

    end
endtask


task memrd_user;
    input  [63:0]    address;
    output [31:0]    data;
    input  [12:0]    data_len;
    begin

    automatic reg [31:0]      data_tmp=0;
    automatic reg [31:0]      data_len_tmp=0;
    integer i;

    data_len_tmp = data_len[12:2] + (|data_len[1:0]);
    pcie_tlp_write(32'h11, 32'h01);
    pcie_tlp_write(32'h12, address[31:0]);
    pcie_tlp_write(32'h13, address[63:32]);
    pcie_tlp_write(32'h14, {20'd0,data_len[12:0]});
    pcie_tlp_write(32'h16, 32'h01);
    pcie_tlp_write(32'h00, 32'h1);

    pcie_tlp_read(32'h00,  data_tmp);
    while(data_tmp[1] != 1'b1)begin
    pcie_tlp_read(32'h00,  data_tmp);
    end

    for(i=0;i<data_len_tmp;i=i+1) begin
    pcie_tlp_read(32'h15,  data);
    end
    pcie_tlp_write(32'h16, 32'h00);
    $display("tb info : rc read  ep with user mode address %h with 0x%h len " , address, data_len);

    end
endtask


task tlp_error; 
    input [31:0] data;
    begin
    // mode1 : error ep 
    if( data == 32'h0 ) begin
        $display("tb info : rc send error tlp with ep ");
        pcie_tlp_write(32'h90, 32'h01);
    // mode2 : error length 
    end else if( data == 32'h1 ) begin
        $display("tb info : rc send error tlp with error length ");
        pcie_tlp_write(32'h91, 32'h01);
    // mode3 : error address 
    end else if( data == 32'h2 ) begin
        $display("tb info : rc send error tlp with error address ");
        pcie_tlp_write(32'h92, 32'h01);
    end
    end
endtask

task pcie_apb4_read;
    input   [31:0]  addr;
    output  [31:0]  data;
begin
    automatic reg     [31:0]  addr_tmp;
    addr_tmp    = {8'h0,addr[23:0]};
    ubus_read(addr_tmp, data );
    //ubus_rd(addr_tmp, data );
end
endtask

task pcie_apb4_write;
    input   [31:0]  addr;
    input   [31:0]  data;
begin
    automatic reg     [31:0]  addr_tmp;
    addr_tmp    = {8'h0,addr[23:0]};
    ubus_write(addr_tmp, data );
    //ubus_wr(addr_tmp, data );
end
endtask

task pcie_tlp_read;
    input   [31:0]  addr;
    output  [31:0]  data;
begin
    automatic reg     [31:0]  addr_tmp;
    addr_tmp    = {8'hFF,addr[23:0]};
    ubus_read(addr_tmp, data );
    //ubus_rd(addr_tmp, data );
end
endtask

task pcie_tlp_write;
    input   [31:0]  addr;
    input   [31:0]  data;
begin
    reg     [31:0]  addr_tmp;
    addr_tmp    = {8'hFF,addr[23:0]};
    ubus_write(addr_tmp, data );
    //ubus_wr(addr_tmp, data );
end
endtask

task ubus_read;
    input   [31:0]  addr;
    output  [31:0]  data;
begin
    @(posedge tb_rc_tl_clk_user);
    tb_ubus_ren  <= 1'b1;
    tb_ubus_raddr<= addr;
    @(posedge tb_rc_tl_clk_user);
    tb_ubus_ren  <= 1'b0;
    wait(tb_ubus_bken);
    @(posedge tb_rc_tl_clk_user);
    data         <= tb_ubus_rdata;
    @(posedge tb_rc_tl_clk_user);
end
endtask

task ubus_write;
    input   [31:0]  addr;
    input   [31:0]  data;
begin
    @(posedge tb_rc_tl_clk_user);
    tb_ubus_wen  <= 1'b1;
    tb_ubus_waddr<= addr;
    tb_ubus_wdata<= data;
    @(posedge tb_rc_tl_clk_user);
    tb_ubus_wen  <= 1'b0;
    @(posedge tb_rc_tl_clk_user);
    @(posedge tb_rc_tl_clk_user);
end
endtask


// Legacy INT
task int_process;
begin
    automatic reg [31:0]  tmp_data;
    @(posedge tb_ep_tl_clk_user );
    user_int_trigger=1'b0;
    @(posedge tb_ep_tl_clk_user );
    user_int_trigger=1'b1;
    repeat(50)begin
    @(posedge tb_ep_tl_clk_user );
    end
    pcie_tlp_read(32'h60, tmp_data);
    if( tmp_data[0] )
        $display("%0t: tb info : detect legacy inta ",$realtime );
    else if(tmp_data[1])
        $display("%0t: tb info : detect legacy intb ",$realtime );
    else if(tmp_data[2])
        $display("%0t: tb info : detect legacy intc ",$realtime );
    else if(tmp_data[3])
        $display("%0t: tb info : detect legacy intd ",$realtime );
    pcie_tlp_write(32'h60, 32'd1);
end
endtask

// Msi INT
task msi_process;
begin
    automatic reg [31:0]  tmp_data;
    @(posedge tb_ep_tl_clk_user );
    user_int_trigger=1'b0;
    @(posedge tb_ep_tl_clk_user );
    user_int_trigger=1'b1;
    repeat(50)begin
    @(posedge tb_ep_tl_clk_user );
    end
    pcie_tlp_read(32'h70, tmp_data);
    while( tmp_data[0] ==1'b0 ) begin
    pcie_tlp_read(32'h70, tmp_data);
    end
    $display("%0t: tb info : detect msi int ",$realtime );
    pcie_tlp_read(32'h71, tmp_data);
    $display("%0t: tb info : detect msi vector %d int ",$realtime, tmp_data[31:0]);
    pcie_tlp_write(32'h70, 32'd1);
end
endtask

// Msi INT
task msix_process;
begin
    automatic reg [31:0]  tmp_data;
    @(posedge tb_ep_tl_clk_user );
    user_int_trigger=1'b0;
    @(posedge tb_ep_tl_clk_user );
    user_int_trigger=1'b1;
    repeat(50)begin
    @(posedge tb_ep_tl_clk_user );
    end
    pcie_tlp_read(32'h70, tmp_data);
    while( tmp_data[0] ==1'b0 ) begin
    pcie_tlp_read(32'h70, tmp_data);
    end
    $display("%0t: tb info : detect msi-x int ",$realtime );
    pcie_tlp_read(32'h71, tmp_data);
    $display("%0t: tb info : detect msi-x vector%d int ",$realtime, tmp_data[31:0]);
    pcie_tlp_write(32'h70, 32'd1);
end
endtask


task io_wr_process;
begin
    tmp_iow_data = 32'h12345678;
    iow(`ADDR_BAR1_BA, tmp_iow_data);
    ior(`ADDR_BAR1_BA, tmp_ior_data);
    if(tmp_iow_data == tmp_ior_data )
        $display("tb info : OK,io read write process success in address %h ", `ADDR_BAR1_BA);
    else
        $display("tb info : Error, io read write process not success " );

    tmp_iow_data = 32'haaaa5555;
    iow(`ADDR_BAR1_BA+'h4, tmp_iow_data);
    ior(`ADDR_BAR1_BA+'h4, tmp_ior_data);
    if(tmp_iow_data == tmp_ior_data )
        $display("tb info : OK,io read write process success in address %h ", `ADDR_BAR1_BA+'h4);
    else
        $display("tb info : Error, io read write process not success " );

    tmp_iow_data = 32'h33445566;
    iow(`ADDR_BAR1_BA+'h8, tmp_iow_data);
    ior(`ADDR_BAR1_BA+'h8, tmp_ior_data);
    if(tmp_iow_data == tmp_ior_data )
        $display("tb info : OK,io read write process success in address %h ", `ADDR_BAR1_BA+'h8);
    else
        $display("tb info : Error, io read write process not success " );

    tmp_iow_data = 32'h33445566;
    iow(`ADDR_BAR1_BA+'hC, tmp_iow_data);
    ior(`ADDR_BAR1_BA+'hC, tmp_ior_data);
    if(tmp_iow_data == tmp_ior_data )
        $display("tb info : OK,io read write process success in address %h ", `ADDR_BAR1_BA+'hC);
    else
        $display("tb info : Error, io read write process not success " );
end
endtask

task interrupt_process;
begin
    `ifdef PH1P_PCIE_LEGACY_INT_ENABLE
    int_process;
    int_process;
    int_process;
    int_process;
    int_process;
    `endif

    `ifdef PH1P_PCIE_MSI_INT_ENABLE
    // msi 
    cfg0r( `ADDR_PF_MSI_CAP + `PCI_MSI_CAP_ID_NEXT_CTRL_REG , tmp_cfg0r_data     );
    if(tmp_cfg0r_data[24])
    $display("tb info : ep pf0 msi enabled , %d msg cap , 64bit address , masking enabled    " , (2<<tmp_cfg0r_data[19:17]));
    else 
    $display("tb info : ep pf0 msi enabled , %d msg cap , 64bit address , masking disabled   " , (2<<tmp_cfg0r_data[19:17]));
    cfg0w( `ADDR_PF_MSI_CAP + `PCI_MSI_CAP_ID_NEXT_CTRL_REG , { tmp_cfg0r_data[31:23] , 3'b010 ,tmp_cfg0r_data[19:17],1'b1,tmp_cfg0r_data[15:0]}     );

    cfg0w( `ADDR_PF_MSI_CAP + `MSI_CAP_OFF_04H_REG , `MSI_CTRL_ADDRL);
    cfg0w( `ADDR_PF_MSI_CAP + `MSI_CAP_OFF_08H_REG , `MSI_CTRL_ADDRH);
    cfg0w( `ADDR_PF_MSI_CAP + `MSI_CAP_OFF_0CH_REG , {16'd0,`MSI_CTRL_DATA});
    cfg0w( `ADDR_PF_MSI_CAP + `MSI_CAP_OFF_10H_REG , `MSI_CTRL_INT_0_MASK_OFF);

    msi_process;
    msi_process;
    msi_process;
    msi_process;
    msi_process;
    `endif

    `ifdef PH1P_PCIE_MSIX_INT_ENABLE
    // msi-x ...
    cfg0r( `ADDR_PF_MSIX_CAP   + `PCI_MSIX_CAP_ID_NEXT_CTRL_REG , tmp_cfg0r_data     );
    cfg0w( `ADDR_PF_MSIX_CAP   + `PCI_MSIX_CAP_ID_NEXT_CTRL_REG , {2'b10,tmp_cfg0r_data[29:0]});
    $display("tb info : ep pf0 msix enabled , table size: %h   " , tmp_cfg0r_data[25:16]);
    cfg0r( `ADDR_PF_MSIX_CAP   + `MSIX_TABLE_OFFSET_REG         , tmp_cfg0r_data     );
    $display("tb info : ep pf0 msix enabled , table offset: %h ,  table bir: %h   " , tmp_cfg0r_data[31:3], tmp_cfg0r_data[2:0]);

    //memwr(`ADDR_BAR4_BA+`MSIX_TABLE_OFFSET+32'h0 , `MSIX_MSG_ADDR0, 13'd4);
    //memwr(`ADDR_BAR4_BA+`MSIX_TABLE_OFFSET+32'h8 , `MSIX_MSG_DATA0, 13'd4);
    //memwr(`ADDR_BAR4_BA+`MSIX_TABLE_OFFSET+32'h10, `MSIX_MSG_ADDR1, 13'd4);
    //memwr(`ADDR_BAR4_BA+`MSIX_TABLE_OFFSET+32'h18, `MSIX_MSG_DATA1, 13'd4);
    //memwr(`ADDR_BAR4_BA+`MSIX_TABLE_OFFSET+32'h20, `MSIX_MSG_ADDR2, 13'd4);
    //memwr(`ADDR_BAR4_BA+`MSIX_TABLE_OFFSET+32'h28, `MSIX_MSG_DATA2, 13'd4);
    //memwr(`ADDR_BAR4_BA+`MSIX_TABLE_OFFSET+32'h30, `MSIX_MSG_ADDR3, 13'd4);
    //memwr(`ADDR_BAR4_BA+`MSIX_TABLE_OFFSET+32'h38, `MSIX_MSG_DATA3, 13'd4);

    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h0 }, `MSIX_MSG_ADDR0    ,13'd4);
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h4 }, `MSIX_MSG_ADDR0>>32,13'd4);
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h8 }, `MSIX_MSG_DATA0    ,13'd4);

    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h10}, `MSIX_MSG_ADDR1    ,13'd4);
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h14}, `MSIX_MSG_ADDR1>>32,13'd4);
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h18}, `MSIX_MSG_DATA1    ,13'd4);

    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h20}, `MSIX_MSG_ADDR2    ,13'd4);
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h24}, `MSIX_MSG_ADDR2>>32,13'd4);
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h28}, `MSIX_MSG_DATA2    ,13'd4);

    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h30}, `MSIX_MSG_ADDR3    ,13'd4);
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h34}, `MSIX_MSG_ADDR3>>32,13'd4);
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA+(`MSIX_TABLE_OFFSET<<3)+32'h38}, `MSIX_MSG_DATA3    ,13'd4);

    msix_process;
    msix_process;
    msix_process;
    msix_process;
    msix_process;
    `endif
end
endtask



