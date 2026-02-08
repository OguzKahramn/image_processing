`include "parameters.svh"


package img_processing_pkg;

//! Vertical resolution of the target image
parameter int IMG_H = `IMG_HEIGHT;
//! Horizontal resolution of the target image
parameter int IMG_W = `IMG_WIDTH;
//! Size of the square convolution window 3x3
parameter int KERNEL_SIZE = 3;

//! Width of the AXI-Stream TDATA signal
parameter int AXIS_TDATA_WIDTH = `AXIS_TDATA_WIDTH;
//! Width of the AXI-Stream TUSER signal (used for Start-of-Frame)
parameter int AXIS_TUSER_WIDTH = `AXIS_TUSER_WIDTH;

//! Represents a single horizontal row of pixels stored in internal memory.Used by the line buffer array to build the sliding window.
typedef logic[7:0] line_buffer_t[IMG_W-1:0];

/**
   * Supported Filter Kernels
   * | Value | Name          | Description                                   |
   * | :---  | :---          | :---                                          |
   * | 2'b00 | KERNEL_BYPASS | Direct pass-through of pixels                 |
   * | 2'b01 | KERNEL_BOX    | 3x3 Mean Blur                                 |
   * | 2'b10 | KERNEL_GAUSS  | 3x3 Gaussian Blur                             |
   * | 2'b11 | KERNEL_SOBEL  | Horizontal Edge Detection (Gradient Magnitude)|
*/
typedef enum logic [1:0] {
  KERNEL_BYPASS,
  KERNEL_BOX,
  KERNEL_GAUSS,
  KERNEL_SOBEL
} kernel_type_t;

endpackage


