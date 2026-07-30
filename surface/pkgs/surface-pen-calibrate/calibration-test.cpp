#include "calibration.h"

#include <array>
#include <cmath>
#include <stdexcept>

namespace {

constexpr double epsilon = 1e-10;

void expect_near(const double actual, const double expected)
{
  if (std::abs(actual - expected) >= epsilon) {
    throw std::runtime_error("Values differ");
  }
}

void test_fit()
{
  constexpr std::array measured {
    calibration::Point {0.1, 0.1},
    calibration::Point {0.9, 0.1},
    calibration::Point {0.9, 0.9},
    calibration::Point {0.1, 0.9},
    calibration::Point {0.5, 0.5},
  };
  constexpr calibration::Matrix wanted {
    .a = 1.04,
    .b = 0.02,
    .c = -0.03,
    .d = -0.01,
    .e = 0.97,
    .f = 0.04,
  };

  std::array<calibration::Point, measured.size()> expected {};
  for (std::size_t index = 0; index < measured.size(); ++index) {
    expected[index] = wanted.map(measured[index]);
  }

  const calibration::FitResult fitted =
    calibration::fit_affine(measured, expected);
  const auto values = fitted.matrix.values();
  const auto wanted_values = wanted.values();
  for (std::size_t index = 0; index < values.size(); ++index) {
    expect_near(values[index], wanted_values[index]);
  }
  expect_near(fitted.rms_error, 0.0);
  expect_near(fitted.maximum_error, 0.0);
}

void test_composition()
{
  constexpr calibration::Matrix first {
    .a = 1.1,
    .b = 0.0,
    .c = -0.05,
    .d = 0.0,
    .e = 0.9,
    .f = 0.02,
  };
  constexpr calibration::Matrix second {
    .a = 1.0,
    .b = 0.01,
    .c = 0.02,
    .d = -0.02,
    .e = 1.0,
    .f = 0.01,
  };
  constexpr calibration::Point point {0.3, 0.7};

  const calibration::Point sequential = second.map(first.map(point));
  const calibration::Point composed =
    calibration::compose(second, first).map(point);
  expect_near(composed.x, sequential.x);
  expect_near(composed.y, sequential.y);
}

void test_singular_points()
{
  constexpr std::array points {
    calibration::Point {0.1, 0.1},
    calibration::Point {0.2, 0.2},
    calibration::Point {0.3, 0.3},
  };

  bool threw = false;
  try {
    static_cast<void>(calibration::fit_affine(points, points));
  } catch (const std::runtime_error &) {
    threw = true;
  }
  if (!threw) {
    throw std::runtime_error("Singular calibration points were accepted");
  }
}

} // namespace

int main()
{
  test_fit();
  test_composition();
  test_singular_points();
}
