import numpy as np

def get_kernel(name: str):
  if name == "box":
      return np.ones((3,3),np.int32)/9
  elif name == "gauss":
     return np.array([
        [1, 2, 1],
        [2, 4, 2],
        [1, 2, 1]
     ], dtype=np.int32) / 16
  elif name == "sobel_x":
     return np.array([
        [-1, 0, 1],
        [-2, 0, 2],
        [-1, 0, 1]
     ], dtype=np.int32)
  else:
     raise ValueError(f"Unknown kernel {name}")