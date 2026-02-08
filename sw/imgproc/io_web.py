import requests
from io import BytesIO
from PIL import Image
import cv2
import random
import os
import numpy as np

"""
  Fetches a random square image from picsum.photos and saves it as grayscale.

  The image is saved to 'test_vectors/images/random_image.jpg'.
"""
def download_random_image():
  size = random.randint(60,750)
  url = f"https://picsum.photos/{size}"

  response = requests.get(url)
  img = Image.open(BytesIO(response.content))

  gray_img = img.convert("L")
  img_array = np.array(gray_img, dtype=np.uint8)

  os.makedirs("test_vectors/images", exist_ok=True)
  cv2.imwrite("test_vectors/images/random_image.jpg", img_array)
  print("Downloaded random image of shape:", img_array.shape)