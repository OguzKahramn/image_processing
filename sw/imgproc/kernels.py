import numpy as np

"""
   Returns a pre-defined 3x3 convolution kernel matrix.

   Args:
      name (str): The identifier for the kernel ('BOX', 'GAUSS', or 'SOBEL_X').

   Returns:
      np.ndarray: A 3x3 matrix of type int32 or float.

   Raises:
      ValueError: If the kernel name is not supported.
"""
def get_kernel(name: str):
  if name == "BOX":
      return np.ones((3,3),np.int32)/9
  elif name == "GAUSS":
     return np.array([
        [1, 2, 1],
        [2, 4, 2],
        [1, 2, 1]
     ], dtype=np.int32) / 16
  elif name == "SOBEL_X":
     return np.array([
        [-1, 0, 1],
        [-2, 0, 2],
        [-1, 0, 1]
     ], dtype=np.int32)
  else:
     raise ValueError(f"Unknown kernel {name}, available: : BOX, GAUSS, SOBEL_X")