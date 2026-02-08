import argparse
from imgproc.kernels import get_kernel
from imgproc.image_processing_model import ImageProcessingModel
from imgproc.io import image_to_txt, txt_to_image
from imgproc.processing_helper import apply_filter, diff, valid_region
from imgproc.generate_hdl_params import generate_hdl_params

def main():
  parser = argparse.ArgumentParser(
    description="Image processing reference model for FPGA verification"
  )

  sub = parser.add_subparsers(dest="cmd", required="True")

  gen = sub.add_parser("gen-txt")
  gen.add_argument("-i","--image",
                   required=True,
                   help="Input image path")
  gen.add_argument("-o","--out",
                   required=True,
                   help="Pixels text file path for FGPA input")

  params = sub.add_parser("gen-params",
                          help="Generates SystemVerilog parameters.svh from image")
  params.add_argument("-i", "--image",
                      required=True,
                      help="Input image path")
  params.add_argument("-f", "--file",
                      required=True,
                      help="Output SystemVerilog file (e.g. hdl/parameters.svh)")
  
  comp = sub.add_parser("compare")
  comp.add_argument("-i","--image",
                    required=True,
                    help="Input image path")
  comp.add_argument("-f","--fpga-txt", required=True,
                    help="FPGA output text file path")
  comp.add_argument("-k","--kernel",
                    required=True,
                    help="Kernel type")
  comp.add_argument("-o","--out-txt",
                    required=False,
                    help="Python processed imaged text file path")

  args = parser.parse_args()

  if args.cmd == "gen-txt":
    model = ImageProcessingModel(args.image)
    image_to_txt(model.image, args.out)

  elif args.cmd == "gen-params":
    model = ImageProcessingModel(args.image)
    generate_hdl_params(args.file, model.height, model.width)

  elif args.cmd == "compare":
    model = ImageProcessingModel(args.image)
    kernel = get_kernel(args.kernel)
    ref_full = apply_filter(model.image,kernel)

    fpga = txt_to_image(args.fpga_txt, model.height, model.width)
    ref = valid_region(ref_full)
    #fpga = valid_region(fpga_full)
    model.show(model.image, "Original")
    model.show(ref, "Reference - (python filterted)")
    model.show(fpga, "FPGA output")
    d = diff(ref, fpga)
    image_to_txt(ref, args.out_txt)
    model.show(d, "Difference")

if __name__ == "__main__":
  main()