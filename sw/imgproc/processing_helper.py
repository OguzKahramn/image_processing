import cv2
import numpy as np

def apply_filter(image: np.ndarray, kernel: np.ndarray):
  return cv2.filter2D(image, -1, kernel)

def diff(image1: np.ndarray, image2: np.ndarray):
  img1 = np.clip(image1,0,255).astype(np.uint8)
  img2 = np.clip(image2,0,255).astype(np.uint8)
  return cv2.absdiff(img1, img2)