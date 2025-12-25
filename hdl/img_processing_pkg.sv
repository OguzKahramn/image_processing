//`include "parameters.svh"


package img_processing_pkg;

parameter int IMG_H = 410; //`IMG_HEIGHT;
parameter int IMG_W = 670; //`IMG_WIDTH;
parameter int KERNEL_SIZE = 3;

parameter int AXIS_TDATA_WIDTH = 8; //`AXIS_TDATA_WIDTH;
parameter int AXIS_TUSER_WIDTH = 1; //`AXIS_TUSER_WIDTH;

typedef logic[7:0] line_buffer_t[IMG_W-1:0];


endpackage


