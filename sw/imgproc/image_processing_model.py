import cv2
import numpy as np

class ImageProcessingModel:
  def __init__(self, image_path: str):
    self.image = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if self.image is None:
      raise ValueError(f"Cannot load the image {image_path}")

    self.height, self.width = self.image.shape

  def show(self, img, title="Image"):
    img8 = np.clip(img,0,255).astype(np.uint8)
    cv2.imshow(title, img8)
    cv2.waitKey(0)