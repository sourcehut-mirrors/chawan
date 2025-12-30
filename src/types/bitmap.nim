type
  NetworkBitmap* = ref object
    width*: int
    height*: int
    cacheId*: int
    imageId*: int
    vector*: bool # not a bitmap?
    contentType*: string
