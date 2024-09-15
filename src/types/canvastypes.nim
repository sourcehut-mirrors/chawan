type
  CanvasFillRule* = enum
    cfrNonZero = "nonzero"
    cfrEvenOdd = "evenodd"

  PaintCommand* = enum
    pcSetDimensions, pcFillRect, pcStrokeRect, pcFillPath, pcStrokePath,
    pcFillText, pcStrokeText

  CanvasTextAlign* = enum
    ctaStart = "start"
    ctaEnd = "end"
    ctaLeft = "left"
    ctaRight = "right"
    ctaCenter = "center"
