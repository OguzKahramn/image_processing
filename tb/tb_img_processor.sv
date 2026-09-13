`timescale 1ns/1ps

//`include "img_processing_pkg.sv"
import img_processing_pkg::*;


`ifndef PIXELS_FILE
  `define PIXELS_FILE "pixels_in.txt"
`endif

`ifndef PIXELS_OUT_FILE
  `define PIXELS_OUT_FILE "pixel_out_fpga.txt"
`endif

`ifndef KERNEL_TYPE
  `define KERNEL_TYPE KERNEL_SOBEL
`endif


module tb_img_processor();

  //! Tdata width of AXIS interface
  parameter int TDATA_WIDTH = AXIS_TDATA_WIDTH;
  //! Tuser width of AXIS interface
  parameter int TUSER_WIDTH = AXIS_TUSER_WIDTH;

  //! Pixels transferred per beat, and words needed to cover one image line (ceiling division)
  localparam int NPIX          = TDATA_WIDTH/8;
  localparam int WORDS_PER_LINE = (IMG_W + NPIX - 1)/NPIX;

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
  int word_idx;   //! index of the word currently loaded into s_axis.tdata, within the current line
  int line_idx;   //! index of the line currently being fed in
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
  .TDATA_WIDTH(TDATA_WIDTH),
  .TUSER_WIDTH(TUSER_WIDTH)
  ) DUT(
  .clk(clk),
  .reset_n(resetn),
  .kernel_type(kernel_type),

  .s_axis(s_axis),
  .m_axis(m_axis)
  );


  initial begin
    data_file = $fopen(`PIXELS_FILE,"r");
    if(data_file == `NULL)begin
      $display("data_file handle was null");
      $finish;
    end
  end

  integer val;
  int i;

  initial begin
    i = 0;
    while (!$feof(data_file)) begin
     $fscanf(data_file, "%d", val);
    pixels[i] = val[7:0];
    i++;
    end
    $fclose(data_file);
  end

  initial begin
    wr_data_file = $fopen(`PIXELS_OUT_FILE,"w");
    if(wr_data_file == `NULL)begin
      $display("pixel_out_fpga handle was null");
      $finish;
    end
  end

  //! Packs NPIX pixels of line li, word wi into one beat. Columns past IMG_W-1 (the ragged tail
  //! of the last word on a line) are zero-padded and marked invalid via tkeep, not pulled from
  //! the next line.
  function automatic void get_word(input int li, input int wi,
                                    output logic [TDATA_WIDTH-1:0] word_data,
                                    output logic [NPIX-1:0]        word_keep);
    int col;
    word_data = '0;
    word_keep = '0;
    for (int k = 0; k < NPIX; k++) begin
      col = wi*NPIX + k;
      if (col < IMG_W) begin
        word_data[k*8 +: 8] = pixels[li*IMG_W + col];
        word_keep[k]        = 1'b1;
      end
    end
  endfunction

  logic [TDATA_WIDTH-1:0] next_word_data;
  logic [NPIX-1:0]        next_word_keep;

  always_ff @(posedge clk) begin : read_text_file
    if(!resetn)begin
      s_axis.tlast  <= 'd0;
      s_axis.tvalid <= 'd0;
      s_axis.tdata  <= 'd0;
      s_axis.tkeep  <= 'd0;
      s_axis.tuser  <= 'd1;
      counter    <= 'd0;
      word_idx   <= 0;
      line_idx   <= 0;
    end
    else begin
      if(counter < 'd4)begin
        counter <= counter + 'd1;
        kernel_type <= `KERNEL_TYPE;
      end
      else if(counter == 'd4)begin
        counter <= counter + 'd1;
        get_word(0, 0, next_word_data, next_word_keep);
        s_axis.tdata  <= next_word_data;
        s_axis.tkeep  <= next_word_keep;
        s_axis.tlast  <= (WORDS_PER_LINE == 1); // degenerate case: line is a single word
        s_axis.tuser  <= 1'b1;
        s_axis.tvalid <= 1'b1;
      end
      else if(s_axis.tready && s_axis.tvalid && line_idx < IMG_H)begin
        s_axis.tuser <= 1'b0;
        if (word_idx == WORDS_PER_LINE-1) begin
          // just sent the last word of a line -> advance to the next line
          if (line_idx+1 < IMG_H) begin
            get_word(line_idx+1, 0, next_word_data, next_word_keep);
            s_axis.tdata  <= next_word_data;
            s_axis.tkeep  <= next_word_keep;
            s_axis.tlast  <= (WORDS_PER_LINE == 1);
          end
          else begin
            s_axis.tvalid <= 1'b0; // no more lines
          end
          word_idx <= 0;
          line_idx <= line_idx + 1;
        end
        else begin
          get_word(line_idx, word_idx+1, next_word_data, next_word_keep);
          s_axis.tdata <= next_word_data;
          s_axis.tkeep <= next_word_keep;
          s_axis.tlast <= (word_idx+1 == WORDS_PER_LINE-1);
          word_idx     <= word_idx + 1;
        end
      end
    end
  end


  //! Unpacks each beat's NPIX lanes via tkeep, writing one pixel value per line to the output
  //! file - same one-pixel-per-line format the original 8-bit testbench produced, regardless of
  //! TDATA_WIDTH. The IMG_H-3 finish condition is unrelated to NPIX (it comes from the 2-line
  //! vertical margin of the 3x3 kernel), so it is unchanged from the original testbench.
  always_ff @(posedge clk ) begin : write_pixels_from_fpga_output
    if(!resetn) begin
      line_counter <= 'd0;
    end
    else begin
      if(m_axis.tready & m_axis.tvalid) begin
        for (int k = 0; k < NPIX; k++) begin
          if (m_axis.tkeep[k]) begin
            $fwrite(wr_data_file,"%d\n", m_axis.tdata[k*8 +: 8]);
          end
        end
        if (m_axis.tlast) begin
          if (line_counter == IMG_H-3) begin
            $fclose(wr_data_file);
            $finish;
          end
          else begin
            line_counter <= line_counter + 'd1;
          end
        end
      end
    end
  end

  initial begin
    $dumpfile("output.vcd");
    $dumpvars();
  end
endmodule