#include "calibration.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <stdexcept>

namespace calibration {
namespace {

using Matrix3 = std::array<std::array<double, 3>, 3>;
using Vector3 = std::array<double, 3>;

Vector3 solve(Matrix3 matrix, Vector3 right_hand_side)
{
  for (std::size_t column = 0; column < 3; ++column) {
    std::size_t pivot = column;
    for (std::size_t row = column + 1; row < 3; ++row) {
      if (std::abs(matrix[row][column]) >
          std::abs(matrix[pivot][column])) {
        pivot = row;
      }
    }

    if (std::abs(matrix[pivot][column]) < 1e-12) {
      throw std::runtime_error("Calibration points do not span the screen");
    }

    std::swap(matrix[column], matrix[pivot]);
    std::swap(right_hand_side[column], right_hand_side[pivot]);

    const double divisor = matrix[column][column];
    for (std::size_t index = column; index < 3; ++index) {
      matrix[column][index] /= divisor;
    }
    right_hand_side[column] /= divisor;

    for (std::size_t row = 0; row < 3; ++row) {
      if (row == column) {
        continue;
      }

      const double factor = matrix[row][column];
      for (std::size_t index = column; index < 3; ++index) {
        matrix[row][index] -= factor * matrix[column][index];
      }
      right_hand_side[row] -= factor * right_hand_side[column];
    }
  }

  return right_hand_side;
}

} // namespace

Point Matrix::map(const Point point) const
{
  return {
    .x = (a * point.x) + (b * point.y) + c,
    .y = (d * point.x) + (e * point.y) + f,
  };
}

std::array<double, 6> Matrix::values() const
{
  return {a, b, c, d, e, f};
}

Matrix compose(const Matrix &outer, const Matrix &inner)
{
  return {
    .a = (outer.a * inner.a) + (outer.b * inner.d),
    .b = (outer.a * inner.b) + (outer.b * inner.e),
    .c = (outer.a * inner.c) + (outer.b * inner.f) + outer.c,
    .d = (outer.d * inner.a) + (outer.e * inner.d),
    .e = (outer.d * inner.b) + (outer.e * inner.e),
    .f = (outer.d * inner.c) + (outer.e * inner.f) + outer.f,
  };
}

FitResult fit_affine(const std::span<const Point> measured,
                     const std::span<const Point> expected)
{
  if (measured.size() != expected.size() || measured.size() < 3) {
    throw std::invalid_argument(
      "At least three measured/expected point pairs are required");
  }

  Matrix3 normal {};
  Vector3 right_x {};
  Vector3 right_y {};

  for (std::size_t index = 0; index < measured.size(); ++index) {
    const Vector3 row {measured[index].x, measured[index].y, 1.0};

    for (std::size_t y = 0; y < 3; ++y) {
      for (std::size_t x = 0; x < 3; ++x) {
        normal[y][x] += row[y] * row[x];
      }
      right_x[y] += row[y] * expected[index].x;
      right_y[y] += row[y] * expected[index].y;
    }
  }

  const Vector3 horizontal = solve(normal, right_x);
  const Vector3 vertical = solve(normal, right_y);
  const Matrix result {
    .a = horizontal[0],
    .b = horizontal[1],
    .c = horizontal[2],
    .d = vertical[0],
    .e = vertical[1],
    .f = vertical[2],
  };

  double squared_error = 0.0;
  double maximum_error = 0.0;
  for (std::size_t index = 0; index < measured.size(); ++index) {
    const Point mapped = result.map(measured[index]);
    const double error =
      std::hypot(mapped.x - expected[index].x,
                 mapped.y - expected[index].y);
    squared_error += error * error;
    maximum_error = std::max(maximum_error, error);
  }

  return {
    .matrix = result,
    .rms_error = std::sqrt(squared_error /
                           static_cast<double>(measured.size())),
    .maximum_error = maximum_error,
  };
}

} // namespace calibration
