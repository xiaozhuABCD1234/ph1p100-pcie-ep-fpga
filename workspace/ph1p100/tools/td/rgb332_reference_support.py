"""Exact insertion shared by the reference candidate and its DDR simulation."""
def attach_reference(source: bytes) -> bytes:
    anchor=b' rgb332_display_pixels #(.SW(SW),.SH(SH),.FRAMES_PER_MODE(480)) u_pixels('
    assert source.count(anchor)==1
    source=source.replace(anchor,b' wire[23:0] display_camera_rgb;\n'+anchor)
    anchor=b'.rgb(rgb),.out_vs(out_vs),.out_hs(out_hs),.out_de(out_de),'
    assert source.count(anchor)==1
    source=source.replace(anchor,b'.rgb(display_camera_rgb),.out_vs(out_vs),.out_hs(out_hs),.out_de(out_de),')
    assert source.count(b'endmodule')==1
    return source.replace(b'endmodule',b''' // Reference bars bypass camera pixel values while capture/DDR still run.
 rgb332_reference_overlay #(.SW(SW),.SH(SH),.REFERENCE_ROWS((SH>=64)?64:4)) u_reference(
 .pclk(pclk),.rst_n(pixel_reset[1]),.vs(out_vs),.de(out_de),
 .camera_rgb(display_camera_rgb),.rgb(rgb));
endmodule''')
