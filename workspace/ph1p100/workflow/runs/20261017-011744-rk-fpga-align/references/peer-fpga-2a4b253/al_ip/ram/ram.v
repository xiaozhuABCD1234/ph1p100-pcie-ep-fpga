/************************************************************\
**	Copyright (c) 2012-2024 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Feb 27 2025 18:30:21
**	TD version	:	6.1.141043
************************************************************/
`timescale 1ns/1ps
module ram
(
  input   [255:0]               dia,
  input   [6:0]                 addra,
  input                         cea,
  input                         clka,
  output  [255:0]               dob,
  input   [6:0]                 addrb,
  input                         ceb
);

  ram_a5091d0ea69c
  #(
      .DATA_WIDTH_A(256),
      .ADDR_WIDTH_A(7),
      .DATA_DEPTH_A(128),
      .DATA_WIDTH_B(256),
      .ADDR_WIDTH_B(7),
      .DATA_DEPTH_B(128),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_a5091d0ea69c_Inst
  (
      .dia(dia),
      .addra(addra),
      .cea(cea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb),
      .ceb(ceb)
  );
endmodule
