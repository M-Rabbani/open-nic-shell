// rx_header_peek.sv
// Peek first 2 beats (128B) to parse Ethernet/VLAN/IPv4/TCP/UDP headers.
// Stalls upstream while collecting up to 2 beats or until tlast.
// Asserts meta_valid with extracted fields. Does not consume stream.

module rx_header_peek #(
  parameter int DATA_WIDTH = 512,
  parameter int KEEP_WIDTH = DATA_WIDTH/8
) (
  input  wire                    clk,
  input  wire                    rst_n,

  input  wire                    s_axis_tvalid,     //
  input  wire [DATA_WIDTH-1:0]   s_axis_tdata,
  input  wire [KEEP_WIDTH-1:0]   s_axis_tkeep,
  input  wire                    s_axis_tlast,
  input  wire [15:0]             s_axis_tuser_size,
  input  wire [15:0]             s_axis_tuser_src,
  input  wire [15:0]             s_axis_tuser_dst,
  
  output wire                    s_axis_tready,

  output reg                     meta_valid,
  output reg [31:0]              meta_ethertype,
  output reg                     meta_is_ipv4,
  output reg [31:0]              meta_ip_src,
  output reg [31:0]              meta_ip_dst,
  output reg [15:0]              meta_l4_src,
  output reg [15:0]              meta_l4_dst,
  output reg [7:0]               meta_ip_proto,
  output reg [127:0]             meta_snapshot      //debugging
);

  localparam int BYTES = DATA_WIDTH/8;
  reg [DATA_WIDTH-1:0] beat0, beat1;
  reg [KEEP_WIDTH-1:0] keep0, keep1;
  reg have0, have1;
  reg capturing;

  assign s_axis_tready = (!capturing) || (capturing && !have1); //deassert to stall when capturing & vice versa

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have0 <= 1'b0; have1 <= 1'b0; capturing <= 1'b0;
      meta_valid <= 1'b0;
      meta_ethertype <= 32'd0;
      meta_is_ipv4 <= 1'b0;
      meta_ip_src <= 32'd0;
      meta_ip_dst <= 32'd0;
      meta_l4_src <= 16'd0;
      meta_l4_dst <= 16'd0;
      meta_ip_proto <= 8'd0;
      meta_snapshot <= 128'd0;
    end else begin
      meta_valid <= 1'b0;
      if (s_axis_tvalid && s_axis_tready) begin
        if (!capturing) begin
          capturing <= 1'b1;
          beat0 <= s_axis_tdata;
          keep0 <= s_axis_tkeep;
          have0 <= 1'b1;
          if (s_axis_tlast) begin       //only one beat
            have1 <= 1'b0;
            parse_beat0(beat0);
            meta_valid <= 1'b1;
            capturing <= 1'b0;
            have0 <= 1'b0;
          end
        end else if (have0 && !have1) begin     //two beats
          beat1 <= s_axis_tdata;
          keep1 <= s_axis_tkeep;
          have1 <= 1'b1;
          parse_beats(beat0, beat1);
          meta_valid <= 1'b1;
          capturing <= 1'b0;
          have0 <= 1'b0; have1 <= 1'b0;
        end
      end
    end
  end



  //one beat (ethernet + optional vlan, ip header partially)
  task automatic parse_beat0(input [DATA_WIDTH-1:0] b0);
    reg [7:0] bytes [0:BYTES-1];
    integer i;
    reg [15:0] ethertype_field;
    integer vlan_offset;

    for (i=0;i<BYTES;i=i+1) bytes[i] = b0[(DATA_WIDTH-1) - (8*i) -: 8];     //realign bytes
    meta_snapshot <= b0[DATA_WIDTH-1 -: 128];

    ethertype_field = {bytes[12], bytes[13]};
    vlan_offset = 0;

    //check for VLAN tag (0x8100)
    if (ethertype_field == 16'h8100) begin          //skip vlan
      ethertype_field = {bytes[16], bytes[17]};     //skip vlan
      vlan_offset = 4;
    end

    meta_ethertype <= ethertype_field;

    if (ethertype_field == 16'h0800) begin  //ipv4
      meta_is_ipv4 <= 1'b1;
      meta_ip_proto <= bytes[23 + vlan_offset];                                                                             // tcp/udp
      meta_ip_src <= {bytes[26 + vlan_offset],bytes[27 + vlan_offset],bytes[28 + vlan_offset],bytes[29 + vlan_offset]};     //addresses
      meta_ip_dst <= {bytes[30 + vlan_offset],bytes[31 + vlan_offset],bytes[32 + vlan_offset],bytes[33 + vlan_offset]};
      meta_l4_src <= 16'd0;                                                                                                 //need 2nd beat to get ports?? skip just in case
      meta_l4_dst <= 16'd0;
    end else begin
      meta_is_ipv4 <= 1'b0;
      meta_ip_proto <= 8'd0;
      meta_ip_src <= 32'd0;
      meta_ip_dst <= 32'd0;
      meta_l4_src <= 16'd0;
      meta_l4_dst <= 16'd0;
    end
  endtask

  //all two beats (ethernet + optional VLAN + full ipv4 + l4 ports)
  task automatic parse_beats(input [DATA_WIDTH-1:0] b0, input [DATA_WIDTH-1:0] b1);
    localparam int BYTES2 = BYTES*2;
    reg [7:0] bytes [0:BYTES2-1];
    integer i;
    reg [15:0] ethertype_field;
    integer vlan_offset;

    for (i=0;i<BYTES;i=i+1) bytes[i] = b0[(DATA_WIDTH-1) - (8*i) -: 8];         //realign bytes
    for (i=0;i<BYTES;i=i+1) bytes[BYTES+i] = b1[(DATA_WIDTH-1) - (8*i) -: 8];   //realign bytes
    meta_snapshot <= {b0[DATA_WIDTH-1 -: 64], b1[DATA_WIDTH-1 -: 64]};

    ethertype_field = {bytes[12], bytes[13]};
    vlan_offset = 0;

    //check for VLAN tag (0x8100)
    if (ethertype_field == 16'h8100) begin          //skip vlan
      ethertype_field = {bytes[16], bytes[17]};     //skip vlan
      vlan_offset = 4;
    end
    meta_ethertype <= ethertype_field;

    if (ethertype_field == 16'h0800) begin  //ipv4
      meta_is_ipv4 <= 1'b1;
      meta_ip_proto <= bytes[23 + vlan_offset];                                                                              // tcp/udp
      meta_ip_src <= {bytes[26 + vlan_offset],bytes[27 + vlan_offset],bytes[28 + vlan_offset],bytes[29 + vlan_offset]};      //addresses
      meta_ip_dst <= {bytes[30 + vlan_offset],bytes[31 + vlan_offset],bytes[32 + vlan_offset],bytes[33 + vlan_offset]};
      meta_l4_src <= {bytes[34 + vlan_offset],bytes[35 + vlan_offset]};                                                      //2 beats gives ports
      meta_l4_dst <= {bytes[36 + vlan_offset],bytes[37 + vlan_offset]}; 
    end else begin
      meta_is_ipv4 <= 1'b0;
      meta_ip_proto <= 8'd0;
      meta_ip_src <= 32'd0;
      meta_ip_dst <= 32'd0;
      meta_l4_src <= 16'd0;
      meta_l4_dst <= 16'd0;
    end
  endtask

endmodule
