# DASHED LINE 2D

Draws a dashed polyline with per-segment width and color control.

Width:
  width          — base width in pixels
  width_curve    — optional Curve sampled 0→1 along total arc length.
                   Output multiplies base width.  Flat at 1.0 = uniform.

Color:
  default_color  — base color (used when gradient is null)
  gradient       — optional Gradient sampled 0→1 along total arc length.
                   When set, overrides default_color per-segment.

Animation:
  flow     — pixels per second

Both curve and gradient are sampled at the midpoint of each dash segment  
so the visual transition is smooth across the whole line.
