// filter_rules.sv
// Implements two maskable rules. Each rule_cfg layout (32 bits):
// bit 0: EN
// bits [2:1]: KEY_SEL (0=dst IP,1=src IP,2=dst port,3=src port)
// bit 3: DIR (unused)
// bits [5:4]: L4_SEL (0=any,1=TCP,2=UDP,3=both)
// bit 6: IPV4_ONLY (1=match only if IPv4)
// others reserved

module filter_rules (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         meta_valid,     //input data from header_peek
  input  wire         is_ipv4,
  input  wire [31:0]  ip_src,
  input  wire [31:0]  ip_dst,
  input  wire [15:0]  l4_src,
  input  wire [15:0]  l4_dst,
  input  wire [7:0]   ip_proto,

  input  wire [31:0]  rule0_cfg,      //rules from filter_regs
  input  wire [31:0]  rule0_key,
  input  wire [31:0]  rule0_mask,
  input  wire [31:0]  rule1_cfg,
  input  wire [31:0]  rule1_key,
  input  wire [31:0]  rule1_mask,

  input  wire [1:0]   default_action,
  
  output reg          allow
);

  function automatic bit masked_eq32(input [31:0] a, input [31:0] b, input [31:0] mask);
    masked_eq32 = ((a & mask) == (b & mask));
  endfunction
  function automatic bit masked_eq16(input [15:0] a, input [15:0] b, input [15:0] mask);
    masked_eq16 = ((a & mask) == (b & mask));
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      allow <= 1'b0;
    end else begin
      if (!meta_valid) allow <= 1'b0;
      else begin
        bit r0_en = rule0_cfg[0];                   //decode rule_cfg
        bit [1:0] r0_sel = rule0_cfg[2:1];
        bit r0_ipv4_only = rule0_cfg[6];
        bit [1:0] r0_l4 = rule0_cfg[5:4];

        bit r1_en = rule1_cfg[0];
        bit [1:0] r1_sel = rule1_cfg[2:1];
        bit r1_ipv4_only = rule1_cfg[6];
        bit [1:0] r1_l4 = rule1_cfg[5:4];

        bit r0_hit = 1'b0;                          //default is 0, assuming rules are independent. otherwise default = 1
        bit r1_hit = 1'b0;

        if (r0_en) begin                                        //check rule0
          if (r0_ipv4_only && !is_ipv4) r0_hit = 1'b0;
          else case (r0_sel)
            2'd0: r0_hit = masked_eq32(ip_dst, rule0_key, rule0_mask);
            2'd1: r0_hit = masked_eq32(ip_src, rule0_key, rule0_mask);
            2'd2: r0_hit = masked_eq16(l4_dst, rule0_key[15:0], rule0_mask[15:0]);
            2'd3: r0_hit = masked_eq16(l4_src, rule0_key[15:0], rule0_mask[15:0]);
            default: r0_hit = 1'b0;
          endcase
          if (r0_l4 != 2'd0) begin
            if (r0_l4 == 1 && ip_proto != 8'd6) r0_hit = 1'b0;
            if (r0_l4 == 2 && ip_proto != 8'd17) r0_hit = 1'b0;
          end
        end

        if (r1_en) begin                                        //check rule1
          if (r1_ipv4_only && !is_ipv4) r1_hit = 1'b0;
          else case (r1_sel)
            2'd0: r1_hit = masked_eq32(ip_dst, rule1_key, rule1_mask);
            2'd1: r1_hit = masked_eq32(ip_src, rule1_key, rule1_mask);
            2'd2: r1_hit = masked_eq16(l4_dst, rule1_key[15:0], rule1_mask[15:0]);
            2'd3: r1_hit = masked_eq16(l4_src, rule1_key[15:0], rule1_mask[15:0]);
            default: r1_hit = 1'b0;
          endcase
          if (r1_l4 != 2'd0) begin
            if (r1_l4 == 1 && ip_proto != 8'd6) r1_hit = 1'b0;
            if (r1_l4 == 2 && ip_proto != 8'd17) r1_hit = 1'b0;
          end
        end

        if (r0_hit || r1_hit) allow <= 1'b1;                        //assuming filtering rules are independent? check project semantics
        else allow <= (default_action == 2'd1) ? 1'b1 : 1'b0;
      end
    end
  end

endmodule
