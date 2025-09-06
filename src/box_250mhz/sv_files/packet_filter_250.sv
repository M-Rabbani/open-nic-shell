// packet_filter_250.sv
module packet_filter_250 #(
  parameter int DATA_WIDTH = 512,
  parameter int KEEP_WIDTH = 64,
  parameter int NUM_CMAC_PORT = 1

) (
  // clocks & reset
  input  wire                axis_aclk,
  input  wire                axil_aclk,
  input  wire                box_rstn,

  // AXI4-Lite slave (32-bit addr/data)
  input  wire                s_axil_awvalid,
  input  wire [31:0]         s_axil_awaddr,
  output wire                s_axil_awready,
  input  wire                s_axil_wvalid,
  input  wire [31:0]         s_axil_wdata,
  output wire                s_axil_wready,
  output wire                s_axil_bvalid,
  output wire [1:0]          s_axil_bresp,
  input  wire                s_axil_bready,
  input  wire                s_axil_arvalid,
  input  wire [31:0]         s_axil_araddr,
  output wire                s_axil_arready,
  output wire                s_axil_rvalid,
  output wire [31:0]         s_axil_rdata,
  output wire [1:0]          s_axil_rresp,
  input  wire                s_axil_rready,

  // AXIS RX (from adapter into box)
  input      [NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tvalid,
  input  [512*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tdata,
  input   [64*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tkeep,
  input      [NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tlast,
  input   [16*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tuser_size,
  input   [16*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tuser_src,
  input   [16*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tuser_dst,
  output     [NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tready,

  // AXIS TX (to qdma)
  output     [NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tvalid,
  output [512*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tdata,
  output  [64*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tkeep,
  output     [NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tlast,
  output  [16*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tuser_size,
  output  [16*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tuser_src,
  output  [16*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tuser_dst,
  input      [NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tready
);

  // internal register outputs (cross-clock handled? in axil module?)
  wire        reg_en;
  wire [1:0]  reg_default_action; 
  wire [31:0] reg_pkt_in;
  wire [31:0] reg_pkt_pass;
  wire [31:0] reg_pkt_drop;

  wire [31:0] rule0_cfg, rule0_key, rule0_mask;
  wire [31:0] rule1_cfg, rule1_key, rule1_mask;
  wire        print_enable;
  wire        soft_reset;

  // AXI-Lite registers (use axil_aclk)
  axil_filter_regs u_axil_regs (
    .clk_axil    (axil_aclk),       //clk should be good? 125
    .rst_n       (box_rstn),

    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awaddr (s_axil_awaddr),
    .s_axil_awready(s_axil_awready),
    .s_axil_wvalid (s_axil_wvalid),
    .s_axil_wdata  (s_axil_wdata),
    .s_axil_wready (s_axil_wready),
    .s_axil_bvalid (s_axil_bvalid),
    .s_axil_bresp  (s_axil_bresp),
    .s_axil_bready (s_axil_bready),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_araddr (s_axil_araddr),
    .s_axil_arready(s_axil_arready),
    .s_axil_rvalid (s_axil_rvalid),
    .s_axil_rdata  (s_axil_rdata),
    .s_axil_rresp  (s_axil_rresp),
    .s_axil_rready (s_axil_rready),

    .reg_en(reg_en),
    .reg_default_action(reg_default_action),
    .reg_pkt_in(reg_pkt_in),
    .reg_pkt_pass(reg_pkt_pass),
    .reg_pkt_drop(reg_pkt_drop),
    .rule0_cfg(rule0_cfg),
    .rule0_key(rule0_key),
    .rule0_mask(rule0_mask),
    .rule1_cfg(rule1_cfg),
    .rule1_key(rule1_key),
    .rule1_mask(rule1_mask),
    .print_enable(print_enable),
    .soft_reset(soft_reset)
  );

  // header peek/parsing (use axis_aclk) 250
  wire header_valid;
  wire [15:0] hdr_tuser_size;
  wire [15:0] hdr_tuser_src;
  wire [15:0] hdr_tuser_dst;
  wire [31:0] ethertype;
  wire is_ipv4;
  wire [31:0] ip_src, ip_dst;
  wire [15:0] l4_src, l4_dst;
  wire [7:0] ip_proto;
  wire [127:0] meta_snapshot;

  rx_header_peek #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_WIDTH(KEEP_WIDTH)
  ) u_rx_peek (
    .clk(axis_aclk),      //clk should be good?
    .rst_n(box_rstn),

    .s_axis_tvalid     (s_axis_adap_rx_250mhz_tvalid[0]),               //problem? if cmac > 1
    .s_axis_tdata      (s_axis_adap_rx_250mhz_tdata),
    .s_axis_tkeep      (s_axis_adap_rx_250mhz_tkeep),
    .s_axis_tlast      (s_axis_adap_rx_250mhz_tlast[0]),
    .s_axis_tuser_size (s_axis_adap_rx_250mhz_tuser_size),
    .s_axis_tuser_src  (s_axis_adap_rx_250mhz_tuser_src),
    .s_axis_tuser_dst  (s_axis_adap_rx_250mhz_tuser_dst),
    .s_axis_tready     (s_axis_adap_rx_250mhz_tready[0]),

    .meta_valid(header_valid),
    .meta_ethertype(ethertype),
    .meta_is_ipv4(is_ipv4),
    .meta_ip_src(ip_src),
    .meta_ip_dst(ip_dst),
    .meta_l4_src(l4_src),
    .meta_l4_dst(l4_dst),
    .meta_ip_proto(ip_proto),
    .meta_snapshot(meta_snapshot)
  );

  // rules
  wire allow;
  filter_rules u_filter_rules (
    .clk(axis_aclk),          //clk 250
    .rst_n(box_rstn),
    .meta_valid(header_valid),
    .is_ipv4(is_ipv4),
    .ip_src(ip_src),
    .ip_dst(ip_dst),
    .l4_src(l4_src),
    .l4_dst(l4_dst),
    .ip_proto(ip_proto),
    .rule0_cfg(rule0_cfg),
    .rule0_key(rule0_key),
    .rule0_mask(rule0_mask),
    .rule1_cfg(rule1_cfg),
    .rule1_key(rule1_key),
    .rule1_mask(rule1_mask),
    .default_action(reg_default_action),
    .allow(allow)
  );

  // gate
  axis_packet_gate #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_WIDTH(KEEP_WIDTH)
  ) u_axis_gate (
    .clk(axis_aclk),        //clk 250
    .rst_n(box_rstn),

    .s_axis_tvalid     (s_axis_adap_rx_250mhz_tvalid[0]),
    .s_axis_tdata      (s_axis_adap_rx_250mhz_tdata),
    .s_axis_tkeep      (s_axis_adap_rx_250mhz_tkeep),
    .s_axis_tlast      (s_axis_adap_rx_250mhz_tlast[0]),
    .s_axis_tuser_size (s_axis_adap_rx_250mhz_tuser_size),
    .s_axis_tuser_src  (s_axis_adap_rx_250mhz_tuser_src),
    .s_axis_tuser_dst  (s_axis_adap_rx_250mhz_tuser_dst),
    .s_axis_tready     (),                                      //unused, so keep emmpty?

    .decision_valid(header_valid),
    .decision_allow(allow),

    .m_axis_tvalid     (m_axis_adap_tx_250mhz_tvalid[0]),
    .m_axis_tdata      (m_axis_adap_tx_250mhz_tdata),
    .m_axis_tkeep      (m_axis_adap_tx_250mhz_tkeep),
    .m_axis_tlast      (m_axis_adap_tx_250mhz_tlast[0]),
    .m_axis_tuser_size (m_axis_adap_tx_250mhz_tuser_size),
    .m_axis_tuser_src  (m_axis_adap_tx_250mhz_tuser_src),
    .m_axis_tuser_dst  (m_axis_adap_tx_250mhz_tuser_dst),
    .m_axis_tready     (m_axis_adap_tx_250mhz_tready[0]),      //tready signal we use/assert

    .cnt_in(), .cnt_pass(), .cnt_drop()
  );

endmodule
