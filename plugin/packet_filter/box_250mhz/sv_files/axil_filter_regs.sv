// axil_filter_regs.sv
// Minimal AXI4-Lite register file for config & stats.
// Implements read/write with simple single-beat responses.
// Reg map (offsets in bytes):
// 0x0000 CTRL
// 0x0004 STATS_PKT_IN
// 0x0008 STATS_PKT_PASS
// 0x000C STATS_PKT_DROP
// 0x0010 RULE0_CFG
// 0x0014 RULE0_KEY
// 0x0018 RULE0_MASK
// 0x0020 RULE1_CFG
// 0x0024 RULE1_KEY
// 0x0028 RULE1_MASK
// 0x0030 PRINT_CTRL
// 0x0040 SOFT_RESET (write 1 to reset)

// axil_filter_regs.sv
module axil_filter_regs (
  input  wire        clk_axil,
  input  wire        rst_n,

  // AXI4-Lite slave (simple)           125MHz
  input  wire        s_axil_awvalid,
  input  wire [31:0] s_axil_awaddr,
  output reg         s_axil_awready,
  input  wire        s_axil_wvalid,
  input  wire [31:0] s_axil_wdata,
  output reg         s_axil_wready,
  output reg         s_axil_bvalid,
  output reg [1:0]   s_axil_bresp,
  input  wire        s_axil_bready,
  input  wire        s_axil_arvalid,
  input  wire [31:0] s_axil_araddr,
  output reg         s_axil_arready,
  output reg         s_axil_rvalid,
  output reg [31:0]  s_axil_rdata,
  output reg [1:0]   s_axil_rresp,
  input  wire        s_axil_rready,

  // outputs
  output reg         reg_en,
  output reg [1:0]   reg_default_action,
  output reg [31:0]  reg_pkt_in,
  output reg [31:0]  reg_pkt_pass,
  output reg [31:0]  reg_pkt_drop,

  output reg [31:0] rule0_cfg,
  output reg [31:0] rule0_key,
  output reg [31:0] rule0_mask,
  output reg [31:0] rule1_cfg,
  output reg [31:0] rule1_key,
  output reg [31:0] rule1_mask,

  output reg         print_enable,
  output reg         soft_reset
);

  // Reg memory (word indexed)
  reg [31:0] mem [0:255];

  integer i;
  always_ff @(posedge clk_axil or negedge rst_n) begin
    if (!rst_n) begin
      for (i=0;i<256;i=i+1) mem[i] <= 32'd0;
      s_axil_awready <= 1'b0;
      s_axil_wready  <= 1'b0;
      s_axil_bvalid  <= 1'b0;
      s_axil_arready <= 1'b0;
      s_axil_rvalid  <= 1'b0;

      reg_en <= 1'b0;
      reg_default_action <= 2'd0;
      reg_pkt_in <= 32'd0;
      reg_pkt_pass <= 32'd0;
      reg_pkt_drop <= 32'd0;
      rule0_cfg <= 32'd0;
      rule0_key <= 32'd0;
      rule0_mask <= 32'hFFFF_FFFF;
      rule1_cfg <= 32'd0;
      rule1_key <= 32'd0;
      rule1_mask <= 32'hFFFF_FFFF;
      print_enable <= 1'b0;
      soft_reset <= 1'b0;
    end else begin
      // write handshake simplification
      if (s_axil_awvalid && !s_axil_awready) s_axil_awready <= 1'b1;
      else s_axil_awready <= 1'b0;

      if (s_axil_wvalid && !s_axil_wready) s_axil_wready <= 1'b1;
      else s_axil_wready <= 1'b0;

      if (s_axil_awvalid && s_axil_wvalid && !s_axil_bvalid) begin
        // write to mem
        integer idx = s_axil_awaddr[11:2]; // small address window mapping
        mem[idx] <= s_axil_wdata;
        s_axil_bvalid <= 1'b1;
        s_axil_bresp  <= 2'b00;
        // map regs
        case (idx)
          0: begin reg_en <= s_axil_wdata[0]; reg_default_action <= s_axil_wdata[3:2]; end
          1: reg_pkt_in <= s_axil_wdata;
          2: reg_pkt_pass <= s_axil_wdata;
          3: reg_pkt_drop <= s_axil_wdata;
          4: rule0_cfg <= s_axil_wdata;
          5: rule0_key <= s_axil_wdata;
          6: rule0_mask <= s_axil_wdata;
          8: rule1_cfg <= s_axil_wdata;
          9: rule1_key <= s_axil_wdata;
          10: rule1_mask <= s_axil_wdata;
          12: print_enable <= s_axil_wdata[0];
          16: soft_reset <= s_axil_wdata[0];
          default: ;
        endcase
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end

      // read
      if (s_axil_arvalid && !s_axil_arready) s_axil_arready <= 1'b1;
      else s_axil_arready <= 1'b0;

      if (s_axil_arvalid && !s_axil_rvalid) begin
        integer ridx = s_axil_araddr[11:2];
        s_axil_rdata <= mem[ridx];
        case (ridx)
          0: s_axil_rdata <= {16'd0, reg_default_action, 12'd0, reg_en};
          1: s_axil_rdata <= reg_pkt_in;
          2: s_axil_rdata <= reg_pkt_pass;
          3: s_axil_rdata <= reg_pkt_drop;
          4: s_axil_rdata <= rule0_cfg;
          5: s_axil_rdata <= rule0_key;
          6: s_axil_rdata <= rule0_mask;
          8: s_axil_rdata <= rule1_cfg;
          9: s_axil_rdata <= rule1_key;
          10: s_axil_rdata <= rule1_mask;
          12: s_axil_rdata <= {31'd0, print_enable};
          16: s_axil_rdata <= {31'd0, soft_reset};
          default: ;
        endcase
        s_axil_rvalid <= 1'b1;
        s_axil_rresp <= 2'b00;
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end

endmodule


  // Allow external logic to update counters by writing to stats regs.
  // The gate module drives cnt_in/cnt_pass/cnt_drop wires which are sampled by regs.
  // For simplicity we expose them as outputs to be wired in top-level (packet_filter_250),
  // then top-level writes them back into these regs. Here, we simply keep reg values.


