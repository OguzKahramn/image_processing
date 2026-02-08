import cv2
import numpy as np

def apply_filter(image: np.ndarray, kernel: np.ndarray):
  return cv2.filter2D(image, -1, kernel,borderType=cv2.BORDER_CONSTANT)

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


def valid_region(image: np.ndarray):
  return image[1:-1, 2:-1]