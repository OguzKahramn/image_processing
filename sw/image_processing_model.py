import cv2
import numpy as np

class imageProcessing:

  def __init__(self,path,kernel):
    self.image = cv2.imread(path,cv2.IMREAD_GRAYSCALE)
    if self.image is None:
      raise ValueError("Image could not find")
    self.kernel = kernel
    self.diff_img = None
    self.height, self.width = self.image.shape
    print(f"Img Height:{self.height}, Img Width:{self.width}")
    self.processedImg = np.zeros_like(self.image,dtype=np.int32)
    self.processedFpgaImg = np.zeros_like(self.image,dtype=np.int32)

  def showImg(self,image, title="Image"):
    img8 = np.clip(image, 0, 255).astype(np.uint8)
    cv2.imshow(title,img8)
    cv2.waitKey(0)

  def gaussImg(self):
    self.processedImg = cv2.filter2D(self.image,-1,self.kernel)

  def compareImg(self,image1,image2):
    self.diff_img = cv2.absdiff(image1,image2)

  def convertImgtoTxt(self,image,path):
    with open(path,"w") as f:
      for i in range(self.height):
        for j in range(self.width):
          f.write(f"{image[i][j]}\n")
      f.close()

  def convertText2Img(self, path):
    with open(path, "r") as f:
        data = [int(line.strip()) for line in f if line.strip()]

    print(f"FPGA pixel count: {len(data)}")

    idx = 0
    for i in range(1, self.height-2):
        for j in range(1, self.width-2):
            if idx >= len(data):
                print("⚠ Ran out of FPGA data at idx =", idx)
                return
            self.processedFpgaImg[i][j] = min(max(data[idx], 0), 255)
            idx += 1


kernelGaus = np.ones((3,3),np.int32)/9
img = imageProcessing("gemi-anadolu.jpg",kernelGaus)
img.showImg(img.image, "original")
img.gaussImg()
img.showImg(img.processedImg, "Processed")
img.compareImg(img.image,img.processedImg)
img.showImg(img.diff_img, "difference")
img.convertImgtoTxt(img.image,"pixels_in.txt")
img.convertImgtoTxt(img.processedImg,"pixels_out.txt")
img.convertText2Img("pixel_out_fpga.txt")
img.showImg(img.processedFpgaImg,"FPGA Output")





