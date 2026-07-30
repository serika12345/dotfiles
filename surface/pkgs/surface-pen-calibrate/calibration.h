#pragma once

#include <array>
#include <span>

namespace calibration {

struct Point {
  double x;
  double y;
};

struct Matrix {
  double a = 1.0;
  double b = 0.0;
  double c = 0.0;
  double d = 0.0;
  double e = 1.0;
  double f = 0.0;

  [[nodiscard]] Point map(Point point) const;
  [[nodiscard]] std::array<double, 6> values() const;
};

struct FitResult {
  Matrix matrix;
  double rms_error;
  double maximum_error;
};

struct TipSample {
  Point measured;
  Point correction_per_cm;
};

struct TipDistanceFit {
  double distance;
  Point constant_error;
  double rms_error;
};

[[nodiscard]] Matrix compose(const Matrix &outer, const Matrix &inner);

[[nodiscard]] FitResult fit_affine(std::span<const Point> measured,
                                   std::span<const Point> expected);

[[nodiscard]] TipDistanceFit
fit_tip_distance(std::span<const TipSample> samples, Point expected);

} // namespace calibration
