# Image Processing FPGA Simulation

This repository provides a Python + Verilator workflow to simulate image processing kernels (Sobel, Box, Gauss) on FPGA. It allows generating pixel input files, running FPGA simulations, comparing results with Python references, and testing with random images from the web.

## Directory Structure

```
sw/
├─ cli.py                 # Command-line interface for image processing
├─ imgproc/               # Image processing Python modules
├─ __init__.py
├─ requirements.txt
hdl/                       # HDL modules
tb/                        # Testbench files
test_vectors/
├─ images/                 # Input images
├─ fpga_out/               # FPGA simulation output
├─ golden/                 # Reference outputs
├─ input/                  # Input pixel files
```

## Setup 

1. Install Python dependencies

```
make install
```

2. Make sure Verilator is installed and available in your PATH. If not, set VERILATOR_ROOT in your environment:

```
export VERILATOR_ROOT=/path/to/verilator
```

## Makefile Commands

Here is the summary of the available commands:

| Target  | Description |
| ------------- | ------------- |
| install | Downloads necessary python packages  |
| gen-param | Generates HDL parameter file `parameters.svh` from the image. |
| gen-txt | Converts an image to pixel `.txt` file for FPGA simulation. |
| build | Compiles SystemVerilog sources and testbench using Verilator. |
| run | Runs the compiled Verilator simulation. |
| sim | Full simulation workflow: build --> run --> compare. |
| compare | Compares FPGA output with Python reference and prints differences. |
| download_random_img | Downloads a random image from `Picsum` and saves it to `test_vectors/images/random_image.jpg` |
| random_test | Performs a full simulation using a random image: downloads it, generates parameters, runs simulation, and compares output. |
| clean | Cleans simulation directory and generated files. |

## Example Workflows

* Run simulation on a specific image

```
# Generate HDL parameters for the image
make gen-param

# Generate pixel input file
make gen-txt

# Build and run simulation
make sim
```

* Download a random image and test FPGA pipeline

```
# Run full simulation using the random image
make random_test
```
or
```
make random_test KERNEL=BOX
```

This will automatically:

1. Download a random image.
2. Generate HDL parameters and pixel input file.
3. Run FPGA simulation.
4. Compare FPGA output with Python reference.

* Compare outputs manually

```
make compare KERNEL=BOX IMAGE_FILE=test_vectors/images/lena_gray.bmp
```

This will compare the FPGA output (`test_vectors/fpga_out/pixel_out_fpga.txt`) against the Python reference output for the selected kernel (`BOX`). Make sure that `test_vectors/fpga_out/pixel_out_fpga.txt` has the same image output as `IMAGE_FILE` as command.

## Customizing the Kernel

By default, SOBEL_X kernel is used. To change the kernel:

```
make KERNEL=BOX sim IMAGE_FILE=test_vectors/images/gemi-anadolu.jpg
make KERNEL=GAUSS sim IMAGE_FILE=test_vectors/images/dog.jpg
```





