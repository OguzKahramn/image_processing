`timescale 1ns/1ps

//`include "img_processing_pkg.sv"
import img_processing_pkg::*;

module tb_img_processor();

  //! Data width of AXI-Stream interface
  parameter int TDATA_WIDTH = 8;
  //! Tdest width of AXIS interface
  parameter int TUSER_WIDTH =1;

  localparam T = 8;

  localparam MEM_SIZE = IMG_H * IMG_W;

  integer               data_file    ; // file handler
  integer               scan_file    ; // file handler
  integer               wr_data_file ; // file handler
  `define NULL 0

  //! Clock and async reset signals
  logic clk = 0;
  logic resetn = 0;

  //! Clock generation: 8ns period (125MHz)
  always #(T/2) clk = ~ clk;

  kernel_type_t kernel_type;
  //! AXI-Stream slave interface for input packets
  axi_stream_if #(.TDATA_WIDTH_P(TDATA_WIDTH), .TUSER_WIDTH_P(TUSER_WIDTH)) s_axis();
  //! AXI-Stream master interface for output packets
  axi_stream_if #(.TDATA_WIDTH_P(TDATA_WIDTH), .TUSER_WIDTH_P(TUSER_WIDTH)) m_axis();


  logic [7:0] pixels [MEM_SIZE-1:0];
  logic [$clog2(MEM_SIZE)-1:0] pixel_counter;
  logic [$clog2(IMG_W)-1:0] width_counter;
  logic [3:0] counter;
  logic [$clog2(IMG_H)-1:0]line_counter;

  assign m_axis.tready = 1;

  initial begin
    clk = 1;
    resetn = 0;
    #(T/2*100);
    resetn = 1;
  end

  img_processor #(
  .TDATA_WIDTH(AXIS_TDATA_WIDTH),
  .TUSER_WIDTH(AXIS_TUSER_WIDTH)
  ) DUT(
  .clk(clk),
  .reset_n(resetn),
  .kernel_type(kernel_type),

  .s_axis(s_axis),
  .m_axis(m_axis)
  );


  initial begin
    data_file = $fopen("pixels_in.txt","r");
    if(data_file == `NULL)begin
      $display("data_file handle was null");
      $finish;
    end
  end

  integer val;
  int i;
initial begin
  // @(posedge resetn);
  // $readmemd("pixels_in.txt", pixels);

    i = 0;
    while (!$feof(data_file)) begin
     $fscanf(data_file, "%d", val);   // decimal
    pixels[i] = val[7:0];
    i++;
  end

  $fclose(data_file);
end

initial begin
  wr_data_file = $fopen("pixel_out_fpga.txt","w");
  if(wr_data_file == `NULL)begin
    $display("pixel_out_fpga handle was null");
    $finish;
  end
end

always_ff @(posedge clk) begin : read_text_file
  if(!resetn)begin
    s_axis.tlast <= 'd0;
    s_axis.tvalid <= 'd0;
    s_axis.tdata <= 'd0;
    s_axis.tuser <= 'd1;
    counter <= 'd0;
    pixel_counter <= 'd1;
    width_counter <= 'd1;
  end
  else begin
    if(counter < 'd4)begin
      counter <= counter + 'd1;
      kernel_type <= KERNEL_SOBEL;
    end
    else if(counter == 'd4)begin
      counter <= counter + 'd1;
      s_axis.tdata <= pixels[0];
      s_axis.tuser <= 1'b1;
      s_axis.tvalid <= 1'b1;
    end
    else if(s_axis.tready && s_axis.tvalid && pixel_counter < MEM_SIZE-1)begin
      s_axis.tdata <= pixels[pixel_counter];
      pixel_counter <= pixel_counter + 'd1;
      s_axis.tuser <= 1'b0;
      width_counter <= width_counter + 'd1;
      if(width_counter == IMG_W-1)begin
        s_axis.tlast <= 'd1;
        width_counter <= 'd0;
      end
      else begin
        s_axis.tlast <= 'd0;
      end
    end
  end
end


always_ff @(posedge clk ) begin : write_calc_power
  if(!resetn) begin
    line_counter <= 'd0;
  end
  else begin
    if(m_axis.tready & m_axis.tvalid & m_axis.tlast & line_counter==IMG_H-3)begin
      $fwrite(wr_data_file,"%d\n",m_axis.tdata);
      $fclose(wr_data_file);
    end
    else if(m_axis.tready & m_axis.tvalid & m_axis.tlast)begin
      line_counter <= line_counter +'d1;
      $fwrite(wr_data_file,"%d\n",m_axis.tdata);
    end
    else if(m_axis.tready & m_axis.tvalid)begin
      $fwrite(wr_data_file,"%d\n",m_axis.tdata);
    end
  end
end




endmodule
