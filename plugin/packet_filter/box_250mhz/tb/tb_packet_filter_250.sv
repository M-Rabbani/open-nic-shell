//tb_packet_filter_250.sv
`timescale 1ns/1ps
module tb_packet_filter_250;

  // clocks
  logic axis_aclk = 0;
  logic axil_aclk = 0;
  always #2 axis_aclk = ~axis_aclk; // 250 MHz -> 4 ns period
  always #5 axil_aclk = ~axil_aclk; // 100 MHz for AXI-Lite (example)

  // reset
  logic box_rstn = 0;

  // AXI-Lite wires
  logic s_axil_awvalid; logic [31:0] s_axil_awaddr; logic s_axil_awready;
  logic s_axil_wvalid; logic [31:0] s_axil_wdata; logic s_axil_wready;
  logic s_axil_bvalid; logic [1:0] s_axil_bresp; logic s_axil_bready;
  logic s_axil_arvalid; logic [31:0] s_axil_araddr; logic s_axil_arready;
  logic s_axil_rvalid; logic [31:0] s_axil_rdata; logic [1:0] s_axil_rresp; logic s_axil_rready;

  // AXIS RX (to DUT)
  logic s_axis_rx_tvalid;
  logic [511:0] s_axis_rx_tdata;
  logic [63:0]  s_axis_rx_tkeep;
  logic s_axis_rx_tlast;
  logic [15:0] s_axis_rx_tuser_size;
  logic [15:0] s_axis_rx_tuser_src;
  logic [15:0] s_axis_rx_tuser_dst;
  wire s_axis_rx_tready;

  // AXIS TX (from DUT)
  wire m_axis_tx_tvalid;
  wire [511:0] m_axis_tx_tdata;
  wire [63:0]  m_axis_tx_tkeep;
  wire m_axis_tx_tlast;
  wire [15:0] m_axis_tx_tuser_size;
  wire [15:0] m_axis_tx_tuser_src;
  wire [15:0] m_axis_tx_tuser_dst;
  logic m_axis_tx_tready;

  // DUT
  packet_filter_250 dut (
    .axis_aclk(axis_aclk),
    .axil_aclk(axil_aclk),
    .box_rstn(box_rstn),

    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awready(s_axil_awready),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wready(s_axil_wready),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bready(s_axil_bready),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arready(s_axil_arready),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rready(s_axil_rready),

    // AXIS RX (from adapter into box)   
    .s_axis_adap_rx_250mhz_tvalid     (s_axis_rx_tvalid),
    .s_axis_adap_rx_250mhz_tdata      (s_axis_rx_tdata),
    .s_axis_adap_rx_250mhz_tkeep      (s_axis_rx_tkeep),
    .s_axis_adap_rx_250mhz_tlast      (s_axis_rx_tlast),
    .s_axis_adap_rx_250mhz_tuser_size (s_axis_rx_tuser_size),
    .s_axis_adap_rx_250mhz_tuser_src  (s_axis_rx_tuser_src),
    .s_axis_adap_rx_250mhz_tuser_dst  (s_axis_rx_tuser_dst),
    .s_axis_adap_rx_250mhz_tready     (s_axis_rx_tready),

    
    // AXIS TX (to qdma)
    .m_axis_adap_tx_250mhz_tvalid     (m_axis_tx_tvalid),
    .m_axis_adap_tx_250mhz_tdata      (m_axis_tx_tdata),
    .m_axis_adap_tx_250mhz_tkeep      (m_axis_tx_tkeep),
    .m_axis_adap_tx_250mhz_tlast      (m_axis_tx_tlast),
    .m_axis_adap_tx_250mhz_tuser_size (m_axis_tx_tuser_size),
    .m_axis_adap_tx_250mhz_tuser_src  (m_axis_tx_tuser_src),
    .m_axis_adap_tx_250mhz_tuser_dst  (m_axis_tx_tuser_dst),
    .m_axis_adap_tx_250mhz_tready     (m_axis_tx_tready)
  );

  // AXI-Lite helper tasks (operate on axil_aclk)
  task automatic axil_write(input [31:0] addr, input [31:0] data);
    begin
      @(posedge axil_aclk);
      s_axil_awaddr <= addr;
      s_axil_awvalid <= 1;
      s_axil_wdata <= data;
      s_axil_wvalid <= 1;
      s_axil_bready <= 1;
      // wait for write acceptance
      wait (s_axil_awready && s_axil_wready);
      @(posedge axil_aclk);
      s_axil_awvalid <= 0;
      s_axil_wvalid <= 0;
      wait (s_axil_bvalid);
      @(posedge axil_aclk);
      s_axil_bready <= 0;
      @(posedge axil_aclk);
    end
  endtask

  task automatic axil_read(input [31:0] addr, output [31:0] data);
    begin
      @(posedge axil_aclk);
      s_axil_araddr <= addr;
      s_axil_arvalid <= 1;
      s_axil_rready <= 1;
      wait(s_axil_arready);
      @(posedge axil_aclk);
      s_axil_arvalid <= 0;
      wait(s_axil_rvalid);
      data = s_axil_rdata;
      @(posedge axil_aclk);
      s_axil_rready <= 0;
      @(posedge axil_aclk);
    end
  endtask

  // Packet creation helper (single-beat IPv4 UDP)
  task automatic send_ipv4_udp(input [31:0] src_ip, input [31:0] dst_ip, input [15:0] src_port, input [15:0] dst_port);
    reg [511:0] beat;
    integer i;
    reg [7:0] bytes[0:127];
    begin
      // create a simple 64B payload with Ethernet + IPv4 + UDP minimal
      // We place data in big-endian byte packing consistent with parser used above.
      // Clear
      beat = '0;
      // Ethernet: dst(6), src(6), ethertype (2) -> we only fill ethertype at bytes 12..13
      // Ethertype IPv4 at offset 12..13
      // IP src at offsets 26..29, dst 30..33 (per parser)
      // L4 ports at 34..37 (src,dst) per parser
      // Build bytes array for convenience
      for (i=0;i<128;i=i+1) bytes[i] = 8'h00;
      bytes[12] = 8'h08; bytes[13] = 8'h00; // IPv4
      // set proto to UDP (offset 23)
      bytes[23] = 8'd17;
      // src ip at 26..29
      bytes[26] = src_ip[31:24]; bytes[27] = src_ip[23:16]; bytes[28] = src_ip[15:8]; bytes[29] = src_ip[7:0];
      bytes[30] = dst_ip[31:24]; bytes[31] = dst_ip[23:16]; bytes[32] = dst_ip[15:8]; bytes[33] = dst_ip[7:0];
      // UDP ports
      bytes[34] = src_port[15:8]; bytes[35] = src_port[7:0];
      bytes[36] = dst_port[15:8]; bytes[37] = dst_port[7:0];

      // pack into 512-bit beat (big-endian within vector)
      for (i=0;i<64;i=i+1) begin
        beat[(512-1) - (8*i) -: 8] = bytes[i];
      end

      @(posedge axis_aclk);
      s_axis_rx_tdata <= beat;
      s_axis_rx_tkeep <= 64'hFFFF_FFFF_FFFF_FFFF;
      s_axis_rx_tlast <= 1;
      s_axis_rx_tvalid <= 1;
      s_axis_rx_tuser_size <= 16'd64;
      s_axis_rx_tuser_src <= 16'd0;
      s_axis_rx_tuser_dst <= 16'd0;
      // wait for acceptance
      wait (s_axis_rx_tready && s_axis_rx_tvalid);
      @(posedge axis_aclk);
      s_axis_rx_tvalid <= 0;
      s_axis_rx_tlast <= 0;
      s_axis_rx_tdata <= '0;
      s_axis_rx_tkeep <= '0;
    end
  endtask

  // Monitor counts
  integer pass_cnt = 0;
  always @(posedge axis_aclk) begin
    if (m_axis_tx_tvalid && m_axis_tx_tready && m_axis_tx_tlast) begin
      pass_cnt = pass_cnt + 1;
      $display("[%0t] Observed passed packet (m_axis). total_pass=%0d", $time, pass_cnt);
    end
  end

  // Stimulus
  initial begin
    // init
    s_axil_awvalid=0; s_axil_wvalid=0; s_axil_bready=0;
    s_axil_arvalid=0; s_axil_rready=0;
    s_axis_rx_tvalid=0; s_axis_rx_tlast=0; s_axis_rx_tdata='0; s_axis_rx_tkeep='0;
    m_axis_tx_tready = 1;

    // release reset after some cycles
    box_rstn = 0;
    repeat (20) @(posedge axis_aclk);
    box_rstn = 1;
    repeat (5) @(posedge axis_aclk);

    // configure: enable filter, default drop
    axil_write(32'h0000, 32'h00000001); // reg_en = 1, default action = 0(drop)

    // Rule0: enable, KEY_SEL=0 dst IP (bits 2:1 = 00), IPV4_ONLY=1 (bit6)
    // cfg bits: bit0 EN=1, bit6 IPV4_ONLY=1 -> 0x41
    axil_write(32'h0010, 32'h00000041);
    // KEY = 192.168.1.100
    axil_write(32'h0014, 32'hC0A80164);
    axil_write(32'h0018, 32'hFFFFFFFF);

    // send matching
    send_ipv4_udp(32'h0A000001, 32'hC0A80164, 16'd1234, 16'd5678);
    //repeat (10) @(posedge axis_aclk);

    // send non-matching
    send_ipv4_udp(32'h0A000001, 32'hC0A80165, 16'd1234, 16'd5678);
    //repeat (20) @(posedge axis_aclk);

    send_ipv4_udp(32'h0A000001, 32'hC0A80164, 16'd1234, 16'd5678);  //needs 3rd packet due to edgecase issues with tlast

    #50 

    /*
    // read counters (optional)
    reg [31:0] v;
    axil_read(32'h0004, v); // pkt_in
    $display("AXIL pkt_in=%0d", v);
    axil_read(32'h0005, v); // pkt_pass
    $display("AXIL pkt_pass=%0d", v);

    // check expected: pass_cnt should be 1
    if (pass_cnt == 1) $display("TEST PASSED: pass_cnt==1");
    else $display("TEST FAILED: pass_cnt=%0d (expected 1)", pass_cnt);
    */
    $finish;
  end

endmodule
