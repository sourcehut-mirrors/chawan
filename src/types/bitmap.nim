type
  NetworkBitmap* = ref object
    width*: int
    height*: int
    cacheId*: int = -1
    imageId*: int
    contentType*: string
