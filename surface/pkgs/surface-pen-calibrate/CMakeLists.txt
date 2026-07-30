cmake_minimum_required(VERSION 3.20)

project(surface-pen-calibrate VERSION 0.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

qt_add_executable(surface-pen-calibrate
  calibration.cpp
  calibration.h
  main.cpp
)

target_link_libraries(surface-pen-calibrate PRIVATE Qt6::Widgets)
target_compile_options(surface-pen-calibrate PRIVATE
  -Wall
  -Wextra
  -Wpedantic
  -Werror
)
target_compile_definitions(surface-pen-calibrate PRIVATE
  INSTALL_HELPER_PATH="${INSTALL_HELPER_PATH}"
  PKEXEC_PATH="${PKEXEC_PATH}"
)

install(TARGETS surface-pen-calibrate
  RUNTIME DESTINATION bin
)
install(FILES
  surface-pen-calibrate.desktop
  surface-pen-tip-distance.desktop
  DESTINATION share/applications
)

include(CTest)
if(BUILD_TESTING)
  add_executable(calibration-test
    calibration.cpp
    calibration.h
    calibration-test.cpp
  )
  target_compile_options(calibration-test PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Werror
  )
  add_test(NAME calibration-test COMMAND calibration-test)
endif()
