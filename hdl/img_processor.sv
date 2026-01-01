`include "img_processing_pkg.sv"
import img_processing_pkg::*;

`default_nettype none;

module img_processor #(
  parameter int TDATA_WIDTH=AXIS_TDATA_WIDTH,
  parameter int TUSER_WIDTH=AXIS_TUSER_WIDTH
)(
  input  wire  clk,
  input  wire  reset_n,
  input  wire kernel_type_t kernel_type,

  axi_stream_if.slave s_axis,
  axi_stream_if.master m_axis
);

localparam int NUM_LINE_BUFFS = KERNEL_SIZE + 1;
localparam int PIPELINE_STAGE = 2;
line_buffer_t line_buffer[NUM_LINE_BUFFS-1:0]; //! 4 line buffers

logic [$clog2(NUM_LINE_BUFFS)-1:0] row0,row1,row2;
logic [$clog2(IMG_W)-1:0] pixel_cntr;
logic [$clog2(IMG_H)-1:0] line_cntr;
logic [$clog2(IMG_H)-1:0] m_line_cntr;
logic [$clog2(NUM_LINE_BUFFS)-1:0] wr_cntr;
logic [$clog2(IMG_W)-1:0] rd_pixel;
int i,j;

logic signed [15:0] conv_sum;
logic [7:0] pixel_out;
logic window_valid;
logic [PIPELINE_STAGE-1:0] valid_pipe;
logic [PIPELINE_STAGE-1:0] last_pipe;
logic [PIPELINE_STAGE-1:0] tuser_pipe;

assign window_valid = (line_cntr >=2 && pixel_cntr>=2 &&  (pixel_cntr <= IMG_W-2));
assign rd_pixel = pixel_cntr;

assign m_axis.tdata = pixel_out;
assign m_axis.tvalid = valid_pipe[PIPELINE_STAGE-1];
assign m_axis.tlast = last_pipe[PIPELINE_STAGE-1];
assign m_axis.tuser = tuser_pipe[PIPELINE_STAGE-1];
assign s_axis.tready = m_axis.tready;


always_ff @(posedge clk)begin : pixel_counter
  if(!reset_n)begin
    pixel_cntr <= 'd0;
  end
  else begin
    if(s_axis.tvalid & s_axis.tready & s_axis.tlast)begin
      pixel_cntr <= 'd0;
    end
    else if (s_axis.tvalid & s_axis.tready)begin
      pixel_cntr <= pixel_cntr + 'd1;
    end
  end
end

always_ff @(posedge clk)begin : line_counter
  if(!reset_n)begin
    line_cntr <= 'd0;
    wr_cntr <= 'd0;
  end
  else begin
    if(s_axis.tvalid & s_axis.tready & s_axis.tuser[0])begin
      line_cntr <= 'd0;
      wr_cntr <= 'd0;
    end
    else if (s_axis.tvalid & s_axis.tready & s_axis.tlast)begin
      line_cntr <= line_cntr + 'd1;
      wr_cntr <= (wr_cntr == NUM_LINE_BUFFS-1) ? 0 : wr_cntr + 'd1;
    end
  end
end

always_ff @(posedge clk)begin : fill_buffers
  if(!reset_n)begin
    for(i=0;i<NUM_LINE_BUFFS;i++)begin
      for(j=0;j<IMG_W;j++)begin
        line_buffer[i][j]='d0;
      end
    end
  end
  else begin
    if(s_axis.tready & s_axis.tvalid)begin
      line_buffer[wr_cntr][pixel_cntr] <= s_axis.tdata;
    end
  end
end

always_comb begin
  row2 = wr_cntr;
  row1 = (wr_cntr + NUM_LINE_BUFFS - 1) % NUM_LINE_BUFFS;
  row0 = (wr_cntr + NUM_LINE_BUFFS - 2) % NUM_LINE_BUFFS;
end

always_ff @(posedge clk)begin
  if(!reset_n)begin
    conv_sum <= 'd0;
  end
  else begin
    if(window_valid)begin
      case(kernel_type)
      KERNEL_BYPASS: begin
        conv_sum <= line_buffer[row0][rd_pixel];
      end
      KERNEL_BOX: begin
        conv_sum <= line_buffer[row0][rd_pixel-1]+
                    line_buffer[row0][rd_pixel  ]+
                    line_buffer[row0][rd_pixel+1]+
                    line_buffer[row1][rd_pixel-1]+
                    line_buffer[row1][rd_pixel  ]+
                    line_buffer[row1][rd_pixel+1]+
                    line_buffer[row2][rd_pixel-1]+
                    line_buffer[row2][rd_pixel  ]+
                    line_buffer[row2][rd_pixel+1];
      end
      KERNEL_GAUSS:begin
        conv_sum <= line_buffer[row0][rd_pixel-1]+
                    (line_buffer[row0][rd_pixel  ]<<1)+
                    line_buffer[row0][rd_pixel+1]+
                    (line_buffer[row1][rd_pixel-1]<<1)+
                    (line_buffer[row1][rd_pixel  ]<<2)+
                    (line_buffer[row1][rd_pixel+1]<<1)+
                    line_buffer[row2][rd_pixel-1]+
                    (line_buffer[row2][rd_pixel  ]<<1)+
                    line_buffer[row2][rd_pixel+1];
      end
      KERNEL_SOBEL: begin
        conv_sum <= (line_buffer[row0][rd_pixel+1] - line_buffer[row0][rd_pixel-1]) +
                    ((line_buffer[row1][rd_pixel+1] - line_buffer[row1][rd_pixel-1]) <<< 1) +
                    (line_buffer[row2][rd_pixel+1] - line_buffer[row2][rd_pixel-1]);
      end
      default: begin
        conv_sum <= line_buffer[row0][rd_pixel];
      end
      endcase
    end
  end
end

always_ff @(posedge clk)begin
  if(!reset_n)begin
    pixel_out <= 'd0;
  end
  else begin
    case(kernel_type)
      KERNEL_BOX:begin
        pixel_out <= conv_sum * 28 >> 8;
      end
      KERNEL_GAUSS:begin
        pixel_out <= conv_sum >> 4;
      end
      KERNEL_SOBEL:begin
        pixel_out = (conv_sum < 0) ? 0 : (conv_sum > 255) ? 255 : conv_sum;
      end
      default: pixel_out <= conv_sum[7:0];
    endcase
  end
end

always_ff @(posedge clk)begin
  if(!reset_n)begin
    valid_pipe <= 'd0;
    last_pipe <= 'd0;
    tuser_pipe <= 'd0;
  end
  else begin
    valid_pipe <= {valid_pipe[PIPELINE_STAGE-2:0],window_valid};
    last_pipe <= {last_pipe[PIPELINE_STAGE-2:0],(window_valid && rd_pixel == IMG_W-2)};
    tuser_pipe <= {tuser_pipe[PIPELINE_STAGE-2:0],(window_valid & m_line_cntr==0 & rd_pixel==2)};
  end
end

always_ff @(posedge clk)begin
  if(!reset_n)begin
    m_line_cntr <= 'd0;
  end
  else if(m_axis.tready & m_axis.tvalid & m_axis.tlast & m_line_cntr == IMG_H-3)begin
    m_line_cntr <= 'd0;
  end
  else if(m_axis.tready & m_axis.tvalid & m_axis.tlast)begin
    m_line_cntr <= m_line_cntr + 'd1;
  end
end

endmodule

`default_nettype wire
