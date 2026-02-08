import cv2
import numpy as np

"""
  A model used to handle image loading and visualization for HDL verification.

  Attributes:
    image (np.ndarray): The grayscale image data.
    height (int): Image height.
    width (int): Image width.
"""
class ImageProcessingModel:
  """
    Loads an image from disk and converts it to grayscale for processing.

    Args:
      image_path (str): Path to the source image.
        
    Raises:
      ValueError: If the image cannot be found or loaded.
  """
  def __init__(self, image_path: str):
    self.image = cv2.imread(image_path)
    if self.image is None:
      raise ValueError(f"Cannot load the image {image_path}")
    self.image = cv2.cvtColor(self.image, cv2.COLOR_BGR2GRAY)
    self.height, self.width = self.image.shape

  """
    Displays an image using OpenCV, handling clipping and type casting.

    Args:
      img (np.ndarray): The image array to display.
      title (str, optional): Window title. Defaults to "Image".
  """
  def show(self, img, title="Image"):
    img8 = np.clip(img,0,255).astype(np.uint8)
    cv2.imshow(title, img8)
    cv2.waitKey(0)