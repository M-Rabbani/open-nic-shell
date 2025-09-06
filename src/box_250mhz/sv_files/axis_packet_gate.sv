// axis_packet_gate.sv
// Gate that forwards full packets if decision_allow==1, otherwise consumes/drops them.
// The module must be backpressure-safe: it reads s_axis when upstream ready and either
// forwards to m_axis or discards while still consuming tvalid/tlast.

module axis_packet_gate #(
  parameter int DATA_WIDTH = 512,
  parameter int KEEP_WIDTH = DATA_WIDTH/8
) (
  input  wire                  clk,
  input  wire                  rst_n,

  // s_axis in
  input  wire                  s_axis_tvalid,
  input  wire [DATA_WIDTH-1:0] s_axis_tdata,
  input  wire [KEEP_WIDTH-1:0] s_axis_tkeep,
  input  wire                  s_axis_tlast,
  input  wire [15:0]           s_axis_tuser_size,
  input  wire [15:0]           s_axis_tuser_src,
  input  wire [15:0]           s_axis_tuser_dst,
  
  output reg                   s_axis_tready,

  // decision
  input  wire                  decision_valid,
  input  wire                  decision_allow,

  // m_axis out
  output reg                   m_axis_tvalid,
  output reg [DATA_WIDTH-1:0]  m_axis_tdata,
  output reg [KEEP_WIDTH-1:0]  m_axis_tkeep,
  output reg                   m_axis_tlast,
  output reg [15:0]            m_axis_tuser_size,
  output reg [15:0]            m_axis_tuser_src,
  output reg [15:0]            m_axis_tuser_dst,
 
  input  wire                  m_axis_tready,

  // counters (debugging)
  output reg [31:0]            cnt_in,
  output reg [31:0]            cnt_pass,
  output reg [31:0]            cnt_drop
);

  typedef enum logic [1:0] {IDLE=2'd0, STREAM=2'd1, DISCARD=2'd2} state_t;
  state_t state;
  reg allow_latched;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      s_axis_tready <= 1'b0;
      m_axis_tvalid <= 1'b0;
      cnt_in <= 32'd0;
      cnt_pass <= 32'd0;
      cnt_drop <= 32'd0;
      allow_latched <= 1'b0;
    end else begin
      // default deassert outputs (will be set when needed)
      m_axis_tvalid <= 1'b0;
      m_axis_tdata <= '0;
      m_axis_tkeep <= '0;
      m_axis_tlast <= 1'b0;
      m_axis_tuser_size <= 16'd0;
      m_axis_tuser_src <= 16'd0;
      m_axis_tuser_dst <= 16'd0;

      case (state)
        IDLE: begin
          // accept new packet only when decision_valid; otherwise stall upstream
          s_axis_tready <= decision_valid;
          if (s_axis_tvalid && (s_axis_tready || decision_valid)) begin
            cnt_in <= cnt_in + 1;
            allow_latched <= decision_allow;
            if (decision_allow || allow_latched) begin                         // FORWARDING
              // attempt to forward beat
              if (m_axis_tready) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata <= s_axis_tdata;
                m_axis_tkeep <= s_axis_tkeep;
                m_axis_tlast <= s_axis_tlast;
                m_axis_tuser_size <= s_axis_tuser_size;
                m_axis_tuser_src  <= s_axis_tuser_src;
                m_axis_tuser_dst  <= s_axis_tuser_dst;
                cnt_pass <= cnt_pass + 1;
                if (s_axis_tlast) state <= IDLE;
                else state <= STREAM;
              end else begin
                // backpressure from downstream: deassert ready.
                s_axis_tready <= 1'b0;
                state <= IDLE;
              end
            end else begin                                    // DROPPING
              // drop packet (consume until tlast)
              cnt_drop <= cnt_drop + 1;
              if (s_axis_tlast) state <= IDLE;
              else state <= DISCARD;
            end
          end
        end

        STREAM: begin
          // forward subsequent beats                         // FORWARDING
          if (s_axis_tvalid && m_axis_tready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata <= s_axis_tdata;
            m_axis_tkeep <= s_axis_tkeep;
            m_axis_tlast <= s_axis_tlast;
            m_axis_tuser_size <= s_axis_tuser_size;
            m_axis_tuser_src <= s_axis_tuser_src;
            m_axis_tuser_dst <= s_axis_tuser_dst;
            if (s_axis_tlast) state <= IDLE;
            else state <= STREAM;
          end
          s_axis_tready <= m_axis_tready;
        end

        DISCARD: begin                                        // DROPPING
          // consume until tlast
          s_axis_tready <= 1'b1;
          if (s_axis_tvalid && s_axis_tready) begin
            if (s_axis_tlast) state <= IDLE;
            else state <= DISCARD;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule

