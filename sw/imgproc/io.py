import numpy as np

def image_to_txt(image: np.ndarray, path: str):
  with open(path, "w") as f:
    for pix in image.flatten():
      f.write(f"{int(pix)}\n")

def txt_to_image(path: str, height: int, width:int):
  with open(path, "r") as f:
    data = [int(line.strip()) for line in f if line.strip()]

  img = np.zeros((height, width),dtype=np.int32)
  idx = 0
  for i in range(1, height-2):
      for j in range(1, width-2):
          if idx >= len(data):
              print("Ran out of FPGA data at idx =", idx)
              return
          img[i,j] = min(max(data[idx], 0), 255)
          idx += 1

  return img