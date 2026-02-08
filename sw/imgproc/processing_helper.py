import cv2
import numpy as np

"""
  Applies the 2D convolution filter to an image.

  Args:
    image (np.ndarray): The source grayscale image.
    kernel (np.ndarray): The 3x3 matrix to apply.

  Returns:
    np.ndarray: The filtered image.
"""
def apply_filter(image: np.ndarray, kernel: np.ndarray):
  return cv2.filter2D(image, -1, kernel,borderType=cv2.BORDER_CONSTANT)

"""
  Calculates and visualizes the absolute difference between two images.

  Used to compare the Python 'Golden Model' against the FPGA simulation output.
  Prints statistics about the maximum deviation and the location of errors.

  Args:
    image1 (np.ndarray): Reference image (Python).
    image2 (np.ndarray): Test image (FPGA).

  Returns:
    np.ndarray: An image representing the absolute difference.
"""
def diff(image1: np.ndarray, image2: np.ndarray):
  print(f"Image 1 shape:{image1.shape}")
  print(f"Image 2 shape:{image2.shape}")
  img1 = np.clip(image1,0,255).astype(np.uint8)
  img2 = np.clip(image2,0,255).astype(np.uint8)
  dif_img = cv2.absdiff(img1, img2)
  locations = np.where(dif_img == dif_img.max())
  coords = list(zip(locations[1], locations[0]))
  print("Max diff:", dif_img.max())
  print(f"Number of max-diff pixels: {len(coords)}")
  print(f"First few locations (row, col): {coords[:5]}")
  return dif_img

"""
  Trims the image edges to match the FPGA's valid output window.

  Because a 3x3 convolution without padding loses 1 pixel on each side,
  this crops the reference to match the hardware's internal 'window_valid' logic.
"""
def valid_region(image: np.ndarray):
  return image[1:-1, 2:-1]