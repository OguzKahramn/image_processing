//`include "img_processing_pkg.sv"
import img_processing_pkg::*;

`default_nettype none;

module img_processor #(
  parameter int TDATA_WIDTH=AXIS_TDATA_WIDTH, //! TDATA width in bits (must be a multiple of 8)
  parameter int TUSER_WIDTH=AXIS_TUSER_WIDTH  //! TUSER width in bits
)(
  input  wire  clk,                      //! System clock
  input  wire  reset_n,                  //! Active-low system reset
  input  wire kernel_type_t kernel_type, //! Kernel type for convolution

  axi_stream_if.slave s_axis,            //! Incoming pixel data AXI4-Stream interface
  axi_stream_if.master m_axis            //! Outgoing pixel data AXI4-Stream interface
);

//! Number of pixels transferred per beat
localparam int NPIX = TDATA_WIDTH/8;
//! Number of NPIX-wide words needed to cover a line
localparam int WORDS_PER_LINE = (IMG_W + NPIX - 1)/NPIX;
//! Number of line buffers is matrix size plus 1
localparam int NUM_LINE_BUFFS = KERNEL_SIZE + 1;
//! Convolution latency
localparam int PIPELINE_STAGE = 2;
//! Pixel-level start/end margins, carried over unchanged from the original single-pixel design
localparam int MARGIN_START_PIX = 2;
localparam int MARGIN_END_PIX   = 1;

//! Total valid columns per line, and how many NPIX-wide output beats they take.
localparam int V = IMG_W - MARGIN_START_PIX - MARGIN_END_PIX;
localparam int OUT_WORDS_PER_LINE = (V + NPIX - 1)/NPIX;
//! Which input word the valid range starts in, and the byte offset within it.
localparam int BASE  = MARGIN_START_PIX / NPIX;
localparam int SHIFT = MARGIN_START_PIX % NPIX;

initial begin
  assert (TDATA_WIDTH % 8 == 0)
    else $fatal(1, "TDATA_WIDTH must be a multiple of 8");
  assert (WORDS_PER_LINE >= 3)
    else $fatal(1, "Image too narrow for this NPIX");
  assert (V > 0)
    else $fatal(1, "Margins consume the entire line width");
end

//! Rolling line buffers: one NPIX-pixel-wide word per stored entry (BRAM-friendly, single write
//! port). The last word of each line may contain trailing don't-care bytes past column IMG_W-1.
logic [TDATA_WIDTH-1:0] line_buffer[NUM_LINE_BUFFS-1:0][WORDS_PER_LINE-1:0];

//! ---- Write side (unchanged in spirit from the original): tracks the word currently arriving ----
logic [$clog2(NUM_LINE_BUFFS)-1:0] wr_cntr;
logic [$clog2(WORDS_PER_LINE)-1:0] word_cntr;
logic [$clog2(IMG_H)-1:0]          line_cntr;
logic [$clog2(IMG_H)-1:0] m_line_cntr;
logic accept;
assign accept = s_axis.tvalid && s_axis.tready;

//! ---- Processing side: delayed by exactly one ACCEPTED beat behind the write side ----
//! pwc ("processing word counter") = word_cntr captured the cycle it was written, so by the time
//! we read line_buffer[.][pwc] it has definitely been committed. row2_d/line_cntr_d are captured
//! the same way so they stay aligned with pwc even across a line boundary.
logic [$clog2(WORDS_PER_LINE)-1:0] pwc;
logic [$clog2(NUM_LINE_BUFFS)-1:0] row2_d;
logic [$clog2(IMG_H)-1:0]          line_cntr_d;

always_ff @(posedge clk) begin
  if (!reset_n) begin
    pwc         <= '0;
    row2_d      <= '0;
    line_cntr_d <= '0;
  end else if (accept) begin
    pwc         <= word_cntr;  // the word just written this cycle
    row2_d      <= wr_cntr;    // the row it was written into (pre-update, matches word_cntr's row)
    line_cntr_d <= line_cntr;  // line count at that same moment (pre-update)
  end
end

logic [$clog2(NUM_LINE_BUFFS)-1:0] row0, row1;
assign row1 = (row2_d + NUM_LINE_BUFFS - 1) % NUM_LINE_BUFFS;
assign row0 = (row2_d + NUM_LINE_BUFFS - 2) % NUM_LINE_BUFFS;

//! Clamped neighbour word indices for reads that stay within already-committed rows (row0/row1,
//! and row2's own left neighbour). row2's right neighbour is NOT read this way - see below.
logic [$clog2(WORDS_PER_LINE)-1:0] pwc_m1, pwc_p1;
assign pwc_m1 = (pwc == 0)                 ? pwc : pwc - 1'b1;
assign pwc_p1 = (pwc == WORDS_PER_LINE-1)  ? pwc : pwc + 1'b1;

int i,j;

//! Per-lane convolution sum / output pixel - one full 3x3 conv per pixel in word "pwc".
//! window_valid is now ONLY the line-availability gate (>= 2 completed lines); the pixel-level
//! start/end margin is enforced entirely by the output re-tiling stage below, not here. Lanes
//! that fall outside the margin still get computed (harmless - they're simply never selected by
//! the re-tiler), which is what lets the re-tiler treat every input word uniformly.
logic signed [15:0] conv_sum [NPIX-1:0];
logic [7:0] pixel_out [NPIX-1:0];
logic window_valid;
assign window_valid = (line_cntr_d >= 2);

//! Tracks, in lockstep with conv_sum/pixel_out's PIPELINE_STAGE-cycle latency, which pwc value
//! and validity a given pixel_out sample corresponds to.
logic [PIPELINE_STAGE-1:0] valid_pipe;
logic [$clog2(WORDS_PER_LINE)-1:0] pwc_pipe [PIPELINE_STAGE-1:0];

//! NOTE: unlike pwc/row2_d/line_cntr_d above, this stage (and prev_* below) must NOT freeze when
//! accept is low - if it did, the last line's already-captured pwc value would get stuck mid-pipe
//! forever once s_axis.tvalid drops at end-of-stream, and that line's tlast would never emerge.
//! It has to keep shifting every cycle to drain whatever's already in flight.
always_ff @(posedge clk) begin
  if (!reset_n) begin
    valid_pipe <= '0;
    for (int p = 0; p < PIPELINE_STAGE; p++) pwc_pipe[p] <= '0;
  end else begin
    valid_pipe   <= {valid_pipe[PIPELINE_STAGE-2:0], window_valid};
    pwc_pipe[0]  <= pwc;
    for (int p = 1; p < PIPELINE_STAGE; p++) pwc_pipe[p] <= pwc_pipe[p-1];
  end
end

//! ---- Output re-tiling: combine THIS word's pixel_out with the PREVIOUS word's (held one more
//! cycle) to form beats aligned to the valid range instead of to physical word boundaries. ----
logic [7:0] prev_pixel_out [NPIX-1:0];
logic [$clog2(WORDS_PER_LINE)-1:0] prev_pwc;
logic prev_valid;

//! Same reasoning as the valid_pipe/pwc_pipe stage above: must keep advancing every cycle so the
//! final line's data can drain out after s_axis.tvalid drops.
always_ff @(posedge clk) begin
  if (!reset_n) begin
    for (int b = 0; b < NPIX; b++) prev_pixel_out[b] <= '0;
    prev_pwc   <= '0;
    prev_valid <= 1'b0;
  end else begin
    for (int b = 0; b < NPIX; b++) prev_pixel_out[b] <= pixel_out[b];
    prev_pwc   <= pwc_pipe[PIPELINE_STAGE-1];
    prev_valid <= valid_pipe[PIPELINE_STAGE-1];
  end
end

//! Output word index o = prev_pwc - BASE (the word that "prev_pixel_out" belongs to).
logic out_valid, out_last, out_tuser;
logic [NPIX-1:0]        out_keep;
logic [TDATA_WIDTH-1:0] out_data;

assign out_valid = prev_valid && valid_pipe[PIPELINE_STAGE-1] &&
                    (prev_pwc >= BASE) && (prev_pwc <= BASE + OUT_WORDS_PER_LINE - 1);
assign out_last  = out_valid && (pwc_pipe[PIPELINE_STAGE-1] == WORDS_PER_LINE-1);
assign out_tuser = out_valid && (prev_pwc == BASE) && (m_line_cntr == 0);

generate
  for (genvar oj = 0; oj < NPIX; oj++) begin : gen_retile
    // Lanes below NPIX-SHIFT come from the tail of the previous word; the rest come from the
    // head of the current word. SHIFT and the split point are compile-time constants.
    if (oj < NPIX-SHIFT) begin : gen_from_prev
      assign out_data[oj*8 +: 8] = prev_pixel_out[SHIFT+oj];
    end
    else begin : gen_from_cur
      assign out_data[oj*8 +: 8] = pixel_out[SHIFT+oj-NPIX];
    end
    // Validity only needs the upper margin check - the lower margin is already guaranteed by
    // starting output-word 0 exactly at column MARGIN_START_PIX.
    assign out_keep[oj] = ((prev_pwc - BASE)*NPIX + oj) <= (V - 1);
  end
endgenerate

assign m_axis.tdata  = out_data;
assign m_axis.tvalid = out_valid;
assign m_axis.tlast  = out_last;
assign m_axis.tuser  = out_tuser;
assign m_axis.tkeep  = out_keep;
assign s_axis.tready = m_axis.tready;


//! Handles word indexing within a single horizontal line.
always_ff @(posedge clk)begin : word_counter
  if(!reset_n)begin
    word_cntr <= 'd0;
  end
  else begin
    if(s_axis.tvalid & s_axis.tready & s_axis.tlast)begin
      word_cntr <= 'd0;
    end
    else if (s_axis.tvalid & s_axis.tready)begin
      word_cntr <= word_cntr + 'd1;
    end
  end
end

assert_word_cnt: assert property (
  @(posedge clk) disable iff (!reset_n || s_axis.tvalid && s_axis.tready && s_axis.tlast)
  (s_axis.tvalid && s_axis.tready) |=> (word_cntr == ($past(word_cntr)+'d1))
);

assert_word_cnt_tlast: assert property (
  @(posedge clk) disable iff (!reset_n)
  (s_axis.tvalid && s_axis.tready && s_axis.tlast) |=> (word_cntr == 0)
);

assert_master_tuser_low: assert property (
  @(posedge clk) disable iff (!reset_n || (m_axis.tvalid && m_axis.tready && m_line_cntr == 0))
  (m_axis.tvalid && m_axis.tready) |=> (m_axis.tuser == 0)
);

assert_frame_start: assert property (
  @(posedge clk) disable iff (reset_n)
  m_axis.tuser[0] |=> ! m_axis.tuser[0]
);

assert_tkeep: assert property (
  @(posedge clk) disable iff (!reset_n || (m_axis.tvalid && m_axis.tready && m_axis.tlast))
  m_axis.tvalid |=> &m_axis.tkeep
);

//! Tracks current line index and manages the circular write pointer for the line buffers (unchanged).
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

//! Buffer Write Logic: Stores incoming AXI-Stream data into the circular line buffer array.
always_ff @(posedge clk)begin : fill_buffers
  if(!reset_n)begin
    for(i=0;i<NUM_LINE_BUFFS;i++)begin
      for(j=0;j<WORDS_PER_LINE;j++)begin
        line_buffer[i][j]='0;
      end
    end
  end
  else begin
    if(s_axis.tready & s_axis.tvalid)begin
      line_buffer[wr_cntr][word_cntr] <= s_axis.tdata;
    end
  end
end

//! Per-lane Convolution Core: one 3x3 window computed per pixel in the current word.
//! row0/row1 are fully-written, older lines - always safe to read directly at pwc-1/pwc/pwc+1.
//! row2 is the line still being filled: pwc-1 and pwc are guaranteed committed by construction
//! (pwc lags word_cntr by exactly one accepted beat), but pwc+1 is exactly what's on s_axis.tdata
//! *right now* - not yet in line_buffer - so that one tap is forwarded straight from the bus
//! instead of read back from memory.
generate
  for (genvar k = 0; k < NPIX; k++) begin : gen_lane

    logic [7:0] p0m, p0c, p0p;
    logic [7:0] p1m, p1c, p1p;
    logic [7:0] p2m, p2c, p2p;

    always_comb begin
      // row0 (fully committed - plain reads)
      p0c = line_buffer[row0][pwc][k*8 +: 8];
      p0m = (k == 0)      ? line_buffer[row0][pwc_m1][(NPIX-1)*8 +: 8] : line_buffer[row0][pwc][(k-1)*8 +: 8];
      p0p = (k == NPIX-1) ? line_buffer[row0][pwc_p1][0          +: 8] : line_buffer[row0][pwc][(k+1)*8 +: 8];
      // row1 (fully committed - plain reads)
      p1c = line_buffer[row1][pwc][k*8 +: 8];
      p1m = (k == 0)      ? line_buffer[row1][pwc_m1][(NPIX-1)*8 +: 8] : line_buffer[row1][pwc][(k-1)*8 +: 8];
      p1p = (k == NPIX-1) ? line_buffer[row1][pwc_p1][0          +: 8] : line_buffer[row1][pwc][(k+1)*8 +: 8];
      // row2 (being filled): center/left are safely committed by now; right is forwarded from s_axis
      p2c = line_buffer[row2_d][pwc][k*8 +: 8];
      p2m = (k == 0)      ? line_buffer[row2_d][pwc_m1][(NPIX-1)*8 +: 8] : line_buffer[row2_d][pwc][(k-1)*8 +: 8];
      p2p = (k == NPIX-1) ? s_axis.tdata[0 +: 8]                          : line_buffer[row2_d][pwc][(k+1)*8 +: 8];
    end

    always_ff @(posedge clk)begin
      if(!reset_n)begin
        conv_sum[k] <= 'd0;
      end
      else begin
        if(window_valid)begin
          case(kernel_type)
          KERNEL_BYPASS: begin
            conv_sum[k] <= p0c;
          end
          KERNEL_BOX: begin
            conv_sum[k] <= p0m+p0c+p0p + p1m+p1c+p1p + p2m+p2c+p2p;
          end
          KERNEL_GAUSS:begin
            conv_sum[k] <= p0m + (p0c<<1) + p0p +
                           (p1m<<1) + (p1c<<2) + (p1p<<1) +
                           p2m + (p2c<<1) + p2p;
          end
          KERNEL_SOBEL: begin
            conv_sum[k] <= (p0p - p0m) + ((p1p - p1m) <<< 1) + (p2p - p2m);
          end
          default: begin
            conv_sum[k] <= p0c;
          end
          endcase
        end
      end
    end

    //! Post-Processing: Normalization and Bit-depth reduction (per lane).
    always_ff @(posedge clk)begin
      if(!reset_n)begin
        pixel_out[k] <= 'd0;
      end
      else begin
        case(kernel_type)
          KERNEL_BOX:begin
            pixel_out[k] <= conv_sum[k] * 28 >> 8;
          end
          KERNEL_GAUSS:begin
            pixel_out[k] <= conv_sum[k] >> 4;
          end
          KERNEL_SOBEL:begin
            pixel_out[k] <= (conv_sum[k] < 0) ? 8'd0 : (conv_sum[k] > 255) ? 8'd255 : conv_sum[k][7:0];
          end
          default: pixel_out[k] <= conv_sum[k][7:0];
        endcase
      end
    end

  end
endgenerate

//!Output Line Counter: Tracks outgoing frame progress.
always_ff @(posedge clk)begin
  if(!reset_n)begin
    m_line_cntr <= 'd0;
  end
  else if(m_axis.tready & m_axis.tvalid & m_axis.tlast & m_line_cntr == IMG_H-2)begin
    m_line_cntr <= 'd0;
  end
  else if(m_axis.tready & m_axis.tvalid & m_axis.tlast)begin
    m_line_cntr <= m_line_cntr + 'd1;
  end
end

endmodule

`default_nettype wire